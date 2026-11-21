package main

import (
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
