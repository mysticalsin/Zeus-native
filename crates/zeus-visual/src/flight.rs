use crate::Point;

/// Damped follow. Response 0.2 s, damping 0.6. The rest spot is 35 pt right and 25 pt down
/// from the pointer when down is a smaller y.
pub struct Spring {
    pub position: Point,
    pub velocity: Point,
}

impl Spring {
    pub const RESPONSE: f64 = 0.2;
    pub const DAMPING: f64 = 0.6;
    pub const OFFSET_X: f64 = 35.0;
    pub const OFFSET_Y: f64 = 25.0;

    pub fn rest(pointer: Point) -> Point {
        Point::new(pointer.x + Self::OFFSET_X, pointer.y - Self::OFFSET_Y)
    }

    pub fn tracks_pointer(show_is_never: bool) -> bool {
        !show_is_never
    }

    pub fn stepped(&self, target: Point, dt: f64, reduced_motion: bool) -> Self {
        if reduced_motion {
            return Self { position: target, velocity: Point::ZERO };
        }
        if !dt.is_finite() || dt <= 0.0 {
            return Self { position: self.position, velocity: self.velocity };
        }
        let x = axis(self.position.x, self.velocity.x, target.x, dt);
        let y = axis(self.position.y, self.velocity.y, target.y, dt);
        Self { position: Point::new(x.0, y.0), velocity: Point::new(x.1, y.1) }
    }
}

fn axis(pos: f64, vel: f64, target: f64, dt: f64) -> (f64, f64) {
    let omega = 2.0 * std::f64::consts::PI / Spring::RESPONSE;
    let zeta = Spring::DAMPING;
    let x0 = pos - target;
    let beta = zeta * omega;
    let omega_d = omega * (1.0 - zeta * zeta).max(0.0).sqrt();
    let decay = (-beta * dt).exp();
    let sine = (omega_d * dt).sin();
    let cosine = (omega_d * dt).cos();
    let swing = (vel + beta * x0) / omega_d;
    let offset = decay * (x0 * cosine + swing * sine);
    let speed = -beta * offset + decay * omega_d * (-x0 * sine + swing * cosine);
    if !offset.is_finite() || !speed.is_finite() {
        return (target, 0.0);
    }
    (target + offset, speed)
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Flight {
    pub from: Point,
    pub control: Point,
    pub to: Point,
    pub duration: f64,
    pub reduced_motion: bool,
}

impl Flight {
    pub const SCALE_REST: f64 = 1.0;
    pub const SCALE_PEAK: f64 = 1.3;
    pub const GLOW_REST: f64 = 8.0;
    pub const GLOW_PEAK: f64 = 14.0;

    pub fn duration(distance: f64, reduced_motion: bool) -> f64 {
        if reduced_motion {
            return 0.0;
        }
        let clamped = (distance / 800.0).clamp(0.6, 1.4);
        (clamped * 1000.0).round() / 1000.0
    }

    pub fn plan(from: Point, to: Point, reduced_motion: bool) -> Self {
        let distance = (to.x - from.x).hypot(to.y - from.y);
        let lift = (0.2 * distance).min(80.0);
        let control = Point::new((from.x + to.x) / 2.0, (from.y + to.y) / 2.0 + lift);
        Self {
            from,
            control,
            to,
            duration: Self::duration(distance, reduced_motion),
            reduced_motion,
        }
    }

    pub fn sample(&self, time: f64) -> FlightSample {
        let linear = linear(time, self.duration);
        let eased = linear * linear * (3.0 - 2.0 * linear);
        let position = self.bezier(eased);
        let tangent = self.bezier_tangent(eased);
        let rotation = if tangent.x.hypot(tangent.y) > 0.0001 {
            tangent.x.atan2(tangent.y) * 180.0 / std::f64::consts::PI
        } else {
            0.0
        };
        let pulse = if self.reduced_motion { 0.0 } else { (std::f64::consts::PI * linear).sin() };
        FlightSample {
            position,
            rotation,
            scale: Self::SCALE_REST + (Self::SCALE_PEAK - Self::SCALE_REST) * pulse,
            glow: Self::GLOW_REST + (Self::GLOW_PEAK - Self::GLOW_REST) * pulse,
            progress: linear,
        }
    }

    fn bezier(&self, t: f64) -> Point {
        let u = 1.0 - t;
        Point::new(
            u * u * self.from.x + 2.0 * u * t * self.control.x + t * t * self.to.x,
            u * u * self.from.y + 2.0 * u * t * self.control.y + t * t * self.to.y,
        )
    }

    fn bezier_tangent(&self, t: f64) -> Point {
        Point::new(
            2.0 * (1.0 - t) * (self.control.x - self.from.x) + 2.0 * t * (self.to.x - self.control.x),
            2.0 * (1.0 - t) * (self.control.y - self.from.y) + 2.0 * t * (self.to.y - self.control.y),
        )
    }
}

pub struct FlightSample {
    pub position: Point,
    pub rotation: f64,
    pub scale: f64,
    pub glow: f64,
    pub progress: f64,
}

fn linear(time: f64, duration: f64) -> f64 {
    if duration <= 0.0 {
        1.0
    } else {
        (time / duration).clamp(0.0, 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rest_sits_thirty_five_right_and_twenty_five_down() {
        assert_eq!(Spring::rest(Point::new(10.0, 40.0)), Point::new(45.0, 15.0));
    }

    #[test]
    fn reduced_motion_lands_on_the_target_with_no_flight_time() {
        let spring = Spring { position: Point::ZERO, velocity: Point::new(40.0, 0.0) };
        let stepped = spring.stepped(Point::new(80.0, 10.0), 0.016, true);
        assert_eq!(stepped.position, Point::new(80.0, 10.0));
        assert_eq!(stepped.velocity, Point::ZERO);
        let flight = Flight::plan(Point::ZERO, Point::new(600.0, 0.0), true);
        assert_eq!(flight.duration, 0.0);
        let sample = flight.sample(0.0);
        assert_eq!(sample.position, Point::new(600.0, 0.0));
        assert_eq!(sample.scale, Flight::SCALE_REST);
    }

    #[test]
    fn a_six_hundred_point_hop_lifts_eighty_and_lasts_three_quarters_of_a_second() {
        let flight = Flight::plan(Point::ZERO, Point::new(600.0, 0.0), false);
        assert!((flight.duration - 0.75).abs() < 1e-12);
        assert!((flight.control.y - 80.0).abs() < 1e-12);
        assert!((flight.control.x - 300.0).abs() < 1e-12);
    }

    #[test]
    fn never_does_not_track_the_pointer() {
        assert!(!Spring::tracks_pointer(true));
        assert!(Spring::tracks_pointer(false));
    }
}
