#!/usr/bin/env bash
# 利用者のファイルを Google Drive へ安全に写し、確認後に手元を空けます。
set -uo pipefail

SCRIPT_DIR="$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="${SC_OFFLOAD_STATE_DIR:-$CLAUDE_DIR/storage-cleanup-kit-offload}"

fail() { printf '中止: %s\n' "$*" >&2; exit 1; }
usage() {
  printf '%s\n' \
    '使い方:' \
    '  drive-offload.sh roots' \
    '  drive-offload.sh candidates [--min-mb N]' \
    '  drive-offload.sh copy <写し先フォルダー> <元>...' \
    '  drive-offload.sh status <記録ファイル>' \
    '  drive-offload.sh finish <記録ファイル>'
}

drive_roots() {
  if [ -n "${SC_DRIVE_ROOTS:-}" ]; then
    old_ifs=$IFS; IFS=:
    for root in $SC_DRIVE_ROOTS; do
      [ -d "$root" ] && (unset CDPATH; cd -- "$root" 2>/dev/null && pwd -P)
    done
    IFS=$old_ifs
    return
  fi
  for base in "$HOME"/Library/CloudStorage/GoogleDrive-*; do
    [ -d "$base" ] || continue
    for name in 'My Drive' 'マイドライブ' 'Shared drives' '共有ドライブ'; do
      [ -d "$base/$name" ] && printf '%s\n' "$base/$name"
    done
  done
}

canonical_existing() {
  if [ -d "$1" ]; then (unset CDPATH; cd -- "$1" 2>/dev/null && pwd -P); return; fi
  parent=$(dirname -- "$1") || return 1
  name=$(basename -- "$1") || return 1
  parent_abs=$(unset CDPATH; cd -- "$parent" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$parent_abs" "$name"
}

is_within() {
  child=$1; parent=${2%/}
  [ "$child" = "$parent" ] || case "$child" in "$parent"/*) return 0;; *) return 1;; esac
}

file_stats() {
  target=$1
  if [ -f "$target" ]; then
    [ "$(basename -- "$target")" = '.DS_Store' ] && { printf '0\t0\n'; return; }
    printf '1\t%s\n' "$(stat -f '%z' "$target" 2>/dev/null)"
    return
  fi
  find "$target" -type f ! -name '.DS_Store' -exec stat -f '%z' {} + 2>/dev/null |
    awk '{count += 1; bytes += $1} END {printf "%d\t%d\n", count, bytes}'
}

secret_paths() {
  target=$1
  if [ -f "$target" ]; then
    base=$(basename -- "$target")
    case "$base" in
      .env.example|.env.sample|.env.tpl|.env.template) return;;
      .env|.env.*|*.pem|*.p12|*.pfx|*.key|id_rsa*|id_ecdsa*|id_ed25519*|*.keychain|*.keychain-db) printf '%s\n' "$target";;
    esac
    return
  fi
  find "$target" \( -type d \( -name .ssh -o -name .gnupg \) -prune -print \) -o \
    \( -type f \( -name .env -o -name '.env.*' -o -name '*.pem' -o -name '*.p12' -o -name '*.pfx' -o -name '*.key' -o -name 'id_rsa*' -o -name 'id_ecdsa*' -o -name 'id_ed25519*' -o -name '*.keychain' -o -name '*.keychain-db' \) \
    ! -name .env.example ! -name .env.sample ! -name .env.tpl ! -name .env.template -print \) 2>/dev/null
}

source_reason() {
  source=$1
  [ -e "$source" ] || { printf '存在しません'; return; }
  [ ! -L "$source" ] || { printf 'シンボリックリンクです'; return; }
  source_abs=$(canonical_existing "$source") || { printf '絶対パスを確認できません'; return; }
  home_abs=$(canonical_existing "$HOME") || { printf 'HOME を確認できません'; return; }
  is_within "$source_abs" "$home_abs" || { printf 'HOME の外です'; return; }
  [ "$source_abs" != "$home_abs" ] || { printf 'HOME そのものです'; return; }
  is_within "$source_abs" "$home_abs/Library" && { printf 'HOME/Library の中です'; return; }
  is_within "$source_abs" "$home_abs/.Trash" && { printf 'ゴミ箱の中です'; return; }
  claude_abs=$(canonical_existing "$CLAUDE_DIR" 2>/dev/null || printf '%s\n' "$CLAUDE_DIR")
  is_within "$source_abs" "$claude_abs" && { printf 'Claude の設定フォルダーの中です'; return; }
  while IFS= read -r root; do is_within "$source_abs" "$root" && { printf 'Drive の中です'; return; }; done <<EOF
$(drive_roots)
EOF
  if [ -d "$source_abs" ] && [ -n "$(find "$source_abs" -name .git -print -quit 2>/dev/null)" ]; then
    printf 'コードは git で管理してください'; return
  fi
  secrets=$(secret_paths "$source_abs")
  [ -z "$secrets" ] || { printf '秘密らしいファイルを含みます: %s' "$secrets"; return; }
}

show_roots() {
  roots=$(drive_roots)
  [ -n "$roots" ] || fail 'Google Drive（パソコン版）が見つかりません。入れると、ここに移せます'
  printf '%s\n' "$roots"
}

candidate_line() {
  path=$1; min_bytes=$2; kind=$3
  if [ -d "$path" ]; then object_type='フォルダー'; else object_type='ファイル'; fi
  stats=$(file_stats "$path") || return
  bytes=$(printf '%s\n' "$stats" | awk -F '\t' '{print $2}')
  [ "$bytes" -ge "$min_bytes" ] || return
  reason=$(source_reason "$path")
  if [ -z "$reason" ] && [ -d "$path" ]; then
    package=$(find "$path" -type d \( -name '*.photoslibrary' -o -name '*.musiclibrary' -o -name '*.tvlibrary' -o -name '*.fcpbundle' -o -name '*.app' -o -name '*.imovielibrary' -o -name '*.logicx' \) -print -quit 2>/dev/null)
    [ -z "$package" ] || reason='パッケージ形式はアプリの機能で移してください'
  fi
  if [ -n "$reason" ]; then printf '%s\t%s・%s\t%s\t移せません: %s\n' "$bytes" "$kind" "$object_type" "$path" "$reason"
  else printf '%s\t%s・%s\t%s\t移せます\n' "$bytes" "$kind" "$object_type" "$path"; fi
}

show_candidates() {
  min_mb=500
  if [ "${1:-}" = '--min-mb' ]; then min_mb=${2:-}; shift 2 || true; fi
  [ "$#" -eq 0 ] || fail 'candidates の引数が正しくありません'
  case "$min_mb" in ''|*[!0-9]*) fail '--min-mb は 0 以上の整数で指定してください';; esac
  temp=$(mktemp "${TMPDIR:-/tmp}/storage-cleanup-candidates.XXXXXX") || fail '一時ファイルを作れません'
  trap 'rm -f -- "$temp"' EXIT HUP INT TERM
  min_bytes=$((min_mb * 1024 * 1024))
  for parent in "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents" "$HOME/Movies" "$HOME/Music" "$HOME/Pictures"; do
    [ -d "$parent" ] || continue
    find "$parent" -mindepth 1 -maxdepth 1 -print 2>/dev/null | while IFS= read -r path; do candidate_line "$path" "$min_bytes" 'あなたのファイル'; done >> "$temp"
  done
  dev_roots=${SC_DEV_ROOTS:-}
  if [ -z "$dev_roots" ]; then
    for root in "$HOME/Projects" "$HOME/projects" "$HOME/Developer" "$HOME/dev" "$HOME/src" "$HOME/code" "$HOME/Plugins" "$HOME/Tools" "$HOME/GitHub"; do [ -d "$root" ] && dev_roots="$dev_roots $root"; done
  fi
  # SC_DEV_ROOTS は storage-check.sh と同じく空白区切りです。
  # shellcheck disable=SC2086
  for root in $dev_roots; do
    [ -d "$root" ] || continue
    find "$root" -maxdepth 3 -type d -name .git -print 2>/dev/null | while IFS= read -r dotgit; do
      repo=$(dirname -- "$dotgit")
      # -z で日本語や空白を含むパスも引用符なしで受け取る
      git -C "$repo" status --porcelain=v1 -z --ignored --untracked-files=normal 2>/dev/null < /dev/null |
        while IFS= read -r -d '' entry; do
          case "$entry" in '!! '*|'?? '*) rel=${entry#???};; *) continue;; esac
          rel=${rel%/}
          case "/$rel/" in */node_modules/*|*/.next/*|*/.venv/*|*/venv/*|*/__pycache__/*|*/dist/*|*/build/*|*/.turbo/*|*/.cache/*|*/target/*|*/.parcel-cache/*|*/coverage/*) continue;; esac
          [ -e "$repo/$rel" ] && candidate_line "$repo/$rel" "$min_bytes" 'git 管理外'
        done
    done >> "$temp"
  done
  sort -t "$(printf '\t')" -k1,1nr "$temp" | awk -F '\t' '{printf "%.1f MB\t%s\t%s\t%s\n", $1/1048576, $2, $3, $4}'
  printf '移すかどうかは、あなたが決めます。ここでは何も変えていません\n'
}

validate_destination() {
  destination=$1
  case "/$destination/" in */../*|*/./*) return 1;; esac
  probe=$destination
  while [ ! -e "$probe" ]; do next=$(dirname -- "$probe"); [ "$next" != "$probe" ] || return 1; probe=$next; done
  [ -d "$probe" ] || return 1
  probe_abs=$(canonical_existing "$probe") || return 1
  suffix=${destination#"$probe"}; destination_abs="${probe_abs}${suffix}"
  while IFS= read -r root; do is_within "$destination_abs" "$root" && { printf '%s\n' "$destination_abs"; return 0; }; done <<EOF
$(drive_roots)
EOF
  return 1
}

copy_items() {
  [ "$#" -ge 2 ] || { usage >&2; exit 1; }
  destination=$1; shift
  case "$destination" in *"
"*|*"	"*) fail '写し先のパスに改行またはタブは使えません';; esac
  destination_abs=$(validate_destination "$destination") || fail '写し先は見つかった Drive の中にしてください'
  errors=''; seen=''
  for source in "$@"; do
    case "$source" in *"
"*|*"	"*) errors="$errors
$source: パスに改行またはタブは使えません"; continue;; esac
    reason=$(source_reason "$source")
    source_abs=$(canonical_existing "$source" 2>/dev/null || printf '%s\n' "$source")
    if printf '%s\n' "$seen" | grep -Fqx -- "$source_abs"; then reason='同じ元が二重に指定されています'; fi
    seen="$seen
$source_abs"
    [ -z "$reason" ] || errors="$errors
$source: $reason"
    name=$(basename -- "$source")
    [ ! -e "$destination_abs/$name" ] || errors="$errors
$source: 写し先に同じ名前があります"
  done
  [ -z "$errors" ] || fail "次の元は写せません:${errors}"
  mkdir -p "$destination_abs" || fail '写し先を作れません'
  rows=''
  for source in "$@"; do
    source_abs=$(canonical_existing "$source") || fail '元を確認できません'
    copy_path="$destination_abs/$(basename -- "$source_abs")"
    source_device=$(stat -f '%d' "$source_abs") || fail '元のボリュームを確認できません'
    destination_device=$(stat -f '%d' "$destination_abs") || fail '写し先のボリュームを確認できません'
    if [ "$source_device" = "$destination_device" ]; then cp -Rc "$source_abs" "$destination_abs/" || fail "コピーに失敗しました。作りかけは消していません: $copy_path"
    else cp -R "$source_abs" "$destination_abs/" || fail "コピーに失敗しました。作りかけは消していません: $copy_path"; fi
    source_stats=$(file_stats "$source_abs"); copy_stats=$(file_stats "$copy_path")
    [ "$source_stats" = "$copy_stats" ] || fail "件数または量が一致しません。写しは消していません: $copy_path"
    rows="$rows
$source_abs	$copy_path	$source_stats"
  done
  mkdir -p "$STATE_DIR" || fail '記録の置き場を作れません'
  record="$STATE_DIR/offload-$(date '+%Y%m%d-%H%M%S').tsv"
  [ ! -e "$record" ] || fail "記録ファイルが既にあります: $record"
  { printf '# storage-cleanup-kit offload\n'; printf '# created\t%s\n' "$(date '+%s')"; printf '%s\n' "${rows#
}"; } > "$record" || fail '記録を作れません'
  printf '写しました。元はそのまま残っています。記録: %s\n' "$record"
  printf '上がるまで待ってから drive-offload.sh status %s。全部上がったら drive-offload.sh finish %s を、あなたがターミナル（Claude Code なら先頭に !）で実行します\n' "$record" "$record"
}

check_record() {
  record=$1
  [ -f "$record" ] || fail '記録ファイルがありません'
  [ "$(sed -n '1p' "$record")" = '# storage-cleanup-kit offload' ] || fail '記録の先頭行が正しくありません'
  awk -F '\t' 'NR == 2 && NF == 2 && $1 == "# created" && $2 ~ /^[0-9]+$/ {ok=1} END {exit !ok}' "$record" || fail '記録の作成行が正しくありません'
  awk -F '\t' 'NR > 2 && substr($0,1,1)!="#" && NF != 4 {exit 1} END {if (NR < 3) exit 1}' "$record" || fail '記録の明細が正しくありません'
}

run_cloud() {
  command -v swift >/dev/null 2>&1 || fail 'swift がないため、上がり済みか確かめられないので止めます'
  # 記録を読むループの中で呼ぶため、標準入力を渡さない
  swift "$SCRIPT_DIR/cloud-status.swift" "$@" < /dev/null
}

status_record() {
  [ "$#" -eq 1 ] || { usage >&2; exit 1; }
  record=$1; check_record "$record"
  overall=0
  while IFS="$(printf '\t')" read -r source copy count bytes; do
    case "$source" in \#*|'') continue;; esac
    status=0; run_cloud "$copy" || status=$?
    case "$status" in 0) :;; 1) overall=1;; 2) [ "$overall" -eq 0 ] && overall=2;; 3) [ "$overall" -eq 0 ] && overall=3;; *) overall=1;; esac
  done < "$record"
  [ "$overall" -ne 0 ] || printf '全部上がりました。finish を実行できます\n'
  return "$overall"
}

finish_record() {
  [ "$#" -eq 1 ] || { usage >&2; exit 1; }
  record=$1; check_record "$record"
  awk -F '\t' 'NF == 2 && $1 == "# finished" && $2 ~ /^[0-9]+$/ {found=1} END {exit !found}' "$record" && { printf '済んでいます\n'; return 0; }
  active=0; errors=''
  # 記録への追記は全処理が終わった後だけです。
  # shellcheck disable=SC2094
  while IFS="$(printf '\t')" read -r source copy count bytes; do
    case "$source" in \#*|'') continue;; esac
    [ -e "$copy" ] || errors="$errors
$copy: 写しがありません"
    if [ ! -e "$source" ]; then printf 'もう消えています: %s\n' "$source"; continue; fi
    active=$((active + 1))
    # フォルダーの日時は Finder が .DS_Store を書くだけでも変わるため、ファイルだけを見る（増減は件数で見る）
    changed=$(find "$source" -newer "$record" -type f ! -name .DS_Store -print -quit 2>/dev/null)
    [ -z "$changed" ] || errors="$errors
$source: 写したあとに元が変わっています。copy からやり直してください"
    current=$(file_stats "$source"); copied=$(file_stats "$copy" 2>/dev/null || printf '不明')
    [ "$current" = "$count	$bytes" ] || errors="$errors
$source: 元の件数または量が記録と違います"
    [ "$copied" = "$count	$bytes" ] || errors="$errors
$copy: 写しの件数または量が記録と違います"
    reason=$(source_reason "$source"); [ -z "$reason" ] || errors="$errors
$source: $reason"
  done < "$record"
  [ -z "$errors" ] || fail "安全確認に通りません:${errors}"
  [ "$active" -gt 0 ] || { printf '元はすべてもう消えています\n'; return 0; }
  cloud_status=0
  while IFS="$(printf '\t')" read -r source copy count bytes; do case "$source" in \#*|'') continue;; esac; run_cloud "$copy" || cloud_status=1; done < "$record"
  [ "$cloud_status" -eq 0 ] || fail '全部が上がり済みと確かめられないので、何も消していません'
  before_kb=$(df -k "$HOME" 2>/dev/null | tail -1 | awk '{print $4}')
  while IFS="$(printf '\t')" read -r source copy count bytes; do
    case "$source" in \#*|'') continue;; esac
    [ -e "$source" ] || continue
    reason=$(source_reason "$source"); [ -z "$reason" ] || fail "$source: $reason"
    parent=$(dirname -- "$source"); name=$(basename -- "$source")
    rm -rf -- "$source" || fail "元を消せません: $source"
    marker="$parent/退避先.md"
    [ -e "$marker" ] || printf '# 退避先\n' > "$marker"
    printf -- '- %s → %s（%s・storage-cleanup-kit）\n' "$name" "$copy" "$(date '+%Y-%m-%d')" >> "$marker"
  done < "$record"
  while IFS="$(printf '\t')" read -r source copy count bytes; do case "$source" in \#*|'') continue;; esac; run_cloud --evict "$copy" || printf '手元の中身を外せませんでした: %s\n' "$copy" >&2; done < "$record"
  after_kb=$(df -k "$HOME" 2>/dev/null | tail -1 | awk '{print $4}')
  awk -v before="$before_kb" -v after="$after_kb" 'BEGIN {printf "消す前 %.1f GB → 終了 %.1f GB（%+.1f GB）\n", before/1048576, after/1048576, (after-before)/1048576}'
  printf '# finished\t%s\n' "$(date '+%s')" >> "$record"
  printf '元は Drive に残っています。開くとその場でダウンロードされます\n'
}

command=${1:-}; [ "$#" -gt 0 ] && shift
case "$command" in
  roots) [ "$#" -eq 0 ] || fail 'roots に引数はありません'; show_roots;;
  candidates) show_candidates "$@";;
  copy) copy_items "$@";;
  status) status_record "$@";;
  finish) finish_record "$@";;
  *) usage >&2; exit 1;;
esac
