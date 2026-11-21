package harupipe

import (
	"math"
	"testing"
)

func TestZeroCapacityRingAcceptsEmptyPush(t *testing.T) {
	r := NewRing(0)
	if err := r.Push(nil); err != nil {
		t.Fatal(err)
	}
	if err := r.Push([]float32{}); err != nil {
		t.Fatal(err)
	}
	if r.Len() != 0 {
		t.Fatalf("len %d", r.Len())
	}
}

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
