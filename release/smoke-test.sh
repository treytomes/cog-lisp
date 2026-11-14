#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : test an unpacked release bundle  (specs/14-phase-8.9-ci-cd.md AC-6/7)
#    release/smoke-test.sh BUNDLE_DIR
#  Runs every example in the bundle with the bundle's own launcher and compares
#  its output with the example's .expected (as tests/phase-5-runner.sh does, with
#  NAME.args and NAME.input), pipes two lines into the REPL, and on Windows also
#  runs one example through cog-lisp.bat. Runs on Linux and in Git Bash on Windows.
#  Prints PASS/FAIL per check and RESULT: n/n; exit 0 only if all pass.
# ===========================================================================
set -u

B="$(cd "${1:?usage: release/smoke-test.sh BUNDLE_DIR}" && pwd)"
cd "$B"
OUT="$(mktemp -d)"
PASS=0
TOTAL=0
check() {
  TOTAL=$((TOTAL + 1))
  if [ "$2" = 1 ]; then PASS=$((PASS + 1)); echo "  PASS  $1"; else echo "  FAIL  $1"; fi
}

echo "== cog-lisp release bundle : $B =="

# the licenses: every one THIRD-PARTY-NOTICES.md names is in licenses/, and no
# library the notices do not cover (they cover the VM, libffi, winpthreads)
ok=1
for f in LICENSE THIRD-PARTY-NOTICES.md; do [ -s "$f" ] || { echo "    missing $f"; ok=0; }; done
for f in $(grep -o 'licenses/[A-Za-z0-9._-]*\.txt' THIRD-PARTY-NOTICES.md | sort -u); do
  case "$f" in
    *winpthreads*) [ -f pharo/libwinpthread-1.dll ] || continue ;;
  esac
  [ -s "$f" ] || { echo "    missing $f"; ok=0; }
done
check "the bundle carries LICENSE, the notices and every license they name" $ok
ok=0; [ -s docs/builtins.md ] && grep -q "string-ref" docs/builtins.md && ok=1
check "the bundle carries the reference of the built-ins (docs/builtins.md)" $ok
ok=0; [ -s docs/manual/README.md ] && [ -s docs/manual/01-getting-started.md ] && ok=1
check "the bundle carries the manual (docs/manual/)" $ok
# the agent skill (Phase 10 step 10.7), stamped with this bundle's version
V="$(basename "$B")"; V="${V#cog-lisp-}"
ok=0; [ -s .agents/skills/cog-lisp/SKILL.md ] && [ -s .agents/skills/cog-lisp/reference.md ] &&
  head -1 .agents/skills/cog-lisp/SKILL.md | grep -q '^---' &&
  grep -q "^name: cog-lisp\$" .agents/skills/cog-lisp/SKILL.md &&
  grep -q "^version: $V\$" .agents/skills/cog-lisp/SKILL.md && ok=1
check "the bundle carries the agent skill, stamped $V (.agents/skills/cog-lisp/)" $ok
ok=0; [ -s .agents/skills/cog-lisp/console.md ] && [ -s tools/console_driver.py ] && ok=1
check "the bundle carries the console driver and the skill's page on it (specs/36-console-driver.md)" $ok
stray="$(cd pharo && find . -type f \( -iname '*.dll' -o -name '*.so' -o -name '*.so.*' \) | sed 's|.*/||' |
  grep -Ev '^(lib)?(PharoVMCore|ffi|tty|winpthread-1|B2DPlugin|BitBltPlugin|DSAPrims|FileAttributesPlugin|FilePlugin|FloatArrayPlugin|JPEGReaderPlugin|LargeIntegers|LocalePlugin|MiscPrimitivePlugin|NewFilePlugin|SocketPlugin|SqueakSSL|SurfacePlugin|UUIDPlugin|UnixOSProcessPlugin)\.(dll|so)$' || true)"
ok=0; [ -z "$stray" ] && ok=1
check "the VM folder holds only the VM, its plugins, libffi and winpthreads" $ok
[ "$ok" = 1 ] || echo "$stray" | sed 's/^/    /'

for f in examples/*.lisp examples/*/main.lisp; do
  base="${f%.lisp}"
  [ -f "$base.expected" ] || continue
  name="$(basename "$base")"
  args=()
  [ -f "$base.args" ] && read -r -a args < "$base.args"
  input=/dev/null
  [ -f "$base.input" ] && input="$base.input"
  ./cog-lisp.sh "$f" ${args[@]+"${args[@]}"} <"$input" >"$OUT/$name.out" 2>"$OUT/$name.err"
  rc=$?
  ok=0; [ "$rc" = 0 ] && cmp -s "$base.expected" "$OUT/$name.out" && ok=1
  check "$name: exit $rc, output matches $name.expected" $ok
  [ "$ok" = 1 ] || { diff "$base.expected" "$OUT/$name.out" | head -5; head -3 "$OUT/$name.err"; }
done

printf '(+ 1 2)\n(display "ok")\n' | ./cog-lisp.sh >"$OUT/repl.out" 2>&1
ok=0; grep -q '> 3' "$OUT/repl.out" && grep -q 'ok' "$OUT/repl.out" && ok=1
check "the REPL reads piped input" $ok

if [ -f cog-lisp.bat ]; then
  cmd //d //c ".\\cog-lisp.bat examples\\hello.lisp" </dev/null >"$OUT/bat.out" 2>&1
  ok=0; cmp -s examples/hello.expected "$OUT/bat.out" && ok=1
  check "cog-lisp.bat runs a program" $ok
fi

# the MCP server's launcher answers initialize (specs/35-mcp-server.md R-15, AC-20)
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{}}}' > "$OUT/mcp.in"
./mcp-server.sh examples <"$OUT/mcp.in" >"$OUT/mcp.out" 2>"$OUT/mcp.err"
rc=$?
ok=0; [ "$rc" = 0 ] && [ "$(wc -l < "$OUT/mcp.out")" -eq 1 ] && grep -q '"serverInfo":{"name":"cog-lisp"' "$OUT/mcp.out" && ok=1
check "mcp-server.sh answers initialize, one line on stdout (exit $rc)" $ok
[ "$ok" = 1 ] || { head -c 300 "$OUT/mcp.out"; head -3 "$OUT/mcp.err"; }
if [ -f mcp-server.bat ]; then
  cmd //d //c ".\\mcp-server.bat examples" <"$OUT/mcp.in" >"$OUT/mcp-bat.out" 2>"$OUT/mcp-bat.err"
  ok=0; [ "$(wc -l < "$OUT/mcp-bat.out")" -eq 1 ] && grep -q '"serverInfo":{"name":"cog-lisp"' "$OUT/mcp-bat.out" && ok=1
  check "mcp-server.bat answers initialize, one line on stdout" $ok
fi

# require finds the bundle's own libraries from a program in another folder
# (specs/18-library-path.md AC-1)
ELSE="$(mktemp -d)"
printf "(require 'cl)\n(defun twice (x) (* 2 x))\n(display (twice 21))\n(newline)\n" > "$ELSE/p.lisp"
(cd "$ELSE" && "$B/cog-lisp.sh" p.lisp) </dev/null >"$OUT/else.out" 2>&1
ok=0; [ "$(cat "$OUT/else.out")" = 42 ] && ok=1
check "require finds the bundle's libraries from a program in another folder" $ok
[ "$ok" = 1 ] || head -3 "$OUT/else.out"

# Live HTTPS from the bundle (specs/21-https-and-json.md AC-4), only with
# COGLISP_LIVE_HTTPS=1: a good certificate is accepted, an expired one refused.
if [ "${COGLISP_LIVE_HTTPS:-}" = 1 ]; then
  printf '%s\n' '(display (http-status (http-get "https://example.com/" (quote ()) 20)))' '(newline)' \
    '(display (guard (e (#t (error-object-message e))) (http-get "https://expired.badssl.com/" (quote ()) 20)))' \
    '(newline)' > "$ELSE/https.lisp"
  (cd "$ELSE" && "$B/cog-lisp.sh" https.lisp) </dev/null >"$OUT/https.out" 2>&1
  ok=0; head -1 "$OUT/https.out" | tr -d '\r' | grep -qx 200 &&
    grep -q "http: certificate rejected by expired.badssl.com" "$OUT/https.out" && ok=1
  check "live: the bundle fetches over HTTPS and refuses an expired certificate" $ok
  [ "$ok" = 1 ] || head -3 "$OUT/https.out"
fi
rm -rf "$ELSE"

# Starting anywhere (specs/17-startup-anywhere.md AC-5): the bundle made read-only,
# run from a read-only folder. Root ignores permissions, so only as another user.
if [ "$(uname -s)" = Linux ] && [ "$(id -u)" != 0 ]; then
  RO="$(mktemp -d)"
  chmod -R a-w "$B"; chmod 555 "$RO"
  (cd "$RO" && "$B/cog-lisp.sh" "$B/examples/hello.lisp") </dev/null >"$OUT/ro.out" 2>"$OUT/ro.err"
  rc=$?
  chmod -R u+w "$B"; chmod 755 "$RO"
  ok=0; [ "$rc" = 0 ] && cmp -s examples/hello.expected "$OUT/ro.out" && [ ! -s "$OUT/ro.err" ] && [ -z "$(ls -A "$RO")" ] && ok=1
  check "a read-only bundle runs from a read-only folder, writing nothing there" $ok
  [ "$ok" = 1 ] || head -3 "$OUT/ro.err"
  rm -rf "$RO"
fi

rm -rf "$OUT"
echo
echo "== RESULT: $PASS/$TOTAL checks passed =="
[ "$PASS" = "$TOTAL" ]
