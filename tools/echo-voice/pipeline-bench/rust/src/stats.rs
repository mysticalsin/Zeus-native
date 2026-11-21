/// numpy.percentile (linear) over nanoseconds -> ms summary JSON.
pub fn percentile(sorted: &[f64], q: f64) -> f64 {
    if sorted.is_empty() { return f64::NAN; }
    let pos = (sorted.len() - 1) as f64 * q / 100.0;
    let (lo, hi) = (pos.floor() as usize, pos.ceil() as usize);
    sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo as f64)
}
pub fn summary_json(ns: &[u64]) -> String {
    if ns.is_empty() {
        // null percentiles: an empty sample has no quantile. mean 0 (not -0, not NaN).
        return "{\"n\": 0, \"p50_ms\": null, \"p95_ms\": null, \"p99_ms\": null, \"max_ms\": null, \"mean_ms\": 0}".to_string();
    }
    let mut ms: Vec<f64> = ns.iter().map(|&v| v as f64 / 1e6).collect();
    ms.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let mean = ms.iter().sum::<f64>() / ms.len().max(1) as f64;
    format!("{{\"n\": {}, \"p50_ms\": {}, \"p95_ms\": {}, \"p99_ms\": {}, \"max_ms\": {}, \"mean_ms\": {}}}",
        ms.len(), percentile(&ms, 50.0), percentile(&ms, 95.0), percentile(&ms, 99.0), ms.last().copied().unwrap_or(f64::NAN), mean)
}
