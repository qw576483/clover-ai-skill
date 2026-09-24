# -*- coding: utf-8 -*-
# evidence-whitelist-crosscheck.py -- INDEPENDENT recomputation of the delivery-cleanup whitelist.
#
# PROVENANCE (lifted into the skill 2026-09-24): written inside one project ("the source project"
# below); plan area, asset/state area, evidence subtrees, document set and index roots are arguments
# now.  Case citations of the form <letters>-<alnum> are that project's work-item ids, kept because
# they mark WHERE a rule was paid for.
#
# WHY IT MUST STAY A SECOND IMPLEMENTATION: the carrier rule was stated wrong three times by the lead
# (".ai-tmp" -> "test/" -> "reachability"), each time from memory.  The answer has to be a COMMAND,
# and a command written by one slice has to be recomputed by another, in a different language, before
# anyone trusts it.  Deliberately NOT a translation of scripts/cited-evidence-whitelist.ps1.
#
# v3 -- PATTERN-FORM IS NOW BUCKETED BY EXPANDABILITY (CR-U5R's mechanical definition, adopted):
#   order matters: strip a ":line" suffix FIRST, then bucket.
#     A  brace with explicit items, no ellipsis   e.g. CR-U5-units-bind-{0,7,14}.tsv   -> EXPAND
#     B  brace/glob carrying an ellipsis          e.g. CR-T3-re-{00-baseline,...}.png  -> candidates
#     C  glob  * / ?                              e.g. p1-g1-audit-step*.txt           -> EXPAND by listing
#   A and C are mechanically expandable, so MISSING is judged on the EXPANSIONS.
#   B cannot be expanded; it is listed for a human, never counted as missing, and -- because for a
#   CLEANUP conservative means keep -- every same-prefix/same-extension candidate is whitelisted.
#   Whitelist = A-expansions + C-expansions + B-candidates + every non-pattern citation.
#   All separators normalised to "/" on write (the two producers used to disagree, and a consumer
#   matching one form silently missed the other -- measured: 43 duplicate entries).
#
# Earlier rulings still encoded:
#   R1 SCOPE     = the whole cehua/ tree, not 4 ledgers (a 4-ledger whitelist left 71 cited
#                  carriers unprotected).
#   R2 AMBIGUITY = several candidates => ambiguous: list all, whitelist all in-zone candidates.
#   R3 PATTERNS  = never counted as missing (proven necessary in BOTH implementations).
#
# USAGE
#   python scripts/evidence-whitelist-crosscheck.py --root <project> --plan-dir <plan-area> [--scope all|f2] [--inject NAME]
import argparse
import fnmatch
import os
import re
import sys

ROOT = os.getcwd()
EVIDENCE_DIR = ".ai-tmp"
CEHUA = "\u7b56\u5212"      # the source project's plan area -- a DEFAULT, override with --plan-dir
F2_SCOPE = []               # --scope f2 document subset; empty => the whole plan area (loudly)
EVIDENCE_SUBTREES = ["screenshots", "test", "drivers"]   # --evidence-subtrees
TOKEN = re.compile(r"[^\s`()\[\]{}<>|\"'；;，,。、：:！!？?（）【】《》…·]+")
# WIDE additionally allows the pattern characters, so a citation like
#   AV1-census{,2,3,4}.tsv   or   CR-T3-re-{00-baseline,...}.png
# is captured WHOLE and can then be bucketed by expandability.  With the narrow token only, the
# match stopped at the brace and the remainder looked like an ordinary truncated file name -- which
# is exactly how both implementations produced phantom "missing" files.  Measured.
WIDE = re.compile(r"[^\s`()\[\]<>|\"'；;，,。、：:！!？?（）【】《》·\\/]+")
# Ordered extractors for the path-form tail.  NAME_BRACE allows ASCII commas INSIDE the braces while
# still stopping at every other punctuation, so `AV1-census{,2,3,4}.tsv` is captured whole.
# NOTE: separators are ALLOWED INSIDE the name.  A citation may point into a subdirectory
# (".ai-tmp/screenshots/AL3-shots\\AL3-busy-login.png"); excluding the separator truncates it at the
# backslash, so the real file is never whitelisted while a bogus directory entry is.  Measured: this
# verifier missed 15 such files and the other implementation caught them -- cross-checking paid off
# in both directions.
_NAME = r"[^\s`()\[\]{}<>|\"'；;，,。、：:！!？?（）【】《》…·]+"
NAME_BRACE = re.compile(_NAME + r"\{[^{}]*\}" + _NAME)
NAME_GLOB = re.compile(_NAME + r"[*?]" + _NAME)
EXT_MANDATED = (".txt", ".tsv", ".png", ".log", ".md", ".jpg")
FORBID = set('{*?…')


def rel(p):
    return os.path.relpath(p, ROOT).replace("/", "\\")


def build_index():
    skip = {"library", "temp", "obj", "logs", "node_modules", ".git", ".ai-tmp"}
    idx = {}
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d.lower() not in skip]
        for fn in filenames:
            idx.setdefault(fn.lower(), []).append(rel(os.path.join(dirpath, fn)))
    return idx


def scope_files(scope):
    if scope == "f2":
        if not F2_SCOPE:
            print("WARN  --scope f2 without --scope-docs: falling back to the WHOLE plan area")
            return scope_files("all")
        return [os.path.join(CEHUA, n) if not os.path.isabs(n) else n for n in F2_SCOPE
                if os.path.exists(os.path.join(CEHUA, n) if not os.path.isabs(n) else n)]
    out = []
    for dp, dn, fns in os.walk(CEHUA):
        for fn in fns:
            if fn.lower().endswith((".md", ".tsv")):
                out.append(os.path.join(dp, fn))
    return sorted(out)


def bucket_of(name):
    """A = expandable brace, B = ellipsis inside a brace/glob, C = glob, None = literal."""
    if "{" not in name and "*" not in name and "?" not in name:
        return None
    if "\u2026" in name:
        return "B"
    if "{" in name:
        return "A" if re.search(r"\{[^{}]*\}", name) else "B"
    return "C"


def expand_A(name):
    m = re.search(r"\{([^{}]*)\}", name)
    if not m:
        return []
    return [name[:m.start()] + p.strip() + name[m.end():] for p in m.group(1).split(",")]


def expand_C(name):
    """glob against the directory it lives in: <dir>/<pattern> -> matching file names."""
    d, pat = os.path.split(name)
    full = os.path.join(ROOT, ".ai-tmp", d) if d else None
    if not full or not os.path.isdir(full):
        return []
    return [os.path.join(d, f) for f in os.listdir(full) if fnmatch.fnmatch(f, pat)]


def candidates_B(name):
    """same directory + literal prefix + literal extension -- a heuristic, and labelled as one."""
    d, base = os.path.split(name)
    m = re.match(r"^([^{}*?]*)[{*?].*?(\.[A-Za-z0-9]+)$", base)
    if not m:
        return []
    prefix, ext = m.group(1), m.group(2)
    full = os.path.join(ROOT, ".ai-tmp", d) if d else None
    if not full or not os.path.isdir(full):
        return []
    return [os.path.join(d, f) for f in os.listdir(full)
            if f.startswith(prefix) and f.endswith(ext)]


def main():
    global ROOT, CEHUA, F2_SCOPE, EVIDENCE_SUBTREES
    ap = argparse.ArgumentParser()
    # --root replaces the old "three levels up from __file__" derivation: inside a project the script
    # lived at tools/probes/<file>, so that worked; shipped in a skill it would walk to the SKILL
    # directory and index the skill instead of the project.
    ap.add_argument("--root", default=os.getcwd(),
                    help="project root (default: current directory)")
    ap.add_argument("--plan-dir", default="",
                    help="area whose documents are the CITATION SOURCE, project-relative or absolute")
    ap.add_argument("--state-dir", default="tools/probes",
                    help="where the whitelist product is written (project-relative or absolute)")
    ap.add_argument("--scope", default="all", choices=["all", "f2"])
    ap.add_argument("--scope-docs", default="",
                    help="comma-separated document subset for --scope f2 (empty => whole plan area)")
    ap.add_argument("--evidence-subtrees", default="screenshots,test,drivers",
                    help="subtree names under the cleanup zone that count as EVIDENCE (comma list)")
    ap.add_argument("--inject", action="append", default=[])
    # --inject-path adds a synthetic PATH-FORM citation (relative to .ai-tmp/).  Needed to prove
    # bucket A in both directions with KNOWN samples: an expandable brace whose members exist
    # (known-correct) and one whose members do not (known-wrong).  The bare-name hook above cannot
    # exercise the brace/bucket-A path at all.
    ap.add_argument("--inject-path", action="append", default=[])
    args = ap.parse_args()

    ROOT = os.path.abspath(args.root)
    if not os.path.isdir(ROOT):
        print("FAIL  project root not found: %s" % ROOT)
        return 1
    CEHUA = args.plan_dir or "\u7b56\u5212"      # source-project default; see the module header
    if not os.path.isabs(CEHUA):
        CEHUA = os.path.join(ROOT, CEHUA)
    F2_SCOPE = [s.strip() for s in args.scope_docs.split(",") if s.strip()]
    EVIDENCE_SUBTREES = [s.strip() for s in args.evidence_subtrees.split(",") if s.strip()]
    if not os.path.isdir(CEHUA):
        print("FAIL  plan dir not found: %s   (pass --plan-dir; an empty scope cannot be verified)" % CEHUA)
        return 1
    print("root             = %s" % ROOT)
    print("plan dir         = %s" % CEHUA)
    print("evidence subtree = %s" % ",".join(EVIDENCE_SUBTREES))
    # Citation shapes: "<zone>/<evidence-subtree>/<name>" and the whole-ref form used to blank them
    # out before the bare-name scan.  Built from the parameters so a project with different subtree
    # names is not silently scanned with someone else's list.
    alt = "|".join(re.escape(s) for s in EVIDENCE_SUBTREES)
    # ev_re MUST capture the subtree name: the caller keys the citation on m.group(1).  Making this
    # group non-capturing is a cheap mistake that fails loudly but late (IndexError after the tree
    # walk, so it costs a full run to notice).
    ev_re = re.compile(r"\.ai-tmp[\\/](%s)[\\/]" % alt)
    ev_re_any = re.compile(r"\.ai-tmp[\\/](?:%s)[\\/][^\s]*" % alt)

    idx = build_index()
    ev_roots = {s: os.path.join(ROOT, EVIDENCE_DIR, s) for s in EVIDENCE_SUBTREES}
    files = scope_files(args.scope)
    print("scope            = %s  (%d file(s))" % (args.scope, len(files)))

    path_refs, bare_refs = {}, {}
    for f in files:
        doc = rel(f)
        with open(f, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                for m in re.finditer(ev_re, line):
                    tail = line[m.end():]
                    # ordered: whole brace form FIRST (commas are legal inside braces but are
                    # punctuation everywhere else, so a single character class cannot express both),
                    # then a glob form, then an ordinary name.  Getting this order wrong is what made
                    # bucket A read 0 while the same citations were reported as truncated literals.
                    mb = NAME_BRACE.match(tail)
                    mg = NAME_GLOB.match(tail)
                    if mb:
                        name = mb.group(0)
                    elif mg:
                        name = mg.group(0)
                    else:
                        t = TOKEN.match(tail)
                        name = t.group(0) if t else ""
                    nxt = tail[len(name):len(name) + 1]
                    path_refs.setdefault("%s/%s" % (m.group(1), name), []).append(("%s:%d" % (doc, lineno), nxt))
                stripped = re.sub(ev_re_any, " ", line)
                for m in re.finditer(r"(?<![\w\\/.])([A-Za-z0-9_\-\.]+\.[A-Za-z0-9]+)", stripped):
                    nm = m.group(1)
                    if nm.lower().endswith(EXT_MANDATED):
                        bare_refs.setdefault(nm, []).append(("%s:%d" % (doc, lineno), stripped[m.end():m.end() + 1]))
    for inj in args.inject:
        bare_refs.setdefault(inj, []).append(("INJECTED(self-test)", ""))
    for inj in args.inject_path:
        rel_inj = inj.replace("\\", "/")
        for pfx in (".ai-tmp/", ""):
            if rel_inj.startswith(pfx):
                rel_inj = rel_inj[len(pfx):]
                break
        path_refs.setdefault(rel_inj, []).append(("INJECTED(self-test)", ""))

    p_lit, p_miss, pA, pB, pC = [], [], [], [], []
    for key, cites in sorted(path_refs.items()):
        d, name = key.split("/", 1)
        if not name:
            continue
        nxt = cites[0][1]
        b = bucket_of(name) if (not nxt or nxt not in FORBID) else bucket_of(name + nxt)
        if b is None and (nxt in FORBID):
            b = "C" if nxt in "*?" else ("B" if nxt == "\u2026" else "A")
        if b == "A":
            pA.append((key, cites, expand_A(name) or expand_A(name + nxt)))
        elif b == "B":
            pB.append((key, cites, candidates_B(name) or candidates_B(name + nxt)))
        elif b == "C":
            pC.append((key, cites, expand_C(name) or expand_C(name + nxt)))
        else:
            (p_lit if os.path.exists(os.path.join(ROOT, ".ai-tmp", d, name.replace("/", os.sep))) else p_miss).append((key, cites))
    print("STEP1 path refs  = %d  (literal exist %d, literal MISSING %d | A expandable %d, B ellipsis %d, C glob %d)"
          % (len(path_refs), len(p_lit), len(p_miss), len(pA), len(pB), len(pC)))

    # MISSING is now judged on the EXPANSIONS of A and C
    a_miss = [(k, c, [e for e in ex if not os.path.exists(os.path.join(ROOT, ".ai-tmp", k.split("/")[0], e.replace("/", os.sep)))]) for k, c, ex in pA]
    a_miss = [x for x in a_miss if x[2]]
    c_miss = [(k, c, [e for e in ex if not os.path.exists(os.path.join(ROOT, ".ai-tmp", k.split("/")[0], e.replace("/", os.sep)))]) for k, c, ex in pC]
    c_miss = [x for x in c_miss if x[2]]

    in_ev, elsewhere, unres, amb, bpat = [], [], [], [], []
    for nm, cites in sorted(bare_refs.items(), key=lambda kv: kv[0].lower()):
        if bucket_of(nm) or (cites[0][1] and cites[0][1] in FORBID):
            bpat.append((nm, cites))
            continue
        ev = []
        for d, r in ev_roots.items():
            if os.path.isfile(os.path.join(r, nm)):
                ev.append(rel(os.path.join(r, nm)))
        cand = ev if ev else idx.get(nm.lower(), [])
        if len(cand) > 1:
            amb.append((nm, cand, cites))
        elif len(cand) == 1:
            (in_ev if ev else elsewhere).append((nm, cand[0], cites))
        else:
            unres.append((nm, cites))
    print("STEP2 bare refs  = %d  (evidence %d, elsewhere %d, unresolved %d, ambiguous %d, pattern-bare %d)"
          % (len(bare_refs), len(in_ev), len(elsewhere), len(unres), len(amb), len(bpat)))

    wl = set()
    for key, _ in p_lit:
        d, name = key.split("/", 1)
        if d in ("test", "screenshots"):
            wl.add(".ai-tmp/%s/%s" % (d, name))
    for nm, p, _ in in_ev:
        wl.add(p)
    for nm, cands, _ in amb:
        for c in cands:
            if c.startswith(".ai-tmp"):
                wl.add(c)
    for key, _, ex in pA + pC:                     # A/C: expansions that EXIST must survive cleanup
        d = key.split("/")[0]
        for e in ex:
            if os.path.exists(os.path.join(ROOT, ".ai-tmp", d, e.replace("/", os.sep))):
                wl.add(".ai-tmp/%s/%s" % (d, e))
    for key, _, cands in pB:                       # B: every candidate is kept (conservative)
        d = key.split("/")[0]
        for c in cands:
            if os.path.exists(os.path.join(ROOT, ".ai-tmp", d, c.replace("/", os.sep))):
                wl.add(".ai-tmp/%s/%s" % (d, c))
    for nm, _ in bpat:
        for d, r in ev_roots.items():
            if os.path.isfile(os.path.join(r, nm)):
                wl.add(rel(os.path.join(r, nm)))

    # A whitelist entry must be a REAL FILE.  Without this filter a token that was truncated at some
    # character the tokenizer does not accept (a directory name such as ".ai-tmp/test/driver") lands
    # in the list, and a consumer checking "is it in the whitelist" gets a yes for something that can
    # never be deleted anyway.  Measured.
    wl = {p for p in wl
          if os.path.isfile(os.path.join(ROOT, p.replace("/", os.sep).replace("\\", os.sep)))}
    wl = {p.replace("\\", "/") for p in wl}
    # scope goes into the FILE NAME.  This verifier criticised the other tool for having both scopes
    # write one path (last run wins) -- and then had exactly the same defect itself.  Fixing the
    # criticism without fixing the critic is how a rule rots.
    # The name matches the PowerShell side's -Partner default on purpose: the union step is the only
    # consumer, and a name mismatch there is a LOUD failure (exit 3), never a silent empty union.
    # scripts/ is derived from the relative form so an absolute --state-dir still lands correctly.
    state = args.state_dir
    if not os.path.isabs(state):
        state = os.path.join(ROOT, state)
    os.makedirs(state, exist_ok=True)
    out = os.path.join(state, "evidence-whitelist-crosscheck-whitelist-%s.txt" % args.scope)
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        for p in sorted(wl):
            fh.write(p + "\n")
    print("WHITELIST (uniq) = %d   -> %s" % (len(wl), rel(out)))

    print("")
    print("--- FAIL: literal path absent from disk ---")
    for key, c in p_miss:
        print("  .ai-tmp/%s  (cited %dx, first %s)" % (key, len(c), c[0][0]))
    for key, c, e in a_miss:
        print("  .ai-tmp/%s  A-expansion(s) absent: %s" % (key, ", ".join(e)))
    for key, c, e in c_miss:
        print("  .ai-tmp/%s  C-glob no match: %s" % (key, ", ".join(e)))
    if not (p_miss or a_miss or c_miss):
        print("  (none)")
    print("")
    print("--- HUMAN: bucket B (ellipsis: NOT mechanically expandable; candidates kept, never deleted) ---")
    for key, c, cands in pB:
        print("  .ai-tmp/%s  (cited %dx) -> %d candidate(s): %s" % (key, len(c), len(cands), ", ".join(os.path.basename(x) for x in cands[:6])))
    if not pB:
        print("  (none)")
    print("")
    print("--- HUMAN: bucket A/C expansions (mechanically expanded; these names are whitelisted) ---")
    for key, c, ex in pA + pC:
        print("  .ai-tmp/%s  (cited %dx) -> %s" % (key, len(c), ", ".join(ex) or "?"))
    if not (pA or pC):
        print("  (none)")
    print("")
    print("--- HUMAN: unresolved bare names (NOT a verdict) ---")
    for nm, c in unres:
        print("  %-32s (cited %dx)" % (nm, len(c)))
    if not unres:
        print("  (none)")
    print("")
    print("--- HUMAN: ambiguous bare names -- all in-zone candidates whitelisted ---")
    for nm, cands, c in amb:
        print("  %-24s (cited %dx, %d candidates)" % (nm, len(c), len(cands)))
    if not amb:
        print("  (none)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
