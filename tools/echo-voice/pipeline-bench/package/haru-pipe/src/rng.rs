/// xorshift32: the shared deterministic chunk-size sequence of all three implementations.
pub struct XorShift32(pub u32);
impl XorShift32 {
    pub fn new() -> Self { XorShift32(0x9E37_79B9) }
    #[allow(clippy::should_implement_trait)]
    pub fn next(&mut self) -> u32 { let mut s = self.0; s ^= s << 13; s ^= s >> 17; s ^= s << 5; self.0 = s; s }
    /// 5..40 ms of 48 kHz audio per socket read.
    pub fn chunk_samples(&mut self) -> usize { 240 + (self.next() % 1681) as usize }
}
impl Default for XorShift32 { fn default() -> Self { Self::new() } }
