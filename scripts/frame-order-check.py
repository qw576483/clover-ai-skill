#!/usr/bin/env python3
"""OFFLINE check of sprite-sheet frame ORDER and per-frame PIVOT anchor.

WHY IT EXISTS: two of the classic "the sprite shivers / the body slides on every frame change"
root causes are pure resource/import facts, so they can be judged WITHOUT the editor and
WITHOUT Play mode (seconds, not minutes).  This script reads the `.png.meta` files that Unity
itself wrote, so it is ground truth for what the importer produced -- it does not trust any C#
code and needs no third-party module (stdlib only).

  cause A (frame order): a sub-sprite may be named like `frame_000_0`
      (`.meta` -> spriteSheet.sprites[i].name).  A parser that takes the digits at the END of the
      name gets "0" for EVERY frame of that shape => one distinct sort key => the sort is a no-op
      => playback order is whatever the loader happened to return.  The fix is to take the
      second-to-last purely numeric underscore segment.  Both counts are printed, so the defect
      and its fix are visible on one line.
  cause B (per-frame pivot): every sub-sprite's pivot is the centre of its OWN crop rect, and the
      crop rects differ per frame => the body shifts on every frame change.  A fix must give every
      frame of a directory the SAME texture-space anchor.  Printed per frame, plus the two
      candidate shared anchors a rebuild can use.

Usage
    python frame-order-check.py <sprite-dir-name> [--sprite-root <dir>] [--areas a,b,c]

  --sprite-root  root that holds the sprite folders            (default: ./client/Assets/Resources/Sprites)
  --areas        comma-separated sub-folders to look in; empty = walk the whole sprite root
  <sprite-dir-name> is matched as a DIRECTORY BASENAME (not a path), so one name can exist under
  several areas and every hit is checked.

Output is ASCII only on purpose: this script must stay readable in any console code page.
Exit code 0 = the directory was checked (whatever the verdict); 2 = directory not found;
3 = sibling modules could not be parsed.

NOTE: the numbers printed here are FACTS about the import (rects, pivots, sort keys) -- this
script deliberately prints no pass/fail verdict of its own, because "which anchor is correct"
comes from the reference game's baseline image, not from this file.
"""

import argparse
import os
import re
import sys


def abs_path(p):
    """Every path this script reports must be absolute: a relative root gets resolved against
    whatever CWD the caller happened to be in, which silently reports "no such frame"."""
    return os.path.abspath(os.path.expanduser(p))


# A Unity sprite name may contain dots/digits ("Seg.1", "frame_003"); the parse only cares about
# the underscore-separated numeric segments.
NAME_RE = re.compile(r"^\s*name:\s*(\S+)\s*$", re.M)
RECT_RE = re.compile(
    r"^\s*name:\s*(\S+)\s*\n"          # the sub-sprite name
    r"\s*rect:\s*\n"
    r"\s*serializedVersion:\s*\d+\s*\n"
    r"\s*x:\s*(-?\d+)\s*\n"
    r"\s*y:\s*(-?\d+)\s*\n"
    r"\s*width:\s*(-?\d+)\s*\n"
    r"\s*height:\s*(-?\d+)\s*\n",
    re.M,
)
PPU_RE = re.compile(r"^\s*spritePixelsToUnits:\s*([\d.]+)\s*$", re.M)


def second_last_numeric(name):
    """Fixed rule: the second-to-last purely numeric underscore segment.

    frame_000_0 -> 0 ; frame_7_1 -> 7 ; frame_003 -> 3 ; gen_frame_012 -> 12 ;
    a name with no numeric segment -> -1
    """
    if not name:
        return -1
    segs = name.split("_")
    for i in range(len(segs) - 2, -1, -1):
        if segs[i].isdigit():
            return int(segs[i])
    if segs and segs[-1].isdigit():
        return int(segs[-1])
    return -1


def tail_numeric(name):
    """The broken rule kept for comparison: digits at the very end of the name."""
    if not name:
        return -1
    digits = 0
    for ch in reversed(name):
        if ch.isdigit():
            digits += 1
        else:
            break
    return int(name[len(name) - digits:]) if digits else -1


def png_size(path):
    """Read width/height straight out of the PNG IHDR chunk (stdlib only, no Pillow)."""
    try:
        with open(path, "rb") as fh:
            head = fh.read(24)
    except OSError:
        return None
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")


def find_dirs(sprite_root, sprite_dir, areas):
    """Locate every directory named <sprite_dir>. Returns (hits, scanned_root)."""
    hits = []
    if areas:
        for area in areas:
            d = os.path.join(sprite_root, area, sprite_dir)
            if os.path.isdir(d):
                hits.append(abs_path(d))
        return hits, sprite_root
    for dp, dns, _fns in os.walk(sprite_root):
        for dn in list(dns):
            if dn == sprite_dir:
                hits.append(abs_path(os.path.join(dp, dn)))
    return sorted(hits), sprite_root


def check(path):
    metas = sorted(f for f in os.listdir(path) if f.endswith(".png.meta"))
    frames = []
    ppu = None
    for m in metas:
        try:
            text = open(os.path.join(path, m), encoding="utf-8").read()
        except OSError as exc:
            print("  !! unreadable %s : %s" % (m, exc))
            continue
        mm = RECT_RE.search(text)
        if not mm:
            print("  !! no sprite rect found in %s" % m)
            continue
        if ppu is None:
            p = PPU_RE.search(text)
            ppu = float(p.group(1)) if p else None
        frames.append({
            "meta": m, "name": mm.group(1),
            "x": int(mm.group(2)), "y": int(mm.group(3)),
            "w": int(mm.group(4)), "h": int(mm.group(5)),
        })

    print("dir            = %s" % path)
    print("png.meta count = %d   (sprites parsed = %d)   ppu = %s" % (len(metas), len(frames), ppu))
    if not frames:
        print("  !! no sub-sprite rect parsed at all -- NOT-JUDGED for this directory")
        return

    # A union anchor is only meaningful if every frame really is a crop of ONE shared canvas:
    # print the canvas sizes instead of assuming it.
    sizes = {}
    for f in frames:
        s = png_size(os.path.join(path, f["meta"][:-5]))   # strip the ".meta" suffix
        sizes.setdefault(s, []).append(f["name"])
    readable = ["%sx%s (%d frames)" % (k[0], k[1], len(v)) for k, v in sizes.items() if k]
    print("canvas size(s) = %s" % (", ".join(readable) if readable else "(unreadable)"))

    # --- frame ORDER (cause A) -------------------------------------------------
    by_new = sorted(frames, key=lambda f: second_last_numeric(f["name"]))
    keys_new = [second_last_numeric(f["name"]) for f in by_new]
    keys_old = set(tail_numeric(f["name"]) for f in frames)
    print("")
    print("[cause A] frame order")
    print("  sortedFirst5 (by fixed rule) = %s" % " ".join(f["name"] for f in by_new[:5]))
    print("  sortedLast5  (by fixed rule) = %s" % " ".join(f["name"] for f in by_new[-5:]))
    print("  indexFirst5 = %s   indexLast5 = %s" % (keys_new[:5], keys_new[-5:]))
    print("  distinctKeys new(second-last) = %d   old(tail) = %d  <-- old == 1 means the sort was a NO-OP"
          % (len(set(keys_new)), len(keys_old)))
    print("  strictlyIncreasing = %s" % all(keys_new[i] > keys_new[i - 1] for i in range(1, len(keys_new))))

    # --- per-frame anchor (cause B) -------------------------------------------
    # Unity's importer sets pivot = centre of each sprite's own rect.  Textures of one directory
    # share the same canvas (checked above), so the anchor in TEXTURE pixels for frame i is
    # (rect.x + w/2, rect.y + h/2).
    x0 = min(f["x"] for f in frames)
    y0 = min(f["y"] for f in frames)
    x1 = max(f["x"] + f["w"] for f in frames)
    y1 = max(f["y"] + f["h"] for f in frames)
    print("")
    print("[cause B] per-frame pivot / shared anchor")
    print("  union rect (canvas px) = x=%d y=%d w=%d h=%d" % (x0, y0, x1 - x0, y1 - y0))
    print("  candidate anchor A (union bottom-centre) = (%.1f, %.1f)" % ((x0 + x1) / 2.0, float(y0)))
    print("  candidate anchor B (union centre)        = (%.1f, %.1f)" % ((x0 + x1) / 2.0, (y0 + y1) / 2.0))
    print("  rect.y range = %d..%d   rect.x range = %d..%d"
          % (min(f["y"] for f in frames), max(f["y"] for f in frames),
             min(f["x"] for f in frames), max(f["x"] for f in frames)))
    sample = by_new[:5] + by_new[-5:]
    print("  per-frame anchor of 10 frames (imported = own rect centre; MUST differ => the shift):")
    for f in sample:
        ax = f["x"] + f["w"] / 2.0
        ay = f["y"] + f["h"] / 2.0
        print("    idx=%-4s name=%-14s rect=(%d,%d,%d,%d) anchor=(%.1f,%.1f)"
              % (second_last_numeric(f["name"]), f["name"], f["x"], f["y"], f["w"], f["h"], ax, ay))
    axs = set((f["x"] + f["w"] / 2.0, f["y"] + f["h"] / 2.0) for f in frames)
    print("  distinct anchors across ALL %d frames = %d  <-- >1 is exactly the per-frame shift"
          % (len(frames), len(axs)))
    spread_x = max(a[0] for a in axs) - min(a[0] for a in axs)
    spread_y = max(a[1] for a in axs) - min(a[1] for a in axs)
    print("  anchor spread = %.1f px x %.1f px  (= %.3f x %.3f tiles at ppu=%s)"
          % (spread_x, spread_y, spread_x / (ppu or 100.0), spread_y / (ppu or 100.0), ppu))
    print("")
    print("  note: Sprite.Create's pivot argument is RECT-RELATIVE normalized, so a shared")
    print("        TEXTURE anchor (ax, ay) is expressed per frame as ((ax-x)/w, (ay-y)/h).")


def main(argv):
    ap = argparse.ArgumentParser(description="offline sprite frame-order / pivot check")
    ap.add_argument("sprite_dir", help="directory basename that holds the frame .png.meta files")
    ap.add_argument("--sprite-root", default=os.path.join(os.getcwd(), "client", "Assets", "Resources", "Sprites"),
                    help="root holding the sprite folders (default: ./client/Assets/Resources/Sprites)")
    ap.add_argument("--areas", default="", help="comma-separated sub-folders; empty = walk the whole root")
    a = ap.parse_args(argv[1:])
    sprite_root = abs_path(a.sprite_root)
    areas = [x for x in a.areas.split(",") if x]
    if not os.path.isdir(sprite_root):
        print("sprite root not found: %s" % sprite_root)
        return 2
    dirs, _ = find_dirs(sprite_root, a.sprite_dir, areas)
    if not dirs:
        print("directory not found under %s : %s" % (sprite_root, a.sprite_dir))
        return 2
    for d in dirs:
        check(d)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
