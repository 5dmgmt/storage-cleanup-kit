#!/usr/bin/env bash
# Mac のストレージ使用量を計測します。ファイルは変更しません。
set -uo pipefail

H="$HOME"
AS="$H/Library/Application Support"
CA="$H/Library/Caches"

line() { printf '%s\n' '────────────────────────────────────────────────────────────────'; }
size_of() { du -sh "$1" 2>/dev/null | awk 'NR == 1 {print $1}'; }
row() {
  if [ -e "$2" ]; then
    printf '  %-42s %8s   %s\n' "$1" "$(size_of "$2")" "$3"
  fi
}
sum_find_kb() {
  find "$1" -maxdepth "$2" -type d -name "$3" -prune -exec du -sk {} + 2>/dev/null |
    awk '{total += $1} END {printf "%.1fG", total / 1024 / 1024}'
}
top_find_dirs() {
  find "$1" -maxdepth "$2" -type d -name "$3" -prune -exec du -sk {} + 2>/dev/null |
    sort -rn | head -5 | awk '{kb=$1; $1=""; sub(/^ /, ""); printf "    %.1fG  %s\n", kb/1024/1024, $0}'
}

printf '読み取り専用の計測です。何も削除しません。数分かかることがあります。\n\n'

line
printf '■ ディスク\n'
line
DISK_PATH="/System/Volumes/Data"
[ -e "$DISK_PATH" ] || DISK_PATH="/"
df -k "$DISK_PATH" 2>/dev/null | tail -1 | awk '{printf "  空き %.1fGB / 使用 %.1fGB / 使用率 %s\n", $4/1024/1024, $3/1024/1024, $5}'
printf '\n'

line
printf '■ 再生成されるもの（消す候補。作ったデータではありません）\n'
line
row 'Homebrew キャッシュ' "$CA/Homebrew" 'brew cleanup --prune=all 後、必要時に再取得'
row 'npm キャッシュ' "$H/.npm" 'npm が必要時に再取得'
row 'pnpm キャッシュ' "$H/Library/pnpm/store" 'pnpm が必要時に再取得'
row 'pnpm キャッシュ' "$CA/pnpm" 'pnpm が必要時に再取得'
row 'yarn キャッシュ' "$H/Library/Caches/Yarn" 'yarn が必要時に再取得'
row 'bun キャッシュ' "$H/.bun/install/cache" 'bun が必要時に再取得'
row 'pip キャッシュ' "$CA/pip" 'pip が必要時に再取得'
row 'Playwright ブラウザ' "$CA/ms-playwright" 'npx playwright install'
row 'Playwright ブラウザ (go)' "$CA/ms-playwright-go" '利用する道具が再取得'
row 'node-gyp キャッシュ' "$CA/node-gyp" 'node-gyp が再生成'
row 'Chrome の HTTP キャッシュ' "$CA/Google/Chrome" 'Chrome 終了後。自動で再取得'
row 'Chrome-headless の HTTP キャッシュ' "$CA/Google/Chrome-headless" '終了後。自動で再取得'

SW_KB="$(find "$AS/Google/Chrome" -mindepth 3 -maxdepth 3 -type d -path '*/Service Worker/CacheStorage' -prune -exec du -sk {} + 2>/dev/null | awk '{s += $1} END {print s+0}')"
printf '  %-42s %7.1fG   %s\n' 'Chrome の Service Worker（全プロファイル）' "$(awk -v kb="$SW_KB" 'BEGIN {print kb/1024/1024}')" 'サイトが再取得'
find "$AS/Google/Chrome" -mindepth 3 -maxdepth 3 -type d -path '*/Service Worker/CacheStorage' -prune 2>/dev/null | sed 's/^/    /'

row 'Spotlight の個人索引' "$H/Library/Metadata/CoreSpotlight" '自動再構築。数時間は検索が遅くなる場合あり'
row 'Claude Desktop の VM' "$AS/Claude/vm_bundles" 'アプリ終了後。次回利用時に再取得'
row 'Claude Desktop の Cache' "$AS/Claude/Cache" 'アプリ終了後。自動で再取得'
row 'Xcode DerivedData' "$H/Library/Developer/Xcode/DerivedData" '次回ビルドで再生成'
row 'Xcode iOS DeviceSupport' "$H/Library/Developer/Xcode/iOS DeviceSupport" '必要時に再取得'

if [ -n "${SC_DEV_ROOTS:-}" ]; then
  DEV_ROOTS="$SC_DEV_ROOTS"
else
  DEV_ROOTS=""
  for candidate in "$H/Projects" "$H/projects" "$H/Developer" "$H/dev" "$H/src" "$H/code" "$H/Plugins" "$H/Tools" "$H/GitHub"; do
    [ -d "$candidate" ] && DEV_ROOTS="$DEV_ROOTS $candidate"
  done
fi
# SC_DEV_ROOTS は仕様上、空白区切りのパス一覧です。
# shellcheck disable=SC2086
for root in $DEV_ROOTS; do
  [ -d "$root" ] || continue
  printf '  %-42s %8s   %s\n' "node_modules 合計: ${root}" "$(sum_find_kb "$root" 3 node_modules)" 'パッケージマネージャーで再導入'
  top_find_dirs "$root" 3 node_modules
  printf '  %-42s %8s   %s\n' ".next 合計: ${root}" "$(sum_find_kb "$root" 3 .next)" '次回ビルドで再生成'
  top_find_dirs "$root" 3 .next
done
printf '\n'

line
printf '■ Chrome の自分の複製\n'
line
CLONE_COUNT=0
CLONE_OLDEST='—'
CLONE_NEWEST='—'
if [ "${SC_SKIP_SYSTEM_SCAN:-0}" != "1" ]; then
  # /private/var/folders/<2文字>/<ID>/X/com.google.Chrome.code_sign_clone/code_sign_clone.* ＝ 深さ 5
  CLONE_DATES="$(find /private/var/folders -mindepth 5 -maxdepth 5 -type d -path '*/X/com.google.Chrome.code_sign_clone/*' -exec stat -f '%B' {} + 2>/dev/null | sort -n)"
  if [ -n "$CLONE_DATES" ]; then
    CLONE_COUNT="$(printf '%s\n' "$CLONE_DATES" | wc -l | tr -d ' ')"
    CLONE_OLDEST="$(date -r "$(printf '%s\n' "$CLONE_DATES" | head -1)" '+%Y-%m-%d %H:%M' 2>/dev/null || printf '不明')"
    CLONE_NEWEST="$(date -r "$(printf '%s\n' "$CLONE_DATES" | tail -1)" '+%Y-%m-%d %H:%M' 2>/dev/null || printf '不明')"
  fi
fi
printf '  個数 %s / 最古 %s / 最新 %s\n' "$CLONE_COUNT" "$CLONE_OLDEST" "$CLONE_NEWEST"
printf '  見かけの量は当てになりません（APFS の複製で中身を共有）。Chrome を終了してから消してよい候補です。\n\n'

line
printf '■ ログの暴走\n'
line
if [ -d "$H/Library/Logs" ]; then
  du -sk "$H/Library/Logs"/* 2>/dev/null | sort -rn | head -5 | awk '{kb=$1; $1=""; sub(/^ /, ""); printf "  %.1fM  %s\n", kb/1024, $0}'
  for log_dir in "$H/Library/Logs"/*; do
    [ -d "$log_dir" ] || continue
    log_count="$(find "$log_dir" -maxdepth 1 -type f -print 2>/dev/null | head -10001 | wc -l | tr -d ' ')"
    [ "$log_count" -le 10000 ] || printf '  暴走の疑い: %s（1万件超）\n' "$log_dir"
  done
fi
printf '\n'

line
printf '■ 消してはいけないもの（索引・状態）\n'
line
row 'DriveFS（索引）' "$AS/Google/DriveFS" 'キャッシュではありません。消しません'
DRIVE_WAL_KB="$(find "$AS/Google/DriveFS" -maxdepth 3 -type f -name '*-wal' -exec du -sk {} + 2>/dev/null | awk '{s += $1} END {print s+0}')"
printf '  %-42s %7.1fM   %s\n' 'DriveFS の -wal' "$(awk -v kb="$DRIVE_WAL_KB" 'BEGIN {print kb/1024}')" 'Drive 終了で縮むことがあります。直接消しません'
row 'Chrome Cookies' "$AS/Google/Chrome/Default/Cookies" 'ログイン状態。消しません'
row 'Chrome Login Data' "$AS/Google/Chrome/Default/Login Data" '保存したログイン情報。消しません'
row 'Chrome Bookmarks' "$AS/Google/Chrome/Default/Bookmarks" 'ブックマーク。消しません'
printf '\n'

line
printf '■ あなたのデータ（中身を見てから決める）\n'
line
row 'Downloads' "$H/Downloads" '消しません'
row 'Desktop' "$H/Desktop" '消しません'
row 'Movies' "$H/Movies" '消しません'
row 'Documents' "$H/Documents" '消しません'
printf '  500MB を超えるファイル（上位10）\n'
find "$H" -xdev \( -path "$H/Library" -o -path "$H/.Trash" -o -path "$H/Library/CloudStorage" -o -path "$H/Library/Mobile Documents" \) -prune -o -type f -size +500M -exec du -k {} + 2>/dev/null |
  sort -rn | head -10 | awk '{kb=$1; $1=""; sub(/^ /, ""); printf "    %.1fG  %s\n", kb/1024/1024, $0}'
if trash_size="$(size_of "$H/.Trash")" && [ -n "$trash_size" ]; then
  printf '  %-42s %8s   %s\n' 'ゴミ箱' "$trash_size" '利用者自身が捨てた物を含むため空にしません'
else
  printf '  ゴミ箱                                   読めません\n'
fi
printf '\n'

line
printf '■ ホーム直下（上位10）\n'
line
du -sh "$H"/* "$H"/.[!.]* 2>/dev/null | sort -hr | head -10 | sed 's/^/  /'
printf '\n'

line
printf '■ ホームの外\n'
line
if [ "${SC_SKIP_SYSTEM_SCAN:-0}" = "1" ]; then
  printf '  テスト設定により省略しました\n'
else
  for path in /Applications /Library /opt/homebrew /private/var/folders /private/tmp; do
    note=''
    [ "$path" = /private/var/folders ] && note='見かけの量（Chrome の複製を重ねて数えます）'
    [ -e "$path" ] && printf '  %-42s %8s   %s\n' "$path" "$(size_of "$path")" "$note"
  done
fi
printf '\n'

line
printf '■ 起動中で終了が要るアプリ\n'
line
if pgrep -x Claude >/dev/null 2>&1; then printf '  Claude Desktop       起動中\n'; else printf '  Claude Desktop       終了\n'; fi
# pgrep では「ヘッドレスを除く」ができないため ps を絞り込む
# shellcheck disable=SC2009
if ps ax -o command= 2>/dev/null | grep -E '^/Applications/Google Chrome\.app/Contents/MacOS/Google Chrome( |$)' | grep -v -- '--headless' >/dev/null 2>&1; then printf '  Google Chrome        起動中（ヘッドレスを除く）\n'; else printf '  Google Chrome        終了\n'; fi
if pgrep -x 'Google Drive' >/dev/null 2>&1; then printf '  Google Drive         起動中\n'; else printf '  Google Drive         終了\n'; fi
