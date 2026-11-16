# Claude Code に頼むときのプロンプト

## 導入するとき

次の枠の中を Claude Code に貼り付けてください。

```text
私の Mac に storage-cleanup-kit を入れるのを手伝ってください。
公開リポジトリ: https://github.com/5dmgmt/storage-cleanup-kit

進め方:
1. リポジトリを ~/Tools/storage-cleanup-kit に clone し、既にあればそのフォルダーで README.md を最後まで読んでください。
2. ./install.sh が ~/.claude/skills/storage-cleanup/ へ何を置くか、既存のスキルがある場合にどこへ退避するかを説明し、私の了解を取ってください。
3. 了解後に ./install.sh を実行してください。
4. 一度だけ bash ~/.claude/skills/storage-cleanup/bin/storage-check.sh を実行し、結果を専門用語を避けて説明してください。この段階では何も消さないでください。

守ってほしいこと:
- 私の了解なしにファイルを消したり、アプリを終了したりしないでください。
- sudo を使わないでください。
- シークレットや .env の値を表示しないでください。
```

## 使うとき

```text
ストレージを空けてください。消す前に一覧と量と戻し方を見せて、私の了解を取ってください。私のファイルは消さないでください。アプリを終了する必要がある場合も、先にまとめて確認してください。
```

## 新しい版へ更新するとき

```text
私の Mac に入っている storage-cleanup-kit を更新するのを手伝ってください。
clone した ~/Tools/storage-cleanup-kit で、私の変更がないことを確認してから git pull してください。変更があれば先に相談してください。CHANGELOG.md を読み、変更点を短く説明してください。./install.sh が既存版をバックアップして入れ替えることを説明し、私の了解後に実行してください。sudo を使わず、シークレットや .env の値を表示しないでください。
```
