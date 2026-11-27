use crate::flight::Flight;
use crate::ink::{InkStep, InkTrail};
use crate::showcase::pixel_size;

pub struct InkBox {
    trail: InkTrail,
}

/// Flight numbers the Mac app draws. Layout matches `ZeusFlight` in `zeus_visual.h`.
#[repr(C)]
pub struct ZeusFlight {
    pub from_x: f64,
    pub from_y: f64,
    pub control_x: f64,
    pub control_y: f64,
    pub to_x: f64,
    pub to_y: f64,
    pub duration: f64,
    pub reduced_motion: i32,
}

#[repr(C)]
pub struct ZeusPixels {
    pub width: i32,
    pub height: i32,
}

#[no_mangle]
pub extern "C" fn zeus_visual_flight(
    from_x: f64,
    from_y: f64,
    to_x: f64,
    to_y: f64,
    reduced_motion: i32,
) -> ZeusFlight {
    zeus_visual_flight_tangent(from_x, from_y, to_x, to_y, reduced_motion, 0.0, 0.0, 0)
}

#[no_mangle]
pub extern "C" fn zeus_visual_flight_tangent(
    from_x: f64,
    from_y: f64,
    to_x: f64,
    to_y: f64,
    reduced_motion: i32,
    tangent_x: f64,
    tangent_y: f64,
    has_tangent: i32,
) -> ZeusFlight {
    let departure = if has_tangent != 0 {
        Some(crate::Point::new(tangent_x, tangent_y))
    } else {
        None
    };
    let flight = Flight::plan_with_tangent(
        crate::Point::new(from_x, from_y),
        crate::Point::new(to_x, to_y),
        departure,
        reduced_motion != 0,
    );
    ZeusFlight {
        from_x: flight.from.x,
        from_y: flight.from.y,
        control_x: flight.control.x,
        control_y: flight.control.y,
        to_x: flight.to.x,
        to_y: flight.to.y,
        duration: flight.duration,
        reduced_motion: i32::from(flight.reduced_motion),
    }
}

#[no_mangle]
pub extern "C" fn zeus_visual_ink_new() -> *mut InkBox {
    Box::into_raw(Box::new(InkBox { trail: InkTrail::new() }))
}

#[no_mangle]
pub extern "C" fn zeus_visual_ink_free(ptr: *mut InkBox) {
    if !ptr.is_null() {
        drop(unsafe { Box::from_raw(ptr) });
    }
}

#[no_mangle]
pub extern "C" fn zeus_visual_ink_reset(ptr: *mut InkBox) {
    if let Some(ink) = unsafe { ptr.as_mut() } {
        ink.trail = InkTrail::new();
    }
}

#[no_mangle]
pub extern "C" fn zeus_visual_ink_add(ptr: *mut InkBox, x: f64, y: f64, time: f64) -> i32 {
    let Some(ink) = (unsafe { ptr.as_mut() }) else { return 0 };
    match ink.trail.add(crate::Point::new(x, y), time) {
        InkStep::Dropped => 0,
        InkStep::Began => 1,
        InkStep::Extended => 2,
    }
}

#[no_mangle]
pub extern "C" fn zeus_visual_ink_end(ptr: *mut InkBox) {
    if let Some(ink) = unsafe { ptr.as_mut() } {
        ink.trail.end_stroke();
    }
}

/// Writes smoothed strokes. `stroke_lengths[i]` is how many points belong to stroke i.
/// Returns the number of strokes written. Stops before overflowing the buffers.
#[no_mangle]
pub extern "C" fn zeus_visual_ink_smoothed(
    ptr: *mut InkBox,
    xs: *mut f64,
    ys: *mut f64,
    stroke_lengths: *mut i32,
    max_strokes: i32,
    max_points: i32,
) -> i32 {
    let Some(ink) = (unsafe { ptr.as_mut() }) else { return 0 };
    if xs.is_null() || ys.is_null() || stroke_lengths.is_null() || max_strokes <= 0 || max_points <= 0 {
        return 0;
    }
    let smoothed = ink.trail.smoothed();
    let mut written_points = 0i32;
    let mut written_strokes = 0i32;
    for stroke in smoothed {
        if written_strokes >= max_strokes || written_points >= max_points {
            break;
        }
        let room = (max_points - written_points) as usize;
        let count = stroke.len().min(room);
        for (offset, point) in stroke.iter().take(count).enumerate() {
            unsafe {
                *xs.add(written_points as usize + offset) = point.x;
                *ys.add(written_points as usize + offset) = point.y;
            }
        }
        unsafe { *stroke_lengths.add(written_strokes as usize) = count as i32 };
        written_points += count as i32;
        written_strokes += 1;
    }
    written_strokes
}

#[no_mangle]
pub extern "C" fn zeus_visual_pixel_size(width: f64, height: f64, scale: f64) -> ZeusPixels {
    let (pixel_width, pixel_height) = pixel_size(width, height, scale);
    ZeusPixels { width: pixel_width, height: pixel_height }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pause_through_the_c_api_starts_a_second_stroke() {
        let ink = zeus_visual_ink_new();
        assert_eq!(zeus_visual_ink_add(ink, 0.0, 0.0, 0.0), 1);
        assert_eq!(zeus_visual_ink_add(ink, 1.0, 0.0, 0.1), 0);
        assert_eq!(zeus_visual_ink_add(ink, 20.0, 0.0, 1.0), 1);
        zeus_visual_ink_free(ink);
    }

    #[test]
    fn the_c_flight_matches_the_swift_hop() {
        let flight = zeus_visual_flight(0.0, 0.0, 600.0, 0.0, 0);
        assert!((flight.duration - 0.75).abs() < 1e-12);
        assert!((flight.control_y - 80.0).abs() < 1e-12);
        assert_eq!(flight.reduced_motion, 0);
        let reduced = zeus_visual_flight(0.0, 0.0, 600.0, 0.0, 1);
        assert_eq!(reduced.duration, 0.0);
        assert_eq!(reduced.reduced_motion, 1);
    }
}
