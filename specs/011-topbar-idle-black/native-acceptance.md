# Quiet top bar, pitch black

Mac acceptance for the idle top bar. This file is the run. It does not install Zeus, it does not start `/Applications/Zeus.app`, and it does not add a dependency or a CI job.

There is no Xcode project and no XCUITest target, so this run does not use XCUITest. There is no snapshot harness for a live menu-bar window, so this run does not add one. Linux cannot compile or launch the app. A unit test of the chrome model is not this run.

Build from a detached clone. Do not call `scripts/install.sh`.

```sh
git clone https://github.com/mysticalsin/Zeus-native.git "$HOME/zeus-idle-black-clone"
cd "$HOME/zeus-idle-black-clone"
git fetch origin zeus-bot/topbar-idle-black
git switch --detach origin/zeus-bot/topbar-idle-black
scripts/bundle.sh
```

Launch `build/Zeus.app/Contents/MacOS/Zeus` from that clone. Quit any other copy first so only one process is drawing bars.

## What must be true

The pointer is not over the bar, and nothing is asking for attention (no approval, recording, music wing, dictation, cue, focus timer, alert, light, or non-idle character activity).

- The bar background is sRGB `#000000`, alpha 1. Sampled pixels are `0, 0, 0`.
- No glass blur, material, vibrancy, gradient, tint, translucency, shadow or grey on that background.
- The only drawn content is the selected character. Classic shows the Zeus mascot. Orb (Jarvis) shows the Jarvis orb.
- Moving the pointer onto the bar restores the existing hover drawing, then the existing open animation. Moving it away returns to the quiet bar with the existing close animation.
- Reduce Motion keeps those same end states and does not play the spring. The existing motion path already drops the spring when Reduce Motion is on.
- Each display has one bar. The process opens no extra window.

Attention that already shows while the pointer is away stays. This run does not delete it. See the open question in the pull request.

## Capture

Record the previous wallpaper and accessibility values, and put them back at the end. Toggle them in System Settings. Do not script a permission prompt.

Do this whole matrix:

| Character | Wallpaper | Reduce Transparency | Reduce Motion |
|---|---|---|---|
| Classic (Zeus) | light | off | off |
| Classic (Zeus) | dark | off | off |
| Classic (Zeus) | light | on | off |
| Classic (Zeus) | dark | on | off |
| Orb (Jarvis) | light | off | off |
| Orb (Jarvis) | dark | off | off |
| Orb (Jarvis) | light | on | off |
| Orb (Jarvis) | dark | on | on |

For each cell, with the pointer in the middle of the display and the bar quiet:

```sh
OUT="$HOME/zeus-idle-black-evidence"
mkdir -p "$OUT"
# x,y,w,h are the bar's rectangle in global points, one capture per display.
screencapture -x -R "$X,$Y,$W,$H" "$OUT/$NAME.png"
```

Sample the bar background. Skip the character's pixels. Every other pixel in the bar rectangle must be `0, 0, 0`. The sampler uses the Python standard library. It walks the PNG filters and prints the first pixel that is not `0,0,0`, or `pass` with the count of background pixels. The operator marks the character box and the sampler ignores that box.

```sh
python3 - "$OUT/$NAME.png" "$CHAR_X" "$CHAR_Y" "$CHAR_W" "$CHAR_H" << 'PY'
import struct, sys, zlib
path, cx, cy, cw, ch = sys.argv[1:]
cx, cy, cw, ch = map(int, (cx, cy, cw, ch))
data = open(path, "rb").read()
assert data[:8] == b"\x89PNG\r\n\x1a\n"
pos, width, height, color, raw = 8, 0, 0, 0, b""
while pos + 8 <= len(data):
    length, kind = struct.unpack(">I4s", data[pos:pos+8])
    chunk = data[pos+8:pos+8+length]
    if kind == b"IHDR":
        width, height, depth, color, comp, filt, interlace = struct.unpack(">IIBBBBB", chunk)
        assert depth == 8 and color in (2, 6) and (comp, filt, interlace) == (0, 0, 0)
    elif kind == b"IDAT":
        raw += chunk
    pos += 12 + length
    if kind == b"IEND":
        break
blob = zlib.decompress(raw)
channels = 4 if color == 6 else 3
stride = width * channels
rows, i = [], 0
prev = bytearray(stride)
for _ in range(height):
    filt = blob[i]
    i += 1
    row = bytearray(blob[i:i+stride])
    i += stride
    if filt == 1:
        for p in range(channels, stride):
            row[p] = (row[p] + row[p - channels]) & 255
    elif filt == 2:
        for p in range(stride):
            row[p] = (row[p] + prev[p]) & 255
    elif filt == 3:
        for p in range(stride):
            left = row[p - channels] if p >= channels else 0
            row[p] = (row[p] + ((left + prev[p]) // 2)) & 255
    elif filt == 4:
        def paeth(a, b, c):
            est = a + b - c
            da, db, dc = abs(est-a), abs(est-b), abs(est-c)
            return a if da <= db and da <= dc else b if db <= dc else c
        for p in range(stride):
            left = row[p - channels] if p >= channels else 0
            up = prev[p]
            ul = prev[p - channels] if p >= channels else 0
            row[p] = (row[p] + paeth(left, up, ul)) & 255
    elif filt != 0:
        raise SystemExit(f"bad filter {filt}")
    rows.append(row)
    prev = row
bad = 0
seen = 0
for y, row in enumerate(rows):
    for x in range(width):
        if cx <= x < cx + cw and cy <= y < cy + ch:
            continue
        o = x * channels
        pixel = tuple(row[o:o+3])
        seen += 1
        if pixel != (0, 0, 0):
            bad += 1
            if bad == 1:
                print(f"fail {path} first {x},{y} rgb {pixel}")
print(("fail" if bad else "pass"), path, "background", seen, "bad", bad)
raise SystemExit(1 if bad else 0)
PY
```

`screencapture` writes device pixels. `$CHAR_*` is the character's box in that image, not in points. Cover the mascot or the orb and nothing else. A pass with `bad 0` is the proof. One grey pixel fails the cell.

The bar must fail this sample on a build from `012ba6038fbc3653e70a687fb72aee02b31147fb` and pass on this branch. Keep both PNGs.

## Hover

On the Classic, light wallpaper, Reduce Transparency off, Reduce Motion off cell:

1. Capture the quiet bar (`hover-out-before.png`).
2. Move the pointer onto the bar and capture during the open (`hover-in-1.png`, `hover-in-2.png`, `hover-in-3.png`, about one frame apart). The bar must grow with the existing open motion and show the existing open drawing, not a new one.
3. Move the pointer to the middle of the display and capture during the close (`hover-out-1.png`, `hover-out-2.png`, `hover-out-3.png`). It must return to the quiet bar.
4. Turn Reduce Motion on and repeat. The end states match. The frames do not show the spring travelling; the existing Reduce Motion path removes it.

Do not add a new animation to make these frames easier to catch.

## Displays and windows

With two or more displays connected, each display has one bar at its top. Capture each. There is not a second bar on any display.

Count the process's windows after launch, with the bar quiet and no settings window opened:

```sh
osascript -e 'tell application "System Events" to get name of every window of (first process whose unix id is '"$(pgrep -n Zeus)"')'
```

The quiet process shows no extra window. A settings window, a chat window, or a second island fails the run.

## Done

Write `summary.txt` with the head sha, each cell's `pass` line, the hover frame names, the window list, and the display count. This run is still required after the unit tests pass. A Linux result does not replace it.
