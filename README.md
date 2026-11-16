# storage-cleanup-kit

Mac のストレージを安全に整理するための Claude Code スキルです。最初に容量を計測し、「再生成されるもの」「索引・状態」「あなたのデータ」に分け、消してよい候補と戻し方を示します。利用者の了解を得るまでは何も消しません。

利用状況を外部へ送る機能はありません。計測スクリプトは読み取り専用です。

## 何をする道具か

- ディスク、開発用キャッシュ、ビルド成果物、ログ、ホーム内外の大きな場所を計測します。
- Chrome、Drive、Claude Desktop で、消してよいものと残すべきものを分けます。
- 利用者のファイルをクラウドへ移す場合は、アップロード済みかを一件ずつ確認します。
- Google Drive へ写し、上がり済みを確認してから元と手元の複製を安全に外します。
- 削除候補、量、戻し方を示し、了解を得てから整理します。

次のことは行いません。

- 利用者のファイルを了解なしに消しません。
- DriveFS の索引、Chrome の Cookies・Login Data・Bookmarks を消しません。
- アプリを了解なしに終了しません。
- `sudo` を使いません。
- ゴミ箱を空にしません。

## 入れ方

Claude Code に任せる場合は、[PROMPT.md](PROMPT.md) の「導入するとき」の文面をそのまま貼り付けてください。導入前の説明、インストール、読み取り専用の初回計測までを一緒に進めます。

自分で入れる場合は、macOS のターミナルで次を実行します。

```bash
git clone https://github.com/5dmgmt/storage-cleanup-kit.git ~/Tools/storage-cleanup-kit
cd ~/Tools/storage-cleanup-kit
./install.sh
```

既に `~/.claude/skills/storage-cleanup/`（`CLAUDE_CONFIG_DIR` を設定している場合はその中）がある場合は、同じ設定フォルダーの `storage-cleanup-kit-backups/` に日時を付けて退避してから入れます。

## 使い方

Claude Code を開き直し、「ストレージが足りない」「容量なんとかして」「ディスクが一杯」または `/storage-cleanup` と伝えてください。

最初の計測だけを手で行う場合は、次を実行します。このスクリプトは何も変更しません。

```bash
bash ~/.claude/skills/storage-cleanup/bin/storage-check.sh
```

クラウド上のフォルダーを確認する場合は、次のように実行します。既定では状態を表示するだけです。

```bash
swift ~/.claude/skills/storage-cleanup/bin/cloud-status.swift "$HOME/Library/CloudStorage/<フォルダー>"
```

`--evict` は、アップロード済みでローカルに内容があるファイルだけ、Finder の「ダウンロードを削除」と同じ方法でローカルから外します。実行前に対象を確認してください。

Drive へ移す道具（`~/.claude/skills/storage-cleanup/bin/drive-offload.sh`）には、次の五つのコマンドがあります。

```bash
drive-offload.sh roots
drive-offload.sh candidates [--min-mb N]
drive-offload.sh copy <写し先フォルダー> <元>...
drive-offload.sh status <記録ファイル>
drive-offload.sh finish <記録ファイル>
```

順に、Drive の確認、候補表示、写すだけのコピー、上がり済み確認、確認済みの元とローカル内容を外す処理です。`finish` は利用者自身が実行します。

## 消さないもの

- Google Drive の `DriveFS`（ファイル一覧を管理する索引）
- Chrome の Cookies、Login Data、Bookmarks、拡張機能の設定
- Downloads、Desktop、Documents、Movies などの利用者が作成・取得したファイル
- 使用中の開発環境、launchd・cron が使う依存、作業中のリポジトリや worktree の生成物
- アップロード済みと確認できないクラウド上のファイル
- 上がり済みと確かめられない元

## 動作環境

- macOS 14 以降を想定
- macOS 標準の Bash 3.2
- `cloud-status.swift` を使う場合のみ Swift が必要です。Command Line Tools がない場合は `xcode-select --install` で追加できます。

## アンインストール

clone したフォルダーで次を実行します。

```bash
./uninstall.sh
```

このキットが入れた `~/.claude/skills/storage-cleanup/` だけを確認して外します。導入時に作成したバックアップは残します。

## License

MIT License です。詳細は [LICENSE](LICENSE) をご覧ください。
