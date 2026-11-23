#!/usr/bin/env bash
# Tests for drift-guard.sh: a stubbed `lps` serves fixtures, a temporary git repo provides the worktree.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/drift-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0

mkdir -p "$TMP/bin" "$TMP/fix" "$TMP/repo"
# The stub answers from the worktree (previous commit) with before.json, from the repo with after.json.
cat >"$TMP/bin/lps" <<STUB
#!/usr/bin/env bash
case "\$PWD" in
  */base) n=before ;;
  *) n=after ;;
esac
cat "$TMP/fix/\$n.json"
exit "\$(cat "$TMP/fix/\$n.code")"
STUB
chmod +x "$TMP/bin/lps"

git -C "$TMP/repo" init --quiet
git -C "$TMP/repo" -c user.name=t -c user.email=t@t commit --quiet --allow-empty -m base
SHA="$(git -C "$TMP/repo" rev-parse HEAD)"

# run <name> <expected exit> <expected stderr fragment> <before code> <before json> <after code> <after json> [PATH]
run() {
  local name="$1" want="$2" frag="$3" path="${8:-$TMP/bin:$PATH}"
  printf '%s' "$5" >"$TMP/fix/before.json"
  printf '%s' "$7" >"$TMP/fix/after.json"
  echo "$4" >"$TMP/fix/before.code"
  echo "$6" >"$TMP/fix/after.code"
  local err code
  err="$(cd "$TMP/repo" && PATH="$path" bash "$SCRIPT" site "$SHA" 2>&1 >/dev/null)"
  code=$?
  if [ "$code" -eq "$want" ] && [[ "$err" == *"$frag"* ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name (exit $code, want $want, want stderr containing: $frag)"
    printf '     %s\n' "${err//$'\n'/$'\n     '}"
    FAILED=1
  fi
}

DRIFT='{"resources":{"posts":{"changed":[{"id":"a"}],"removed":[],"added":[]}}}'
CLEAN='{"resources":{"posts":{"changed":[],"removed":[],"added":[]}}}'
ERR_AND_DRIFT='{"resources":{"menus":{"error":"boom","changed":[],"removed":[],"added":[]},"posts":{"changed":[{"id":"a"}],"removed":[],"added":[]}}}'
ERR_ONLY='{"resources":{"menus":{"error":"boom","changed":[],"removed":[],"added":[]},"posts":{"changed":[],"removed":[],"added":[]}}}'

run "overlapping id blocks" 1 "posts/a" 1 "$DRIFT" 1 "$DRIFT"
run "no overlap passes" 0 "" 1 "$DRIFT" 0 "$CLEAN"
run "resource in error (exit 2) still blocks another resource" 1 "posts/a" 2 "$ERR_AND_DRIFT" 2 "$ERR_AND_DRIFT"
run "resource in error is reported, others pass" 0 "could not be compared" 2 "$ERR_ONLY" 2 "$ERR_ONLY"
run "exit above 2 is inconclusive" 0 "inconclusive" 3 "$DRIFT" 1 "$DRIFT"
run "report without resources is inconclusive" 0 "inconclusive" 1 '{"drift":true}' 1 '{"drift":true}'

# jq missing: a PATH with git and bash tools but no jq.
mkdir -p "$TMP/nojq"
for t in bash git mktemp rm cat dirname env sort comm sed; do
  ln -sf "$(command -v "$t")" "$TMP/nojq/$t"
done
ln -sf "$TMP/bin/lps" "$TMP/nojq/lps"
run "jq missing fails closed" 1 "jq not found, install it or set LOOPRESS_SKIP_DRIFT_GUARD=1 to deploy without the guard" 1 "$DRIFT" 1 "$DRIFT" "$TMP/nojq"

exit "$FAILED"
