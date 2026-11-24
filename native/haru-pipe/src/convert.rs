//! int16 <-> float32 with libsndfile's conventions (what `soundfile` does upstream).

/// int16 PCM -> float32 in [-1, 1): `x / 32768`.
pub fn i16_to_f32(x: &[i16]) -> Vec<f32> {
    x.iter().map(|&v| v as f32 * (1.0 / 32768.0)).collect()
}

/// float32 -> int16 PCM: `floor(x * 32768)` clipped to [-32768, 32767].
/// Matches libsndfile 1.2.2 as bundled with soundfile 0.14 (probed, see REPORT.md).
pub fn f32_to_i16(x: &[f32]) -> Vec<i16> {
    let mut out = vec![0i16; x.len()];
    f32_to_i16_into(x, &mut out);
    out
}

#[inline]
pub fn f32_to_i16_into(x: &[f32], out: &mut [i16]) {
    for (o, &v) in out.iter_mut().zip(x) {
        let s = (v * 32768.0).floor();
        *o = if s >= 32767.0 {
            32767
        } else if s <= -32768.0 {
            -32768
        } else {
            s as i16
        };
    }
}

/// Interleaved multi-channel -> mono, `mean(axis=1)` in float32 like numpy.
pub fn to_mono(interleaved: &[f32], channels: usize) -> Vec<f32> {
    match channels {
        0 => Vec::new(),
        1 => interleaved.to_vec(),
        2 => interleaved
            .chunks_exact(2)
            .map(|c| (c[0] + c[1]) / 2.0)
            .collect(),
        n => interleaved
            .chunks_exact(n)
            .map(|c| c.iter().sum::<f32>() / n as f32)
            .collect(),
    }
}
