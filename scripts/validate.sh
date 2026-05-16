#!/usr/bin/env bash
# Pre-flight validation for the audit-repo-security skill.
# Run this before packaging or shipping a release.
#
# Checks:
#   1. Every ```json fenced block parses cleanly with Python's json.loads.
#   2. All required prompt files exist.
#   3. Every file referenced from the README output tree actually exists.
#   4. No stale `med` confidence value (banned in favor of `medium`).
#   5. No fake-JSON schema notation inside ```json blocks (pipe-delimited
#      enum strings like "a | b | c").
#
# Exits 0 on success, 1 on any failure. Each failing check prints to stderr.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SKILL_DIR"

FAIL=0
pass() { printf '  \033[32mOK\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1" >&2; FAIL=1; }
section() { printf '\n%s\n' "$1"; }

section "1. JSON block validation"
python3 - <<'PY' || FAIL=1
import re, json, pathlib, sys
ok = bad = 0
for p in sorted(pathlib.Path('.').rglob('*.md')):
    for i, block in enumerate(re.findall(r'```json\n(.*?)\n```', p.read_text(), re.DOTALL)):
        try:
            json.loads(block); ok += 1
        except json.JSONDecodeError as e:
            bad += 1
            print(f'  FAIL {p}#{i}: {e}', file=sys.stderr)
print(f'  OK   {ok} json blocks parsed cleanly' + (f', {bad} invalid' if bad else ''))
sys.exit(1 if bad else 0)
PY

section "2. Required prompt files"
required=(
  SKILL.md README.md CHANGELOG.md LICENSE
  prompts/01-pre-recon.md prompts/02-recon.md prompts/02b-secret-triage.md
  prompts/03-vuln-injection.md prompts/04-vuln-xss.md prompts/05-vuln-auth.md
  prompts/06-vuln-authz.md prompts/07-vuln-ssrf.md prompts/08-supply-chain.md
  prompts/09-report.md
  schemas/findings-queue.md
  scripts/package.sh scripts/validate.sh
)
missing=()
for f in "${required[@]}"; do
  [ -f "$f" ] || missing+=("$f")
done
if [ ${#missing[@]} -eq 0 ]; then
  pass "all ${#required[@]} required files present"
else
  fail "missing files:"
  printf '       %s\n' "${missing[@]}" >&2
fi

section "3. README output-tree references"
# Match by basename — the README's layout block indents files under their parent
# directory rather than spelling out full paths.
declare -a referenced=(
  prompts/01-pre-recon.md prompts/02-recon.md prompts/02b-secret-triage.md
  prompts/03-vuln-injection.md prompts/04-vuln-xss.md prompts/05-vuln-auth.md
  prompts/06-vuln-authz.md prompts/07-vuln-ssrf.md prompts/08-supply-chain.md
  prompts/09-report.md
  schemas/findings-queue.md
  scripts/package.sh
)
broken=()
for f in "${referenced[@]}"; do
  base="$(basename "$f")"
  grep -qF "$base" README.md || broken+=("$base not referenced in README")
  [ -f "$f" ] || broken+=("$f referenced but missing")
done
if [ ${#broken[@]} -eq 0 ]; then
  pass "README references match the filesystem"
else
  fail "README/filesystem mismatch:"
  printf '       %s\n' "${broken[@]}" >&2
fi

section "4. Stale 'med' confidence value"
# Match standalone 'med' inside JSON-ish contexts (quoted "med" or | med |) but
# allow "medium", "med-confidence" inside CHANGELOG history references.
hits="$(grep -rEn '"med"|\| med \||/med/' --include='*.md' . 2>/dev/null \
  | grep -v 'CHANGELOG.md' || true)"
if [ -z "$hits" ]; then
  pass "no 'med' confidence values outside CHANGELOG history"
else
  fail "stale 'med' values found:"
  printf '       %s\n' "$hits" >&2
fi

section '5. Fake-JSON schema notation inside json blocks'
python3 - <<'PY' || FAIL=1
import re, pathlib, sys
# Pipe-delimited enum strings like "a | b | c" or true | false inside ```json blocks
# are invalid; the records must commit to one value per field.
bad = []
pat_block = re.compile(r'```json\n(.*?)\n```', re.DOTALL)
pat_pipe = re.compile(r'"[^"\n]*\|[^"\n]*"')  # any quoted string containing |
pat_bool_alt = re.compile(r':\s*true\s*\|\s*false')  # raw true | false
for p in sorted(pathlib.Path('.').rglob('*.md')):
    for i, block in enumerate(pat_block.findall(p.read_text())):
        for m in pat_pipe.findall(block):
            # Tolerate strings where '|' is genuinely part of the value
            # (e.g., a regex example). Heuristic: flag only if the pipe is
            # surrounded by spaces, which is how enum schemas were written.
            if ' | ' in m:
                bad.append((p, i, m))
        if pat_bool_alt.search(block):
            bad.append((p, i, 'true | false'))
if bad:
    for p, i, snippet in bad:
        print(f'  FAIL {p}#{i}: {snippet}', file=sys.stderr)
    sys.exit(1)
print('  OK   no pipe-delimited enum strings inside json blocks')
PY

echo
if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Validation failed. Fix the items above before packaging." >&2
  exit 1
fi
