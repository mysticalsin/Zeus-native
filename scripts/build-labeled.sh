#!/usr/bin/env bash
# Labeled build wrapper. Emits PERMISSION-GATE lines for integrator logs (Accessibility + Screen Recording).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TCC=$(mktemp -t zeus-tcc.XXXXXX.swift)
trap 'rm -f "$TCC"' EXIT
cat >"$TCC" <<'SWIFT'
import ApplicationServices
import AVFoundation
import CoreGraphics
import Speech
let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? 1 : 0
let speech = SFSpeechRecognizer.authorizationStatus() == .authorized ? 1 : 0
let ax = AXIsProcessTrusted() ? 1 : 0
let screen = CGPreflightScreenCaptureAccess() ? 1 : 0
print("PERMISSION-GATE microphone=\(mic)")
print("PERMISSION-GATE speech=\(speech)")
print("PERMISSION-GATE accessibility=\(ax)")
print("PERMISSION-GATE screenRecording=\(screen)")
// Build/packaging performs no capture. Permission remains a runtime gate on explicit capture actions.
SWIFT

/usr/bin/swift "$TCC"
bash scripts/package.sh "$@"
