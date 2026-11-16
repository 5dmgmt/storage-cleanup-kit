---
name: storage-cleanup
description: Mac のディスク空き容量を安全に回復する。TRIGGER when 利用者が「ストレージが足りない」「容量なんとかして」「ディスクが一杯」「/storage-cleanup」と言ったとき。
user_invocable: true
---

# ストレージ整理

詳しい判断基準と罠は、必要なときに同じフォルダーの `reference.md` を読んでください。

## 1. 最初に計測する

```bash
bash ~/.claude/skills/storage-cleanup/bin/storage-check.sh
```

`CLAUDE_CONFIG_DIR` を設定している場合は、その中の `skills/storage-cleanup` を使います。

開始時の空きを控えます。計測スクリプトは読み取り専用です。

## 2. 三分類する

- 再生成されるもの: キャッシュ、ビルド成果物、node_modules、Spotlight 索引、VM です。消す候補にできます。
- 索引・状態: DriveFS、Chrome の Cookie やログイン情報です。消しません。
- あなたのデータ: Downloads、Desktop、Documents などです。消しません。

「キャッシュ」という名前を信用せず、中身と戻し方を確認します。

## 3. 終了が必要なアプリをまとめて確認する

Chrome、Claude Desktop、Google Drive など、終了が必要なアプリを一覧にして一度に利用者へ確認します。了解を得た後だけ、たとえば `osascript -e 'tell application "Google Chrome" to quit'` を実行します。

## 4. 消す前に確認する

消す物の一覧、量、戻し方を示し、利用者の了解を得ます。次も確認します。

- `lsof +D <対象>` で使用中でないかを確認します。
- `grep -l <フォルダー> ~/Library/LaunchAgents/*.plist` と `crontab -l` で launchd・cron が使う node_modules ではないかを確認します。
- 未コミットの変更があるリポジトリや worktree の生成物は、別の作業中かもしれないため確認します。

Claude Code の自動モードが `rm -rf` や `~/Library` 配下の削除を止めた場合、回り道はしません。対象を名指ししたスクリプトを書き、利用者自身に `! bash <スクリプト>` で実行してもらいます。ゴミ箱は、利用者自身が捨てた物まで空にするため使いません。

## 5. あなたのデータは Drive へ移す

道具は `bash ~/.claude/skills/storage-cleanup/bin/drive-offload.sh <コマンド>` で呼びます（以下は `drive-offload.sh` と略します）。

1. `drive-offload.sh roots` で Drive を確かめます。無ければ手元で空けられる分だけで止め、入れるかを利用者に聞きます。
2. `drive-offload.sh candidates` の結果を、量・中身の見当・移す先の案の表にし、選ばれた物だけを扱います。
3. Drive 内の移す先を利用者と決めます。例は `Mac から移した物_YYYY-MM-DD` です。
4. `drive-offload.sh copy <写し先> <元>...` で写します。この段階では消しません。
5. 上がるまで待ち、`status` で確かめます。大きい場合は利用者に知らせ、待つ間に別の作業をしてかまいません。
6. 全部上がったら `finish` の一行を渡し、利用者がターミナル（Claude Code なら先頭に `!`）で実行します。Claude は `finish` を実行しません。渡す一行の例: `! bash ~/.claude/skills/storage-cleanup/bin/drive-offload.sh finish <記録ファイル>`。`finish` は実行の時点でもう一度全部を確かめ、一件でも外れれば何も消さずに止まります。
7. 結果の空きを報告し、「元は Drive に残っています」と添えます。

## 6. 報告する

前後の空きと差分、内訳、戻し方を報告します。例として node_modules は `npm install`、Playwright は `npx playwright install`、Spotlight は自動再構築されますが数時間は検索が遅くなることがあります。

必ず「作ったデータは1つも消えていません」と報告します。これが言えない削除はしません。

## やらないこと

- DriveFS を消しません。
- Chrome の Cookies・Login Data を消しません。
- 利用者のファイルを了解なしに消しません。
- アプリを了解なしに終了しません。
- `sudo` を使いません。
