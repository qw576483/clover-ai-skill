# -*- coding: utf-8 -*-
"""silent-failures.py -- find the failures that leave no trace, before they cost a day.

WHY THIS EXISTS
---------------
`experience/time-sinks.md` ("the three silent failures") and SKILL.md 3.3 ("every unexpected branch
must leave a trace") both shipped as WORDS ONLY.  A swallowed exception is worse than a crash: the
crash is visible, the swallow is not -- the game keeps running with a null component / an empty
screen / a dead handler and nothing in the log says why.  Nothing mechanically found `catch { }`.

WHY A NEW FILE (not a patch to an existing one)
------------------------------------------------
No existing asset scans C# at all: `tools/verify.ps1` item 2 `hard-rules` only matches a fixed
banned-API list (`PlayerPrefs` / `Resources.Load` / ...).  There was therefore nothing to extend --
and folding a scanner into `hard-rules` would have made that item's FAIL count unattributable (one
number, two unrelated causes).

WHAT IT FINDS (categories)
--------------------------
  empty-catch     `catch { }` / `catch (X) { }`                 -> the body carries nothing at all
  swallow-no-log  the body has statements but neither logs nor rethrows -> the exception is eaten
  discard-return  `_ = <expr>;`                                 -> a value / error is deliberately
                                                                   dropped on the floor

Severity for the exit code: empty-catch and discard-return are FAIL; swallow-no-log is a WARN
(it can be legitimate) -- so the gate can be wired to FAIL without drowning in judgement calls.

COMMENTS AND STRINGS ARE NOT CODE (this is the false-positive fix, read it)
--------------------------------------------------------------------------
Measured trap: grepping for `catch { }` also matches the *documentation* that TELLS you not to
write `catch { }` and the comments that explain it -- and the "fix" that follows is to delete the
documentation, i.e. the opposite of what a gate should cause.  So this scanner never greps raw
text: it first runs a small C# lexer that replaces the inside of `//`, `/* */`, "..." , @"..." and
'...' with spaces **one-for-one** (identical byte count, newlines preserved).  Consequences:
  * the detectors only ever see CODE, so a comment / a string literal can never be a hit;
  * every reported line and column still maps onto the ORIGINAL file, because nothing shifted;
  * the original text is used only to quote the offending line back to the reader.
The decoder is a state machine, not a regex, because `"..."` may contain `//`, `@"..."` swallows
newlines, and `'\''` is a legal char literal -- a regex version gets all three wrong.

Run:
    python scripts/silent-failures.py --root <project-root>
    python scripts/silent-failures.py --root . --subdir client/Assets/Scripts --format tsv
    python scripts/silent-failures.py --root . --only empty-catch
    python scripts/silent-failures.py --root . --json .ai-tmp/test/silent-failures.json
    python scripts/silent-failures.py --self-test    # one clean sample AND one defect sample

Exit: 0 = clean (no FAIL-category hit), 1 = hit(s) found (or the self-test failed), 2 = usage error.
ASCII-only stdout (cp936 console safe).
"""
import argparse
import io
import json
import os
import re
import sys

sys.dont_write_bytecode = True
try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

# category -> severity.  WARN categories never affect the exit code.
SEV = {
    'empty-catch': 'FAIL',
    'discard-return': 'FAIL',
    'swallow-no-log': 'WARN',
}
CATS = ('empty-catch', 'swallow-no-log', 'discard-return')

DEFAULT_SUBDIR = 'client/Assets/Scripts'
DEFAULT_GLOB = '.cs'

# a catch body counts as "traced" when it rethrows or logs through any of the project idioms
TRACE_RE = re.compile(
    r'\bthrow\b'
    r'|\bLogger\s*\.\s*(?:Info|Warn|Warning|Error|Debug)\b'
    r'|\bLog(?:ger)?\s*\.\s*(?:Info|Warn|Warning|Error|Debug|Log|Write)\b'
    r'|\bDebug\s*\.\s*(?:Log|LogWarning|LogError)\b'
    r'|\bConsole\s*\.\s*(?:Write|WriteLine|Error)\b'
    r'|\bFail\s*\(')
DISCARD_RE = re.compile(r'(?:^|[^\w])_\s*=(?!=|>)')
CATCH_RE = re.compile(r'\bcatch\b')


# --------------------------------------------------------------------------- C# lexer
def mask_cs(text):
    """Return a copy of `text` with comment / string / char-literal CONTENTS blanked to spaces.

    Length is preserved exactly (every consumed source char yields exactly one output char, and
    newlines survive), so any offset found in the masked text is also valid in the original.
    """
    out = []
    i = 0
    n = len(text)
    state = 'code'
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ''
        if state == 'code':
            if c == '/' and nxt == '/':
                state = 'line'; out.append('  '); i += 2; continue
            if c == '/' and nxt == '*':
                state = 'block'; out.append('  '); i += 2; continue
            if c == '@' and nxt == '"':
                state = 'vstr'; out.append('  '); i += 2; continue
            if c == '"':
                state = 'str'; out.append(' '); i += 1; continue
            if c == "'":
                state = 'char'; out.append(' '); i += 1; continue
            out.append(c); i += 1
        elif state == 'line':
            if c == '\n':
                state = 'code'; out.append('\n')
            else:
                out.append(' ')
            i += 1
        elif state == 'block':
            if c == '*' and nxt == '/':
                state = 'code'; out.append('  '); i += 2; continue
            out.append('\n' if c == '\n' else ' ')
            i += 1
        elif state == 'str':
            if c == '\\':                       # \" \\ \n ... -- consumes the escaped char
                out.append(' ')
                out.append('\n' if nxt == '\n' else ' ')
                i += 2; continue
            if c == '"':
                state = 'code'; out.append(' '); i += 1; continue
            if c == '\n':                       # unterminated literal: recover at end of line
                state = 'code'; out.append('\n'); i += 1; continue
            out.append(' ')
            i += 1
        elif state == 'char':
            if c == '\\':
                out.append(' ')
                out.append('\n' if nxt == '\n' else ' ')
                i += 2; continue
            if c == "'":
                state = 'code'; out.append(' '); i += 1; continue
            if c == '\n':
                state = 'code'; out.append('\n'); i += 1; continue
            out.append(' ')
            i += 1
        else:                                   # verbatim string @"..."
            if c == '"':
                if nxt == '"':                  # "" is an escaped quote inside a verbatim string
                    out.append('  '); i += 2; continue
                state = 'code'; out.append(' '); i += 1; continue
            out.append('\n' if c == '\n' else ' ')
            i += 1
    return ''.join(out)


def match_pair(text, i, opener, closer):
    """Index of the `closer` matching the `opener` at `i`, or -1. `text` must already be masked."""
    depth = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == opener:
            depth += 1
        elif c == closer:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def line_starts(text):
    starts = [0]
    for m in re.finditer('\n', text):
        starts.append(m.end())
    return starts


def line_at(starts, idx):
    lo, hi = 0, len(starts) - 1
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if starts[mid] <= idx:
            lo = mid
        else:
            hi = mid - 1
    return lo + 1


# --------------------------------------------------------------------------- detectors
def _traced(body):
    return TRACE_RE.search(body) is not None


def scan_text(text, path, only=None):
    """-> list of findings (dicts) for one C# source text.  Pure function (no disk)."""
    masked = mask_cs(text)
    starts = line_starts(text)
    orig = text.split('\n')
    hits = []

    def raw_line(ln):
        return orig[ln - 1].strip() if 1 <= ln <= len(orig) else ''

    # ---- catch clauses: locate the body by brace matching on the MASKED text ----------------
    if 'catch' in masked:
        for m in CATCH_RE.finditer(masked):
            i = m.end()
            n = len(masked)
            while i < n and masked[i] in ' \t\r\n':
                i += 1
            if i < n and masked[i] == '(':
                close = match_pair(masked, i, '(', ')')
                if close < 0:
                    continue
                i = close + 1
                while i < n and masked[i] in ' \t\r\n':
                    i += 1
                if masked.startswith('when', i):          # exception filter: catch (X) when (...)
                    j = i + 4
                    while j < n and masked[j] in ' \t\r\n':
                        j += 1
                    if j < n and masked[j] == '(':
                        c2 = match_pair(masked, j, '(', ')')
                        if c2 < 0:
                            continue
                        i = c2 + 1
                        while i < n and masked[i] in ' \t\r\n':
                            i += 1
            if i >= n or masked[i] != '{':
                continue
            close = match_pair(masked, i, '{', '}')
            if close < 0:
                continue
            body = masked[i + 1:close]
            compact = re.sub(r'\s+', '', body)
            # masking preserves length, so the SAME offsets slice the ORIGINAL body: if it has
            # non-blank content while the masked body is empty, the body is a bare comment (real
            # code, deliberately silent) -- say so, so the reader is not left guessing.
            comment_only = (compact == '' and re.sub(r'\s+', '', text[i + 1:close]) != '')
            ln = line_at(starts, m.start())
            if compact == '':
                hits.append({'cat': 'empty-catch', 'path': path, 'line': ln,
                             'col': m.start() - starts[ln - 1] + 1,
                             'code': raw_line(ln),
                             'detail': 'the catch body carries only a comment -- the failure'
                                       ' still leaves no trace'
                                       if comment_only else
                                       'the catch body is empty -- the failure leaves no trace'})
            elif not _traced(body):
                hits.append({'cat': 'swallow-no-log', 'path': path, 'line': ln,
                             'col': m.start() - starts[ln - 1] + 1,
                             'code': raw_line(ln),
                             'detail': 'the catch body neither logs nor rethrows'})
            i = close

    # ---- explicit discards: `_ = <expr>;` --------------------------------------------------
    for k, mline in enumerate(masked.split('\n'), start=1):
        m = DISCARD_RE.search(mline)
        if m:
            hits.append({'cat': 'discard-return', 'path': path, 'line': k,
                         'col': m.start() + 1, 'code': raw_line(k),
                         'detail': 'the returned value / error is discarded'})

    if only:
        hits = [h for h in hits if h['cat'] in only]
    hits.sort(key=lambda h: (h['line'], h['col'], h['cat']))
    for h in hits:
        h['severity'] = SEV[h['cat']]
    return hits


def scan_root(root, subdir, glob, only=None):
    base = os.path.join(root, subdir.replace('/', os.sep))
    hits = []
    files = 0
    if not os.path.isdir(base):
        return hits, files
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in ('.git', 'obj', 'bin', 'Library', 'Temp')]
        for name in sorted(filenames):
            if not name.endswith(glob):
                continue
            full = os.path.join(dirpath, name)
            files += 1
            try:
                with io.open(full, encoding='utf-8-sig', errors='replace') as f:
                    txt = f.read()
            except OSError as e:
                hits.append({'cat': 'unreadable', 'severity': 'WARN', 'path': full, 'line': 0,
                             'col': 0, 'code': '', 'detail': 'could not read: %s' % e})
                continue
            rel = os.path.relpath(full, root).replace(os.sep, '/')
            hits.extend(scan_text(txt, rel, only))
    return hits, files


# --------------------------------------------------------------------------- reporting
def ascii_(s):
    return str(s).encode('ascii', 'backslashreplace').decode('ascii')


def report(hits, files, root, subdir, out, fmt='text'):
    w = out.write
    nfail = len([h for h in hits if h.get('severity') == 'FAIL'])
    nwarn = len([h for h in hits if h.get('severity') == 'WARN'])
    if fmt == 'tsv':
        for h in hits:
            w('%s\t%s:%s\t%s\t%s\n' % (h['cat'], ascii_(h['path']), h['line'],
                                       ascii_(h['detail']), ascii_(h['code'])))
    else:
        w('silent-failures: root=%s subdir=%s files=%d\n'
          % (ascii_(root), ascii_(subdir), files))
        for h in hits:
            w('  %-4s %-15s %s:%s:  %s\n'
              % (h.get('severity', 'WARN'), h['cat'], ascii_(h['path']), h['line'],
                 ascii_(h['code'])))
        for h in hits:
            if h['cat'] == 'swallow-no-log':
                w('    (warn) %s:%s  %s\n' % (ascii_(h['path']), h['line'], ascii_(h['detail'])))
    if nfail == 0:
        w('RESULT: PASS -- 0 blocking hit (%d WARN, %d file(s) scanned; comments and string\n'
          % (nwarn, files))
        w('        literals are masked out before matching, so documentation is never a hit)\n')
    else:
        w('RESULT: FAIL -- %d blocking hit(s) (+%d WARN); every FAIL row above is real code\n'
          % (nfail, nwarn))
    return 0 if nfail == 0 else 1


# --------------------------------------------------------------------------- self-test
_GOOD = '''using System;
namespace S {
  class A {
    // do NOT write catch (Exception) { } -- that swallows the failure
    /* catch { } */
    const string Doc = "catch (Exception) { } and _ = Foo(); are both banned";
    char C = '{';
    void M() {
      try { Work(); }
      catch (Exception ex) { Game.Logger.Error("Tag", "boom", ex); }
    }
    void N() {
      try { Work(); } catch (Exception) { throw; }
    }
  }
}
'''
_BAD = '''using System;
namespace S {
  class B {
    void M() {
      try { A(); } catch (Exception) { }
      try { B(); } catch { }
      _ = Compute();
    }
    int Compute() { return 1; }
  }
}
'''


def self_test(out):
    w = out.write
    ok = True
    w('=== silent-failures self-test (anti-gaming.md section 5: one clean sample AND one defect) ===\n')
    w('--- sample A: the banned shapes appear ONLY in comments and a string (must PASS) ---\n')
    a = scan_text(_GOOD, 'Sample.Good.cs')
    rc_a = report(a, 1, '.', '<mem>', out)
    ok_a = (a == [] and rc_a == 0)
    w('  self-check %s sample A -> hits=%d (comment / string / throw-only sites must stay silent)\n'
      % ('ok  ' if ok_a else 'FAIL', len(a)))
    ok = ok and ok_a

    w('--- sample B: two empty catches + one discard in real code (must FAIL, all three named) ---\n')
    b = scan_text(_BAD, 'Sample.Bad.cs')
    rc_b = report(b, 1, '.', '<mem>', out)
    want = [('empty-catch', 5), ('empty-catch', 6), ('discard-return', 7)]
    got = [(h['cat'], h['line']) for h in b]
    ok_b = ((rc_b == 1) and got == want)
    w('  self-check %s sample B -> pass=%s got=%s\n'
      % ('ok  ' if ok_b else 'FAIL', rc_b == 0, ascii_(got)))
    ok = ok and ok_b
    w('RESULT: %s -- the scanner stays silent on commented-out code AND names every real hit\n'
      % ('PASS' if ok else 'FAIL'))
    return 0 if ok else 1


# --------------------------------------------------------------------------- main
def main(argv):
    p = argparse.ArgumentParser(description='silent-failures: find untraced failure paths in C#')
    p.add_argument('--root', default=os.getcwd(),
                   help='project root (default: cwd); --subdir resolves here')
    p.add_argument('--subdir', default=DEFAULT_SUBDIR,
                   help='directory to scan, relative to --root (default: %s)' % DEFAULT_SUBDIR)
    p.add_argument('--glob', default=DEFAULT_GLOB, help='file suffix to scan (default: .cs)')
    p.add_argument('--only', default='',
                   help='comma-separated categories: ' + ','.join(CATS))
    p.add_argument('--format', default='text', choices=('text', 'tsv'))
    p.add_argument('--json', default='', help='also write the findings as JSON here')
    p.add_argument('--list-categories', action='store_true')
    p.add_argument('--self-test', action='store_true')
    args = p.parse_args(argv)

    if args.list_categories:
        for c in CATS:
            sys.stdout.write('%s\t%s\n' % (SEV[c], c))
        return 0
    if args.self_test:
        return self_test(sys.stdout)

    only = tuple(c.strip() for c in args.only.split(',') if c.strip())
    bad = [c for c in only if c not in CATS]
    if bad:
        sys.stdout.write('FAIL: unknown category(ies): %s (known: %s)\n'
                         % (ascii_(','.join(bad)), ','.join(CATS)))
        return 2
    if not os.path.isdir(os.path.join(args.root, args.subdir.replace('/', os.sep))):
        sys.stdout.write('FAIL: no such directory: %s\n'
                         % ascii_(os.path.join(args.root, args.subdir)))
        return 2

    hits, files = scan_root(args.root, args.subdir, args.glob, only or None)
    rc = report(hits, files, args.root, args.subdir, sys.stdout, args.format)
    if args.json:
        jp = args.json if os.path.isabs(args.json) else os.path.join(args.root, args.json)
        d = os.path.dirname(jp)
        if d and not os.path.isdir(d):
            os.makedirs(d)
        summary = {
            'root': args.root, 'subdir': args.subdir, 'files': files,
            'counts': dict((c, len([h for h in hits if h['cat'] == c])) for c in CATS),
            'blocking': len([h for h in hits if h.get('severity') == 'FAIL']),
            'warn': len([h for h in hits if h.get('severity') == 'WARN']),
            'hits': hits, 'pass': rc == 0,
        }
        with io.open(jp, 'w', encoding='utf-8', newline='\n') as f:
            f.write(json.dumps(summary, ensure_ascii=False, indent=1))
        sys.stdout.write('findings written to %s\n' % ascii_(jp))
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
