#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check-delivery-docs.py -- the two delivery self-checks that verify.ps1 does not cover.

Skill source: `clover-engine` -> reference/verify-template.md (必查项第 5 / 9 条) and
reference/game-delivery.md (交付闸门详述 ①②③).

  1) CITED PATHS RESOLVE ("路径可达")
     Every concrete file path cited by the delivery documents must exist on disk --
     a citation that points at nothing is worse than no citation, because it reads
     like evidence. When a path does not resolve at the project root, a basename
     fallback is tried (docs legitimately mention paths relative to another root,
     e.g. a baseline image); that fallback can be turned off with
     --no-basename-fallback.

  2) ACCEPTANCE TABLE: THE CONCLUSION COLUMN IS FILLED AND CLEAN ("验收表零空行")
     Only the CONCLUSION cell is judged (an evidence cell is allowed to contain the
     word -- e.g. "delta vs the poster = 0"): it must be non-empty and must not
     carry a non-verdict word (default: 不一致 / 待验 / 未验 / 待补). The class
     column, when present, must name one of the evidence classes. Plus: a blank
     line INSIDE a table body is reported (most renderers silently break the table
     there).

     The column is found from the TABLE HEADER, not from a fixed position, so both
     `| # | ... | 类别 | 证据 | 结论 |` and the older `| # | ... | 证据 | 结论 | 类别 |`
     are handled correctly. Tables without a conclusion column (e.g. the
     allowed-differences table) are skipped rather than mis-judged.

Exit code 0 = everything PASS.

Usage:
  python check-delivery-docs.py --root <project> \
      --docs "策划/验收表.md,策划/对照表.md" \
      --cite-prefix client --cite-prefix tools --cite-prefix 策划

Options:
  --root PATH               project root (default: cwd)
  --docs SPEC               comma/semicolon separated doc paths, relative to --root
                            (default: 策划/验收表.md,策划/对照表.md). Repeatable.
  --cite-prefix P           a path prefix that counts as a citation (repeatable).
                            Default: client tools .ai-tmp 策划 docs 原版资源
  --cite-ext E              file extension that counts as a citation (repeatable).
  --no-basename-fallback    do not accept "basename exists somewhere under root"
  --conclusion-col NAME     header cell naming the conclusion column (default: 结论)
  --class-col NAME          header cell naming the evidence-class column (default: 类别)
  --bad-word W              a word that must NOT appear in a conclusion (repeatable).
                            Default: 不一致 待验 未验 待补
  --class-word W            an accepted evidence class (repeatable).
                            Default: 数值类 表现类 性能类
  --no-require-class        do not require the class column to be filled
  --allow-blank-in-table    do not report blank lines inside a table body
  --json PATH               also write the machine-readable result here
"""

import argparse
import glob
import json
import os
import re
import sys

DEFAULT_DOCS = ("策划/验收表.md", "策划/对照表.md")
DEFAULT_PREFIXES = ("client", "tools", ".ai-tmp", "策划", "docs", "原版资源")
DEFAULT_EXTS = ("cs", "py", "ps1", "md", "txt", "png", "tsv", "jpg", "jpeg", "gif",
                "wav", "mp3", "ttf", "otf", "prefab", "unity", "asset", "meta",
                "json", "csproj", "xlsx", "csv")
DEFAULT_BAD = ("不一致", "待验", "未验", "待补")
DEFAULT_CLASSES = ("数值类", "表现类", "性能类")

SEPARATOR_RE = re.compile(r"^\|[\s\-:|]+\|$")


def split_specs(values):
    out = []
    for v in values:
        for chunk in str(v).replace(";", ",").split(","):
            chunk = chunk.strip()
            if chunk:
                out.append(chunk)
    return out


def split_row(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def parse_tables(lines):
    """Yield (header_line_idx, header_cells, rows) for every GitHub-style table."""
    tables = []
    i = 0
    while i < len(lines):
        if lines[i].strip().startswith("|") and i + 1 < len(lines) and SEPARATOR_RE.match(lines[i + 1].strip()):
            header = split_row(lines[i])
            rows = []
            j = i + 2
            while j < len(lines) and lines[j].strip().startswith("|"):
                rows.append((j + 1, split_row(lines[j])))   # 1-based line number
                j += 1
            tables.append((i + 1, header, rows))
            i = j
        else:
            i += 1
    return tables


def build_parser():
    p = argparse.ArgumentParser(
        prog="check-delivery-docs.py",
        description="Delivery-doc self-check: cited paths resolve + acceptance conclusions are filled and clean.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--root", default="", help="project root (default: cwd)")
    p.add_argument("--docs", action="append", default=[], help="doc paths, relative to --root (repeatable)")
    p.add_argument("--cite-prefix", action="append", default=[], help="path prefix counted as a citation (repeatable)")
    p.add_argument("--cite-ext", action="append", default=[], help="file extension counted as a citation (repeatable)")
    p.add_argument("--no-basename-fallback", action="store_true",
                   help="do not accept 'a file with this basename exists somewhere under --root'")
    p.add_argument("--conclusion-col", default="结论", help="header cell naming the conclusion column")
    p.add_argument("--class-col", default="类别", help="header cell naming the evidence-class column")
    p.add_argument("--bad-word", action="append", default=[], help="word that must not appear in a conclusion (repeatable)")
    p.add_argument("--class-word", action="append", default=[], help="accepted evidence class (repeatable)")
    p.add_argument("--no-require-class", action="store_true", help="do not require the class column to be filled")
    p.add_argument("--allow-blank-in-table", action="store_true", help="do not report blank lines inside a table body")
    p.add_argument("--json", dest="json_path", default="", help="also write the machine-readable result here")
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    root = os.path.abspath(args.root) if args.root else os.getcwd()
    docs = split_specs(args.docs) or list(DEFAULT_DOCS)
    prefixes = split_specs(args.cite_prefix) or list(DEFAULT_PREFIXES)
    exts = split_specs(args.cite_ext) or list(DEFAULT_EXTS)
    bad_words = split_specs(args.bad_word) or list(DEFAULT_BAD)
    class_words = split_specs(args.class_word) or list(DEFAULT_CLASSES)

    doc_paths = []
    for d in docs:
        full = d if os.path.isabs(d) else os.path.join(root, d.replace("/", os.sep))
        doc_paths.append(full)

    fails = []
    report = {"root": root, "docs": [], "problems": {}}

    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:  # pragma: no cover
        pass

    # ---------- 1) cited paths resolve ----------
    cite_re = re.compile(
        r"((?:" + "|".join(re.escape(p) for p in prefixes) + r")/[A-Za-z0-9_./\u4e00-\u9fff\-]*"
        r"\.(?:" + "|".join(re.escape(e) for e in exts) + r"))"
    )
    seen = {}
    missing_docs = []
    for doc in doc_paths:
        if not os.path.isfile(doc):
            missing_docs.append(doc)
            continue
        with open(doc, encoding="utf-8", errors="replace") as fh:
            txt = fh.read()
        report["docs"].append(doc)
        for m in cite_re.finditer(txt):
            seen[m.group(1)] = seen.get(m.group(1), 0) + 1

    print("[1] cited paths: %d distinct" % len(seen))
    unresolved = []
    for p, n in sorted(seen.items()):
        full = os.path.join(root, p.replace("/", os.sep))
        if os.path.exists(full):
            continue
        if not args.no_basename_fallback:
            hits = glob.glob(os.path.join(root, "**", os.path.basename(p)), recursive=True)
            if hits:
                continue
        unresolved.append((p, n))
    for p, n in unresolved:
        print("    MISSING x%d  %s" % (n, p))
    print("    -> %d unresolvable" % len(unresolved))
    if unresolved:
        fails.append("cited-path")
    for doc in missing_docs:
        print("    DOC NOT FOUND: %s" % doc)
    if missing_docs:
        fails.append("doc-missing")

    # ---------- 2) acceptance tables ----------
    rows_judged = 0
    problems = []
    blank_in_table = []
    tables_seen = 0
    verdict_tables = 0
    for doc in doc_paths:
        if not os.path.isfile(doc):
            continue
        with open(doc, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().split("\n")

        if not args.allow_blank_in_table:
            for i in range(1, len(lines) - 1):
                if lines[i].strip() != "":
                    continue
                if not lines[i - 1].rstrip().startswith("|") or not lines[i + 1].strip().startswith("|"):
                    continue
                nxt = lines[i + 2].strip() if i + 2 < len(lines) else ""
                if not SEPARATOR_RE.match(nxt):
                    blank_in_table.append((doc, i + 1))

        for header_line, header, rows in parse_tables(lines):
            tables_seen += 1
            concl_idx = None
            class_idx = None
            for idx, cell in enumerate(header):
                if concl_idx is None and args.conclusion_col and args.conclusion_col in cell:
                    concl_idx = idx
                if class_idx is None and args.class_col and args.class_col in cell:
                    class_idx = idx
            if concl_idx is None:
                continue   # not a verdict table (e.g. the allowed-differences table)
            verdict_tables += 1
            for line_no, cells in rows:
                if line_no == header_line + 1:
                    continue   # separator row
                rows_judged += 1
                if concl_idx >= len(cells):
                    problems.append("%s:%d  row has %d cells, conclusion column is #%d"
                                    % (os.path.basename(doc), line_no, len(cells), concl_idx + 1))
                    continue
                concl = cells[concl_idx]
                if concl == "":
                    problems.append("%s:%d  EMPTY conclusion" % (os.path.basename(doc), line_no))
                for w in bad_words:
                    if w in concl:
                        problems.append("%s:%d  conclusion carries '%s' -> %s"
                                        % (os.path.basename(doc), line_no, w, concl[:60]))
                if class_idx is not None and not args.no_require_class:
                    cls = cells[class_idx] if class_idx < len(cells) else ""
                    if not any(c in cls for c in class_words):
                        problems.append("%s:%d  evidence class missing (expected one of: %s) -> %r"
                                        % (os.path.basename(doc), line_no, "/".join(class_words), cls))

    print("[2] verdict tables: %d of %d table(s) carry a '%s' column; rows judged: %d"
          % (verdict_tables, tables_seen, args.conclusion_col, rows_judged))
    print("    conclusion/class problems: %d ; blank lines inside a table: %d"
          % (len(problems), len(blank_in_table)))
    for b in problems:
        print("    " + b)
    for doc, line_no in blank_in_table:
        print("    blank line inside a table at %s:%d" % (os.path.basename(doc), line_no))
    if rows_judged == 0:
        print("    NOTE: no verdict row was found -- an empty acceptance table is not a pass")
        fails.append("no-verdict-rows")
    if problems:
        fails.append("conclusion")
    if blank_in_table:
        fails.append("blank-line")

    report["problems"] = {
        "unresolved_citations": [{"path": p, "hits": n} for p, n in unresolved],
        "missing_docs": missing_docs,
        "conclusion": problems,
        "blank_in_table": [{"doc": d, "line": n} for d, n in blank_in_table],
        "rows_judged": rows_judged,
        "tables_seen": tables_seen,
        "verdict_tables": verdict_tables,
    }
    report["result"] = "FAIL " + ",".join(fails) if fails else "PASS"

    if args.json_path:
        with open(args.json_path, "w", encoding="utf-8") as fh:
            json.dump(report, fh, ensure_ascii=False, indent=2, sort_keys=True)
            fh.write("\n")

    print("===== selfcheck: %s =====" % report["result"])
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
