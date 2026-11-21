//! Fixed-capacity f32 ring buffer (no allocation on the hot path).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Overflow { pub capacity: usize, pub len: usize, pub incoming: usize }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Underflow { pub len: usize, pub wanted: usize }

pub struct Ring { buf: Vec<f32>, r: usize, n: usize }

impl Ring {
    pub fn new(capacity: usize) -> Self { Ring { buf: vec![0.0; capacity.max(1)], r: 0, n: 0 } }
    pub fn capacity(&self) -> usize { self.buf.len() }
    pub fn len(&self) -> usize { self.n }
    pub fn is_empty(&self) -> bool { self.n == 0 }
    pub fn push(&mut self, x: &[f32]) -> Result<(), Overflow> {
        let cap = self.buf.len();
        if x.len() > cap - self.n { return Err(Overflow { capacity: cap, len: self.n, incoming: x.len() }); }
        let w = (self.r + self.n) % cap;
        let first = x.len().min(cap - w);
        self.buf[w..w + first].copy_from_slice(&x[..first]);
        self.buf[..x.len() - first].copy_from_slice(&x[first..]);
        self.n += x.len();
        Ok(())
    }
    pub fn pop_into(&mut self, out: &mut [f32]) -> Result<(), Underflow> {
        let k = out.len();
        if k > self.n { return Err(Underflow { len: self.n, wanted: k }); }
        let cap = self.buf.len();
        let first = k.min(cap - self.r);
        out[..first].copy_from_slice(&self.buf[self.r..self.r + first]);
        out[first..].copy_from_slice(&self.buf[..k - first]);
        self.r = (self.r + k) % cap;
        self.n -= k;
        Ok(())
    }
    /// Grow (keeps contents); only used off the hot path.
    pub fn grow_to(&mut self, capacity: usize) {
        if capacity <= self.buf.len() { return; }
        let mut v = vec![0.0; self.n];
        let _ = self.pop_into(&mut v);
        self.buf = vec![0.0; capacity];
        self.r = 0; self.n = 0;
        let _ = self.push(&v);
    }
}
