package main

import (
	"bytes"
	encbin "encoding/binary"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

var binary string

func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "haru-cli")
	if err != nil {
		panic(err)
	}
	binary = filepath.Join(dir, "haru-pipe")
	cmd := exec.Command("go", "build", "-o", binary, ".")
	out, err := cmd.CombinedOutput()
	if err != nil {
		panic(string(out) + err.Error())
	}
	code := m.Run()
	os.RemoveAll(dir)
	os.Exit(code)
}

func run(t *testing.T, args ...string) int {
	t.Helper()
	cmd := exec.Command(binary, args...)
	err := cmd.Run()
	if err == nil {
		return 0
	}
	if ee, ok := err.(*exec.ExitError); ok {
		return ee.ExitCode()
	}
	t.Fatal(err)
	return -1
}

func TestBadModeAndEmptyAudioExit2(t *testing.T) {
	root := t.TempDir()
	wl := filepath.Join(root, "wl")
	out := filepath.Join(root, "out")
	if err := os.MkdirAll(wl, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(wl, "manifest.json"), []byte(`{"files":[],"stream":{"file":"s.f32"}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(wl, "s.f32"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if c := run(t, "bench", "--workload", wl, "--out", out, "--mode", "nope"); c != 2 {
		t.Fatalf("bad mode exit %d", c)
	}
	if c := run(t, "nope", "--workload", wl, "--out", out); c != 2 {
		t.Fatalf("unknown command exit %d", c)
	}
	if c := run(t, "bench", "--workload", wl, "--out", out, "--mode", "stream"); c != 2 {
		t.Fatalf("empty stream exit %d", c)
	}
	if c := run(t, "e2e", "--workload", wl, "--frames", "-1"); c != 2 {
		t.Fatalf("negative frames exit %d", c)
	}
}

func wavPCM() []byte {
	data := []byte{0, 0, 0, 0x40}
	fmtc := make([]byte, 16)
	encbin.LittleEndian.PutUint16(fmtc[0:], 1)
	encbin.LittleEndian.PutUint16(fmtc[2:], 1)
	encbin.LittleEndian.PutUint32(fmtc[4:], 24000)
	encbin.LittleEndian.PutUint32(fmtc[8:], 48000)
	encbin.LittleEndian.PutUint16(fmtc[12:], 2)
	encbin.LittleEndian.PutUint16(fmtc[14:], 16)
	chunk := func(id string, body []byte) []byte {
		b := append([]byte(id), make([]byte, 4)...)
		encbin.LittleEndian.PutUint32(b[4:], uint32(len(body)))
		return append(b, body...)
	}
	body := append(chunk("fmt ", fmtc), chunk("data", data)...)
	out := append([]byte("RIFF"), make([]byte, 4)...)
	encbin.LittleEndian.PutUint32(out[4:], uint32(4+len(body)))
	return append(append(out, []byte("WAVE")...), body...)
}

func TestManifestEscapeRefused(t *testing.T) {
	root := t.TempDir()
	wl := filepath.Join(root, "a", "b", "c", "wl")
	out := filepath.Join(root, "a", "b", "out")
	if err := os.MkdirAll(filepath.Join(wl, "subdir"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(out, "reply_subdir"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(root, "a", "keep"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(root, "keep"), 0o755); err != nil {
		t.Fatal(err)
	}
	wav := wavPCM()
	readAt := filepath.Join(root, "a", "keep", "SENTINEL")
	sentinel := filepath.Join(root, "keep", "SENTINEL")
	absWav := filepath.Join(root, "abs.wav")
	if err := os.WriteFile(readAt, wav, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(sentinel, []byte("stay"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(absWav, wav, 0o644); err != nil {
		t.Fatal(err)
	}
	writeManifest := func(name, file string) {
		t.Helper()
		body := fmt.Sprintf("{\"files\":[{\"file\":%q}],\"stream\":{\"file\":\"unused.f32\"}}\n", file)
		if err := os.WriteFile(filepath.Join(wl, "manifest.json"), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	runCase := func(file string) {
		t.Helper()
		writeManifest("m", file)
		cmd := exec.Command(binary, "bench", "--workload", wl, "--out", out, "--mode", "file")
		raw, err := cmd.CombinedOutput()
		code := 0
		if err != nil {
			if ee, ok := err.(*exec.ExitError); ok {
				code = ee.ExitCode()
			} else {
				t.Fatal(err)
			}
		}
		if code != 2 || !bytes.Contains(raw, []byte("refusing manifest path")) {
			t.Fatalf("file %q exit %d output %s", file, code, raw)
		}
		got, err := os.ReadFile(sentinel)
		if err != nil {
			t.Fatal(err)
		}
		if string(got) != "stay" {
			t.Fatalf("sentinel overwritten: %q", got)
		}
	}
	runCase("subdir/../../../../keep/SENTINEL")
	runCase(absWav)
	runCase("")
	link := filepath.Join(wl, "subdir", "escape.wav")
	if err := os.Symlink(sentinel, link); err != nil {
		t.Fatal(err)
	}
	runCase(filepath.Join("subdir", "escape.wav"))
}
