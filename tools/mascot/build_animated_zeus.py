#!/usr/bin/env python3
"""
ZEUS Mascot v2.5 — 2.5D Puppet Rig Compiler, Pose Registration & Batch Animation Exporter.

Idempotent, deterministic asset pipeline derived purely from the pack directory:
1. Preserves all original v2 pack files untouched (SHA256SUMS.txt remains 100% valid).
2. Segments & inpaints `assets/poses/idle.png` + expression donors into 23 clean RGBA puppet
   layers (`assets/rig/*.png`) for real-time 60fps skeletal/spring animation.
3. Computes canonical ground-line & head-scale registration + open-eye landmarks across all
   25 poses into `rig-metadata.json`.
4. Batch-renders transparent animated WebP (`exports/webp/*.webp`), animated APNG
   (`exports/apng/*.png`), and sprite-sheet atlases (`exports/sprites/*`) for all 24 states
   plus a 2.5D Puppet showcase clip.

Zeus integration (finished from Tony's draft):
- The pack is read-only. Derived files go to `--out` (outside the pack); the run ends by re-checking the
  pack's own SHA256SUMS.txt.
- `--export-size 128 320` writes, per manifest state, a PNG sprite atlas per cell size plus JSON frame
  metadata (`<atlas-out>/<size>/<state>.png`, `<atlas-out>/<state>.json`, `index.json`), timed from
  manifest.json (loop / one-shot, seconds) at 12-24 fps. Zeus ships these in Sources/Zeus/Avatar/Anim.
- WebP/APNG previews are optional (`--preview-dir`, keep it out of the repo).

    python3 -m venv /tmp/zeus-mascot-venv && /tmp/zeus-mascot-venv/bin/pip install -r tools/mascot/requirements.txt
    /tmp/zeus-mascot-venv/bin/python tools/mascot/build_animated_zeus.py \\
        --pack Design/mascot-v2/ZEUS_Mascot_Pack_v2 --out /tmp/zeus-mascot-out \\
        --atlas-out Sources/Zeus/Avatar/Anim --preview-dir /tmp/zeus-mascot-preview --qa-out /tmp/zeus-qa.png
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

CANVAS = 1254
CANONICAL_GROUND_Y = 1194
CANONICAL_CENTER_X = 635.0
CANONICAL_HEAD_W = 934.0

# The "world" the frame compositor draws in: the 1254 px pose canvas plus optional padding on every side,
# so hops, raised arms and Zzz can travel past the pose canvas without being clipped. Set by
# `world_padding()` for atlas exports; the default (no padding) is the plain pose canvas.
WORLD = float(CANVAS)
ORIGIN = 0.0


def world_padding(pad: int) -> None:
    global WORLD, ORIGIN
    WORLD = float(CANVAS + 2 * pad)
    ORIGIN = float(pad)


def premult_safe_rgb(img_rgba: np.ndarray, fill_rgb: tuple[int, int, int] = (252, 242, 226)) -> np.ndarray:
    """Propagate opaque boundary colors into transparent pixels so blurs/inpaints never bleed black."""
    out_rgb = img_rgba[:, :, :3].copy()
    empty = img_rgba[:, :, 3] < 48
    opaque = (img_rgba[:, :, 3] >= 48).astype(np.uint8) * 255
    near = cv2.dilate(opaque, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (35, 35))) > 0
    zone = (empty & near).astype(np.uint8) * 255
    bgr = cv2.cvtColor(out_rgb, cv2.COLOR_RGB2BGR)
    bgr[empty] = fill_rgb[::-1]
    if np.any(zone):
        bgr = cv2.inpaint(bgr, zone, 9, cv2.INPAINT_TELEA)
    return cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)


def extract_soft_layer(
    img_rgba: np.ndarray,
    mask_bool: np.ndarray,
    dilate_px: int = 2,
    feather_px: float = 1.2,
    safe_rgb: np.ndarray | None = None,
) -> np.ndarray:
    m = mask_bool.astype(np.uint8) * 255
    if dilate_px > 0:
        k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (dilate_px * 2 + 1, dilate_px * 2 + 1))
        m = cv2.dilate(m, k)
    m_f = cv2.GaussianBlur(m.astype(np.float32), (0, 0), feather_px) if feather_px > 0 else m.astype(np.float32)
    out = np.zeros_like(img_rgba)
    out[:, :, :3] = safe_rgb if safe_rgb is not None else img_rgba[:, :, :3]
    orig_a = img_rgba[:, :, 3].astype(np.float32)
    new_a = np.minimum(orig_a, (m_f / 255.0) * orig_a * 1.06)
    out[:, :, 3] = np.clip(new_a, 0, 255).astype(np.uint8)
    out[out[:, :, 3] < 3] = 0
    return out


def inpaint_mochi(
    img_rgba: np.ndarray,
    hole_mask_bool: np.ndarray,
    dilate_px: int = 9,
    fill_rgb: tuple[int, int, int] = (252, 242, 226),
    smooth_sigma: float = 5.0,
) -> np.ndarray:
    c_rgb = premult_safe_rgb(img_rgba, fill_rgb=fill_rgb)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (dilate_px * 2 + 1, dilate_px * 2 + 1))
    m = cv2.dilate(hole_mask_bool.astype(np.uint8) * 255, k)
    bgr = cv2.cvtColor(c_rgb, cv2.COLOR_RGB2BGR)
    inp = cv2.inpaint(bgr, m, inpaintRadius=16, flags=cv2.INPAINT_TELEA)
    blur = cv2.GaussianBlur(inp, (0, 0), smooth_sigma)
    w = cv2.GaussianBlur((m > 0).astype(np.float32), (0, 0), 4.0)[:, :, None]
    blended = (inp * 0.35 + blur * 0.65) * w + bgr * (1.0 - w)
    out = img_rgba.copy()
    out[:, :, :3] = cv2.cvtColor(np.clip(blended, 0, 255).astype(np.uint8), cv2.COLOR_BGR2RGB)
    return out


def save_cropped_layer(
    layer_rgba: np.ndarray,
    out_path: Path,
    pivot_xy: tuple[float, float] | None = None,
    pad: int = 6,
) -> dict[str, Any]:
    ys, xs = np.where(layer_rgba[:, :, 3] > 2)
    if len(xs) == 0:
        raise ValueError(f"Empty layer for {out_path.name}")
    H, W = layer_rgba.shape[:2]
    x0 = max(0, int(xs.min()) - pad)
    y0 = max(0, int(ys.min()) - pad)
    x1 = min(W, int(xs.max()) + 1 + pad)
    y1 = min(H, int(ys.max()) + 1 + pad)
    cropped = layer_rgba[y0:y1, x0:x1]
    out_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(cropped).save(out_path, optimize=True)
    px, py = pivot_xy if pivot_xy is not None else ((x0 + x1) * 0.5, (y0 + y1) * 0.5)
    return {
        "file": f"assets/rig/{out_path.name}",
        "x": x0,
        "y": y0,
        "w": x1 - x0,
        "h": y1 - y0,
        "pivotX": round(float(px), 2),
        "pivotY": round(float(py), 2),
    }


def extract_puppet_rig(pack_dir: Path, out_dir: Path) -> dict[str, Any]:
    """Segment the pack into puppet layers. Reads `pack_dir` only; writes layers under `out_dir/assets/rig`."""
    poses_dir = pack_dir / "assets" / "poses"
    rig_dir = out_dir / "assets" / "rig"
    rig_dir.mkdir(parents=True, exist_ok=True)

    idle = np.array(Image.open(poses_dir / "idle.png").convert("RGBA"))
    H, W = idle.shape[:2]
    rgb = idle[:, :, :3]
    alpha = idle[:, :, 3]
    fg = alpha > 12
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    yy, xx = np.mgrid[0:H, 0:W]
    safe_c = premult_safe_rgb(idle)

    # 1. Eyes: sclera + upper lash + movable blue iris + specular catchlights
    is_non_skin_face = fg & (
        (rgb[:, :, 0].astype(int) - rgb[:, :, 2].astype(int) < 18)
        | (hsv[:, :, 2] < 198)
        | ((hsv[:, :, 0] >= 88) & (hsv[:, :, 0] <= 142) & (hsv[:, :, 1] >= 35))
    )

    def clean_eye_mask(x0: int, x1: int, y0: int, y1: int) -> np.ndarray:
        roi = (xx >= x0) & (xx <= x1) & (yy >= y0) & (yy <= y1)
        m = (is_non_skin_face & roi).astype(np.uint8) * 255
        m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13, 13)))
        cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        filled = np.zeros_like(m)
        for c in cnts:
            if cv2.contourArea(c) > 25:
                cv2.drawContours(filled, [c], -1, 255, -1)
        return filled > 0

    eye_l_mask = clean_eye_mask(386, 545, 516, 682)
    eye_r_mask = clean_eye_mask(700, 864, 570, 738)

    def decompose_eye(eye_mask: np.ndarray, side: str) -> dict[str, Any]:
        # Fit circle to deep-blue iris pixels
        blue_px = eye_mask & (hsv[:, :, 0] >= 96) & (hsv[:, :, 0] <= 134) & (hsv[:, :, 1] >= 75)
        cnts, _ = cv2.findContours(blue_px.astype(np.uint8) * 255, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        (icx, icy), irad = cv2.minEnclosingCircle(max(cnts, key=cv2.contourArea))
        iris_disc = (((xx - icx) ** 2 + (yy - icy) ** 2) <= (irad * 0.99) ** 2) & eye_mask

        # White catchlights inside the iris disc (high V, low S)
        catch_mask = iris_disc & (hsv[:, :, 2] > 215) & (hsv[:, :, 1] < 65)
        catch_layer = extract_soft_layer(idle, catch_mask, dilate_px=1, feather_px=0.9, safe_rgb=safe_c)

        # Iris without catchlights (inpainted deep sapphire so catchlights can counter-parallax!)
        iris_no_catch = inpaint_mochi(idle, catch_mask, dilate_px=3, fill_rgb=(18, 52, 138), smooth_sigma=2.2)
        iris_layer = extract_soft_layer(iris_no_catch, iris_disc, dilate_px=1, feather_px=1.0)

        # Upper dark lash line (dark pixels near the upper rim of eye_mask, outside inner iris core)
        inner_iris = ((xx - icx) ** 2 + (yy - icy) ** 2) <= (irad * 0.84) ** 2
        ey_ys, ey_xs = np.where(eye_mask)
        ey_mid_y = (ey_ys.min() + ey_ys.max()) * 0.56
        lash_mask = eye_mask & ~inner_iris & (hsv[:, :, 2] < 115) & (yy < ey_mid_y + 22)
        lash_layer = extract_soft_layer(idle, lash_mask, dilate_px=1, feather_px=0.9, safe_rgb=safe_c)

        # Clean cool-white sclera base filling the entire eye socket so iris can move freely inside it!
        sclera = np.zeros_like(idle)
        # Soft vertical shading from cool pale blue-grey at top (for 3D eyeball depth) to crisp white below
        rel_y = np.clip((yy - ey_ys.min()) / max(1.0, float(ey_ys.max() - ey_ys.min())), 0.0, 1.0)
        sclera[:, :, 0] = np.clip(226 + rel_y * 26, 0, 255).astype(np.uint8)
        sclera[:, :, 1] = np.clip(231 + rel_y * 22, 0, 255).astype(np.uint8)
        sclera[:, :, 2] = np.clip(242 + rel_y * 12, 0, 255).astype(np.uint8)
        m_f = cv2.GaussianBlur(eye_mask.astype(np.float32) * 255.0, (0, 0), 1.1)
        sclera[:, :, 3] = np.clip(m_f, 0, 255).astype(np.uint8)

        return {
            "sclera": save_cropped_layer(sclera, rig_dir / f"eye_sclera_{side}.png", (icx, icy)),
            "iris": save_cropped_layer(iris_layer, rig_dir / f"iris_{side}.png", (icx, icy)),
            "catchlight": save_cropped_layer(catch_layer, rig_dir / f"catchlight_{side}.png", (icx, icy)),
            "lash": save_cropped_layer(lash_layer, rig_dir / f"eye_lash_{side}.png", (icx, icy)),
            "center": [round(float(icx), 2), round(float(icy), 2)],
            "radius": round(float(irad), 2),
            "socketBBox": [int(ey_xs.min()), int(ey_ys.min()), int(ey_xs.max() - ey_xs.min()), int(ey_ys.max() - ey_ys.min())],
        }

    eye_left_meta = decompose_eye(eye_l_mask, "left")
    eye_right_meta = decompose_eye(eye_r_mask, "right")

    # Happy `^ ^` closed eye arcs extracted from grateful.png and aligned to idle's eye centers!
    grateful = np.array(Image.open(poses_dir / "grateful.png").convert("RGBA"))
    ghsv = cv2.cvtColor(grateful[:, :, :3], cv2.COLOR_RGB2HSV)
    gfg = grateful[:, :, 3] > 24
    # Closed eye arcs in grateful: y in 530..670, warm cocoa brown only (exclude cobalt scarf H~110)
    garcs = gfg & (yy >= 530) & (yy <= 670) & (ghsv[:, :, 2] < 140) & (ghsv[:, :, 0] < 45)
    gnl, glb, gst, gct = cv2.connectedComponentsWithStats(garcs.astype(np.uint8))
    arc_comps = [(gct[i, 0], gct[i, 1], glb == i) for i in range(1, gnl) if gst[i, 4] > 600]
    arc_comps.sort(key=lambda c: c[0])
    gsafe = premult_safe_rgb(grateful)
    for side, comp, target_meta in [("left", arc_comps[0], eye_left_meta), ("right", arc_comps[-1], eye_right_meta)]:
        arc_raw = extract_soft_layer(grateful, comp[2], dilate_px=2, feather_px=1.1, safe_rgb=gsafe)
        dx = int(round(target_meta["center"][0] - comp[0]))
        dy = int(round(target_meta["center"][1] - comp[1]))
        M = np.float32([[1, 0, dx], [0, 1, dy]])
        arc_aligned = cv2.warpAffine(arc_raw, M, (W, H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0))
        target_meta["happyArc"] = save_cropped_layer(arc_aligned, rig_dir / f"eye_happy_{side}.png", tuple(target_meta["center"]))

    # 2. Eyebrows (strictly outside dilated eye sockets)
    eyes_dil = cv2.dilate((eye_l_mask | eye_r_mask).astype(np.uint8) * 255, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (17, 17))) > 0
    brow_cand = fg & ~eyes_dil & (yy >= 430) & (yy <= 580) & (hsv[:, :, 2] < 148) & (hsv[:, :, 1] < 175)
    nl, lb, st, ct = cv2.connectedComponentsWithStats(brow_cand.astype(np.uint8))
    brows = [(ct[i, 0], ct[i, 1], lb == i) for i in range(1, nl) if st[i, 4] > 450]
    brows.sort(key=lambda b: b[0])
    brow_l_mask, brow_r_mask = brows[0][2], brows[1][2]
    brow_left_meta = save_cropped_layer(
        extract_soft_layer(idle, brow_l_mask, dilate_px=2, feather_px=1.1, safe_rgb=safe_c),
        rig_dir / "brow_left.png",
        (brows[0][0], brows[0][1]),
    )
    brow_right_meta = save_cropped_layer(
        extract_soft_layer(idle, brow_r_mask, dilate_px=2, feather_px=1.1, safe_rgb=safe_c),
        rig_dir / "brow_right.png",
        (brows[1][0], brows[1][1]),
    )

    # 3. Golden lightning bolt tuft (pivot at base tip where bolt joins cloud dome)
    bolt_seed = fg & (hsv[:, :, 0] >= 10) & (hsv[:, :, 0] <= 36) & (hsv[:, :, 1] >= 48) & (yy < 365)
    nl, lb, st, _ = cv2.connectedComponentsWithStats(bolt_seed.astype(np.uint8))
    bolt_mask = (lb == (1 + np.argmax(st[1:, 4]))) | (fg & (yy < 165) & (xx > 540) & (xx < 830))
    bys, bxs = np.where(bolt_mask)
    bolt_base_y = int(bys.max())
    bolt_base_x = float(bxs[bys >= bolt_base_y - 12].mean())
    bolt_meta = save_cropped_layer(
        extract_soft_layer(idle, bolt_mask, dilate_px=2, feather_px=1.1, safe_rgb=safe_c),
        rig_dir / "bolt.png",
        (bolt_base_x, bolt_base_y - 8),
    )

    # 4. Mouth visemes: idle happy open, gentle smile (listening), tiny smirk (thinking), round O (surprised), worried (error), closed mm
    def extract_donor_mouth(pose_name: str, roi_box: tuple[int, int, int, int]) -> tuple[np.ndarray, tuple[float, float], np.ndarray]:
        im = np.array(Image.open(poses_dir / f"{pose_name}.png").convert("RGBA"))
        irgb = im[:, :, :3]
        ihsv = cv2.cvtColor(irgb, cv2.COLOR_RGB2HSV)
        ifg = im[:, :, 3] > 24
        x0, x1, y0, y1 = roi_box
        roi = (xx >= x0) & (xx <= x1) & (yy >= y0) & (yy <= y1)
        rg_d = irgb[:, :, 0].astype(int) - irgb[:, :, 1].astype(int)
        raw = ifg & roi & ((rg_d > 34) | (ihsv[:, :, 2] < 172))
        k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        raw_u8 = cv2.morphologyEx(raw.astype(np.uint8) * 255, cv2.MORPH_CLOSE, k)
        cnts, _ = cv2.findContours(raw_u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        m = np.zeros((H, W), dtype=np.uint8)
        cv2.drawContours(m, [max(cnts, key=cv2.contourArea)], -1, 255, -1)
        m_bool = m > 0
        mys, mxs = np.where(m_bool)
        center = (float(mxs.mean()), float(mys.mean()))
        layer = extract_soft_layer(im, m_bool, dilate_px=2, feather_px=1.1, safe_rgb=premult_safe_rgb(im))
        return layer, center, m_bool

    idle_mouth_layer, mouth_anchor, mouth_mask = extract_donor_mouth("idle", (535, 675, 655, 758))
    mouths_meta: dict[str, Any] = {}
    mouths_meta["happy"] = save_cropped_layer(idle_mouth_layer, rig_dir / "mouth_happy.png", mouth_anchor)

    for key, donor, box in [
        ("smile", "listening", (530, 680, 645, 745)),
        ("smirk", "thinking", (545, 650, 645, 735)),
        ("ooh", "surprised", (560, 665, 630, 735)),
        ("worried", "error", (540, 675, 655, 745)),
    ]:
        mlayer, mcent, _ = extract_donor_mouth(donor, box)
        dx = int(round(mouth_anchor[0] - mcent[0]))
        dy = int(round(mouth_anchor[1] - mcent[1]))
        M = np.float32([[1, 0, dx], [0, 1, dy]])
        aligned = cv2.warpAffine(mlayer, M, (W, H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0))
        mouths_meta[key] = save_cropped_layer(aligned, rig_dir / f"mouth_{key}.png", mouth_anchor)

    # Create a crisp soft-shaded closed 'mm' consonant mouth curve aligned to mouth_anchor
    mm_canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    mm_draw = ImageDraw.Draw(mm_canvas)
    mcx, mcy = mouth_anchor
    mm_draw.arc([mcx - 28, mcy - 12, mcx + 28, mcy + 8], start=15, end=165, fill=(92, 46, 36, 235), width=8)
    mm_canvas = mm_canvas.filter(ImageFilter.GaussianBlur(0.8))
    mouths_meta["closed"] = save_cropped_layer(np.array(mm_canvas), rig_dir / "mouth_closed.png", mouth_anchor)

    # 5. Cobalt Scarf: collar+knot vs spring-swinging hanging tail
    scarf_all = fg & (hsv[:, :, 0] >= 96) & (hsv[:, :, 0] <= 132) & (hsv[:, :, 1] >= 80) & (yy >= 700)
    # Tail hangs below the knot (y >= 884, x <= 688)
    scarf_tail_mask = scarf_all & (yy >= 880) & ((xx <= 686) | (yy >= 904))
    # Keep a small rounded overlap at the top of the tail so rotating +/-18 deg never exposes a gap under the knot
    scarf_collar_mask = scarf_all & ~(scarf_tail_mask & (yy >= 896))
    scarf_safe = premult_safe_rgb(idle, fill_rgb=(21, 87, 231))
    scarf_collar_meta = save_cropped_layer(
        extract_soft_layer(idle, scarf_collar_mask, dilate_px=2, feather_px=1.0, safe_rgb=scarf_safe),
        rig_dir / "scarf_collar.png",
        (658.0, 858.0),
    )
    scarf_tail_meta = save_cropped_layer(
        extract_soft_layer(idle, scarf_tail_mask, dilate_px=2, feather_px=1.0, safe_rgb=scarf_safe),
        rig_dir / "scarf_tail.png",
        (652.0, 886.0),
    )

    # 6. Seamless Head (cloud dome + BOTH cheeks intact, zero step jump!)
    # Follow smooth angled head-neck contour from left cheek bottom (x=420, y=792) to right cheek bottom (x=780, y=872)
    neck_slope_y = 790.0 + np.clip((np.arange(W) - 420.0) / (780.0 - 420.0), 0.0, 1.0) * (872.0 - 790.0)
    # Along the scarf span (435..755), follow scarf top + 6px so head tucks cleanly into the scarf collar
    scarf_top_x, scarf_top_y = [], []
    for sx in range(435, 745, 5):
        sys = np.where(scarf_all[:, sx])[0]
        if len(sys):
            scarf_top_x.append(sx)
            scarf_top_y.append(int(sys.min()))
    scarf_interp = np.interp(np.arange(W), scarf_top_x, scarf_top_y)
    # Blend smoothly outside x=745 so right cheek (x > 745, extending down to y=872) stays 100% on the head!
    head_cut_y = neck_slope_y.copy()
    in_scarf = (np.arange(W) >= 432) & (np.arange(W) <= 742)
    head_cut_y[in_scarf] = np.maximum(scarf_interp[in_scarf] + 6.0, neck_slope_y[in_scarf] - 10.0)
    head_cut_y[743:] = 876.0  # Keep full right cheek & right cloud lobe on head!
    head_cut_y[:432] = 796.0  # Keep full left cheek & left cloud lobe on head!
    head_cut_y = cv2.GaussianBlur(head_cut_y.reshape(1, -1).astype(np.float32), (31, 1), 8.0).ravel()

    head_mask = fg & (yy <= head_cut_y[None, :]) & ~scarf_all

    # Remove bolt tip above dome polynomial and inpaint features into creamy mochi ivory
    dome_pts_x, dome_pts_y = [], []
    for dx in list(range(430, 550, 4)) + list(range(808, 890, 4)):
        col_ys = np.where(fg[:, dx] & ~bolt_mask[:, dx])[0]
        if len(col_ys):
            dome_pts_x.append(dx)
            dome_pts_y.append(int(col_ys.min()))
    dome_poly = np.poly1d(np.polyfit(dome_pts_x, dome_pts_y, 2))
    dome_limit_y = dome_poly(np.arange(W))[None, :]
    bolt_above = bolt_mask & (yy < dome_limit_y + 2)
    bolt_on_dome = bolt_mask & ~bolt_above

    head_blank = extract_soft_layer(idle, head_mask, dilate_px=1, feather_px=1.0, safe_rgb=safe_c)
    head_blank[bolt_above] = 0
    eye_discs = (((xx - 477.0) ** 2 + (yy - 605.0) ** 2) <= 84.0 ** 2) | (((xx - 774.0) ** 2 + (yy - 656.0) ** 2) <= 84.0 ** 2)
    head_holes = bolt_on_dome | brow_l_mask | brow_r_mask | eye_l_mask | eye_r_mask | eye_discs | mouth_mask
    head_blank = inpaint_mochi(head_blank, head_holes, dilate_px=10, fill_rgb=(252, 242, 226), smooth_sigma=5.8)

    dome_roi = (xx >= 535) & (xx <= 825) & (yy >= 140) & (yy <= 252)
    a_dome = cv2.GaussianBlur(np.where(yy < dome_limit_y, 0.0, 255.0).astype(np.float32), (0, 0), 1.8)
    head_blank[:, :, 3] = np.where(dome_roi, np.minimum(head_blank[:, :, 3].astype(np.float32), a_dome), head_blank[:, :, 3]).astype(np.uint8)
    head_blank[head_blank[:, :, 3] < 4] = 0
    head_meta = save_cropped_layer(head_blank, rig_dir / "head_blank.png", (628.0, 818.0))

    # 7. Lower body: Feet, Mitten Paws, and Seamless Pear Torso
    lower_fg = fg & ~head_mask & ~bolt_mask
    foot_l_mask = lower_fg & (yy >= 1104) & (xx < 612)
    foot_r_mask = lower_fg & (yy >= 1104) & (xx >= 612)
    paw_l_mask = lower_fg & ~scarf_all & (yy >= 796) & (yy <= 975) & (xx < 442 - (yy - 800) * 0.12)
    paw_r_mask = lower_fg & ~scarf_all & (yy >= 852) & (yy <= 1025) & (xx > 758 + (900 - np.minimum(yy, 900)) * 0.10)

    foot_left_meta = save_cropped_layer(
        extract_soft_layer(idle, foot_l_mask, dilate_px=2, feather_px=1.0, safe_rgb=safe_c),
        rig_dir / "foot_left.png",
        (536.0, 1110.0),
    )
    foot_right_meta = save_cropped_layer(
        extract_soft_layer(idle, foot_r_mask, dilate_px=2, feather_px=1.0, safe_rgb=safe_c),
        rig_dir / "foot_right.png",
        (692.0, 1110.0),
    )
    paw_left_meta = save_cropped_layer(
        extract_soft_layer(idle, paw_l_mask, dilate_px=3, feather_px=1.1, safe_rgb=safe_c),
        rig_dir / "paw_left.png",
        (434.0, 838.0),
    )
    paw_right_meta = save_cropped_layer(
        extract_soft_layer(idle, paw_r_mask, dilate_px=3, feather_px=1.1, safe_rgb=safe_c),
        rig_dir / "paw_right.png",
        (756.0, 876.0),
    )

    # Torso: pear belly + warm mochi neck cylinder tucked behind head/scarf so head tilt never reveals a gap!
    neck_bridge = ((xx - 602.0) / 145.0) ** 2 + ((yy - 825.0) / 72.0) ** 2 <= 1.0
    torso_core_mask = ((lower_fg & ~paw_l_mask & ~paw_r_mask & (yy <= 1122)) | neck_bridge) & (xx >= 398) & (xx <= 790)
    # Build torso image starting from idle, replacing scarf & neck-bridge pixels with warm ivory before inpainting
    torso_src = idle.copy()
    warm_ivory = np.array([247, 234, 214, 255], dtype=np.uint8)
    torso_src[neck_bridge & ~lower_fg] = warm_ivory
    torso_layer = extract_soft_layer(torso_src, torso_core_mask, dilate_px=2, feather_px=1.3, safe_rgb=safe_c)
    # Ensure neck_bridge is opaque inside torso_layer
    nb_alpha = cv2.GaussianBlur(neck_bridge.astype(np.float32) * 255.0, (0, 0), 2.5)
    torso_layer[:, :, 3] = np.maximum(torso_layer[:, :, 3], nb_alpha.astype(np.uint8))
    # Cleanly remove cobalt scarf & its dark blue cast from torso belly so swinging scarf shows creamy ivory underneath!
    scarf_and_shadow = (scarf_all | (neck_bridge & (yy < 865)) | ((hsv[:, :, 0] >= 85) & (hsv[:, :, 0] <= 140) & (hsv[:, :, 1] >= 35) & (yy >= 760) & (yy <= 1015))) & torso_core_mask
    torso_layer = inpaint_mochi(torso_layer, scarf_and_shadow, dilate_px=11, fill_rgb=(247, 234, 214), smooth_sigma=6.5)
    # Keep largest connected component of torso_layer so no stray pixel island remains
    tnl, tlb, tst, _ = cv2.connectedComponentsWithStats((torso_layer[:, :, 3] > 8).astype(np.uint8))
    if tnl > 1:
        main_t = 1 + int(np.argmax(tst[1:, 4]))
        torso_layer[tlb != main_t] = 0
    torso_meta = save_cropped_layer(torso_layer, rig_dir / "torso.png", (598.0, 1085.0))

    # 8. Split 3D Cobalt Zzz letters from assets/overlays/zzz.png
    zzz_im = np.array(Image.open(pack_dir / "assets" / "overlays" / "zzz.png").convert("RGBA"))
    za = (zzz_im[:, :, 3] > 12).astype(np.uint8)
    znl, zlb, zst, zct = cv2.connectedComponentsWithStats(za)
    z_comps = [(zct[i, 0], zct[i, 1], zlb == i) for i in range(1, znl) if zst[i, 4] > 1000]
    z_comps.sort(key=lambda c: c[0])
    zsafe = premult_safe_rgb(zzz_im, fill_rgb=(21, 87, 231))
    zzz_metas = []
    for idx, (zcx, zcy, zmask) in enumerate(z_comps, start=1):
        zlayer = extract_soft_layer(zzz_im, zmask, dilate_px=2, feather_px=1.0, safe_rgb=zsafe)
        zzz_metas.append(save_cropped_layer(zlayer, rig_dir / f"zzz_{idx}.png", (zcx, zcy)))

    return {
        "canvas": CANVAS,
        "groundY": CANONICAL_GROUND_Y,
        "parts": {
            "torso": torso_meta,
            "footLeft": foot_left_meta,
            "footRight": foot_right_meta,
            "pawLeft": paw_left_meta,
            "pawRight": paw_right_meta,
            "scarfCollar": scarf_collar_meta,
            "scarfTail": scarf_tail_meta,
            "head": head_meta,
            "bolt": bolt_meta,
            "browLeft": brow_left_meta,
            "browRight": brow_right_meta,
            "eyeLeft": eye_left_meta,
            "eyeRight": eye_right_meta,
            "mouths": mouths_meta,
            "zzz": zzz_metas,
        },
    }


def compute_pose_registrations(pack_dir: Path) -> dict[str, Any]:
    """Measure exact scale, ground-line offset, bolt anchor, and open-eye sockets for all 25 poses."""
    poses_dir = pack_dir / "assets" / "poses"
    yy, xx = np.mgrid[0:CANVAS, 0:CANVAS]

    # Perspective & posture target factors relative to canonical front head width (934 px)
    perspective_factor = {
        "walking": 0.92,       # 3/4 stride view naturally has slightly narrower projected cloud width
        "guiding": 0.96,
        "celebrate": 0.96,     # jumping pose
        "sleeping-clean": 0.89,
        "sleeping": 0.89,
    }
    target_ground = {
        "celebrate": 1152,      # mid-hop airborne!
        "sleeping-clean": 1176, # curled bean resting comfortably on floor
        "sleeping": 1176,
    }
    closed_eye_poses = {"grateful", "success", "sleeping-clean", "sleeping", "waking"}

    registrations: dict[str, Any] = {}
    for p in sorted(poses_dir.glob("*.png")):
        pose_id = p.stem
        im = np.array(Image.open(p).convert("RGBA"))
        rgb = im[:, :, :3]
        fg = im[:, :, 3] > 24
        hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
        pys, pxs = np.where(fg)

        x_min, y_min, x_max, y_max = int(pxs.min()), int(pys.min()), int(pxs.max()), int(pys.max())
        raw_ground_y = y_max

        # Measure cloud head width in upper character region (excluding wide outstretched props/arms below cheek)
        head_y_limit = 745 if pose_id not in ("sleeping-clean", "sleeping") else 1020
        widths = []
        centers = []
        for ry in range(max(160, y_min + 80), min(head_y_limit, y_max - 40), 4):
            rxs = np.where(fg[ry])[0]
            if len(rxs) > 120:
                widths.append(int(rxs.max() - rxs.min()))
                centers.append(float(rxs.min() + rxs.max()) * 0.5)
        raw_head_w = float(max(widths)) if widths else float(x_max - x_min)
        raw_head_cx = float(np.median(centers)) if centers else float(pxs.mean())

        pf = perspective_factor.get(pose_id, 1.0)
        scale = float(np.clip((CANONICAL_HEAD_W * pf) / raw_head_w, 0.93, 1.21))
        if pose_id == "idle":
            scale = 1.0

        tgt_gy = target_ground.get(pose_id, CANONICAL_GROUND_Y)
        # Pivot scaling around (raw_head_cx, raw_ground_y) -> mapped to (CANONICAL_CENTER_X, tgt_gy)
        # Screen pos: x' = (x - raw_head_cx) * scale + CANONICAL_CENTER_X
        #             y' = (y - raw_ground_y) * scale + tgt_gy
        offset_x = CANONICAL_CENTER_X - raw_head_cx * scale
        offset_y = tgt_gy - raw_ground_y * scale

        # Detect golden bolt center (for golden aura / spark effects)
        gold = fg & (hsv[:, :, 0] >= 11) & (hsv[:, :, 0] <= 36) & (hsv[:, :, 1] >= 65) & (yy < 560)
        gys, gxs = np.where(gold)
        bolt_center = (
            [round(float(gxs.mean() * scale + offset_x), 1), round(float(gys.mean() * scale + offset_y), 1)]
            if len(gxs) > 300
            else [650.0, 210.0]
        )

        # Detect open blue eyes for authentic curved mochi eyelid blinking on EVERY open-eyed pose!
        eyes_list = []
        if pose_id not in closed_eye_poses:
            # Find deep sapphire iris regions in the face zone (above scarf!)
            # Scarf starts around y > 690 (or lower on smaller poses; relative to y_min..y_max, face is in top 62%)
            face_max_y = int(y_min + (y_max - y_min) * 0.62)
            blue = fg & (hsv[:, :, 0] >= 98) & (hsv[:, :, 0] <= 132) & (hsv[:, :, 1] >= 95) & (yy < face_max_y)
            # Exclude magnifying glass outer ring on `searching` by filling iris circles and checking solidity/area
            nl, lb, st, ct = cv2.connectedComponentsWithStats(blue.astype(np.uint8))
            cand_eyes = []
            for i in range(1, nl):
                bx, by, bw, bh, barea = st[i].tolist()
                if 1200 < barea < 16500 and 32 < bw < 165 and 35 < bh < 165:
                    # Expand slightly to include sclera + upper lash around this iris
                    ex0, ex1 = max(0, bx - 22), min(CANVAS, bx + bw + 22)
                    ey0, ey1 = max(0, by - 24), min(CANVAS, by + bh + 18)
                    eroi = (xx >= ex0) & (xx <= ex1) & (yy >= ey0) & (yy <= ey1)
                    non_skin = fg & eroi & ((rgb[:, :, 0].astype(int) - rgb[:, :, 2].astype(int) < 15) | (hsv[:, :, 2] < 192))
                    em = cv2.morphologyEx(non_skin.astype(np.uint8) * 255, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))
                    ecnts, _ = cv2.findContours(em, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                    if ecnts:
                        ec = max(ecnts, key=cv2.contourArea)
                        ex, ey, ew, eh = cv2.boundingRect(ec)
                        # Sample upper forehead skin & lower cheek skin for seamless 3D gradient eyelid!
                        top_ring = fg & ~non_skin & (xx >= max(0, ex - 12)) & (xx <= min(CANVAS - 1, ex + ew + 12)) & (yy >= max(0, ey - 28)) & (yy <= max(0, ey + 6))
                        bot_ring = fg & ~non_skin & (xx >= max(0, ex - 12)) & (xx <= min(CANVAS - 1, ex + ew + 12)) & (yy >= min(CANVAS - 1, ey + eh - 4)) & (yy <= min(CANVAS - 1, ey + eh + 24))
                        s_top = np.median(rgb[top_ring], axis=0).astype(int).tolist() if np.any(top_ring) else [251, 240, 225]
                        s_bot = np.median(rgb[bot_ring], axis=0).astype(int).tolist() if np.any(bot_ring) else [242, 224, 208]
                        cand_eyes.append({
                            "cx": round(float((ex + ew * 0.5) * scale + offset_x), 1),
                            "cy": round(float((ey + eh * 0.5) * scale + offset_y), 1),
                            "rx": round(float(ew * 0.54 * scale), 1),
                            "ry": round(float(eh * 0.55 * scale), 1),
                            "skinRGB": s_top,
                            "skinBotRGB": s_bot,
                        })
            cand_eyes.sort(key=lambda e: e["cx"])
            filtered = []
            for e in cand_eyes:
                if not filtered or abs(e["cx"] - filtered[-1]["cx"]) > 110 * scale:
                    filtered.append(e)
            if pose_id == "searching" and len(filtered) == 2:
                # Left eye is behind magnifying glass lens; blink exposed right eye cleanly
                eyes_list = [filtered[1]]
            else:
                eyes_list = filtered[:2]

        registrations[pose_id] = {
            "rawBBox": [x_min, y_min, x_max, y_max],
            "rawHeadW": round(raw_head_w, 1),
            "rawGroundY": raw_ground_y,
            "scale": round(scale, 4),
            "offsetX": round(offset_x, 2),
            "offsetY": round(offset_y, 2),
            "groundY": tgt_gy,
            "boltCenter": bolt_center,
            "canBlink": len(eyes_list) > 0,
            "eyes": eyes_list,
        }

    return registrations


# ---------------------------------------------------------------------------
# Procedural Frame Compositor for Batch Exports & Visual QA
# ---------------------------------------------------------------------------

def rotate_rgba(img: Image.Image, angle_ccw: float, center: tuple[float, float]) -> Image.Image:
    """Rotate an RGBA image in premultiplied space so transparent borders never bleed black into edges."""
    out = img.convert("RGBa").rotate(angle_ccw, resample=Image.Resampling.BICUBIC, center=center)
    return out.convert("RGBA")


def transform_layer_pil(
    part_img: Image.Image,
    meta: dict[str, Any],
    canvas_size: int = CANVAS,
    dx: float = 0.0,
    dy: float = 0.0,
    rot_deg: float = 0.0,
    sx: float = 1.0,
    sy: float = 1.0,
) -> Image.Image:
    """Place a cropped rig layer onto a `canvas_size` RGBA image with pivot-anchored scale/rotate/translate."""
    ratio = canvas_size / WORLD
    w = max(1, int(round(meta["w"] * sx * ratio)))
    h = max(1, int(round(meta["h"] * sy * ratio)))
    scaled = part_img.resize((w, h), Image.Resampling.LANCZOS)

    px_local = (meta["pivotX"] - meta["x"]) * sx * ratio
    py_local = (meta["pivotY"] - meta["y"]) * sy * ratio

    # Pad onto a temporary square centered on pivot so rotation pivots around exact anatomical joint!
    rad = int(math.ceil(math.hypot(w, h))) + 8
    tmp = Image.new("RGBA", (rad * 2, rad * 2), (0, 0, 0, 0))
    tmp.paste(scaled, (int(round(rad - px_local)), int(round(rad - py_local))))
    if abs(rot_deg) > 0.02:
        tmp = rotate_rgba(tmp, -rot_deg, (rad, rad))

    dest_px = (meta["pivotX"] + dx + ORIGIN) * ratio
    dest_py = (meta["pivotY"] + dy + ORIGIN) * ratio
    out = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    out.paste(tmp, (int(round(dest_px - rad)), int(round(dest_py - rad))))
    return out


def draw_shadow_pil(canvas_size: int, lift: float = 0.0, spread: float = 1.0) -> Image.Image:
    """Soft floor contact shadow that shrinks and softens as Zeus hops upward."""
    ratio = canvas_size / WORLD
    sh = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    k = max(0.45, 1.0 - lift / 120.0) * spread
    rx = 185 * ratio * k
    ry = 28 * ratio * k
    cx = (CANONICAL_CENTER_X + ORIGIN) * ratio
    cy = (CANONICAL_GROUND_Y + 4 + ORIGIN) * ratio
    alpha = int(52 * k)
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(16, 30, 58, alpha))
    return sh.filter(ImageFilter.GaussianBlur(max(1.5, 9.0 * ratio)))


def draw_curved_eyelid(
    frame: Image.Image,
    eyes: list[dict[str, Any]],
    blink_amount: float,
    canvas_size: int,
) -> None:
    """Draw seamless feathered mochi eyelids + warm cocoa closed-lash arc with ZERO rim outline.

    The lid is the pose's own skin: the eye sockets are filled from the surrounding forehead/cheek
    (so shading and blush match), then revealed top-down through a curved, feathered mask.
    """
    if blink_amount <= 0.03 or not eyes:
        return
    ratio = canvas_size / WORLD
    b = min(1.0, max(0.0, blink_amount))
    overlay = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    # Skin fill for every socket in one inpaint, sampled from the frame itself.
    base = np.array(frame)
    hole = np.zeros((canvas_size, canvas_size), dtype=np.uint8)
    pad_out = max(2.0, 7.0 * ratio)
    for e in eyes:
        cv2.ellipse(
            hole,
            (int(round(e["cx"] * ratio)), int(round(e["cy"] * ratio))),
            (int(round(e["rx"] * 1.18 * ratio + pad_out + 6 * ratio + 3)), int(round(e["ry"] * 1.18 * ratio + pad_out + 6 * ratio + 3))),
            0, 0, 360, 255, -1,
        )
    # Normalised-convolution fill (smooth, streak-free): average only skin-like pixels around the sockets.
    # Dark/blue pixels (brows, mouth, lashes, iris) and the hole itself carry zero weight.
    rgb_f = base[:, :, :3].astype(np.float32)
    skin_like = (
        (base[:, :, 3] > 200)
        & (hole == 0)
        & (rgb_f.max(axis=2) >= 175)
        & ((rgb_f[:, :, 0] - rgb_f[:, :, 2]) >= 8)
    ).astype(np.float32)
    sigma = max(2.5, float(np.mean([e["ry"] for e in eyes])) * ratio * 0.55)
    fill = np.zeros_like(rgb_f)
    weight = np.zeros(rgb_f.shape[:2], dtype=np.float32)
    for sg in (sigma, sigma * 2.5, sigma * 6.0):  # widen until every hole pixel has support
        w = cv2.GaussianBlur(skin_like, (0, 0), sg)
        c = cv2.GaussianBlur(rgb_f * skin_like[:, :, None], (0, 0), sg)
        use = (weight < 0.05) & (w > 0.02)
        fill[use] = c[use] / w[use, None]
        weight[use] = w[use]
    skin_rgb = np.clip(fill, 0, 255).astype(np.uint8)

    for e in eyes:
        cx = e["cx"] * ratio
        cy = e["cy"] * ratio
        # Ensure 100% opaque coverage across the entire eye socket first, feathering strictly outward over skin!
        rx = e["rx"] * 1.18 * ratio
        ry = e["ry"] * 1.18 * ratio
        top_y = cy - ry * 1.12
        lid_bottom = top_y + (2.24 * ry) * b

        mask = Image.new("L", (canvas_size, canvas_size), 0)
        md = ImageDraw.Draw(mask)
        md.ellipse([cx - rx - pad_out, cy - ry - pad_out, cx + rx + pad_out, cy + ry + pad_out], fill=255)
        lid_clip = Image.new("L", (canvas_size, canvas_size), 0)
        lcd = ImageDraw.Draw(lid_clip)
        curve_dip = ry * 0.22 * math.sin(b * math.pi)
        lcd.rectangle([cx - rx - pad_out - 4, top_y - 8, cx + rx + pad_out + 4, lid_bottom], fill=255)
        if curve_dip > 0.4:
            lcd.ellipse([cx - rx - pad_out, lid_bottom - curve_dip, cx + rx + pad_out, lid_bottom + curve_dip], fill=255)

        comb = np.minimum(np.array(mask), np.array(lid_clip))
        dil_k = max(3, int(round(6 * ratio)) | 1)
        comb_dil = cv2.dilate(comb, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (dil_k, dil_k)))
        soft_mask = Image.fromarray(comb_dil).filter(ImageFilter.GaussianBlur(max(1.2, 3.0 * ratio)))

        # putalpha-style RGBA (NOT paste onto (0,0,0,0), which would premultiply black!)
        skin_rgba = np.zeros((canvas_size, canvas_size, 4), dtype=np.uint8)
        skin_rgba[:, :, :3] = skin_rgb
        skin_rgba[:, :, 3] = np.array(soft_mask)
        overlay.alpha_composite(Image.fromarray(skin_rgba))

        # Crisp warm-cocoa eyelash crease following the descending lid edge!
        lash_layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
        ld = ImageDraw.Draw(lash_layer)
        lash_w = max(2, int(round(7.5 * ratio)))
        lash_rx = e["rx"] * 0.88 * ratio
        lash_y = min(cy + e["ry"] * 0.28 * ratio, lid_bottom)
        arc_h = max(3.0 * ratio, e["ry"] * 0.34 * ratio)
        ld.arc(
            [cx - lash_rx, lash_y - arc_h, cx + lash_rx, lash_y + arc_h * 0.55],
            start=14,
            end=166,
            fill=(74, 42, 32, int(242 * min(1.0, b * 1.35))),
            width=lash_w,
        )
        lash_layer = lash_layer.filter(ImageFilter.GaussianBlur(max(0.3, 0.65 * ratio)))
        overlay.alpha_composite(lash_layer)

    frame.alpha_composite(overlay)


def render_puppet_frame(
    rig_meta: dict[str, Any],
    part_imgs: dict[str, Image.Image],
    canvas_size: int = 384,
    gaze_x: float = 0.0,
    gaze_y: float = 0.0,
    blink: float = 0.0,
    happy_eyes: bool = False,
    head_rot: float = 0.0,
    head_dx: float = 0.0,
    head_dy: float = 0.0,
    bolt_rot: float = 0.0,
    scarf_rot: float = 0.0,
    paw_l_rot: float = 0.0,
    paw_r_rot: float = 0.0,
    foot_l_dy: float = 0.0,
    foot_r_dy: float = 0.0,
    body_dy: float = 0.0,
    body_sx: float = 1.0,
    body_sy: float = 1.0,
    brow_l_dy: float = 0.0,
    brow_r_dy: float = 0.0,
    brow_l_rot: float = 0.0,
    brow_r_rot: float = 0.0,
    mouth: str = "happy",
) -> Image.Image:
    parts = rig_meta["parts"]
    frame = draw_shadow_pil(canvas_size, lift=max(0.0, -body_dy))

    # 1. Feet
    frame.alpha_composite(transform_layer_pil(part_imgs["footLeft"], parts["footLeft"], canvas_size, dy=body_dy * 0.15 + foot_l_dy))
    frame.alpha_composite(transform_layer_pil(part_imgs["footRight"], parts["footRight"], canvas_size, dy=body_dy * 0.15 + foot_r_dy))

    # 2. Torso + Paws
    frame.alpha_composite(transform_layer_pil(part_imgs["torso"], parts["torso"], canvas_size, dy=body_dy, sx=body_sx, sy=body_sy))
    frame.alpha_composite(transform_layer_pil(part_imgs["pawLeft"], parts["pawLeft"], canvas_size, dx=head_dx * 0.25, dy=body_dy, rot_deg=paw_l_rot))
    frame.alpha_composite(transform_layer_pil(part_imgs["pawRight"], parts["pawRight"], canvas_size, dx=head_dx * 0.25, dy=body_dy, rot_deg=paw_r_rot))

    # 3. Head sub-canvas so all facial features rotate/translate cleanly with the head pivot!
    head_sub = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    head_sub.alpha_composite(transform_layer_pil(part_imgs["head"], parts["head"], canvas_size))

    # Bolt tuft on top of head with secondary lag
    head_sub.alpha_composite(transform_layer_pil(part_imgs["bolt"], parts["bolt"], canvas_size, dx=gaze_x * 3.0, rot_deg=bolt_rot))

    # Eyes: either happy `^ ^` arcs or clipped movable irises + catchlights + mochi eyelids!
    ratio = canvas_size / WORLD
    if happy_eyes:
        head_sub.alpha_composite(transform_layer_pil(part_imgs["eyeHappyLeft"], parts["eyeLeft"]["happyArc"], canvas_size, dx=gaze_x * 6.0, dy=gaze_y * 4.0))
        head_sub.alpha_composite(transform_layer_pil(part_imgs["eyeHappyRight"], parts["eyeRight"]["happyArc"], canvas_size, dx=gaze_x * 6.0, dy=gaze_y * 4.0))
    else:
        # Native Live2D-style eyelid clip: `head_blank` underneath IS already seamless mochi skin!
        # Clipping the open eye below `lid_y` reveals native cheek/forehead shading with zero patch rim.
        for side_key, p_key in [("eyeLeft", "Left"), ("eyeRight", "Right")]:
            em = parts[side_key]
            ecx = (em["center"][0] + gaze_x * 4.0) * ratio
            ecy = (em["center"][1] + gaze_y * 3.0) * ratio
            erx = em["radius"] * 0.92 * ratio
            ery = em["radius"] * 1.05 * ratio
            lid_y = (ecy - ery) + (2.05 * ery) * blink

            if blink < 0.92:
                sclera_im = transform_layer_pil(part_imgs[f"eyeSclera{p_key}"], em["sclera"], canvas_size, dx=gaze_x * 4.0, dy=gaze_y * 3.0)
                iris_im = transform_layer_pil(part_imgs[f"iris{p_key}"], em["iris"], canvas_size, dx=gaze_x * 18.0, dy=gaze_y * 13.0)
                catch_im = transform_layer_pil(part_imgs[f"catchlight{p_key}"], em["catchlight"], canvas_size, dx=gaze_x * 12.5, dy=gaze_y * 9.0)
                lash_im = transform_layer_pil(part_imgs[f"eyeLash{p_key}"], em["lash"], canvas_size, dx=gaze_x * 4.0, dy=gaze_y * 3.0)

                eye_comp = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
                eye_comp.alpha_composite(sclera_im)
                eye_inner = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
                eye_inner.alpha_composite(iris_im)
                eye_inner.alpha_composite(catch_im)
                comb_a = np.minimum(np.array(eye_inner.getchannel("A")), np.array(sclera_im.getchannel("A")))
                eye_inner.putalpha(Image.fromarray(comb_a))
                eye_comp.alpha_composite(eye_inner)
                eye_comp.alpha_composite(lash_im)

                if blink > 0.03:
                    open_mask = Image.new("L", (canvas_size, canvas_size), 255)
                    omd = ImageDraw.Draw(open_mask)
                    omd.rectangle([0, 0, canvas_size, int(round(lid_y))], fill=0)
                    open_mask = open_mask.filter(ImageFilter.GaussianBlur(max(0.5, 1.0 * ratio)))
                    new_a = Image.fromarray(np.minimum(np.array(eye_comp.getchannel("A")), np.array(open_mask)))
                    eye_comp.putalpha(new_a)
                head_sub.alpha_composite(eye_comp)

            if blink > 0.08:
                lash_arc = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
                ld = ImageDraw.Draw(lash_arc)
                lw = max(2, int(round(7.5 * ratio)))
                ly = min(ecy + ery * 0.25, lid_y)
                ah = max(3.0 * ratio, ery * 0.34)
                ld.arc([ecx - erx, ly - ah, ecx + erx, ly + ah * 0.55], start=14, end=166, fill=(74, 42, 32, int(242 * min(1.0, blink * 1.3))), width=lw)
                head_sub.alpha_composite(lash_arc.filter(ImageFilter.GaussianBlur(max(0.3, 0.6 * ratio))))

    # Eyebrows (expressive tilt & lift!)
    head_sub.alpha_composite(transform_layer_pil(part_imgs["browLeft"], parts["browLeft"], canvas_size, dx=gaze_x * 6.0, dy=brow_l_dy + gaze_y * 4.0, rot_deg=brow_l_rot))
    head_sub.alpha_composite(transform_layer_pil(part_imgs["browRight"], parts["browRight"], canvas_size, dx=gaze_x * 6.0, dy=brow_r_dy + gaze_y * 4.0, rot_deg=brow_r_rot))

    # Mouth viseme
    m_meta = parts["mouths"].get(mouth, parts["mouths"]["happy"])
    head_sub.alpha_composite(transform_layer_pil(part_imgs[f"mouth_{mouth}"], m_meta, canvas_size, dx=gaze_x * 5.0, dy=gaze_y * 3.0))

    # Rotate & place head_sub around neck pivot (628, 818)
    hp_x = int(round(628.0 * ratio))
    hp_y = int(round(818.0 * ratio))
    if abs(head_rot) > 0.02:
        head_sub = rotate_rgba(head_sub, -head_rot, (hp_x, hp_y))
    if abs(head_dx) > 0.1 or abs(head_dy + body_dy) > 0.1:
        shifted = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
        shifted.paste(head_sub, (int(round(head_dx * ratio)), int(round((head_dy + body_dy) * ratio))))
        head_sub = shifted
    frame.alpha_composite(head_sub)

    # 4. Cobalt scarf collar + spring-lagging tail over neck seam
    frame.alpha_composite(transform_layer_pil(part_imgs["scarfCollar"], parts["scarfCollar"], canvas_size, dx=head_dx * 0.45, dy=body_dy))
    frame.alpha_composite(transform_layer_pil(part_imgs["scarfTail"], parts["scarfTail"], canvas_size, dx=head_dx * 0.45, dy=body_dy, rot_deg=scarf_rot))

    return frame


def blink_curve(u: float, at: float = 0.62, width: float = 0.08) -> float:
    """Smooth natural eyelid close-and-open pulse centered at phase `at` in [0..1)."""
    d = abs(u - at)
    if d >= width:
        return 0.0
    return 0.5 * (1.0 + math.cos(math.pi * d / width))


def render_state_frame(
    pose_id: str,
    u: float,
    pose_img: Image.Image,
    reg: dict[str, Any],
    zzz_imgs: list[tuple[Image.Image, dict[str, Any]]],
    canvas_size: int = 384,
) -> Image.Image:
    """Render one frame `u in [0..1)` of any of the 24 states with registered ground-line, real blink & secondary motion."""
    ratio = canvas_size / WORLD
    tau = 2.0 * math.pi * u

    # Bespoke per-state motion choreography (anticipation -> clear action -> soft settle)
    dx, dy, rot, sx, sy = 0.0, 0.0, 0.0, 1.0, 1.0
    blink = 0.0
    glow = 0.0

    if pose_id == "idle":
        breathe = math.sin(tau)
        dy = -7.0 * (0.5 - 0.5 * math.cos(tau))
        sy = 1.0 + 0.016 * breathe
        sx = 1.0 - 0.008 * breathe
        rot = 1.1 * math.sin(tau)
        blink = blink_curve(u, 0.58, 0.055)
    elif pose_id in ("welcome", "goodbye"):
        # Two warm waves / gentle sway + settle
        env = math.sin(math.pi * min(1.0, u * 1.15)) ** 1.1
        rot = -4.2 * math.sin(2.0 * tau) * env
        dy = -10.0 * abs(math.sin(tau)) * env
        sy = 1.0 + 0.018 * math.sin(2.0 * tau) * env
        blink = blink_curve(u, 0.78, 0.07)
    elif pose_id == "listening":
        rot = 3.8 * math.sin(tau)
        dy = -5.0 * (0.5 - 0.5 * math.cos(tau))
        sy = 1.0 + 0.014 * math.sin(tau)
        blink = blink_curve(u, 0.52, 0.06)
    elif pose_id == "thinking":
        rot = -3.0 * math.sin(tau)
        dy = -8.0 * (0.5 - 0.5 * math.cos(tau))
        glow = 0.4 + 0.4 * math.sin(2.0 * tau)
        blink = max(blink_curve(u, 0.30, 0.045), blink_curve(u, 0.43, 0.045))  # thoughtful double-blink!
    elif pose_id == "searching":
        dx = 14.0 * math.sin(tau)
        rot = 3.5 * math.sin(tau)
        dy = -6.0 * abs(math.sin(tau))
        blink = blink_curve(u, 0.72, 0.055)
    elif pose_id == "working":
        dy = -9.0 * abs(math.sin(2.0 * tau))
        sy = 1.0 + 0.02 * math.cos(2.0 * tau)
        sx = 1.0 - 0.012 * math.cos(2.0 * tau)
        rot = 1.8 * math.sin(tau)
        glow = 0.55
        blink = blink_curve(u, 0.64, 0.055)
    elif pose_id == "typing":
        dy = -4.5 * abs(math.sin(3.0 * tau))
        dx = 2.5 * math.sin(3.0 * tau)
        sy = 1.0 - 0.01 * abs(math.sin(3.0 * tau))
        blink = blink_curve(u, 0.50, 0.065)
    elif pose_id == "organizing":
        dx = 12.0 * math.sin(tau)
        rot = 2.8 * math.sin(tau)
        dy = -7.0 * abs(math.cos(tau))
        blink = blink_curve(u, 0.68, 0.055)
    elif pose_id == "guiding":
        # Anticipation -> confident point -> hold
        if u < 0.22:
            p = u / 0.22
            dx = -10.0 * math.sin(p * math.pi * 0.5)
            rot = -2.5 * math.sin(p * math.pi * 0.5)
        elif u < 0.58:
            p = (u - 0.22) / 0.36
            dx = -10.0 + 24.0 * (1.0 - (1.0 - p) ** 3)
            rot = -2.5 + 5.5 * (1.0 - (1.0 - p) ** 3)
            dy = -8.0 * math.sin(p * math.pi)
        else:
            p = (u - 0.58) / 0.42
            dx = 14.0 * math.cos(p * math.pi * 0.5)
            rot = 3.0 * math.cos(p * math.pi * 0.5)
        blink = blink_curve(u, 0.82, 0.06)
    elif pose_id == "approval_wait":
        # Calm, patient breathing — never impatient!
        dy = -5.5 * (0.5 - 0.5 * math.cos(tau))
        sy = 1.0 + 0.012 * math.sin(tau)
        blink = blink_curve(u, 0.55, 0.055)
    elif pose_id == "success":
        # Warm affirmative nod + settle
        nod = math.sin(tau * 1.0) * math.exp(-2.2 * u)
        rot = 4.8 * nod
        dy = 8.0 * max(0.0, nod) - 6.0 * max(0.0, -nod)
        sy = 1.0 - 0.025 * max(0.0, nod)
        sx = 1.0 + 0.018 * max(0.0, nod)
        glow = 0.65 * math.sin(math.pi * u)
    elif pose_id == "celebrate":
        # Squash anticipation -> joyful hop -> cushioned landing settle!
        if u < 0.18:
            p = u / 0.18
            s = math.sin(p * math.pi * 0.5)
            dy = 14.0 * s
            sy = 1.0 - 0.065 * s
            sx = 1.0 + 0.045 * s
        elif u < 0.66:
            p = (u - 0.18) / 0.48
            arc = math.sin(p * math.pi)
            dy = 14.0 * (1.0 - min(1.0, p * 4.0)) - 68.0 * arc
            sy = 1.0 + 0.05 * arc
            sx = 1.0 - 0.03 * arc
            rot = -3.8 * math.sin(p * math.pi)
            glow = 0.9 * arc
        else:
            p = (u - 0.66) / 0.34
            settle = math.sin(p * math.pi) * (1.0 - p)
            dy = 9.0 * settle
            sy = 1.0 - 0.035 * settle
            sx = 1.0 + 0.025 * settle
        blink = blink_curve(u, 0.85, 0.06)
    elif pose_id == "error":
        # Gentle head dip + soft recovery (never distressed)
        env = math.sin(math.pi * u)
        dx = 9.0 * math.sin(3.0 * tau) * math.exp(-3.5 * u)
        dy = 8.0 * env
        rot = -3.2 * env
        blink = blink_curve(u, 0.45, 0.08)
    elif pose_id in ("offline", "paused"):
        dy = -4.0 * (0.5 - 0.5 * math.cos(tau))
        sy = 1.0 + 0.012 * math.sin(tau)
        blink = blink_curve(u, 0.60, 0.06)
    elif pose_id == "sleeping":
        # Uses sleeping-clean + 3 independent 3D cobalt Zzz sprites!
        breathe = math.sin(tau)
        sy = 1.0 + 0.022 * breathe
        sx = 1.0 - 0.010 * breathe
        dy = -2.5 * breathe
    elif pose_id == "waking":
        # Big cozy morning stretch upward then relax!
        stretch = math.sin(math.pi * u) ** 1.3
        dy = -16.0 * stretch
        sy = 1.0 + 0.055 * stretch
        sx = 1.0 - 0.028 * stretch
        rot = -2.5 * math.sin(tau)
    elif pose_id == "curious":
        env = math.sin(math.pi * u)
        rot = 5.5 * env
        dx = 10.0 * env
        sy = 1.0 + 0.02 * env
        blink = blink_curve(u, 0.65, 0.065)
    elif pose_id == "confused":
        env = math.sin(math.pi * u)
        rot = -4.8 * env
        dy = -4.0 * env
        blink = blink_curve(u, 0.55, 0.065)
    elif pose_id == "surprised":
        # Quick pop lift + wide O settle!
        pop = math.sin(math.pi * min(1.0, u * 1.4)) * math.exp(-1.6 * u)
        dy = -34.0 * pop
        sy = 1.0 + 0.055 * pop
        sx = 1.0 - 0.03 * pop
        glow = 0.85 * pop
        blink = blink_curve(u, 0.82, 0.06)
    elif pose_id == "grateful":
        # Warm appreciative bow!
        bow = math.sin(math.pi * u) ** 1.2
        dy = 12.0 * bow
        sy = 1.0 - 0.03 * bow
        rot = 3.5 * bow
    elif pose_id in ("walking", "carrying"):
        # Crisp two-step bounce cycle!
        step = abs(math.sin(tau))
        dy = -18.0 * step
        sy = 1.0 + 0.028 * math.sin(2.0 * tau)
        sx = 1.0 - 0.018 * math.sin(2.0 * tau)
        rot = 2.8 * math.cos(tau)
        dx = 8.0 * math.sin(tau)
        blink = blink_curve(u, 0.70, 0.06)

    spread = 1.25 if pose_id == "sleeping" else 1.0
    frame = draw_shadow_pil(canvas_size, lift=max(0.0, -dy + (CANONICAL_GROUND_Y - reg["groundY"])), spread=spread)

    # Golden bolt aura when thinking / working / celebrating / surprised
    if glow > 0.05:
        aura = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
        ad = ImageDraw.Draw(aura)
        bcx = (reg["boltCenter"][0] + dx + ORIGIN) * ratio
        bcy = (reg["boltCenter"][1] + dy + ORIGIN) * ratio
        ar = 95.0 * ratio
        ad.ellipse([bcx - ar, bcy - ar, bcx + ar, bcy + ar], fill=(245, 186, 50, int(90 * glow)))
        frame.alpha_composite(aura.filter(ImageFilter.GaussianBlur(max(4.0, 18.0 * ratio))))

    # Registered character pose transformed around ground-line pivot (CANONICAL_CENTER_X, reg["groundY"])
    base_s = reg["scale"] * ratio
    w = max(1, int(round(CANVAS * base_s * sx)))
    h = max(1, int(round(CANVAS * base_s * sy)))
    scaled_pose = pose_img.resize((w, h), Image.Resampling.LANCZOS)

    # Compute where raw image's ground anchor lands inside `scaled_pose`
    raw_anchor_x = (CANONICAL_CENTER_X - reg["offsetX"]) / reg["scale"]
    raw_anchor_y = (reg["groundY"] - reg["offsetY"]) / reg["scale"]
    px_local = raw_anchor_x * base_s * sx
    py_local = raw_anchor_y * base_s * sy

    char_canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    dest_x = (CANONICAL_CENTER_X + dx + ORIGIN) * ratio
    dest_y = (reg["groundY"] + dy + ORIGIN) * ratio
    char_canvas.paste(scaled_pose, (int(round(dest_x - px_local)), int(round(dest_y - py_local))))

    # Draw curved mochi eyelid blink in character space before rotation!
    if blink > 0.02 and reg["canBlink"]:
        shifted_eyes = [
            {
                "cx": CANONICAL_CENTER_X + (e["cx"] - CANONICAL_CENTER_X) * sx + dx + ORIGIN,
                "cy": reg["groundY"] + (e["cy"] - reg["groundY"]) * sy + dy + ORIGIN,
                "rx": e["rx"] * sx,
                "ry": e["ry"] * sy,
                "skinRGB": e["skinRGB"],
                "skinBotRGB": e.get("skinBotRGB", e["skinRGB"]),
            }
            for e in reg["eyes"]
        ]
        draw_curved_eyelid(char_canvas, shifted_eyes, blink, canvas_size)

    if abs(rot) > 0.03:
        char_canvas = rotate_rgba(char_canvas, -rot, (int(round(dest_x)), int(round(dest_y))))

    frame.alpha_composite(char_canvas)

    # Staggered 3-piece 3D Cobalt Zzz drift for sleeping!
    if pose_id == "sleeping":
        for idx, (z_im, z_meta) in enumerate(zzz_imgs):
            zu = (u + idx * 0.28) % 1.0
            drift_x = 18.0 * math.sin(zu * math.pi) + idx * 4.0
            drift_y = -62.0 * zu
            z_scale = 0.86 + 0.22 * math.sin(zu * math.pi)
            z_alpha = math.sin(zu * math.pi) ** 0.65
            z_layer = transform_layer_pil(z_im, z_meta, canvas_size, dx=drift_x, dy=drift_y, rot_deg=-8.0 + 16.0 * zu, sx=z_scale, sy=z_scale)
            if z_alpha < 0.99:
                a_ch = z_layer.getchannel("A").point(lambda v: int(v * z_alpha))
                z_layer.putalpha(a_ch)
            frame.alpha_composite(z_layer)

    return frame


def build_qa_sheet(pack_dir: Path, out_dir: Path, rig_meta: dict[str, Any], registrations: dict[str, Any], out_path: Path) -> None:
    part_imgs = load_rig_part_images(out_dir, rig_meta)
    cell = 280
    cols, rows = 6, 5
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (13, 19, 32, 255))
    draw = ImageDraw.Draw(sheet)

    # Row 1: Clean Torso, Clean Head, and 4 articulated 2.5D Puppet expressions!
    t_only = transform_layer_pil(part_imgs["torso"], rig_meta["parts"]["torso"], cell)
    h_only = transform_layer_pil(part_imgs["head"], rig_meta["parts"]["head"], cell)
    p1 = render_puppet_frame(rig_meta, part_imgs, cell, gaze_x=-0.85, gaze_y=-0.65, head_rot=-6.5, bolt_rot=8.0, scarf_rot=12.0, brow_l_dy=-10, brow_r_dy=-4, mouth="smirk")
    p2 = render_puppet_frame(rig_meta, part_imgs, cell, gaze_x=0.85, gaze_y=0.25, blink=0.95, head_rot=5.5, paw_l_rot=18.0, scarf_rot=-11.0, mouth="smile")
    p3 = render_puppet_frame(rig_meta, part_imgs, cell, happy_eyes=True, body_dy=-22.0, body_sy=1.04, bolt_rot=-7.0, paw_l_rot=18.0, paw_r_rot=-18.0, scarf_rot=14.0, mouth="happy")
    p4 = render_puppet_frame(rig_meta, part_imgs, cell, gaze_x=0.0, gaze_y=-0.3, head_rot=-4.0, brow_l_dy=-14, brow_l_rot=-12, brow_r_dy=8, brow_r_rot=-10, mouth="ooh")

    row1 = [
        ("Clean Torso (No Seam)", t_only),
        ("Clean Head (Both Cheeks)", h_only),
        ("Puppet: Look Up-Left", p1),
        ("Puppet: Mochi Blink+Wave", p2),
        ("Puppet: Happy Hop", p3),
        ("Puppet: Ooh + Brows", p4),
    ]
    for i, (lbl, im) in enumerate(row1):
        sheet.alpha_composite(im, (i * cell, 0))
        draw.text((i * cell + 10, cell - 22), lbl, fill=(235, 242, 255, 255))

    # Row 2 vs Row 3: Unregistered Raw (Row 2) vs Ground-Line & Scale Registered + Blink/Zzz (Row 3)!
    # Rows 3-5 are rendered in the padded world (as the atlases are) so hops/arms/Zzz are never clipped.
    world_padding(WORLD_PAD)
    gy_reg = int(round((CANONICAL_GROUND_Y + ORIGIN) * (cell / WORLD)))
    compare_ids = ["idle", "walking", "goodbye", "carrying", "waking", "sleeping"]
    zzz_imgs = [(Image.open(out_dir / z["file"]).convert("RGBA"), z) for z in rig_meta["parts"]["zzz"]]
    for i, pid in enumerate(compare_ids):
        src_name = "sleeping-clean" if pid == "sleeping" else pid
        raw_im = Image.open(pack_dir / "assets" / "poses" / f"{src_name}.png").convert("RGBA")
        # Row 2: Unregistered raw scaled uniformly
        raw_cell = raw_im.resize((cell, cell), Image.Resampling.LANCZOS)
        sheet.alpha_composite(raw_cell, (i * cell, cell))
        gy_line = int(round(CANONICAL_GROUND_Y * (cell / CANVAS)))
        draw.line([(i * cell + 16, cell + gy_line), ((i + 1) * cell - 16, cell + gy_line)], fill=(245, 186, 50, 140), width=1)
        draw.text((i * cell + 10, 2 * cell - 22), f"RAW: {pid}", fill=(173, 190, 214, 255))

        # Row 3: Registered + animated frame
        reg_cell = render_state_frame(pid, 0.58 if pid != "sleeping" else 0.45, raw_im, registrations[src_name], zzz_imgs, cell)
        sheet.alpha_composite(reg_cell, (i * cell, 2 * cell))
        draw.line([(i * cell + 16, 2 * cell + gy_reg), ((i + 1) * cell - 16, 2 * cell + gy_reg)], fill=(82, 224, 74, 170), width=1)
        draw.text((i * cell + 10, 3 * cell - 22), f"REGISTERED: {pid}", fill=(245, 186, 50, 255))

    # Rows 4-5 on a LIGHT background (a dark one hides black fringes): the idle blink sequence, then
    # a spread of states mid-motion. Look for dark halos, lid seams and clipped edges.
    light = Image.new("RGBA", (cols * cell, 2 * cell), (244, 244, 248, 255))
    sheet.alpha_composite(light, (0, 3 * cell))
    idle_img = Image.open(pack_dir / "assets" / "poses" / "idle.png").convert("RGBA")
    for i, u in enumerate([0.52, 0.55, 0.58, 0.61, 0.64, 0.67]):
        f = render_state_frame("idle", u, idle_img, registrations["idle"], zzz_imgs, cell)
        sheet.alpha_composite(f, (i * cell, 3 * cell))
        draw.text((i * cell + 10, 4 * cell - 22), f"idle blink u={u:.2f}", fill=(40, 48, 66, 255))
    for i, (pid, u) in enumerate([("thinking", 0.3), ("searching", 0.25), ("success", 0.2), ("celebrate", 0.4), ("error", 0.5), ("surprised", 0.2)]):
        im = Image.open(pack_dir / "assets" / "poses" / f"{pid}.png").convert("RGBA")
        f = render_state_frame(pid, u, im, registrations[pid], zzz_imgs, cell)
        sheet.alpha_composite(f, (i * cell, 4 * cell))
        draw.text((i * cell + 10, 5 * cell - 22), f"{pid} u={u:.2f}", fill=(40, 48, 66, 255))

    world_padding(0)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path)


def load_rig_part_images(out_dir: Path, rig_meta: dict[str, Any]) -> dict[str, Image.Image]:
    p = rig_meta["parts"]
    imgs = {
        "torso": Image.open(out_dir / p["torso"]["file"]).convert("RGBA"),
        "footLeft": Image.open(out_dir / p["footLeft"]["file"]).convert("RGBA"),
        "footRight": Image.open(out_dir / p["footRight"]["file"]).convert("RGBA"),
        "pawLeft": Image.open(out_dir / p["pawLeft"]["file"]).convert("RGBA"),
        "pawRight": Image.open(out_dir / p["pawRight"]["file"]).convert("RGBA"),
        "scarfCollar": Image.open(out_dir / p["scarfCollar"]["file"]).convert("RGBA"),
        "scarfTail": Image.open(out_dir / p["scarfTail"]["file"]).convert("RGBA"),
        "head": Image.open(out_dir / p["head"]["file"]).convert("RGBA"),
        "bolt": Image.open(out_dir / p["bolt"]["file"]).convert("RGBA"),
        "browLeft": Image.open(out_dir / p["browLeft"]["file"]).convert("RGBA"),
        "browRight": Image.open(out_dir / p["browRight"]["file"]).convert("RGBA"),
        "eyeScleraLeft": Image.open(out_dir / p["eyeLeft"]["sclera"]["file"]).convert("RGBA"),
        "irisLeft": Image.open(out_dir / p["eyeLeft"]["iris"]["file"]).convert("RGBA"),
        "catchlightLeft": Image.open(out_dir / p["eyeLeft"]["catchlight"]["file"]).convert("RGBA"),
        "eyeLashLeft": Image.open(out_dir / p["eyeLeft"]["lash"]["file"]).convert("RGBA"),
        "eyeHappyLeft": Image.open(out_dir / p["eyeLeft"]["happyArc"]["file"]).convert("RGBA"),
        "eyeScleraRight": Image.open(out_dir / p["eyeRight"]["sclera"]["file"]).convert("RGBA"),
        "irisRight": Image.open(out_dir / p["eyeRight"]["iris"]["file"]).convert("RGBA"),
        "catchlightRight": Image.open(out_dir / p["eyeRight"]["catchlight"]["file"]).convert("RGBA"),
        "eyeLashRight": Image.open(out_dir / p["eyeRight"]["lash"]["file"]).convert("RGBA"),
        "eyeHappyRight": Image.open(out_dir / p["eyeRight"]["happyArc"]["file"]).convert("RGBA"),
    }
    for m_name, m_info in p["mouths"].items():
        imgs[f"mouth_{m_name}"] = Image.open(out_dir / m_info["file"]).convert("RGBA")
    return imgs


# ---------------------------------------------------------------------------
# Export: Zeus sprite atlases (PNG + JSON), previews
# ---------------------------------------------------------------------------

# Playback rate per state. Resting states run slow (the app also caps resting playback at ~12 fps);
# busy / snappy states run at up to 24 fps. Frame count = round(seconds * fps).
REST_FPS = 12
BUSY_FPS = 20
FAST_FPS = 24
STATE_FPS: dict[str, int] = {
    "idle": REST_FPS, "listening": REST_FPS, "approval_wait": REST_FPS, "offline": REST_FPS,
    "sleeping": REST_FPS, "paused": REST_FPS, "thinking": REST_FPS, "waking": REST_FPS,
    "welcome": BUSY_FPS, "goodbye": BUSY_FPS, "searching": BUSY_FPS, "working": BUSY_FPS,
    "organizing": BUSY_FPS, "guiding": BUSY_FPS, "confused": BUSY_FPS, "curious": BUSY_FPS,
    "grateful": BUSY_FPS, "success": BUSY_FPS,
    "typing": FAST_FPS, "walking": FAST_FPS, "carrying": FAST_FPS, "celebrate": FAST_FPS,
    "error": FAST_FPS, "surprised": FAST_FPS,
}
SUPERSAMPLE = 2
WORLD_PAD = 140  # px of headroom around the 1254 canvas for hops, raised arms and Zzz


def frame_durations_ms(n_frames: int, seconds: float) -> list[int]:
    """Integer millisecond durations that sum exactly to `seconds`."""
    total = int(round(seconds * 1000.0))
    base = [total * (i + 1) // n_frames - total * i // n_frames for i in range(n_frames)]
    return base


def quantize_atlas(sheet: Image.Image, colors: int = 256) -> Image.Image:
    """Palette-reduce an RGBA atlas (one shared palette, alpha preserved) to keep the PNG small."""
    q = sheet.quantize(colors=colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    return q


def state_timing(sid: str, kind: str, seconds: float) -> tuple[int, int, list[int], float]:
    """(fps, frame count, per-frame ms, u divisor). Loops sample [0,1); one-shots end exactly at rest (u=1) and hold."""
    fps = STATE_FPS.get(sid, BUSY_FPS)
    n = max(4, int(round(seconds * fps)))
    return fps, n, frame_durations_ms(n, seconds), float(n - 1) if kind == "one-shot" else float(n)


def compute_union_crop(
    pack_dir: Path, manifest: dict[str, Any], registrations: dict[str, Any], zzz_imgs: list[tuple[Image.Image, dict[str, Any]]],
    states_filter: set[str] | None, margin: float = 0.025, probe: int = 320,
) -> tuple[int, int, int]:
    """One square crop window (x, y, side, in padded-world px) shared by every state, so the character
    fills the small notch cell yet never gets clipped by any state's motion and never jumps between states."""
    x0, y0, x1, y1 = WORLD, WORLD, 0.0, 0.0
    k = WORLD / probe
    for st in manifest["states"]:
        sid = st["id"]
        if states_filter and sid not in states_filter:
            continue
        _, n, _, denom = state_timing(sid, st["timing_kind"], float(st["seconds"]))
        src_pose = "sleeping-clean" if sid == "sleeping" else sid
        pose_img = Image.open(pack_dir / "assets" / "poses" / f"{src_pose}.png").convert("RGBA")
        for i in range(n):
            f = render_state_frame(sid, i / denom, pose_img, registrations[src_pose], zzz_imgs, probe)
            bb = f.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
            if bb:
                x0, y0, x1, y1 = min(x0, bb[0] * k), min(y0, bb[1] * k), max(x1, bb[2] * k), max(y1, bb[3] * k)
    side = int(min(WORLD, math.ceil(max(x1 - x0, y1 - y0) * (1.0 + 2.0 * margin))))
    cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
    ox = int(round(min(max(cx - side / 2, 0), WORLD - side)))
    oy = int(round(min(max(cy - side / 2, 0), WORLD - side)))
    return ox, oy, side


def export_zeus_atlases(
    pack_dir: Path,
    out_dir: Path,
    manifest: dict[str, Any],
    rig_meta: dict[str, Any],
    registrations: dict[str, Any],
    sizes: list[int],
    atlas_dir: Path,
    preview_dir: Path | None,
    states_filter: set[str] | None,
    quantize: bool,
) -> dict[str, Any]:
    """Render every manifest state once (supersampled) and pack per-size sprite atlases + JSON metadata."""
    sizes = sorted(set(sizes))
    work = max(sizes) * SUPERSAMPLE
    zzz_imgs = [(Image.open(out_dir / z["file"]).convert("RGBA"), z) for z in rig_meta["parts"]["zzz"]]
    for s in sizes:
        (atlas_dir / str(s)).mkdir(parents=True, exist_ok=True)
    if preview_dir is not None:
        (preview_dir / "webp").mkdir(parents=True, exist_ok=True)
        (preview_dir / "apng").mkdir(parents=True, exist_ok=True)

    world_padding(WORLD_PAD)
    crop_x, crop_y, crop_side = compute_union_crop(pack_dir, manifest, registrations, zzz_imgs, states_filter)
    # Render so the crop window is exactly `work` px; then cut it out.
    canvas = int(math.ceil(WORLD * work / crop_side))
    kx = canvas / WORLD
    box = (int(round(crop_x * kx)), int(round(crop_y * kx)), int(round(crop_x * kx)) + work, int(round(crop_y * kx)) + work)
    print(f"  union crop window: x={crop_x} y={crop_y} side={crop_side} of the {int(WORLD)} px padded world -> render canvas {canvas}")

    index: dict[str, Any] = {"version": 1, "sizes": sizes, "crop": {"x": crop_x - int(ORIGIN), "y": crop_y - int(ORIGIN), "side": crop_side, "poseCanvas": CANVAS, "note": "window in 1254 px pose-canvas coordinates (negative = padding above/left)"}, "states": {}}
    for st in manifest["states"]:
        sid = st["id"]
        if states_filter and sid not in states_filter:
            continue
        seconds = float(st["seconds"])
        kind = st["timing_kind"]
        fps, n, durations, denom = state_timing(sid, kind, seconds)

        src_pose = "sleeping-clean" if sid == "sleeping" else sid
        pose_img = Image.open(pack_dir / "assets" / "poses" / f"{src_pose}.png").convert("RGBA")
        reg = registrations[src_pose]
        # Loops sample [0,1) so the last frame leads into the first; one-shots end exactly at rest (u=1) and hold.
        big = [render_state_frame(sid, i / denom, pose_img, reg, zzz_imgs, canvas).crop(box) for i in range(n)]

        cols = int(math.ceil(math.sqrt(n)))
        rows = int(math.ceil(n / cols))
        entry: dict[str, Any] = {
            "name": st["name"],
            "motion": st["motion"],
            "kind": kind,
            "seconds": seconds,
            "fps": fps,
            "frameCount": n,
            "cols": cols,
            "rows": rows,
            "frameDurationsMs": durations,
            "sizes": {},
        }
        for s in sizes:
            sheet = Image.new("RGBA", (cols * s, rows * s), (0, 0, 0, 0))
            cells = [f.resize((s, s), Image.Resampling.LANCZOS) for f in big]
            for i, c in enumerate(cells):
                sheet.paste(c, ((i % cols) * s, (i // cols) * s))
            path = atlas_dir / str(s) / f"{sid}.png"
            (quantize_atlas(sheet) if quantize else sheet).save(path, optimize=True)
            entry["sizes"][str(s)] = {
                "file": f"{s}/{sid}.png",
                "cell": s,
                "width": cols * s,
                "height": rows * s,
                "bytes": path.stat().st_size,
                "frames": [
                    {"i": i, "x": (i % cols) * s, "y": (i // cols) * s, "w": s, "h": s, "ms": durations[i]}
                    for i in range(n)
                ],
            }
            if s == sizes[-1] and preview_dir is not None:
                cells[0].save(
                    preview_dir / "webp" / f"{sid}.webp", format="WEBP", save_all=True, append_images=cells[1:],
                    duration=durations, loop=0 if kind == "loop" else 1, quality=86, method=4,
                )
                cells[0].save(
                    preview_dir / "apng" / f"{sid}.png", format="PNG", save_all=True, append_images=cells[1:],
                    duration=durations, loop=0 if kind == "loop" else 1, disposal=1,
                )
        (atlas_dir / f"{sid}.json").write_text(json.dumps({"state": sid, **entry}, indent=1) + "\n", encoding="utf-8")
        index["states"][sid] = {k: entry[k] for k in ("name", "kind", "seconds", "fps", "frameCount", "cols", "rows")}
        print(f"  {sid:14s} {kind:8s} {n:3d}f @{fps}fps  " + "  ".join(f"{s}px:{entry['sizes'][str(s)]['bytes']//1024}KB" for s in sizes))

    (atlas_dir / "index.json").write_text(json.dumps(index, indent=1) + "\n", encoding="utf-8")
    world_padding(0)
    return index


def export_puppet_showcase(out_dir: Path, rig_meta: dict[str, Any], preview_dir: Path, size: int = 320) -> None:
    """Flagship articulated-puppet clip (previews only, never shipped)."""
    part_imgs = load_rig_part_images(out_dir, rig_meta)
    frames = []
    n_pup = 36
    for i in range(n_pup):
        u = i / float(n_pup)
        tau = 2.0 * math.pi * u
        gx = 0.85 * math.sin(tau)
        gy = -0.45 * math.sin(2.0 * tau)
        hop = -24.0 * max(0.0, math.sin(tau * 2.0 - 1.2)) ** 2 if 0.52 < u < 0.82 else -6.0 * (0.5 - 0.5 * math.cos(tau * 2.0))
        wave_l = 36.0 * abs(math.sin(tau * 3.0)) if u < 0.38 else 6.0 * math.sin(tau)
        bl = max(blink_curve(u, 0.24, 0.05), blink_curve(u, 0.88, 0.05))
        mouth = "ooh" if (0.14 < u < 0.24) else ("smile" if (0.35 < u < 0.52) else "happy")
        frames.append(render_puppet_frame(
            rig_meta, part_imgs, size, gaze_x=gx, gaze_y=gy, blink=bl, happy_eyes=0.56 <= u <= 0.76,
            head_rot=5.5 * math.sin(tau - 0.22), head_dx=gx * 10.0, bolt_rot=-8.0 * math.sin(tau - 0.45),
            scarf_rot=-12.0 * math.sin(tau - 0.50), paw_l_rot=wave_l, paw_r_rot=-14.0 * math.sin(tau * 2.0),
            foot_l_dy=min(0.0, hop * 0.4), foot_r_dy=min(0.0, hop * 0.4), body_dy=hop,
            brow_l_dy=-8.0 * abs(math.sin(tau)), brow_r_dy=-6.0 * abs(math.cos(tau)), mouth=mouth,
        ))
    (preview_dir / "webp").mkdir(parents=True, exist_ok=True)
    (preview_dir / "apng").mkdir(parents=True, exist_ok=True)
    frames[0].save(preview_dir / "webp" / "puppet-showcase.webp", format="WEBP", save_all=True, append_images=frames[1:], duration=95, loop=0, quality=88, method=4)
    frames[0].save(preview_dir / "apng" / "puppet-showcase.png", format="PNG", save_all=True, append_images=frames[1:], duration=95, loop=0, disposal=1)


def sha256_file(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def write_rig_checksums(out_dir: Path, extra: list[Path]) -> int:
    targets = sorted(
        list((out_dir / "assets" / "rig").glob("*.png"))
        + [p for p in [out_dir / "rig-metadata.json"] if p.exists()]
        + [p for e in extra for p in sorted(e.rglob("*")) if p.is_file()]
    )
    lines = [f"{sha256_file(t)}  {t.relative_to(out_dir).as_posix() if t.is_relative_to(out_dir) else t.name}" for t in targets]
    (out_dir / "SHA256SUMS.rig.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return len(lines)


def verify_pack_untouched(pack_dir: Path) -> bool:
    """Check every entry of the pack's own SHA256SUMS.txt (read-only)."""
    sums = pack_dir / "SHA256SUMS.txt"
    if not sums.exists():
        return True
    bad = 0
    for line in sums.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        digest, _, rel = line.partition("  ")
        f = pack_dir / rel.strip()
        if not f.is_file() or sha256_file(f) != digest:
            bad += 1
            print(f"  MISMATCH {rel}")
    return bad == 0


def main() -> None:
    here = Path(__file__).resolve().parent
    default_pack = here.parent.parent / "Design" / "mascot-v2" / "ZEUS_Mascot_Pack_v2"
    parser = argparse.ArgumentParser(description="Build ZEUS v2.5 2.5D Puppet Rig, Registrations & Animation Exports")
    parser.add_argument("--pack", type=Path, default=default_pack, help="v2 mascot pack directory (read-only)")
    parser.add_argument("--out", type=Path, default=Path("/tmp/zeus-mascot-out"), help="derived output dir: assets/rig, rig-metadata.json, SHA256SUMS.rig.txt")
    parser.add_argument("--atlas-out", type=Path, default=None, help="where Zeus atlases go (default: <out>/atlas); e.g. Sources/Zeus/Avatar/Anim")
    parser.add_argument("--preview-dir", type=Path, default=None, help="optional dir for animated WebP/APNG previews (keep outside the repo)")
    parser.add_argument("--qa-out", type=Path, default=None, help="Optional path for visual QA contact sheet")
    parser.add_argument("--skip-exports", action="store_true", help="Only build rig layers + metadata + QA sheet")
    parser.add_argument("--export-size", type=int, nargs="+", default=[128, 320], help="atlas cell sizes in px (default: 128 320)")
    parser.add_argument("--states", nargs="*", default=None, help="only export these state ids")
    parser.add_argument("--no-quantize", action="store_true", help="keep full 32-bit RGBA atlases (larger)")
    args = parser.parse_args()

    pack_dir = args.pack.resolve()
    out_dir = args.out.resolve()
    if out_dir == pack_dir or pack_dir in out_dir.parents:
        parser.error("--out must be outside the pack directory (the pack is never modified)")
    out_dir.mkdir(parents=True, exist_ok=True)
    atlas_dir = (args.atlas_out or (out_dir / "atlas")).resolve()
    manifest = json.loads((pack_dir / "manifest.json").read_text(encoding="utf-8"))

    print("[1/4] Extracting 2.5D Puppet Rig layers...")
    puppet = extract_puppet_rig(pack_dir, out_dir)

    print("[2/4] Computing ground-line & head-scale registrations for all poses...")
    registrations = compute_pose_registrations(pack_dir)

    metadata: dict[str, Any] = {
        "version": "2.5.0",
        "character": "Zeus",
        "canonicalMaster": "assets/poses/idle.png",
        "puppet": puppet,
        "registrations": registrations,
    }

    if args.qa_out is not None:
        print(f"[QA] Rendering visual verification sheet -> {args.qa_out}")
        build_qa_sheet(pack_dir, out_dir, puppet, registrations, args.qa_out)

    extra: list[Path] = []
    if not args.skip_exports:
        print(f"[3/4] Rendering Zeus sprite atlases at {args.export_size} px -> {atlas_dir}")
        metadata["exports"] = export_zeus_atlases(
            pack_dir, out_dir, manifest, puppet, registrations, args.export_size, atlas_dir,
            args.preview_dir, set(args.states) if args.states else None, not args.no_quantize,
        )
        if args.preview_dir is not None:
            export_puppet_showcase(out_dir, puppet, args.preview_dir)
        extra.append(atlas_dir)

    (out_dir / "rig-metadata.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    count = write_rig_checksums(out_dir, extra)
    ok = verify_pack_untouched(pack_dir)
    print(f"[4/4] Done. rig-metadata.json + {count} SHA-256 entries in SHA256SUMS.rig.txt. Original pack checksums valid: {ok}")
    if not ok:
        raise SystemExit("original pack files changed!")


if __name__ == "__main__":
    main()
