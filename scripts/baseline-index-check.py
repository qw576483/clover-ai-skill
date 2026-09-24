#!/usr/bin/env python3
"""OFFLINE check that the artifact a chain ran on IS the frozen baseline, and that the baseline
snapshot covers the dependencies that chain registered.  Seconds-level, read-only.

WHY: an append-only baseline INDEX is only useful if two things hold --
  (1) the retained artifact is honest: its FILENAME (the recorded baseline id) equals the real hash
      of its bytes -- a file that was replaced in place under the same name is otherwise undetectable;
  (2) the index READ RULE is applied: for one baseline id the rows are append-only and the
      AUTHORITATIVE row is the LAST one by frozen-at; earlier rows are SUPERSEDED.  A dependency that
      lives only in a superseded row is a FAIL, not a pass -- that failure mode ("the row I happened
      to match first") is exactly why the rule had to be written down.

Hard rules baked in (each earned by a real incident):
  * every path is ABSOLUTE (derived from -Root) -- a relative path gets resolved against whatever CWD
    the caller had, and then `None.Length == None.Length` looks like "lengths equal = True";
  * no bare equality on possibly-null values: anything that must exist is asserted non-None first;
  * missing / unreadable => a loud NOT-JUDGED, never a silent pass;
  * matchedRows is always PRINTED (never silently picking one row).

Index schema (columns, TAB separated, `#` comments allowed):
    0 sha256_16 | 1 artifact-file | 2 bytes | 3 frozen-at (ISO) | 4 declared-by | 5 mtime-snapshot
  The mtime-snapshot cell holds the snapshot blob (path=value pairs) as one field.

Usage
    python baseline-index-check.py --root <projectRoot> --baseline <sha256_16> \
        --index <rel/path/index.tsv> [--live <rel/path/artifact.dll>] \
        [--retained <rel/path/artifact.dll>] [--deps <rel/path/deps.tsv>]

  --retained   default: <retained-dir>/<baseline>.dll  (--retained-dir defaults to the project root)
  --deps       a TSV/text file, one dependency per line: optional `<side><TAB><repo-relative path>`.
               Lines without a TAB are treated as side "dep".  Listed dependencies must appear in the
               mtime-snapshot cell of the AUTHORITATIVE row.

Exit code: 0 = all required checks pass; 1 = at least one FAIL (NOT-JUDGED items are printed and do
not by themselves fail the run, but they are never counted as passes).
"""
import argparse
import hashlib
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except (AttributeError, ValueError):
    pass     # older interpreter / non-tty: the ASCII-only output must still work


def sha16(p):
    if not p or not os.path.isfile(p):
        return None
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:16].upper()


def readb(p):
    if not p or not os.path.isfile(p):
        return None
    with open(p, "rb") as fh:
        return fh.read()


def apath(root, p):
    return os.path.abspath(p if os.path.isabs(p) else os.path.join(root, p))


def main(argv):
    ap = argparse.ArgumentParser(description="offline frozen-baseline / index read-rule check")
    ap.add_argument("--root", required=True, help="project root (all relative paths resolve here)")
    ap.add_argument("--baseline", required=True, help="the baseline id = sha256_16, UPPERCASE")
    ap.add_argument("--index", required=True, help="baseline index TSV (relative to --root)")
    ap.add_argument("--live", default="", help="the live artifact of this run (optional)")
    ap.add_argument("--retained", default="", help="retained artifact; default <retained-dir>/<baseline>.dll")
    ap.add_argument("--retained-dir", default=".", help="dir holding retained artifacts (default .)")
    ap.add_argument("--deps", default="", help="file listing registered dependencies (optional)")
    ap.add_argument("--expected-cols", type=int, default=6, help="index column count (default 6)")
    a = ap.parse_args(argv[1:])

    root = os.path.abspath(a.root)
    base = a.baseline.strip().upper()
    retained = apath(root, a.retained) if a.retained else os.path.join(apath(root, a.retained_dir), base + ".dll")
    index = apath(root, a.index)
    live = apath(root, a.live) if a.live else ""

    fails, notjudged = [], []
    print("ROOT     = %s" % root)
    print("baseline = %s" % base)

    # ---- 1) the retained artifact must be honest: filename == real hash -------------
    r_hash = sha16(retained)
    if r_hash is None:
        fails.append("retained artifact MISSING -> NOT-JUDGED: %s" % retained)
        print("1 retained : !! MISSING -> NOT-JUDGED: %s" % retained)
    else:
        ok = (r_hash == base)
        print("1 retained : filename=%s real_sha256_16=%s honest=%s" % (base, r_hash, ok))
        if not ok:
            fails.append("retained artifact filename != real hash")

    # ---- 2) retained must be byte-identical to the live artifact of that moment -----
    if not live:
        notjudged.append("byte-identical: no --live given")
        print("2 identical: !! NOT-JUDGED (no --live given)")
    else:
        rb, lb = readb(retained), readb(live)
        if rb is None or lb is None:
            notjudged.append("byte-identical: retained readable=%s live readable=%s" % (rb is not None, lb is not None))
            print("2 identical: !! NOT-JUDGED (retained_readable=%s live_readable=%s)" % (rb is not None, lb is not None))
        else:
            same = (len(rb) == len(lb)) and (rb == lb)
            print("2 identical: len retained=%d live=%d byte_equal=%s" % (len(rb), len(lb), same))
            if not same:
                # expected AFTER the freeze batch edits code: it only invalidates rows not captured
                # on the baseline.  Reported, not failed.
                print("             (the live artifact has moved on since the baseline -- expected once code"
                      " changed after the freeze)")

    # ---- 3) live hash vs baseline (informational) ----------------------------------
    live_hash = sha16(live) if live else None
    print("3 live     : sha256_16=%s  == base? %s" % (live_hash, live_hash == base if live_hash else None))

    # ---- 4) index: schema, baseline present, read rule ------------------------------
    latest = None
    if not os.path.isfile(index):
        notjudged.append("index missing")
        print("4 index    : !! MISSING -> NOT-JUDGED: %s" % index)
    else:
        rows = []
        with open(index, encoding="utf-8") as fh:
            for ln in fh:
                ln = ln.rstrip("\n")
                if not ln.strip() or ln.lstrip().startswith("#"):
                    continue
                rows.append(ln.split("\t"))
        badcols = [i for i, r in enumerate(rows) if len(r) != a.expected_cols]
        print("4 index    : data_rows=%d  rows_with_cols!=%d = %s" % (len(rows), a.expected_cols, badcols[:10]))
        if badcols:
            fails.append("index has %d row(s) with != %d columns" % (len(badcols), a.expected_cols))
        col0 = [r[0] for r in rows]
        print("             baseline in col0 = %s" % (base in col0))
        if live_hash:
            print("             live in col0     = %s" % (live_hash in col0))
        if base not in col0:
            fails.append("baseline %s not in the index" % base)
        mine = [(i, r) for i, r in enumerate(rows) if r[0] == base]
        print("4b read-rule: rows with col0==%s : matchedRows=%d  (NOT silently taking one)" % (base, len(mine)))
        if not mine:
            notjudged.append("no row for this baseline -> cannot apply the last-row read rule")
        else:
            for i, r in mine:
                print("             row[%d] frozen-at=%s bytes=%s snapshot_chars=%d"
                      % (i, r[3], r[2], len(r[5]) if len(r) > 5 else -1))
            order = sorted(mine, key=lambda t: t[1][3])       # ISO-8601 sorts lexicographically
            nondec = all(order[k][1][3] <= order[k + 1][1][3] for k in range(len(order) - 1))
            print("             frozen-at non-decreasing = %s" % nondec)
            if not nondec:
                fails.append("index frozen-at is not non-decreasing for %s" % base)
            li, latest = order[-1]
            print("             AUTHORITATIVE row = row[%d] frozen-at=%s (LAST by frozen-at)" % (li, latest[3]))
            if li != len(rows) - 1:
                print("             NOTE the authoritative row is not the physically last row -- later rows"
                      " carry a different id, which is exactly why the rule is 'by frozen-at'")

    # ---- 5) registered dependencies must be in the AUTHORITATIVE row's snapshot -----
    deps = []
    if a.deps:
        dep_path = apath(root, a.deps)
        if not os.path.isfile(dep_path):
            notjudged.append("deps file missing: %s" % dep_path)
            print("5 deps     : !! NOT-JUDGED (deps file missing: %s)" % dep_path)
        else:
            with open(dep_path, encoding="utf-8") as fh:
                for ln in fh:
                    ln = ln.rstrip("\n")
                    if not ln.strip() or ln.lstrip().startswith("#"):
                        continue
                    parts = ln.split("\t")
                    deps.append((parts[0].strip() if len(parts) > 1 else "dep",
                                 (parts[1] if len(parts) > 1 else parts[0]).strip()))
    else:
        notjudged.append("no --deps given: registered dependencies were not judged")
        print("5 deps     : !! NOT-JUDGED (no --deps given)")

    if deps:
        print("5 deps in the mtime-snapshot of the AUTHORITATIVE row:")
        if latest is None:
            print("             !! NOT-JUDGED (no authoritative row)")
            for side, p in deps:
                notjudged.append("dependency not judged (no authoritative row): %s" % p)
        else:
            mine_rows = [(i, r) for i, r in enumerate(rows) if r[0] == base]
            blob_all = "\n".join(r[5] for _i, r in mine_rows if len(r) > 5)
            for side, p in deps:
                hit = (len(latest) > 5) and (p in latest[5])
                hit_any = p in blob_all
                print("             %-6s %-72s latest=%s  (any-of-%d-rows=%s)" % (side, p, hit, len(mine_rows), hit_any))
                if not hit:
                    if hit_any:
                        fails.append("dependency ONLY in a SUPERSEDED row (dropped by the authoritative row): %s" % p)
                    else:
                        fails.append("dependency not in the mtime-snapshot: %s" % p)

    print("")
    print("RESULT: fails=%d not_judged=%d" % (len(fails), len(notjudged)))
    for x in fails:
        print("  FAIL: " + x)
    for x in notjudged:
        print("  NOT-JUDGED: " + x)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
