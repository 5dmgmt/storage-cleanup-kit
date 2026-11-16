#!/usr/bin/env bash
# このキットが配置した storage-cleanup スキルだけを外します。
set -uo pipefail

INSTALL_DIR="$HOME/.claude/skills/storage-cleanup"

fail() {
  printf 'アンインストール中止: %s\n' "$*" >&2
  exit 1
}

printf '外す候補: %s\n' "$INSTALL_DIR"
[ -f "$INSTALL_DIR/VERSION" ] || fail "VERSION がないため、このキットの物と確認できません"
[ -f "$INSTALL_DIR/SKILL.md" ] || fail "SKILL.md がありません"
grep -Eq '^name:[[:space:]]*storage-cleanup[[:space:]]*$' "$INSTALL_DIR/SKILL.md" || fail "別のスキルの可能性があるため外しません"

printf '確認済みのスキルを外します: %s\n' "$INSTALL_DIR"
rm -rf -- "$INSTALL_DIR" || fail "スキルを外せません"
printf 'アンインストールしました。導入時のバックアップは残しています。\n'
