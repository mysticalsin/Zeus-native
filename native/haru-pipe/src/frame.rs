//! 133 ms model frames. A [`Frame`] can only hold exactly [`FRAME_SAMPLES`] samples.
use crate::ring::Ring;

/// 24 kHz / 7.5 Hz: one Haru step consumes and produces this many samples.
pub const FRAME_SAMPLES: usize = 3200;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FrameError {
    BadFrameSize { expected: usize, got: usize },
}

impl std::fmt::Display for FrameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FrameError::BadFrameSize { expected, got } => {
                write!(f, "a frame is {expected} samples, got {got}")
            }
        }
    }
}
impl std::error::Error for FrameError {}

#[derive(Debug, Clone, PartialEq)]
pub struct Frame(Box<[f32; FRAME_SAMPLES]>);

impl Frame {
    pub fn silence() -> Self {
        Frame(Box::new([0.0; FRAME_SAMPLES]))
    }
    pub fn try_from_slice(x: &[f32]) -> Result<Frame, FrameError> {
        if x.len() != FRAME_SAMPLES {
            return Err(FrameError::BadFrameSize {
                expected: FRAME_SAMPLES,
                got: x.len(),
            });
        }
        let mut f = Frame::silence();
        f.0.copy_from_slice(x);
        Ok(f)
    }
    pub fn as_slice(&self) -> &[f32] {
        &self.0[..]
    }
    pub fn as_mut_slice(&mut self) -> &mut [f32] {
        &mut self.0[..]
    }
}

/// Number of frames `haru-mlx-inference` makes from `n` samples (it zero-pads the tail).
pub fn frame_count(n: usize) -> usize {
    std::cmp::max(1, n.div_ceil(FRAME_SAMPLES))
}

/// Streaming framer: push any number of samples, pop whole frames in order.
pub struct Framer {
    ring: Ring,
}

impl Default for Framer {
    fn default() -> Self {
        Self::new()
    }
}

impl Framer {
    pub fn new() -> Self {
        Self::with_capacity_frames(8)
    }
    pub fn with_capacity_frames(n: usize) -> Self {
        Framer {
            ring: Ring::new(n * FRAME_SAMPLES),
        }
    }
    /// Panics on overflow (a caller that never pops is a bug); use [`Framer::try_push`] to handle it.
    pub fn push(&mut self, x: &[f32]) {
        self.try_push(x).expect("framer overflow")
    }
    pub fn try_push(&mut self, x: &[f32]) -> Result<(), crate::ring::Overflow> {
        if x.len() > self.ring.capacity() - self.ring.len() {
            self.ring.grow_to(self.ring.len() + x.len());
        }
        self.ring.push(x)
    }
    pub fn pop(&mut self) -> Option<Frame> {
        let mut f = Frame::silence();
        if self.pop_into(&mut f) {
            Some(f)
        } else {
            None
        }
    }
    /// Allocation-free pop into an existing frame.
    pub fn pop_into(&mut self, f: &mut Frame) -> bool {
        if self.ring.len() < FRAME_SAMPLES {
            return false;
        }
        self.ring.pop_into(f.as_mut_slice()).is_ok()
    }
    pub fn pending(&self) -> usize {
        self.ring.len()
    }
}
