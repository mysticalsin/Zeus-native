package harupipe

import (
	"encoding/binary"
	"math"
	"testing"
	"time"
)

func pcmWav(tag, bits, ch uint16, rate uint32, payload []byte) []byte {
	fmtc := make([]byte, 16)
	binary.LittleEndian.PutUint16(fmtc[0:], tag)
	binary.LittleEndian.PutUint16(fmtc[2:], ch)
	binary.LittleEndian.PutUint32(fmtc[4:], rate)
	block := uint16(int(ch) * int(bits) / 8)
	binary.LittleEndian.PutUint32(fmtc[8:], rate*uint32(block))
	binary.LittleEndian.PutUint16(fmtc[12:], block)
	binary.LittleEndian.PutUint16(fmtc[14:], bits)
	chunk := func(id string, body []byte) []byte {
		b := append([]byte(id), make([]byte, 4)...)
		binary.LittleEndian.PutUint32(b[4:], uint32(len(body)))
		b = append(b, body...)
		if len(body)%2 == 1 {
			b = append(b, 0)
		}
		return b
	}
	body := append(chunk("fmt ", fmtc), chunk("data", payload)...)
	out := append([]byte("RIFF"), make([]byte, 4)...)
	binary.LittleEndian.PutUint32(out[4:], uint32(4+len(body)))
	return append(append(out, []byte("WAVE")...), body...)
}

func TestDecode24And32BitPCM(t *testing.T) {
	var data24 []byte
	for _, s := range []int32{1, -1, 8388607, -8388608} {
		var b [4]byte
		binary.LittleEndian.PutUint32(b[:], uint32(int32(s)))
		data24 = append(data24, b[:3]...)
	}
	w, err := DecodeWav(pcmWav(1, 24, 1, 24000, data24))
	if err != nil {
		t.Fatal(err)
	}
	want24 := []float32{1.0 / 8388608.0, -1.0 / 8388608.0, 8388607.0 / 8388608.0, -1}
	if len(w.Samples) != len(want24) {
		t.Fatalf("24-bit len %d", len(w.Samples))
	}
	for i := range want24 {
		if math.Abs(float64(w.Samples[i]-want24[i])) > 1e-6 {
			t.Fatalf("24-bit %d got %v want %v", i, w.Samples[i], want24[i])
		}
	}
	var data32 []byte
	for _, s := range []int32{0, 2147483647, -2147483648} {
		var b [4]byte
		binary.LittleEndian.PutUint32(b[:], uint32(s))
		data32 = append(data32, b[:]...)
	}
	w, err = DecodeWav(pcmWav(1, 32, 1, 24000, data32))
	if err != nil {
		t.Fatal(err)
	}
	scale := 2147483648.0
	want32 := []float32{0, float32(2147483647 / scale), -1}
	for i := range want32 {
		if math.Abs(float64(w.Samples[i]-want32[i])) > 1e-6 {
			t.Fatalf("32-bit %d got %v want %v", i, w.Samples[i], want32[i])
		}
	}
}

func TestDecodeRejectsZeroChannelsAndRate(t *testing.T) {
	if _, err := DecodeWav(pcmWav(1, 16, 0, 24000, []byte{0, 0})); err == nil {
		t.Fatal("zero channels accepted")
	}
	if _, err := DecodeWav(pcmWav(1, 16, 1, 0, []byte{0, 0})); err == nil {
		t.Fatal("zero rate accepted")
	}
	defer func() {
		if recover() != nil {
			t.Fatal("ToMono panicked on zero channels")
		}
	}()
	if ToMono([]float32{0.5, -0.5}, 0) != nil {
		t.Fatal("ToMono(ch=0) should return nil, not a partial mix")
	}
}

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

func TestStreamMsgsStayBounded(t *testing.T) {
	raw := make([]byte, 16*6400*4)
	st, _ := StreamRun(raw, 0, 0, nil)
	if st.Index <= 10 {
		t.Fatalf("produced only %d frames", st.Index)
	}
	if len(st.Msgs) > 32*1024 {
		t.Fatalf("msgs grew to %d bytes", len(st.Msgs))
	}
}

func TestBadRatioIsAnError(t *testing.T) {
	for _, c := range [][2]int{{0, 2}, {2, 0}, {0, 0}} {
		if _, err := NewPolyphase(c[0], c[1]); err == nil {
			t.Fatalf("up=%d down=%d returned a filter", c[0], c[1])
		}
	}
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
