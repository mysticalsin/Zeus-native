// haru-pipe (Go port): bench | e2e, same workload and JSON as ../../python/pipe.py.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	hp "echo.local/harupipe/harupipe"
)

type manifest struct {
	Files  []struct{ File string } `json:"files"`
	Stream struct{ File string }   `json:"stream"`
}

func must(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "haru-pipe:", err)
		os.Exit(2)
	}
}

// manifestPath rejects absolute names, empty names, and any ".." element, then
// checks the cleaned path is still inside base.
func manifestPath(base, name string) (string, error) {
	if name == "" || !filepath.IsLocal(name) {
		return "", fmt.Errorf("refusing manifest path %q", name)
	}
	absBase, err := filepath.Abs(base)
	if err != nil {
		return "", err
	}
	absBase = filepath.Clean(absBase)
	full := filepath.Clean(filepath.Join(absBase, name))
	prefix := absBase + string(filepath.Separator)
	if full != absBase && !strings.HasPrefix(full, prefix) {
		return "", fmt.Errorf("refusing manifest path %q", name)
	}
	return full, nil
}

func fileOne(src, dst string) (map[string]any, []int64, float64) {
	t0 := time.Now()
	user, err := hp.LoadAudio(src)
	must(err)
	t1 := time.Now()
	count := hp.FrameCount(len(user))
	user = append(user, make([]float32, count*hp.FrameSamples-len(user))...)
	frames := make([]*hp.Frame, 0, count)
	frames = append(frames, &hp.Frame{})
	per := make([]int64, 0, count)
	for i := 0; i < count-1; i++ {
		a := time.Now()
		f := &hp.Frame{}
		hp.SimModel(user[i*hp.FrameSamples:(i+1)*hp.FrameSamples], f[:])
		frames = append(frames, f)
		per = append(per, int64(time.Since(a)))
	}
	t2 := time.Now()
	stereo := make([]float32, 2*count*hp.FrameSamples)
	for k, f := range frames {
		for i, r := range f {
			n := k*hp.FrameSamples + i
			stereo[2*n], stereo[2*n+1] = user[n], r
		}
	}
	t3 := time.Now()
	must(os.WriteFile(dst, hp.EncodePCM16(hp.SampleRate, 2, stereo), 0o644))
	t4 := time.Now()
	ms := func(a, b time.Time) float64 { return float64(b.Sub(a)) / 1e6 }
	audio := float64(count*hp.FrameSamples) / hp.SampleRate
	return map[string]any{"file": filepath.Base(src), "frames": count, "audio_s": audio, "read_resample_ms": ms(t0, t1),
		"frame_loop_ms": ms(t1, t2), "assemble_ms": ms(t2, t3), "write_ms": ms(t3, t4), "total_ms": ms(t0, t4)}, per, audio
}

func main() {
	if len(os.Args) < 2 {
		must(fmt.Errorf("usage: haru-pipe bench|e2e"))
	}
	fs := flag.NewFlagSet(os.Args[1], flag.ExitOnError)
	wl := fs.String("workload", "", "")
	out := fs.String("out", "", "")
	mode := fs.String("mode", "all", "")
	modelMs := fs.Float64("model-ms", 86.55, "")
	nframes := fs.Int("frames", 40, "")
	must(fs.Parse(os.Args[2:]))
	var man manifest
	b, err := os.ReadFile(filepath.Join(*wl, "manifest.json"))
	must(err)
	must(json.Unmarshal(b, &man))
	if *nframes < 1 {
		must(fmt.Errorf("--frames must be at least 1"))
	}
	res := map[string]any{"impl": "go"}
	rtf := func(wall, audio float64) float64 {
		if audio == 0 {
			must(fmt.Errorf("no audio in workload"))
		}
		return wall / audio
	}
	switch os.Args[1] {
	case "bench":
		if *mode != "all" && *mode != "file" && *mode != "stream" {
			must(fmt.Errorf("bad --mode"))
		}
		must(os.MkdirAll(*out, 0o755))
		if *mode == "all" || *mode == "file" {
			t0 := time.Now()
			var files []map[string]any
			var per []int64
			audio := 0.0
			for _, f := range man.Files {
				src, err := manifestPath(*wl, f.File)
				must(err)
				dst, err := manifestPath(*out, "reply_"+f.File)
				must(err)
				r, p, a := fileOne(src, dst)
				files, per, audio = append(files, r), append(per, p...), audio+a
			}
			wall := time.Since(t0).Seconds()
			res["file"] = map[string]any{"files": files, "wall_s": wall, "audio_s": audio, "rtf": rtf(wall, audio), "per_frame": hp.Summary(per)}
		}
		if *mode == "all" || *mode == "stream" {
			streamPath, err := manifestPath(*wl, man.Stream.File)
			must(err)
			raw, err := os.ReadFile(streamPath)
			must(err)
			framesOut, err := os.Create(filepath.Join(*out, "stream_frames.bin"))
			must(err)
			t0 := time.Now()
			st, per := hp.StreamRunTo(raw, 0, 0, nil, framesOut)
			wall := time.Since(t0).Seconds()
			must(framesOut.Close())
			audio := float64(len(raw)) / 4 / 48000
			res["stream"] = map[string]any{"frames": len(per), "wall_s": wall, "audio_s": audio, "rtf": rtf(wall, audio), "per_frame": hp.Summary(per), "drained_samples": st.Drained}
		}
	case "e2e":
		streamPath, err := manifestPath(*wl, man.Stream.File)
		must(err)
		f, err := os.Open(streamPath)
		must(err)
		raw := make([]byte, *nframes*2*hp.FrameSamples*4+1_000_000)
		n, _ := io.ReadFull(f, raw)
		raw = raw[:n]
		_, per := hp.StreamRun(raw, *nframes, time.Duration(*modelMs*1e6), func() { os.Stdout.WriteString("FIRST_AUDIO\n") })
		s := hp.Summary(per)
		s["overhead_p50_ms"] = s["p50_ms"] - *modelMs
		res["simulated_model_ms"], res["first_audio"] = *modelMs, s
	default:
		must(fmt.Errorf("usage: haru-pipe bench|e2e"))
	}
	enc, err := json.Marshal(res)
	must(err)
	fmt.Println(string(enc))
}
