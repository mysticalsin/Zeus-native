use crate::flight::Flight;
use crate::showcase::pixel_size;

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
    let flight = Flight::plan(
        crate::Point::new(from_x, from_y),
        crate::Point::new(to_x, to_y),
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
pub extern "C" fn zeus_visual_pixel_size(width: f64, height: f64, scale: f64) -> ZeusPixels {
    let (pixel_width, pixel_height) = pixel_size(width, height, scale);
    ZeusPixels { width: pixel_width, height: pixel_height }
}

#[cfg(test)]
mod tests {
    use super::*;

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
