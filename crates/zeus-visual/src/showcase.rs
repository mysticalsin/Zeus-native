/// Canvas the talk drawing surface uses, in screenshot pixels, top-left origin.
pub const CANVAS_WIDTH: f64 = 1280.0;
pub const CANVAS_HEIGHT: f64 = 720.0;

/// Pixel size of a display frame at `scale` backing.
pub fn pixel_size(width: f64, height: f64, scale: f64) -> (i32, i32) {
    let factor = scale.max(1.0);
    (
        ((width * factor).round() as i32).max(1),
        ((height * factor).round() as i32).max(1),
    )
}

/// Scale from the 1280 by 720 canvas onto one real display. `sr` is the uniform scale for rings.
pub fn frame_scale(width: i32, height: i32) -> (f64, f64, f64) {
    let sx = (width.max(1) as f64) / CANVAS_WIDTH;
    let sy = (height.max(1) as f64) / CANVAS_HEIGHT;
    (sx, sy, sx.min(sy))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_retina_frame_doubles_and_stays_at_least_one_pixel() {
        assert_eq!(pixel_size(100.4, 0.2, 2.0), (201, 1));
        assert_eq!(pixel_size(10.0, 10.0, 0.5), (10, 10));
    }

    #[test]
    fn a_full_hd_frame_scales_the_canvas_without_stretching_the_ring() {
        let (sx, sy, sr) = frame_scale(1920, 1080);
        assert!((sx - 1.5).abs() < 1e-12);
        assert!((sy - 1.5).abs() < 1e-12);
        assert!((sr - 1.5).abs() < 1e-12);
    }
}
