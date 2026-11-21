// Package harupipe is the Go port of Haru-4B's host-side audio pipeline
// (same semantics as ../rust and ../python: libsndfile int16 conventions,
// scipy resample_poly, 3200-sample frames, haru-mlx-native socket framing).
package harupipe

import (
	"encoding/binary"
	"errors"
	"fmt"
	"math"
	"os"
	"sort"
	"time"
)

const (
	SampleRate      = 24000
	FrameSamples    = 3200
	FrameSamples48k = 2 * FrameSamples
	MsgFrame        = 0x11
	ClientBlock     = 480
)

// ---------------------------------------------------------------- convert

func I16ToF32(x []int16) []float32 {
	out := make([]float32, len(x))
	for i, v := range x {
		out[i] = float32(v) * (1.0 / 32768.0)
	}
	return out
}

func F32ToI16(x []float32) []int16 {
	out := make([]int16, len(x))
	for i, v := range x {
		s := float32(math.Floor(float64(v * 32768.0)))
		switch {
		case s >= 32767:
			out[i] = 32767
		case s <= -32768:
			out[i] = -32768
		default:
			out[i] = int16(s)
		}
	}
	return out
}

func ToMono(x []float32, ch int) []float32 {
	if ch == 1 {
		return append([]float32(nil), x...)
	}
	n := len(x) / ch
	out := make([]float32, n)
	for i := 0; i < n; i++ {
		var s float32
		for c := 0; c < ch; c++ {
			s += x[i*ch+c]
		}
		out[i] = s / float32(ch)
	}
	return out
}

// ---------------------------------------------------------------- frame

type BadFrameSize struct{ Expected, Got int }

func (e BadFrameSize) Error() string { return fmt.Sprintf("a frame is %d samples, got %d", e.Expected, e.Got) }

type Frame [FrameSamples]float32

func FrameFromSlice(x []float32) (*Frame, error) {
	if len(x) != FrameSamples {
		return nil, BadFrameSize{FrameSamples, len(x)}
	}
	var f Frame
	copy(f[:], x)
	return &f, nil
}

func FrameCount(n int) int {
	c := (n + FrameSamples - 1) / FrameSamples
	if c < 1 {
		c = 1
	}
	return c
}

// ---------------------------------------------------------------- ring

type Ring struct {
	buf  []float32
	r, n int
}

func NewRing(capacity int) *Ring { return &Ring{buf: make([]float32, capacity)} }
func (q *Ring) Len() int        { return q.n }

func (q *Ring) Push(x []float32) error {
	c := len(q.buf)
	if len(x) > c-q.n {
		return errors.New("ring overflow")
	}
	w := (q.r + q.n) % c
	first := min(len(x), c-w)
	copy(q.buf[w:w+first], x[:first])
	copy(q.buf[:len(x)-first], x[first:])
	q.n += len(x)
	return nil
}

func (q *Ring) PopInto(out []float32) error {
	k := len(out)
	if k > q.n {
		return errors.New("ring underflow")
	}
	c := len(q.buf)
	first := min(k, c-q.r)
	copy(out[:first], q.buf[q.r:q.r+first])
	copy(out[first:], q.buf[:k-first])
	q.r = (q.r + k) % c
	q.n -= k
	return nil
}

// ---------------------------------------------------------------- resample (scipy.signal.resample_poly)

func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}

func i0(x float64) float64 {
	sum, term, q := 1.0, 1.0, x*x/4
	for k := 1.0; ; k++ {
		term *= q / (k * k)
		sum += term
		if term < sum*1e-17 {
			return sum
		}
	}
}

func sinc(x float64) float64 {
	if x == 0 {
		return 1
	}
	p := math.Pi * x
	return math.Sin(p) / p
}

func FirwinKaiser(numtaps int, cutoff, beta float64) []float64 {
	alpha := 0.5 * float64(numtaps-1)
	h := make([]float64, numtaps)
	s := 0.0
	for i := range h {
		m := float64(i) - alpha
		r := 2*float64(i)/float64(numtaps-1) - 1
		w := i0(beta*math.Sqrt(math.Max(0, 1-r*r))) / i0(beta)
		h[i] = cutoff * sinc(cutoff*m) * w
		s += h[i]
	}
	for i := range h {
		h[i] /= s
	}
	return h
}

type Polyphase struct {
	up, down, halfLen int
	phases            [][]float32
}

func NewPolyphase(up, down int) *Polyphase {
	g := gcd(up, down)
	up, down = up/g, down/g
	maxRate := max(up, down)
	halfLen := 10 * maxRate
	h64 := FirwinKaiser(2*halfLen+1, 1/float64(maxRate), 5.0)
	h := make([]float32, len(h64))
	for i, v := range h64 {
		h[i] = float32(v) * float32(up)
	}
	phases := make([][]float32, up)
	for p := 0; p < up; p++ {
		var t []float32
		for k := p; k < len(h); k += up {
			t = append(t, h[k])
		}
		for i, j := 0, len(t)-1; i < j; i, j = i+1, j-1 {
			t[i], t[j] = t[j], t[i]
		}
		phases[p] = t
	}
	return &Polyphase{up, down, halfLen, phases}
}

func dot(a, b []float32) float32 {
	var acc [8]float32
	n := len(a) / 8 * 8
	for i := 0; i < n; i += 8 {
		x, y := a[i:i+8:i+8], b[i:i+8:i+8]
		acc[0] += x[0] * y[0]
		acc[1] += x[1] * y[1]
		acc[2] += x[2] * y[2]
		acc[3] += x[3] * y[3]
		acc[4] += x[4] * y[4]
		acc[5] += x[5] * y[5]
		acc[6] += x[6] * y[6]
		acc[7] += x[7] * y[7]
	}
	s := ((acc[0] + acc[4]) + (acc[1] + acc[5])) + ((acc[2] + acc[6]) + (acc[3] + acc[7]))
	for i := n; i < len(a); i++ {
		s += a[i] * b[i]
	}
	return s
}

func (pp *Polyphase) Process(x []float32) []float32 {
	if pp.up == 1 && pp.down == 1 {
		return append([]float32(nil), x...)
	}
	nIn := len(x)
	nOut := (nIn*pp.up + pp.down - 1) / pp.down
	y := make([]float32, nOut)
	for j := 0; j < nOut; j++ {
		c := j*pp.down + pp.halfLen
		taps := pp.phases[c%pp.up]
		iMax := c / pp.up
		iFirst := iMax - len(taps) + 1
		lo, hi := max(iFirst, 0), min(iMax, nIn-1)
		if hi < lo {
			continue
		}
		off := lo - iFirst
		y[j] = dot(x[lo:hi+1], taps[off:off+hi+1-lo])
	}
	return y
}

func To24k(x []float32, rate int) []float32 {
	if rate == SampleRate {
		return append([]float32(nil), x...)
	}
	g := gcd(SampleRate, rate)
	return NewPolyphase(SampleRate/g, rate/g).Process(x)
}

// ---------------------------------------------------------------- wav

type Wav struct {
	Rate, Channels int
	Samples        []float32
}

func DecodeWav(b []byte) (*Wav, error) {
	if len(b) < 12 || string(b[0:4]) != "RIFF" || string(b[8:12]) != "WAVE" {
		return nil, errors.New("not a RIFF/WAVE file")
	}
	var fmtc, data []byte
	for pos := 12; pos+8 <= len(b); {
		id := string(b[pos : pos+4])
		size := int(binary.LittleEndian.Uint32(b[pos+4:]))
		end := min(pos+8+size, len(b))
		if id == "fmt " {
			fmtc = b[pos+8 : end]
		} else if id == "data" {
			data = b[pos+8 : end]
		}
		pos += 8 + size + size&1
	}
	if len(fmtc) < 16 || data == nil {
		return nil, errors.New("missing fmt/data chunk")
	}
	tag := binary.LittleEndian.Uint16(fmtc[0:])
	ch := int(binary.LittleEndian.Uint16(fmtc[2:]))
	rate := int(binary.LittleEndian.Uint32(fmtc[4:]))
	bits := binary.LittleEndian.Uint16(fmtc[14:])
	if tag == 0xFFFE && len(fmtc) >= 26 {
		tag = binary.LittleEndian.Uint16(fmtc[24:])
	}
	var s []float32
	switch {
	case tag == 1 && bits == 16:
		s = make([]float32, len(data)/2)
		for i := range s {
			s[i] = float32(int16(binary.LittleEndian.Uint16(data[2*i:]))) * (1.0 / 32768.0)
		}
	case tag == 3 && bits == 32:
		s = make([]float32, len(data)/4)
		for i := range s {
			s[i] = math.Float32frombits(binary.LittleEndian.Uint32(data[4*i:]))
		}
	default:
		return nil, fmt.Errorf("unsupported WAV format tag %d / %d bits", tag, bits)
	}
	return &Wav{rate, ch, s}, nil
}

func EncodePCM16(rate, ch int, x []float32) []byte {
	dl := len(x) * 2
	out := make([]byte, 44+dl)
	copy(out[0:], "RIFF")
	binary.LittleEndian.PutUint32(out[4:], uint32(36+dl))
	copy(out[8:], "WAVEfmt ")
	binary.LittleEndian.PutUint32(out[16:], 16)
	binary.LittleEndian.PutUint16(out[20:], 1)
	binary.LittleEndian.PutUint16(out[22:], uint16(ch))
	binary.LittleEndian.PutUint32(out[24:], uint32(rate))
	binary.LittleEndian.PutUint32(out[28:], uint32(rate*ch*2))
	binary.LittleEndian.PutUint16(out[32:], uint16(ch*2))
	binary.LittleEndian.PutUint16(out[34:], 16)
	copy(out[36:], "data")
	binary.LittleEndian.PutUint32(out[40:], uint32(dl))
	for i, v := range F32ToI16(x) {
		binary.LittleEndian.PutUint16(out[44+2*i:], uint16(v))
	}
	return out
}

func LoadAudio(path string) ([]float32, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	w, err := DecodeWav(b)
	if err != nil {
		return nil, err
	}
	return To24k(ToMono(w.Samples, w.Channels), w.Rate), nil
}

// ---------------------------------------------------------------- native socket path

func Upsample2xInto(x, out []float32) {
	n := len(x)
	for i := 0; i < n; i++ {
		out[2*i] = x[i]
		if i+1 < n {
			out[2*i+1] = (x[i] + x[i+1]) * 0.5
		} else {
			out[2*i+1] = x[i]
		}
	}
}

func EncodeFrameMsg(index uint32, stepMs float32, pcm []float32, out []byte) []byte {
	payload := 8 + 4*len(pcm)
	var hdr [13]byte
	hdr[0] = MsgFrame
	binary.LittleEndian.PutUint32(hdr[1:], uint32(payload))
	binary.LittleEndian.PutUint32(hdr[5:], index)
	binary.LittleEndian.PutUint32(hdr[9:], math.Float32bits(stepMs))
	out = append(out, hdr[:]...)
	start := len(out)
	out = append(out, make([]byte, 4*len(pcm))...)
	for i, v := range pcm {
		binary.LittleEndian.PutUint32(out[start+4*i:], math.Float32bits(v))
	}
	return out
}

type XorShift32 struct{ S uint32 }

func NewXorShift32() *XorShift32 { return &XorShift32{0x9E3779B9} }
func (r *XorShift32) Next() uint32 {
	s := r.S
	s ^= s << 13
	s ^= s >> 17
	s ^= s << 5
	r.S = s
	return s
}
func (r *XorShift32) ChunkSamples() int { return 240 + int(r.Next()%1681) }

func SimModel(u, out []float32) {
	for i, v := range u {
		o := 0.5 * v
		if o > 1 {
			o = 1
		} else if o < -1 {
			o = -1
		}
		out[i] = o
	}
}

func SpinUntil(deadline time.Time) {
	if d := time.Until(deadline); d > time.Millisecond {
		time.Sleep(d - time.Millisecond)
	}
	for time.Now().Before(deadline) {
	}
}

type Stream struct {
	leftover    float32
	hasLeftover bool
	scratch     []float32
	half        []float32
	in, out     *Ring
	frame       Frame
	reply       Frame
	pcm48       []float32
	block       []float32
	Index       uint32
	Model       time.Duration
	Msgs        []byte
	Drained     int
}

func NewStream(model time.Duration, expected int) *Stream {
	return &Stream{in: NewRing(8 * FrameSamples), out: NewRing(8 * FrameSamples48k), pcm48: make([]float32, FrameSamples48k),
		block: make([]float32, ClientBlock), Index: 1, Model: model, Msgs: make([]byte, 0, expected)}
}

func (s *Stream) emit() {
	SimModel(s.frame[:], s.reply[:])
	if s.Model > 0 {
		SpinUntil(time.Now().Add(s.Model))
	}
	Upsample2xInto(s.reply[:], s.pcm48)
	s.Msgs = EncodeFrameMsg(s.Index, 0, s.pcm48, s.Msgs)
	s.Index++
	if err := s.out.Push(s.pcm48); err != nil {
		panic(err)
	}
	for s.out.Len() >= ClientBlock {
		_ = s.out.PopInto(s.block)
		s.Drained += ClientBlock
	}
}

func (s *Stream) Feed(payload []byte, onFrame func()) {
	s.scratch = s.scratch[:0]
	if s.hasLeftover {
		s.scratch = append(s.scratch, s.leftover)
		s.hasLeftover = false
	}
	for i := 0; i+4 <= len(payload); i += 4 {
		s.scratch = append(s.scratch, math.Float32frombits(binary.LittleEndian.Uint32(payload[i:])))
	}
	even := len(s.scratch) / 2 * 2
	if even < len(s.scratch) {
		s.leftover, s.hasLeftover = s.scratch[even], true
	}
	s.half = s.half[:0]
	for i := 0; i < even; i += 2 {
		s.half = append(s.half, (s.scratch[i]+s.scratch[i+1])/2)
	}
	if len(s.half) == 0 {
		return
	}
	if err := s.in.Push(s.half); err != nil {
		panic(err)
	}
	for s.in.Len() >= FrameSamples {
		_ = s.in.PopInto(s.frame[:])
		s.emit()
		onFrame()
	}
}

func StreamRun(raw []byte, maxFrames int, model time.Duration, first func()) (*Stream, []int64) {
	st := NewStream(model, 2*len(raw)+4096)
	rng := NewXorShift32()
	per := make([]int64, 0, len(raw)/(4*FrameSamples48k)+8)
	var acc int64
	for pos := 0; pos < len(raw); {
		k := rng.ChunkSamples() * 4
		end := min(pos+k, len(raw))
		mark := time.Now()
		st.Feed(raw[pos:end], func() {
			t := time.Now()
			per = append(per, acc+int64(t.Sub(mark)))
			acc, mark = 0, t
			if len(per) == 1 && first != nil {
				first()
			}
		})
		acc += int64(time.Since(mark))
		pos += k
		if maxFrames > 0 && len(per) >= maxFrames {
			break
		}
	}
	return st, per
}

// ---------------------------------------------------------------- stats

func Percentile(sorted []float64, q float64) float64 {
	pos := float64(len(sorted)-1) * q / 100
	lo, hi := int(math.Floor(pos)), int(math.Ceil(pos))
	return sorted[lo] + (sorted[hi]-sorted[lo])*(pos-float64(lo))
}

func Summary(ns []int64) map[string]float64 {
	ms := make([]float64, len(ns))
	sum := 0.0
	for i, v := range ns {
		ms[i] = float64(v) / 1e6
		sum += ms[i]
	}
	sort.Float64s(ms)
	return map[string]float64{"n": float64(len(ms)), "p50_ms": Percentile(ms, 50), "p95_ms": Percentile(ms, 95),
		"p99_ms": Percentile(ms, 99), "max_ms": ms[len(ms)-1], "mean_ms": sum / float64(len(ms))}
}
