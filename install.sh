#!/usr/bin/env bash
# storage-cleanup スキルを利用者の Claude 設定フォルダーへ配置します。
set -uo pipefail

SCRIPT_DIR="$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
INSTALL_DIR="$CLAUDE_DIR/skills/storage-cleanup"

fail() {
  printf 'インストール中止: %s\n' "$*" >&2
  exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "macOS 専用です"
[ -f "$SCRIPT_DIR/skill/SKILL.md" ] || fail "skill/SKILL.md が見つかりません"

if [ -e "$INSTALL_DIR" ]; then
  # skills の中に置くと同じ名前のスキルが二重に読み込まれるため、外へ退避する
  BACKUP_ROOT="$CLAUDE_DIR/storage-cleanup-kit-backups"
  BACKUP_DIR="$BACKUP_ROOT/storage-cleanup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_ROOT" || fail "退避先を作成できません"
  [ ! -e "$BACKUP_DIR" ] || fail "退避先が既にあります: $BACKUP_DIR"
  printf '既存のスキルを退避します: %s -> %s\n' "$INSTALL_DIR" "$BACKUP_DIR"
  mv "$INSTALL_DIR" "$BACKUP_DIR" || fail "既存のスキルを退避できません"
fi

printf 'スキルを配置します: %s\n' "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bin" || fail "配置先を作成できません"
install -m 644 "$SCRIPT_DIR/skill/SKILL.md" "$INSTALL_DIR/SKILL.md" || fail "SKILL.md を配置できません"
install -m 644 "$SCRIPT_DIR/skill/reference.md" "$INSTALL_DIR/reference.md" || fail "reference.md を配置できません"
install -m 755 "$SCRIPT_DIR/skill/bin/storage-check.sh" "$INSTALL_DIR/bin/storage-check.sh" || fail "storage-check.sh を配置できません"
install -m 755 "$SCRIPT_DIR/skill/bin/cloud-status.swift" "$INSTALL_DIR/bin/cloud-status.swift" || fail "cloud-status.swift を配置できません"
install -m 755 "$SCRIPT_DIR/skill/bin/drive-offload.sh" "$INSTALL_DIR/bin/drive-offload.sh" || fail "drive-offload.sh を配置できません"
install -m 644 "$SCRIPT_DIR/VERSION" "$INSTALL_DIR/VERSION" || fail "VERSION を配置できません"

if ! command -v swift >/dev/null 2>&1; then
  printf '案内: swift がないため cloud-status は使えません（xcode-select --install で入ります）。\n'
fi
printf 'インストールしました: %s\n' "$INSTALL_DIR"
printf 'Claude Code を開き直すと /storage-cleanup が使えます。\n'
