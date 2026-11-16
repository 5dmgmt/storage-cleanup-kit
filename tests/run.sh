#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd)"
REPO_DIR="$(unset CDPATH; cd -- "$SCRIPT_DIR/.." && pwd)"
passed=0
failed=0

for test_file in "$SCRIPT_DIR"/test_*.sh; do
  [ -f "$test_file" ] || continue
  printf '実行: %s\n' "$(basename "$test_file")"
  if bash "$test_file"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
done

printf '構文確認: bash -n\n'
syntax_failed=0
while IFS= read -r shell_file; do
  if ! bash -n "$shell_file"; then syntax_failed=1; fi
done < <(find "$REPO_DIR" -type f -name '*.sh' -not -path '*/.git/*' | sort)
if [ "$syntax_failed" -eq 0 ]; then passed=$((passed + 1)); else failed=$((failed + 1)); fi

if command -v shellcheck >/dev/null 2>&1; then
  printf '静的検査: shellcheck\n'
  shellcheck_failed=0
  while IFS= read -r shell_file; do
    if ! shellcheck "$shell_file"; then shellcheck_failed=1; fi
  done < <(find "$REPO_DIR" -type f -name '*.sh' -not -path '*/.git/*' | sort)
  if [ "$shellcheck_failed" -eq 0 ]; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
else
  printf '静的検査: shellcheck は未導入のため省略\n'
fi

if command -v swiftc >/dev/null 2>&1; then
  printf '構文確認: swiftc -parse\n'
  if swiftc -parse "$REPO_DIR/skill/bin/cloud-status.swift"; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
else
  printf '構文確認: swiftc は未導入のため省略\n'
fi

printf '合計: 成功 %s / 失敗 %s\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
