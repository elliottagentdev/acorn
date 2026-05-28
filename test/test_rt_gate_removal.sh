#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ACORN_SCRIPT="${ACORN_SCRIPT:-$(dirname "$0")/../bin/acorn}"
[ -x "$ACORN_SCRIPT" ] || { echo "acorn not executable at $ACORN_SCRIPT" >&2; exit 1; }

PASS=0; FAIL=0
pass(){ PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail(){ FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s -- %s\n' "$1" "$2"; }
assert_eq(){ [ "$2" = "$3" ] && pass "$1" || fail "$1" "expected '$3' got '$2'"; }
assert_contains(){ printf '%s' "$2" | grep -qF -- "$3" && pass "$1" || fail "$1" "missing '$3'"; }
assert_ge(){ [ "$2" -ge "$3" ] && pass "$1" || fail "$1" "expected >= '$3' got '$2'"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== test_rt_gate_removal ==="

count1=$(grep -c '^redteam_universal_gate' "$ACORN_SCRIPT" || true)
assert_eq "function definition removed" "$count1" "0"

count2=$(grep -c 'redteam_universal_gate' "$ACORN_SCRIPT" || true)
assert_eq "no redteam_universal_gate references remain" "$count2" "0"

set +e
out3="$("$ACORN_SCRIPT" _internal rt-gate "$TMP" 2>&1)"
rc3=$?
set -e
assert_eq "rt-gate subcommand exits 1" "$rc3" "1"
assert_contains "rt-gate stderr says Unknown subcommand" "$out3" "Unknown _internal subcommand: rt-gate"

mkdir -p "$TMP/recon"
printf '## Directory Structure\n' > "$TMP/recon/architecture.md"
printf '## Relevant Code\n' > "$TMP/recon/relevant_code.md"
printf '## Conventions\n' > "$TMP/recon/conventions.md"
set +e
"$ACORN_SCRIPT" _internal validate-stage "$TMP" lite 0 >/dev/null 2>&1
rc4=$?
set -e
assert_eq "validate-stage lite 0 still works" "$rc4" "0"

count5=$(grep -c 'Run pre-action rt-gate' "$ACORN_SCRIPT" || true)
assert_eq "rt-gate anchor text removed" "$count5" "0"

count6=$(grep -c 'acorn _internal validate-stage' "$ACORN_SCRIPT" || true)
assert_ge "validate-stage instructions preserved" "$count6" "15"

set +e
bash -n "$ACORN_SCRIPT" 2>/dev/null
rc7=$?
set -e
assert_eq "bash -n passes" "$rc7" "0"

set +e
rendered=$(eval "$(sed '/^main "\$@"/d' "$ACORN_SCRIPT")"; planning_block_quick /tmp/spec-test 2>&1)
set -e
count8=$(printf '%s' "$rendered" | grep -c 'rt-gate' || true)
assert_eq "planning_block_quick has no rt-gate" "$count8" "0"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
