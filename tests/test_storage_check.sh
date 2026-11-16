#!/usr/bin/env bash
set -uo pipefail

REPO_DIR="$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/storage-cleanup-test.XXXXXX")"
FAKE_HOME="$TEST_ROOT/home"
OUTPUT="$TEST_ROOT/output.txt"
BEFORE="$TEST_ROOT/before.txt"
AFTER="$TEST_ROOT/after.txt"

cleanup() { rm -rf -- "$TEST_ROOT"; }
trap cleanup EXIT HUP INT TERM

mkdir -p \
  "$FAKE_HOME/.npm" \
  "$FAKE_HOME/Library/Caches/Google/Chrome" \
  "$FAKE_HOME/Library/Application Support/Google/Chrome/Profile 3/Service Worker/CacheStorage" \
  "$FAKE_HOME/Library/Application Support/Google/DriveFS" \
  "$FAKE_HOME/Library/Logs/Noisy" \
  "$FAKE_HOME/Projects/a/node_modules/pkg" \
  "$FAKE_HOME/Projects/a/.next/cache" \
  "$FAKE_HOME/Downloads" "$FAKE_HOME/Desktop" "$FAKE_HOME/Movies" "$FAKE_HOME/Documents"
dd if=/dev/zero of="$FAKE_HOME/.npm/cache.bin" bs=1048576 count=1 2>/dev/null
dd if=/dev/zero of="$FAKE_HOME/Library/Application Support/Google/Chrome/Profile 3/Service Worker/CacheStorage/profile3.bin" bs=1024 count=8 2>/dev/null
dd if=/dev/zero of="$FAKE_HOME/Projects/a/node_modules/pkg/file.bin" bs=1024 count=4 2>/dev/null
dd if=/dev/zero of="$FAKE_HOME/Projects/a/.next/cache/file.bin" bs=1024 count=4 2>/dev/null
: > "$FAKE_HOME/Library/Application Support/Google/DriveFS/x-wal"
i=1
while [ "$i" -le 20 ]; do
  : > "$FAKE_HOME/Library/Logs/Noisy/log-$i.txt"
  i=$((i + 1))
done

snapshot() {
  find "$FAKE_HOME" -exec stat -f '%N %z %m' {} + 2>/dev/null | sort
}
snapshot > "$BEFORE"

status=0
HOME="$FAKE_HOME" SC_DEV_ROOTS="$FAKE_HOME/Projects" SC_SKIP_SYSTEM_SCAN=1 \
  SC_DRIVE_ROOTS="$FAKE_HOME/Fake Drive" SC_FREE_GB_OVERRIDE=9 \
  bash "$REPO_DIR/skill/bin/storage-check.sh" > "$OUTPUT" || status=$?
[ "$status" -eq 0 ] || { printf '失敗: 終了コード %s\n' "$status" >&2; exit 1; }

snapshot > "$AFTER"
cmp -s "$BEFORE" "$AFTER" || { printf '失敗: 偽 HOME の内容が変わりました\n' >&2; diff -u "$BEFORE" "$AFTER" >&2 || true; exit 1; }

for heading in \
  '■ ディスク' \
  '■ Google Drive' \
  '■ 再生成されるもの' \
  '■ Chrome の自分の複製' \
  '■ ログの暴走' \
  '■ 消してはいけないもの' \
  '■ あなたのデータ' \
  '■ ホーム直下' \
  '■ ホームの外' \
  '■ 起動中で終了が要るアプリ'; do
  grep -Fq "$heading" "$OUTPUT" || { printf '失敗: 見出しがありません: %s\n' "$heading" >&2; exit 1; }
done

grep -Fq '空きが 10GB を切っています' "$OUTPUT" || { printf '失敗: 空き容量の案内がありません\n' >&2; exit 1; }

grep -Fq 'Profile 3/Service Worker/CacheStorage' "$OUTPUT" || { printf '失敗: Profile 3 の Service Worker がありません\n' >&2; exit 1; }
grep -Fq 'node_modules 合計' "$OUTPUT" || { printf '失敗: node_modules がありません\n' >&2; exit 1; }
grep -Fq '.next 合計' "$OUTPUT" || { printf '失敗: .next がありません\n' >&2; exit 1; }

REAL_HOME="$(cd && pwd)"
if [ "$REAL_HOME" != "$FAKE_HOME" ] && grep -Fq "$REAL_HOME/" "$OUTPUT"; then
  printf '失敗: 実 HOME 由来のパスが出力されました\n' >&2
  exit 1
fi

printf '成功: storage-check.sh は偽 HOME を変更せず、必要な節と対象を出力しました\n'
