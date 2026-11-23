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
	// A broken link does not exist, but creating through it would write the target.
	created := filepath.Join(root, "keep", "CREATED.wav")
	if err := os.Symlink(filepath.Join(root, "keep", "missing.wav"), filepath.Join(wl, "subdir", "broken.wav")); err != nil {
		t.Fatal(err)
	}
	runCase(filepath.Join("subdir", "broken.wav"))
	if err := os.WriteFile(filepath.Join(wl, "subdir", "ok.wav"), wav, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(created, filepath.Join(out, "reply_subdir", "ok.wav")); err != nil {
		t.Fatal(err)
	}
	runCase(filepath.Join("subdir", "ok.wav"))
	if _, err := os.Stat(created); !os.IsNotExist(err) {
		t.Fatalf("wrote through a broken symlink: %v", err)
	}
	if err := os.Symlink(filepath.Join(root, "keep"), filepath.Join(wl, "linked")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "keep", "clip.wav"), wav, 0o644); err != nil {
		t.Fatal(err)
	}
	runCase(filepath.Join("linked", "clip.wav"))
	evil := filepath.Join(root, "a", "b", "c", "wl-evil")
	if err := os.MkdirAll(evil, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(evil, "x.wav"), wav, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(evil, "x.wav"), filepath.Join(wl, "subdir", "prefix.wav")); err != nil {
		t.Fatal(err)
	}
	runCase(filepath.Join("subdir", "prefix.wav"))
	if err := os.Symlink("../../../../../keep/SENTINEL", filepath.Join(wl, "subdir", "rel.wav")); err != nil {
		t.Fatal(err)
	}
	runCase(filepath.Join("subdir", "rel.wav"))
	if err := os.MkdirAll(filepath.Join(wl, "via"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(wl, "via", "fresh.wav"), wav, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(root, "keep"), filepath.Join(out, "reply_via")); err != nil {
		t.Fatal(err)
	}
	runCase(filepath.Join("via", "fresh.wav"))
	if _, err := os.Stat(filepath.Join(root, "keep", "fresh.wav")); !os.IsNotExist(err) {
		t.Fatalf("wrote through a directory symlink: %v", err)
	}
	// A link that stays inside the workload is still read.
	if err := os.Symlink("ok.wav", filepath.Join(wl, "subdir", "alias.wav")); err != nil {
		t.Fatal(err)
	}
	writeManifest("m", filepath.Join("subdir", "alias.wav"))
	if c := run(t, "bench", "--workload", wl, "--out", out, "--mode", "file"); c != 0 {
		t.Fatalf("inside symlink exit %d", c)
	}
	got, err := os.ReadFile(sentinel)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "stay" {
		t.Fatalf("sentinel overwritten: %q", got)
	}
	if _, err := os.Stat(created); !os.IsNotExist(err) {
		t.Fatalf("inside symlink wrote outside: %v", err)
	}
	if _, err := os.Stat(filepath.Join(out, "reply_subdir", "alias.wav")); err != nil {
		t.Fatal(err)
	}
}
