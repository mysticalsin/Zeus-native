package harupipe

import "testing"

func TestFrameSizeEnforced(t *testing.T) {
	if _, err := FrameFromSlice(make([]float32, 3199)); err != (BadFrameSize{3200, 3199}) {
		t.Fatalf("want BadFrameSize, got %v", err)
	}
	if _, err := FrameFromSlice(make([]float32, 3200)); err != nil {
		t.Fatal(err)
	}
}

func TestInt16RoundTrip(t *testing.T) {
	all := make([]int16, 0, 65536)
	for v := -32768; v <= 32767; v++ {
		all = append(all, int16(v))
	}
	back := F32ToI16(I16ToF32(all))
	for i := range all {
		if all[i] != back[i] {
			t.Fatalf("%d -> %d", all[i], back[i])
		}
	}
}

func TestResampleLength(t *testing.T) {
	for _, c := range [][2]int{{16000, 16001}, {44100, 44101}, {48000, 48001}} {
		y, err := To24k(make([]float32, c[1]), c[0])
		if err != nil {
			t.Fatal(err)
		}
		g := gcd(24000, c[0])
		up, down := 24000/g, c[0]/g
		if len(y) != (c[1]*up+down-1)/down {
			t.Fatalf("rate %d len %d", c[0], len(y))
		}
	}
}
