//! Pure geometry for showing where something is and for drawing an explanation.
//!
//! The numbers match the Swift boxes the Mac app already uses:
//! `PointingInkTrailBox`, `CompanionMotionBox`, and `ExplainShowcase.pixelSize`.
//! Nothing here reads a pointer, a screen, or a clock.

pub mod flight;
pub mod ink;
pub mod showcase;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}

impl Point {
    pub const ZERO: Self = Self { x: 0.0, y: 0.0 };

    pub fn new(x: f64, y: f64) -> Self {
        Self { x, y }
    }
}
