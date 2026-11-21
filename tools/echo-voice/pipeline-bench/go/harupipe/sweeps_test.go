package harupipe

import (
	"math"
	"testing"
	"time"
)

func TestFiveByteSplitMatchesSingleRead(t *testing.T) {
	raw := make([]byte, 64)
	for i := range raw {
		raw[i] = byte(i)
	}
	whole := NewStream(0, 0)
	whole.Feed(raw, func() {})
	split := NewStream(0, 0)
	split.Feed(raw[:5], func() {})
	split.Feed(raw[5:], func() {})
	got, want := heldSamples(split), heldSamples(whole)
	if len(got) != len(want) {
		t.Fatalf("pending whole=%d split=%d", len(want), len(got))
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("sample %d whole=%v split=%v (pending %d)", i, want[i], got[i], len(want))
		}
	}
}

func heldSamples(s *Stream) []float32 {
	out := make([]float32, s.in.Len())
	if len(out) > 0 {
		if err := s.in.PopInto(out); err != nil {
			panic(err)
		}
	}
	if s.hasLeftover {
		out = append(out, s.leftover)
	}
	return out
}

func TestFirwinSingleTapIsUnity(t *testing.T) {
	done := make(chan []float64, 1)
	go func() { done <- FirwinKaiser(1, 0.5, 5.0) }()
	select {
	case h := <-done:
		if len(h) != 1 || math.Abs(h[0]-1) > 1e-12 {
			t.Fatalf("%v", h)
		}
	case <-time.After(time.Second):
		t.Fatal("FirwinKaiser(1) did not return (division by numtaps-1 feeds NaN into i0)")
	}
}

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
