use std::collections::VecDeque;

use crate::Point;

/// Pointer strokes. Near-duplicate samples are dropped, a pause starts a new stroke,
/// and a sharp corner is kept. A full stroke drops its oldest point from the front
/// without shifting the rest.
pub struct InkTrail {
    pub strokes: VecDeque<VecDeque<Point>>,
    pub dropped_points: u32,
    open: bool,
    last_time: Option<f64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InkStep {
    Dropped,
    Began,
    Extended,
}

impl InkTrail {
    pub const MIN_SPACING: f64 = 2.5;
    pub const PAUSE_SPLIT: f64 = 0.6;
    pub const MAX_STROKES: usize = 16;
    pub const MAX_POINTS_PER_STROKE: usize = 512;
    pub const CORNER_DEGREES: f64 = 55.0;

    pub fn new() -> Self {
        Self { strokes: VecDeque::new(), dropped_points: 0, open: false, last_time: None }
    }

    pub fn add(&mut self, point: Point, time: f64) -> InkStep {
        if !point.x.is_finite() || !point.y.is_finite() || !time.is_finite() {
            self.dropped_points += 1;
            return InkStep::Dropped;
        }
        if self.open {
            if let Some(mut current) = self.strokes.pop_back() {
                if let Some(last) = current.back().copied() {
                    if distance(point, last) < Self::MIN_SPACING {
                        self.strokes.push_back(current);
                        self.dropped_points += 1;
                        return InkStep::Dropped;
                    }
                }
                if self.last_time.is_some_and(|last| time - last >= Self::PAUSE_SPLIT) {
                    self.strokes.push_back(current);
                    self.open = false;
                } else {
                    current.push_back(point);
                    if current.len() > Self::MAX_POINTS_PER_STROKE {
                        current.pop_front();
                        self.dropped_points += 1;
                    }
                    self.strokes.push_back(current);
                    self.last_time = Some(time);
                    return InkStep::Extended;
                }
            }
        }
        if self.strokes.len() >= Self::MAX_STROKES {
            self.strokes.pop_front();
            self.dropped_points += 1;
        }
        self.strokes.push_back(VecDeque::from([point]));
        self.open = true;
        self.last_time = Some(time);
        InkStep::Began
    }

    pub fn end_stroke(&mut self) {
        self.open = false;
    }

    pub fn is_drawing(&self) -> bool {
        self.open
    }

    pub fn smoothed(&self) -> Vec<Vec<Point>> {
        self.strokes
            .iter()
            .map(|stroke| {
                let (head, tail) = stroke.as_slices();
                if tail.is_empty() {
                    smooth(head)
                } else {
                    let mut owned = Vec::with_capacity(stroke.len());
                    owned.extend_from_slice(head);
                    owned.extend_from_slice(tail);
                    smooth(&owned)
                }
            })
            .collect()
    }
}

impl Default for InkTrail {
    fn default() -> Self {
        Self::new()
    }
}

pub fn smooth(points: &[Point]) -> Vec<Point> {
    if points.len() < 3 {
        return points.to_vec();
    }
    let mut corners = vec![0usize];
    for index in 1..points.len() - 1 {
        if turn(points[index - 1], points[index], points[index + 1]) > InkTrail::CORNER_DEGREES {
            corners.push(index);
        }
    }
    corners.push(points.len() - 1);
    let mut out = Vec::new();
    for pair in corners.windows(2) {
        let mut run = points[pair[0]..=pair[1]].to_vec();
        run = cut(&cut(&run));
        if out.is_empty() {
            out.extend(run);
        } else {
            out.extend(run.into_iter().skip(1));
        }
    }
    out
}

fn cut(run: &[Point]) -> Vec<Point> {
    if run.len() < 3 {
        return run.to_vec();
    }
    let first = run[0];
    let last = *run.last().expect("run has a last point");
    let mut out = vec![first];
    for index in 0..run.len() - 1 {
        let a = run[index];
        let b = run[index + 1];
        if index != 0 {
            out.push(Point::new(0.75 * a.x + 0.25 * b.x, 0.75 * a.y + 0.25 * b.y));
        }
        if index != run.len() - 2 {
            out.push(Point::new(0.25 * a.x + 0.75 * b.x, 0.25 * a.y + 0.75 * b.y));
        }
    }
    out.push(last);
    out
}

/// Degrees the path turns at `b`. 0 is straight on, 180 is a reversal.
pub fn turn(a: Point, b: Point, c: Point) -> f64 {
    let ux = b.x - a.x;
    let uy = b.y - a.y;
    let vx = c.x - b.x;
    let vy = c.y - b.y;
    if distance(Point::new(ux, uy), Point::ZERO) == 0.0 || distance(Point::new(vx, vy), Point::ZERO) == 0.0 {
        return 0.0;
    }
    (ux * vy - uy * vx).atan2(ux * vx + uy * vy).abs() * 180.0 / std::f64::consts::PI
}

fn distance(a: Point, b: Point) -> f64 {
    let dx = b.x - a.x;
    let dy = b.y - a.y;
    (dx * dx + dy * dy).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_right_angle_is_ninety_degrees() {
        let degrees = turn(Point::ZERO, Point::new(1.0, 0.0), Point::new(1.0, 1.0));
        assert!((degrees - 90.0).abs() < 1e-9);
    }

    #[test]
    fn a_pause_starts_a_new_stroke_and_a_near_point_is_dropped() {
        let mut trail = InkTrail::new();
        assert_eq!(trail.add(Point::new(0.0, 0.0), 0.0), InkStep::Began);
        assert_eq!(trail.add(Point::new(1.0, 0.0), 0.1), InkStep::Dropped);
        assert_eq!(trail.add(Point::new(10.0, 0.0), 0.2), InkStep::Extended);
        assert_eq!(trail.add(Point::new(20.0, 0.0), 1.0), InkStep::Began);
        assert_eq!(trail.strokes.len(), 2);
        assert!(trail.is_drawing());
    }

    #[test]
    fn a_long_stroke_drops_the_oldest_point_and_keeps_the_newest() {
        let mut trail = InkTrail::new();
        for index in 0..600 {
            let x = index as f64 * 10.0;
            trail.add(Point::new(x, 0.0), index as f64 * 0.01);
        }
        assert_eq!(trail.strokes.len(), 1);
        let stroke = &trail.strokes[0];
        assert_eq!(stroke.len(), InkTrail::MAX_POINTS_PER_STROKE);
        assert_eq!(stroke.front().copied(), Some(Point::new(880.0, 0.0)));
        assert_eq!(stroke.back().copied(), Some(Point::new(5990.0, 0.0)));
    }

    #[test]
    fn endpoints_of_a_straight_run_stay_put() {
        let points = [Point::new(0.0, 0.0), Point::new(10.0, 0.0), Point::new(20.0, 0.0)];
        let smoothed = smooth(&points);
        assert_eq!(smoothed.first().copied(), Some(points[0]));
        assert_eq!(smoothed.last().copied(), Some(points[2]));
    }
}
