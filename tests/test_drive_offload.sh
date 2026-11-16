#!/usr/bin/env bash
set -uo pipefail

REPO_DIR="$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)"
TOOL="$REPO_DIR/skill/bin/drive-offload.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/storage-offload-test.XXXXXX")"
TEST_ROOT="$(unset CDPATH; cd -- "$TEST_ROOT" && pwd -P)"
FAKE_HOME="$TEST_ROOT/home"
FAKE_DRIVE="$FAKE_HOME/Library/CloudStorage/FakeDrive/My Drive"
STATE_DIR="$TEST_ROOT/state"
OUTPUT="$TEST_ROOT/output.txt"

cleanup() { rm -rf -- "$TEST_ROOT"; }
trap cleanup EXIT HUP INT TERM

mkdir -p "$FAKE_DRIVE" "$STATE_DIR" "$FAKE_HOME/Downloads" "$FAKE_HOME/Library/Test"
run_tool() {
  HOME="$FAKE_HOME" SC_DRIVE_ROOTS="$FAKE_DRIVE" SC_OFFLOAD_STATE_DIR="$STATE_DIR" \
    bash "$TOOL" "$@"
}
expect_reject() {
  output=$1; shift
  status=0
  run_tool "$@" > "$output" 2>&1 || status=$?
  [ "$status" -eq 1 ] || { printf '失敗: 拒否されませんでした: %s\n' "$*" >&2; exit 1; }
}

run_tool roots > "$OUTPUT"
grep -Fq "$FAKE_DRIVE" "$OUTPUT" || { printf '失敗: 偽の Drive が出ません\n' >&2; exit 1; }

mkdir -p "$FAKE_HOME/Downloads/code/.git" "$FAKE_HOME/Downloads/secret" "$FAKE_HOME/Downloads/example"
: > "$FAKE_HOME/Downloads/secret/.env"
: > "$FAKE_HOME/Downloads/example/.env.example"
expect_reject "$OUTPUT" copy "$FAKE_DRIVE/git-test" "$FAKE_HOME/Downloads/code"
[ ! -e "$FAKE_DRIVE/git-test" ] || { printf '失敗: git 拒否時に写し先ができました\n' >&2; exit 1; }
expect_reject "$OUTPUT" copy "$FAKE_DRIVE/secret-test" "$FAKE_HOME/Downloads/secret"
[ ! -e "$FAKE_DRIVE/secret-test" ] || { printf '失敗: 秘密拒否時に写し先ができました\n' >&2; exit 1; }
expect_reject "$OUTPUT" copy "$FAKE_DRIVE/library-test" "$FAKE_HOME/Library/Test"
[ ! -e "$FAKE_DRIVE/library-test" ] || { printf '失敗: Library 拒否時に写し先ができました\n' >&2; exit 1; }
expect_reject "$OUTPUT" copy "$FAKE_HOME/outside-drive" "$FAKE_HOME/Downloads/example"
[ ! -e "$FAKE_HOME/outside-drive" ] || { printf '失敗: Drive 外拒否時に写し先ができました\n' >&2; exit 1; }
mkdir -p "$FAKE_DRIVE/collision/example"
expect_reject "$OUTPUT" copy "$FAKE_DRIVE/collision" "$FAKE_HOME/Downloads/example"
expect_reject "$OUTPUT" copy "$FAKE_DRIVE/duplicate-test" "$FAKE_HOME/Downloads/example" "$FAKE_HOME/Downloads/example"
[ ! -e "$FAKE_DRIVE/duplicate-test" ] || { printf '失敗: 二重指定の拒否時に写し先ができました\n' >&2; exit 1; }

mkdir -p "$FAKE_HOME/Downloads/folder"
printf '内容\n' > "$FAKE_HOME/Downloads/folder/a.txt"
printf '単体\n' > "$FAKE_HOME/Downloads/one.txt"
run_tool copy "$FAKE_DRIVE/accepted" "$FAKE_HOME/Downloads/example" > "$OUTPUT"
sleep 1
run_tool copy "$FAKE_DRIVE/copied" "$FAKE_HOME/Downloads/folder" "$FAKE_HOME/Downloads/one.txt" > "$OUTPUT"
[ -e "$FAKE_HOME/Downloads/folder/a.txt" ] && [ -e "$FAKE_HOME/Downloads/one.txt" ] || { printf '失敗: copy が元を消しました\n' >&2; exit 1; }
cmp -s "$FAKE_HOME/Downloads/folder/a.txt" "$FAKE_DRIVE/copied/folder/a.txt" || { printf '失敗: フォルダーの写しが違います\n' >&2; exit 1; }
cmp -s "$FAKE_HOME/Downloads/one.txt" "$FAKE_DRIVE/copied/one.txt" || { printf '失敗: ファイルの写しが違います\n' >&2; exit 1; }
record=$(find "$STATE_DIR" -type f -name 'offload-*.tsv' -print | sort | tail -1)
[ -n "$record" ] || { printf '失敗: 記録がありません\n' >&2; exit 1; }

status=0
run_tool status "$record" > "$OUTPUT" 2>&1 || status=$?
[ "$status" -eq 3 ] || { printf '失敗: File Provider でない写しの status が終了コード 3 ではありません: %s\n' "$status" >&2; exit 1; }

status=0
run_tool finish "$record" > "$OUTPUT" 2>&1 || status=$?
[ "$status" -ne 0 ] || { printf '失敗: File Provider でない写しで finish が通りました\n' >&2; exit 1; }
[ -e "$FAKE_HOME/Downloads/folder/a.txt" ] || { printf '失敗: 止まった finish が元を消しました\n' >&2; exit 1; }

sleep 1
: > "$FAKE_HOME/Downloads/folder/.DS_Store"
status=0
run_tool finish "$record" > "$OUTPUT" 2>&1 || status=$?
grep -Fq '変わっています' "$OUTPUT" && { printf '失敗: .DS_Store だけの変化を「変わった」と判定しました\n' >&2; exit 1; }
[ -e "$FAKE_HOME/Downloads/folder/a.txt" ] || { printf '失敗: 止まった finish が元を消しました\n' >&2; exit 1; }
rm -f -- "$FAKE_HOME/Downloads/folder/.DS_Store"

sleep 1
touch "$FAKE_HOME/Downloads/folder/a.txt"
expect_reject "$OUTPUT" finish "$record"
grep -Fq '変わっています' "$OUTPUT" || { printf '失敗: 変更後の案内がありません\n' >&2; exit 1; }

mkdir -p "$FAKE_HOME/Projects/repo/node_modules/pkg" "$FAKE_HOME/Downloads/large"
git -C "$FAKE_HOME/Projects/repo" init -q
printf '候補\n' > "$FAKE_HOME/Downloads/large/item.txt"
printf '除外\n' > "$FAKE_HOME/Projects/repo/node_modules/pkg/item.txt"
printf 'node_modules/\n' > "$FAKE_HOME/Projects/repo/.gitignore"
mkdir -p "$FAKE_HOME/Projects/repo/資料 OCR"
printf '日本語\n' > "$FAKE_HOME/Projects/repo/資料 OCR/page.txt"
before="$TEST_ROOT/before.txt"; after="$TEST_ROOT/after.txt"
find "$FAKE_HOME" -exec stat -f '%N %m' {} + 2>/dev/null | sort > "$before"
HOME="$FAKE_HOME" SC_DRIVE_ROOTS="$FAKE_DRIVE" SC_OFFLOAD_STATE_DIR="$STATE_DIR" SC_DEV_ROOTS="$FAKE_HOME/Projects" \
  bash "$TOOL" candidates --min-mb 0 > "$OUTPUT"
find "$FAKE_HOME" -exec stat -f '%N %m' {} + 2>/dev/null | sort > "$after"
cmp -s "$before" "$after" || { printf '失敗: candidates が偽 HOME を変えました\n' >&2; diff -u "$before" "$after" >&2 || true; exit 1; }
grep -Fq "$FAKE_HOME/Downloads/large" "$OUTPUT" || { printf '失敗: 利用者の候補が出ません\n' >&2; exit 1; }
grep -Fq "$FAKE_HOME/Projects/repo/資料 OCR" "$OUTPUT" || { printf '失敗: 日本語と空白を含む git 管理外の候補が出ません\n' >&2; exit 1; }
grep -Fq 'node_modules' "$OUTPUT" && { printf '失敗: node_modules が候補に出ました\n' >&2; exit 1; }

printf '成功: drive-offload.sh は偽 HOME と偽 Drive だけで安全条件を満たしました\n'
