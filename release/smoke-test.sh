#!/usr/bin/env bash
# ===========================================================================
#  cog-lisp : test an unpacked release bundle  (specs/phase-8.9-ci-cd.md AC-6/7)
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

rm -rf "$OUT"
echo
echo "== RESULT: $PASS/$TOTAL checks passed =="
[ "$PASS" = "$TOTAL" ]
