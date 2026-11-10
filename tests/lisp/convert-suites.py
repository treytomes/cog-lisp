"""Phase 8 step 8.1: move language-behavior checks from the Smalltalk suites to
LISP test files (specs/13-phase-8-self-hosting.md section 4.1).

A check moves only when it is exactly "evaluate this LISP source and compare the
result with a plain value" (or "expect an error"); everything else stays in the
Smalltalk suite. Setup statements (evaluating LISP for effect) are copied, in
order, so the LISP file sees the same definitions; they stay in the suite too.

  python tests/lisp/convert-suites.py --dry    report what would move
  python tests/lisp/convert-suites.py          write tests/lisp/phase-*.lisp,
                                               trim the suites, list moved checks
Run once; kept in the repository as the record of how the tests were moved.
"""
import io, re, sys

SUITES = ['phase-3-compiler', 'phase-4-runtime', 'phase-5-shell', 'phase-6-tail-calls',
          'phase-7-macros', 'phase-7.5-review', 'phase-7.6-interop', 'phase-7.7-conditions',
          'phase-7.8-native-data', 'phase-7.9-groundwork']
EVALUATORS = {'ev', 'evAll'}


def st_string(text, i):
    """The Smalltalk string literal starting at text[i] == "'": (value, end index)."""
    assert text[i] == "'"
    out, j = [], i + 1
    while True:
        if text[j] == "'":
            if j + 1 < len(text) and text[j + 1] == "'":
                out.append("'"); j += 2; continue
            return ''.join(out), j + 1
        out.append(text[j]); j += 1


def statements(region):
    """Split a block body into top-level statements: (start, end, text)."""
    result, depth, i, start = [], 0, 0, 0
    n = len(region)
    while i < n:
        c = region[i]
        if c == "'":
            _, i = st_string(region, i); continue
        if c == '"':
            i = region.index('"', i + 1) + 1; continue
        if c == '$' and i + 1 < n:
            i += 2; continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == '.' and depth == 0 and (i + 1 >= n or region[i + 1] in ' \t\r\n'):
            result.append((start, i + 1, region[start:i + 1])); start = i + 1
        i += 1
    if region[start:].strip():
        result.append((start, n, region[start:]))
    return result


def strip_comments(s):
    out, i = [], 0
    while i < len(s):
        if s[i] == "'":
            _, j = st_string(s, i); out.append(s[i:j]); i = j; continue
        if s[i] == '"':
            i = s.index('"', i + 1) + 1; continue
        out.append(s[i]); i += 1
    return ''.join(out).strip()


def chunk(s):
    return s.replace('!!', '!')


def lisp_string(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def balanced(s):
    """s is one parenthesized expression: (...)."""
    if not (s.startswith('(') and s.endswith(')')):
        return False
    depth, i = 0, 0
    while i < len(s):
        c = s[i]
        if c == "'":
            _, i = st_string(s, i); continue
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0 and i != len(s) - 1:
                return False
        i += 1
    return True


def lisp_source(expr, evaluators=None):
    """'(ev value: <string>)' -> the LISP source, else None."""
    expr = expr.strip()
    if not balanced(expr):
        return None
    inner = expr[1:-1].strip()
    m = re.match(r'(\w+) value: ', inner)
    if not m or m.group(1) not in (evaluators or EVALUATORS):
        return None
    rest = inner[m.end():]
    if not rest.startswith("'"):
        return None
    value, end = st_string(rest, 0)
    if rest[end:].strip():
        return None
    return chunk(value)


DEFINING = re.compile(r'\((define|define-macro|set!|define-test|load)[\s)]')


def as_code(source):
    """The LISP expression to check: the source itself when it is one form that
    defines nothing at top level, else (eval-all "source")."""
    from_eval = '(eval-all ' + lisp_string(source) + ')'
    s = source.strip()
    # procedure-source needs the text, which only compiling from source keeps
    if s.startswith('(') and s.count('\n') == 0 and not DEFINING.search(s) and 'procedure-source' not in s:
        depth, ok, i = 0, True, 0
        instr = False
        while i < len(s):
            c = s[i]
            if instr:
                if c == '\\': i += 2; continue
                if c == '"': instr = False
            elif c == '"': instr = True
            elif c == ';': ok = False; break
            elif c == '(': depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0 and i != len(s) - 1: ok = False; break
            i += 1
        if ok and depth == 0:
            return s
    return from_eval


def expected(expr):
    """A Smalltalk expected value -> a LISP expression, else None."""
    e = expr.strip()
    while balanced(e) and not re.match(r'\((lst|LispReader|LispSymbol|sym|rd) ', e):
        e = e[1:-1].strip()
    if re.fullmatch(r'-?\d+', e) or re.fullmatch(r'-?\d+\.\d+', e):
        return e
    if e == 'true': return '#t'
    if e == 'false': return '#f'
    if e == 'LispEmptyList default': return "'()"
    if e == 'LispUnspecified default': return '(if #f #f)'
    if e.startswith("'"):
        v, end = st_string(e, 0)
        if e[end:].strip(): return None
        return lisp_string(chunk(v))
    m = re.fullmatch(r"\$([A-Za-z0-9])", e)
    if m: return '#\\' + m.group(1)
    m = re.fullmatch(r"\((?:lst value:|LispReader read:|rd value:) ('.*')\)", e, re.S)
    if m:
        v, end = st_string(m.group(1), 0)
        if m.group(1)[end:].strip(): return None
        return "'" + chunk(v)
    m = re.fullmatch(r"\((?:LispSymbol named:|sym value:) ('[^']*')\)", e)
    if m:
        return "'" + chunk(st_string(m.group(1), 0)[0])
    return None


def parse_args(text, keywords):
    """'k1: a k2: b' with the given keywords in order -> [a, b], split at top level."""
    parts, pos = [], 0
    marks = []
    depth, i = 0, 0
    while i < len(text):
        c = text[i]
        if c == "'":
            _, i = st_string(text, i); continue
        if c == '"':
            i = text.index('"', i + 1) + 1; continue
        if c in '([{': depth += 1
        elif c in ')]}': depth -= 1
        elif depth == 0:
            for k in keywords:
                if text.startswith(k, i) and (i == 0 or text[i - 1] in ' \t\r\n'):
                    marks.append((i, k)); break
        i += 1
    seq = [k for _, k in marks]
    if seq != list(keywords):
        return None
    for idx, (at, k) in enumerate(marks):
        end = marks[idx + 1][0] if idx + 1 < len(marks) else len(text)
        parts.append(text[at + len(k):end].strip())
    return parts


def convert(stmt):
    """A statement -> ('check', label, lisp) | ('setup', lisp) | None."""
    s = strip_comments(stmt).rstrip('.').strip()
    # check value: L value: A value: E   /   h check: L actual: A expected: E
    for head, kws in (('check value:', ['value:', 'value:']), ('h check:', ['actual:', 'expected:'])):
        if s.startswith(head):
            rest = s[len(head):].strip()
            if not rest.startswith("'"): return None
            label, end = st_string(rest, 0)
            args = parse_args(rest[end:].strip(), kws)
            if not args: return None
            src = lisp_source(args[0])
            exp = expected(args[1])
            if src is not None and exp is not None:
                return ('check', chunk(label), '(check ' + as_code(src) + ' ' + exp + ')')
            # (w value: S) expected: 'text'  -> the value as write prints it
            # (msg value: S) expected: 'text' -> the error message
            for fn, form in (('w', 'check-written'), ('msg', 'check-error')):
                src = lisp_source(args[0], {fn})
                if src is not None and args[1].startswith("'"):
                    text, end = st_string(args[1], 0)
                    if args[1][end:].strip(): return None
                    code = eval_code(src) if form == 'check-error' else as_code(src)
                    return ('check', chunk(label), '(' + form + ' ' + code + ' ' + lisp_string(chunk(text)) + ')')
            return None
    # checkErr value: L value: [ev value: S]  (2 args), checkErr(Class) value: L value: C value: [..]
    m = re.match(r"(checkErr|checkErrClass) value: ", s)
    if m:
        rest = s[m.end():]
        if not rest.startswith("'"): return None
        label, end = st_string(rest, 0)
        tail = rest[end:].strip()
        args = parse_args(tail, ['value:', 'value:']) or parse_args(tail, ['value:'])
        if not args: return None
        blk = args[-1]
        if not (blk.startswith('[') and blk.endswith(']')): return None
        src = lisp_source('(' + blk[1:-1].strip() + ')')
        if src is None: return None
        if len(args) == 2 and args[0] not in ('Error', 'LispError'):
            return ('check', chunk(label), '(check-error-class ' + eval_code(src) + ' ' + args[0] + ')')
        return ('check', chunk(label), '(check-error ' + eval_code(src) + ')')
    # checkMsg value: L value: C value: 'needle' value: [ev value: S]
    if s.startswith('checkMsg value: '):
        rest = s[len('checkMsg value: '):]
        label, end = st_string(rest, 0)
        args = parse_args(rest[end:].strip(), ['value:', 'value:', 'value:'])
        if not args or not args[1].startswith("'"): return None
        needle = chunk(st_string(args[1], 0)[0])
        blk = args[2]
        if not (blk.startswith('[') and blk.endswith(']')): return None
        src = lisp_source('(' + blk[1:-1].strip() + ')')
        if src is None: return None
        return ('check', chunk(label), '(check-error ' + eval_code(src) + ' ' + lisp_string(needle) + ')')
    # setup: ev value: S
    m = re.fullmatch(r"(\w+) value: ('.*')", s, re.S)
    if m and m.group(1) in EVALUATORS:
        v, end = st_string(m.group(2), 0)
        if m.group(2)[end:].strip(): return None
        return ('setup', chunk(v))
    return None


def eval_code(source):
    """Error checks evaluate at test time: a compile error must fail its check,
    not stop the whole file from loading."""
    return '(eval-all ' + lisp_string(source) + ')'


# Checks that depend on running inside a Smalltalk test rather than a LISP
# program, so they stay in their suites: under the runner there is a top-level
# abort restart and a load path, and one check needs a Smalltalk-side definition.
STAY = {
    'AC-4 ... and it sees restarts established below it',
    'AC-9 compute-restarts, innermost first',
    'AC-11 the restarts on offer',
    'AC-6 current-load-path is #f outside a load',
    'AC-18 define:as:',
}


def side_effect_sources(stmt):
    """LISP sources inside a statement that stays in Smalltalk, when they define or
    load something that later checks may depend on."""
    out = []
    for m in re.finditer(r"\b(?:ev|evAll|w|msg) value: '", stmt):
        v = chunk(st_string(stmt, m.end() - 1)[0])
        # not the framework's own self-test (it resets the counters), and not a
        # fragment of source that the Smalltalk check assembles
        if 'define-test' in v or '%pass' in v or v.count('(') != v.count(')'):
            continue
        if re.search(r'\((define|define-macro|set!|load|defun|defvar|defmacro)[\s)]', v):
            out.append(v)
    if "'cl.lisp'" in stmt:
        out.append('(load "../../lib/cl.lisp")')
    return out


def region_of(text):
    start = text.index('\n[\n') + 3
    end = text.index('\nh finish', start)
    return start, end


def main(dry):
    moved_names, report = [], []
    for name in SUITES:
        path = 'tests/' + name + '.st'
        text = io.open(path, encoding='utf-8', newline='').read()
        rstart, rend = region_of(text)
        region = text[rstart:rend]
        out_lisp, keep, moved, setups = [], [], 0, 0
        for (a, b, stmt) in statements(region):
            c = convert(stmt)
            if c and c[0] == 'check' and c[1] in STAY:
                c = None
            if c and c[0] == 'check':
                moved += 1
                moved_names.append(name + ': ' + c[1])
                out_lisp.append('(define-test ' + lisp_string(c[1]) + '\n  ' + c[2] + ')')
                # keep the statement's leading comment lines, drop the check
                lead = stmt[:len(stmt) - len(stmt.lstrip())]
                comments = re.findall(r'"[^"]*"', stmt[:stmt.find(strip_comments(stmt)[:10]) if strip_comments(stmt) else 0])
                keep.append(lead + ('\n'.join(comments) + '\n' if comments else ''))
                # a moved check that defines something stays behind as a setup,
                # because checks that remain in the suite may depend on it
                for m in re.finditer(r"\b(ev|evAll|w|msg) value: '", stmt):
                    src_lit_start = m.end() - 1
                    v, end = st_string(stmt, src_lit_start)
                    if re.search(r'\((define|define-macro|set!!?|load)[\s)]', v):
                        keep.append('[' + ('ev' if m.group(1) in ('w', 'msg') else m.group(1)) + ' value: '
                                    + stmt[src_lit_start:end] + '] on: Error do: [:e | nil].\n'
                                    + '"(the check itself moved to tests/lisp/' + name + '.lisp)"\n')
            else:
                if c and c[0] == 'setup':
                    setups += 1
                    out_lisp.append('(define-test "setup"\n  (eval-all ' + lisp_string(c[1]) + '))')
                elif not c:
                    for src in side_effect_sources(stmt):
                        setups += 1
                        out_lisp.append('(define-test "setup (from a check that stays in the suite)"\n'
                                        '  (guard (e (#t #f)) (eval-all ' + lisp_string(src) + ')))')
                keep.append(stmt)
        total_checks = moved + sum(1 for (_, _, st) in statements(region) if re.search(r'\b(check|checkErr|checkErrClass|checkMsg|h check)\b', strip_comments(st)) and not convert(st))
        report.append('%-24s moved %3d   setups copied %2d' % (name, moved, setups))
        if dry or moved == 0:
            continue
        lisp_path = 'tests/lisp/' + name + '.lisp'
        header = (';;; ' + name + '.lisp -- the language-behavior checks of tests/' + name + '.st,\n'
                  ';;; moved to cog-lisp (Phase 8 step 8.1; generated by tests/lisp/convert-suites.py).\n'
                  ';;; Test names keep their spec references (AC-n, review ids).\n'
                  '(load "../../lib/test.lisp")\n\n')
        body = '\n'.join(out_lisp)
        io.open(lisp_path, 'w', encoding='utf-8', newline='\n').write(header + body + '\n\n(run-tests)\n')
        new_region = ''.join(keep)
        new_region = re.sub(r'\n{3,}', '\n\n', new_region)
        io.open(path, 'w', encoding='utf-8', newline='').write(text[:rstart] + new_region + text[rend:])
    print('\n'.join(report))
    print('total moved:', len(moved_names))
    if not dry:
        io.open('tests/lisp/moved-checks.txt', 'w', encoding='utf-8', newline='\n').write(
            '# Checks moved from the Smalltalk suites to tests/lisp/ (Phase 8 step 8.1)\n' + '\n'.join(moved_names) + '\n')


if __name__ == '__main__':
    main('--dry' in sys.argv)
