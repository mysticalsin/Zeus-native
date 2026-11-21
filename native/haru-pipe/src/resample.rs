//! `scipy.signal.resample_poly` re-implemented (window=('kaiser', 5.0), padtype='constant').
//! Output length `ceil(n * up / down)`, same filter taps (f64 design, f32 taps like scipy
//! for float32 input), same alignment (`n_pre_remove`). Sums run in f32 in a different
//! order than scipy's upfirdn, so outputs agree to ~1e-6, not bit for bit (see parity test).

fn gcd(a: u64, b: u64) -> u64 {
    if b == 0 {
        a
    } else {
        gcd(b, a % b)
    }
}

/// Modified Bessel function of the first kind, order 0 (power series).
/// Stops when the term overflows f64 instead of spinning on `inf < inf`.
fn i0(x: f64) -> f64 {
    if !x.is_finite() {
        return f64::INFINITY;
    }
    let (mut sum, mut term, q) = (1.0f64, 1.0f64, x * x / 4.0);
    let mut k = 1.0;
    for _ in 0..256 {
        term *= q / (k * k);
        if !term.is_finite() {
            return f64::INFINITY;
        }
        sum += term;
        if !sum.is_finite() || term < sum * 1e-17 {
            return sum;
        }
        k += 1.0;
    }
    sum
}

fn kaiser(beta: f64, r: f64) -> f64 {
    let arg = beta * (1.0 - r * r).max(0.0).sqrt();
    // The power series overflows for a large beta. The ratio of the two
    // Bessel values is exp(arg - beta) * sqrt(beta / arg) in that regime.
    if beta.abs() > 40.0 {
        if arg <= 0.0 {
            return 0.0;
        }
        let log_ratio = (arg - beta) + 0.5 * (beta / arg).ln();
        return log_ratio.exp();
    }
    let denom = i0(beta);
    let numer = i0(arg);
    if denom.is_finite() && numer.is_finite() && denom != 0.0 {
        numer / denom
    } else if r.abs() < 1e-12 {
        1.0
    } else {
        0.0
    }
}

fn sinc(x: f64) -> f64 {
    if x == 0.0 {
        1.0
    } else {
        let p = std::f64::consts::PI * x;
        p.sin() / p
    }
}

/// `firwin(numtaps, cutoff, window=('kaiser', beta))` (lowpass, scaled to unit DC gain).
pub fn firwin_kaiser(numtaps: usize, cutoff: f64, beta: f64) -> Vec<f64> {
    let alpha = 0.5 * (numtaps as f64 - 1.0);
    let mut h: Vec<f64> = (0..numtaps)
        .map(|i| {
            let m = i as f64 - alpha;
            let r = if numtaps > 1 {
                2.0 * i as f64 / (numtaps as f64 - 1.0) - 1.0
            } else {
                0.0
            };
            let w = kaiser(beta, r);
            cutoff * sinc(cutoff * m) * w
        })
        .collect();
    let s: f64 = h.iter().sum();
    h.iter_mut().for_each(|v| *v /= s);
    h
}

/// Polyphase filter bank for a fixed (up, down) pair; reuse it across calls.
pub struct Polyphase {
    up: usize,
    down: usize,
    half_len: usize,
    taps_len: usize,
    phases: Vec<Vec<f32>>,
}

impl Polyphase {
    pub fn new(up: u64, down: u64) -> Self {
        if up == 0 || down == 0 {
            return Polyphase {
                up: 0,
                down: 0,
                half_len: 0,
                taps_len: 0,
                phases: Vec::new(),
            };
        }
        let g = gcd(up, down);
        let (up, down) = ((up / g) as usize, (down / g) as usize);
        let max_rate = up.max(down);
        let half_len = 10 * max_rate;
        let h64 = firwin_kaiser(2 * half_len + 1, 1.0 / max_rate as f64, 5.0);
        let h: Vec<f32> = h64.iter().map(|&v| (v as f32) * up as f32).collect(); // h = f32(firwin) * up
                                                                                 // phase p holds h[p], h[p+up], ... reversed, so each output is a contiguous dot product.
        let phases = (0..up)
            .map(|p| {
                let mut t: Vec<f32> = h.iter().skip(p).step_by(up).copied().collect();
                t.reverse();
                t
            })
            .collect();
        Polyphase {
            up,
            down,
            half_len,
            taps_len: h.len(),
            phases,
        }
    }

    pub fn output_len(&self, n_in: usize) -> usize {
        if self.down == 0 {
            return 0;
        }
        (n_in * self.up).div_ceil(self.down)
    }

    pub fn process(&self, x: &[f32]) -> Vec<f32> {
        if self.up == 0 || self.down == 0 {
            return Vec::new();
        }
        if self.up == 1 && self.down == 1 {
            return x.to_vec();
        }
        let n_in = x.len();
        let n_out = self.output_len(n_in);
        let mut y = vec![0f32; n_out];
        let (up, down, hl, l) = (
            self.up as i64,
            self.down as i64,
            self.half_len as i64,
            self.taps_len as i64,
        );
        for (j, out) in y.iter_mut().enumerate() {
            let c = j as i64 * down + hl; // centre of output j on the upsampled grid
            let p = (c % up) as usize;
            let i_max = c / up; // newest input sample under the filter
            let taps = &self.phases[p];
            let t_len = taps.len() as i64; // == ceil((l - p) / up)
            debug_assert_eq!(t_len, (l - p as i64 + up - 1) / up);
            let i_first = i_max - t_len + 1; // input index aligned with taps[0]
            let lo = i_first.max(0);
            let hi = i_max.min(n_in as i64 - 1);
            if hi < lo {
                continue;
            }
            let xs = &x[lo as usize..=hi as usize];
            let ts = &taps[(lo - i_first) as usize..(lo - i_first) as usize + xs.len()];
            *out = dot(xs, ts);
        }
        y
    }
}

#[inline]
fn dot(a: &[f32], b: &[f32]) -> f32 {
    // 8 independent accumulators let LLVM vectorise without -ffast-math.
    let mut acc = [0f32; 8];
    let (ca, cb) = (a.chunks_exact(8), b.chunks_exact(8));
    let (ra, rb) = (ca.remainder(), cb.remainder());
    for (x, y) in ca.zip(cb) {
        for k in 0..8 {
            acc[k] += x[k] * y[k];
        }
    }
    let mut s = ((acc[0] + acc[4]) + (acc[1] + acc[5])) + ((acc[2] + acc[6]) + (acc[3] + acc[7]));
    for (x, y) in ra.iter().zip(rb) {
        s += x * y;
    }
    s
}

pub fn resample_poly(x: &[f32], up: u64, down: u64) -> Vec<f32> {
    Polyphase::new(up, down).process(x)
}

/// Any rate -> 24 kHz, as `haru_mlx.audio.decode_audio` does.
pub fn to_24k(x: &[f32], rate: u32) -> Vec<f32> {
    if rate == 0 {
        return Vec::new();
    }
    if rate == crate::SAMPLE_RATE {
        return x.to_vec();
    }
    let g = gcd(crate::SAMPLE_RATE as u64, rate as u64);
    resample_poly(x, crate::SAMPLE_RATE as u64 / g, rate as u64 / g)
}
