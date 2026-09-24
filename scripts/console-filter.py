#!/usr/bin/env python3
"""Filter a dumped `unity command console` result file and print the entries.

WHY A FILE INSTEAD OF `python -c`: the CLI prints NDJSON (several lines, sometimes with a
banner), and an inline `python -c` one-liner gets its quoting layer eaten by PowerShell
(measured several times).  So dump the CLI output to a file once and call this script on it.

Usage
    python console-filter.py <dump-file> [keyword ...]
    python console-filter.py <dump-file> --all          # print every entry, not just WARN/ERROR

  keywords given  -> print only entries whose first message line contains one of them
  keywords absent -> print only WARN / ERROR / FATAL  (the usual "did anything go wrong")

Exit code: 0 = the dump was parsed (whatever the verdict); 2 = file missing / unreadable.

NOTE ON ENCODING: the dump is read with `utf-8-sig`, because a PowerShell redirect writes a
BOM.  Reading it as plain utf-8 leaves a leading U+FEFF on line 1 and the NDJSON prefix match
(`{"type":"result"`) then fails silently -- which looks exactly like "the CLI returned nothing".
"""
import io
import json
import os
import sys

# The ndjson line shape emitted by the unity CLI: {"type":"result", ...}
RESULT_PREFIX = '{"type":"result"'


def load_entries(path):
    """Return (entries, parsed_any) from a dumped CLI result file."""
    txt = io.open(path, encoding='utf-8-sig').read()
    entries = []
    parsed_any = False
    for line in txt.splitlines():
        line = line.strip()
        if not line.startswith(RESULT_PREFIX):
            continue
        parsed_any = True
        d = json.loads(line)
        if d.get('errors'):
            # the CLI itself reported a failure: never swallow it
            print('CLI-ERR:', json.dumps(d['errors'], ensure_ascii=False)[:300])
        r = (d.get('data') or {}).get('result')
        if isinstance(r, str):
            try:
                r = json.loads(r)
            except ValueError:
                pass
        if isinstance(r, dict) and 'entries' in r:
            entries = r['entries']
        else:
            # shape returned by run_script: not an entry list
            inner = r.get('result') if isinstance(r, dict) else r
            print('RESULT:', inner)
    return entries, parsed_any


def main(argv):
    args = [a for a in argv[1:] if a != '--all']
    show_all = '--all' in argv[1:]
    if not args:
        print(__doc__.strip())
        return 2
    path = args[0]
    keys = args[1:]
    if not os.path.isfile(path):
        print('FAIL dump file not found: %s' % path)
        return 2
    entries, parsed_any = load_entries(path)
    if not parsed_any:
        # Loud, not silent: an unparsed dump and an empty console look identical otherwise.
        print('WARN no "%s" line found in %s -- the dump was not parsed (banner-only? wrong file?)'
              % (RESULT_PREFIX, path))
        return 0
    if not entries:
        print('(no console entries in the dump)')
        return 0
    print('--- console entries: %d ---' % len(entries))
    for e in entries:
        msg = (e.get('message') or '').split('\n')[0]
        lvl = str(e.get('level', '?')).upper()
        if keys:
            if not any(k.lower() in msg.lower() for k in keys):
                continue
        elif not show_all:
            if lvl not in ('WARN', 'ERROR', 'FATAL'):
                continue
        print(lvl.ljust(5), msg[:190])
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
