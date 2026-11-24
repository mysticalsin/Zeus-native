//! The fixed benchmark workload, step for step the same as python/pipe.py.
use crate::frame::{frame_count, Frame, FRAME_SAMPLES};
use crate::native::{encode_frame_msg, upsample_2x_into, Ingest, FRAME_SAMPLES_48K};
use crate::ring::Ring;
use crate::rng::XorShift32;
use std::time::{Duration, Instant};

pub const CLIENT_BLOCK: usize = 480;

/// Stand-in model: frame t+1 = clip(0.5 * user frame t).
#[inline]
pub fn sim_model(user: &[f32], out: &mut [f32]) {
    for (o, &u) in out.iter_mut().zip(user) {
        *o = (0.5 * u).clamp(-1.0, 1.0);
    }
}

pub fn spin_until(deadline: Instant) {
    let now = Instant::now();
    if deadline > now + Duration::from_millis(1) {
        std::thread::sleep(deadline - now - Duration::from_millis(1));
    }
    while Instant::now() < deadline {
        std::hint::spin_loop();
    }
}

pub struct FileResult {
    pub json: String,
    pub per_frame_ns: Vec<u64>,
    pub audio_s: f64,
}

pub fn file_one(src: &std::path::Path, dst: &std::path::Path) -> std::io::Result<FileResult> {
    let t0 = Instant::now();
    let mut user = crate::wav::load_audio(src)?;
    let t1 = Instant::now();
    let count = frame_count(user.len());
    user.resize(count * FRAME_SAMPLES, 0.0);
    let mut frames: Vec<Frame> = Vec::with_capacity(count);
    frames.push(Frame::silence());
    let mut per = Vec::with_capacity(count);
    for index in 0..count - 1 {
        let a = Instant::now();
        let u = &user[index * FRAME_SAMPLES..(index + 1) * FRAME_SAMPLES];
        let mut f = Frame::silence();
        sim_model(u, f.as_mut_slice());
        frames.push(f);
        per.push(a.elapsed().as_nanos() as u64);
    }
    let t2 = Instant::now();
    let mut stereo = vec![0f32; 2 * count * FRAME_SAMPLES];
    for (k, f) in frames.iter().enumerate() {
        for (i, &r) in f.as_slice().iter().enumerate() {
            let n = k * FRAME_SAMPLES + i;
            stereo[2 * n] = user[n];
            stereo[2 * n + 1] = r;
        }
    }
    let t3 = Instant::now();
    crate::wav::write_pcm16(dst, crate::SAMPLE_RATE, 2, &stereo)?;
    let t4 = Instant::now();
    let ms = |a: Instant, b: Instant| (b - a).as_nanos() as f64 / 1e6;
    let audio_s = (count * FRAME_SAMPLES) as f64 / crate::SAMPLE_RATE as f64;
    let name = src.file_name().unwrap().to_string_lossy();
    Ok(FileResult {
        json: format!("{{\"file\": \"{name}\", \"frames\": {count}, \"audio_s\": {audio_s}, \"read_resample_ms\": {}, \"frame_loop_ms\": {}, \"assemble_ms\": {}, \"write_ms\": {}, \"total_ms\": {}}}",
            ms(t0, t1), ms(t1, t2), ms(t2, t3), ms(t3, t4), ms(t0, t4)),
        per_frame_ns: per, audio_s,
    })
}

/// NativeServer._serve's audio path plus a client playback jitter buffer.
pub struct Stream {
    ingest: Ingest,
    out: Ring,
    frame: Frame,
    reply: Frame,
    pcm48: Vec<f32>,
    block: Vec<f32>,
    pub index: u32,
    pub model: Duration,
    pub msgs: Vec<u8>,
    pub drained: usize,
}

impl Stream {
    pub fn new(model: Duration, expected_bytes: usize) -> Self {
        Stream {
            ingest: Ingest::new(),
            out: Ring::new(8 * FRAME_SAMPLES_48K),
            frame: Frame::silence(),
            reply: Frame::silence(),
            pcm48: vec![0.0; FRAME_SAMPLES_48K],
            block: vec![0.0; CLIENT_BLOCK],
            index: 1,
            model,
            msgs: Vec::with_capacity(expected_bytes),
            drained: 0,
        }
    }
    fn emit(&mut self) {
        sim_model(self.frame.as_slice(), self.reply.as_mut_slice());
        if !self.model.is_zero() {
            spin_until(Instant::now() + self.model);
        }
        upsample_2x_into(self.reply.as_slice(), &mut self.pcm48);
        encode_frame_msg(self.index, 0.0, &self.pcm48, &mut self.msgs);
        self.index += 1;
        self.out.push(&self.pcm48).expect("jitter buffer overflow");
        while self.out.len() >= CLIENT_BLOCK {
            self.out.pop_into(&mut self.block).unwrap();
            self.drained += CLIENT_BLOCK;
        }
    }
    pub fn feed(&mut self, payload: &[u8], mut on_frame: impl FnMut()) {
        self.ingest.feed_bytes(payload);
        while self.ingest.pop_into(&mut self.frame) {
            self.emit();
            on_frame();
        }
    }
}

pub fn stream_run(
    raw: &[u8],
    max_frames: usize,
    model: Duration,
    mut first: impl FnMut(),
) -> (Stream, Vec<u64>) {
    let mut st = Stream::new(model, raw.len() * 2 + 4096);
    let mut rng = XorShift32::new();
    let mut per: Vec<u64> = Vec::with_capacity(raw.len() / (4 * 2 * FRAME_SAMPLES) + 8);
    let (mut acc, mut pos) = (0u64, 0usize);
    while pos < raw.len() {
        let k = rng.chunk_samples() * 4;
        let end = (pos + k).min(raw.len());
        let mut mark = Instant::now();
        st.feed(&raw[pos..end], || {
            let t = Instant::now();
            per.push(acc + (t - mark).as_nanos() as u64);
            acc = 0;
            mark = t;
            if per.len() == 1 {
                first();
            }
        });
        acc += mark.elapsed().as_nanos() as u64;
        pos += k;
        if max_frames > 0 && per.len() >= max_frames {
            break;
        }
    }
    (st, per)
}
