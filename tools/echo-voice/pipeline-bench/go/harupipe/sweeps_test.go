package harupipe

import (
	"math"
	"testing"
)

func TestEmptySummaryIsFinite(t *testing.T) {
	s := Summary(nil)
	if s["n"] != 0 {
		t.Fatalf("n=%v", s["n"])
	}
	for _, key := range []string{"p50_ms", "p95_ms", "p99_ms", "max_ms", "mean_ms"} {
		v := s[key]
		if math.IsNaN(v) || math.IsInf(v, 0) {
			t.Fatalf("%s=%v", key, v)
		}
	}
}
