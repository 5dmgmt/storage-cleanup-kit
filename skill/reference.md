# ストレージ整理の判断基準

## 三分類

「再生成されるもの」だけを削除候補にします。索引・状態は再構築やログアウトを招くため残し、利用者のデータはクラウドへの退避を含めて本人に確認します。「Cache」という名前だけでは決めず、実体を確認してください。

## 主な再生成物と戻し方

| 対象 | 戻し方・影響 |
|---|---|
| Homebrew・npm・pnpm・yarn・bun・pip のキャッシュ | 次回利用時に再取得 |
| node_modules | パッケージマネージャーで再インストール |
| `.next` | 次回のビルド |
| Playwright | `npx playwright install` |
| Spotlight の個人索引 | 自動再構築。しばらく検索が遅くなることがあります |
| Claude Desktop の VM | 次回利用時に再取得 |
| Xcode DerivedData | 次回ビルド |

休眠中かどうかは最終コミット日だけでは決められません。横断作業で更新されるため、いま動かしている案件かで判断します。未コミットの変更があるリポジトリや worktree は、別の作業中として扱います。

## Chrome のプロファイルとキャッシュ

Chrome はプロファイルと HTTP キャッシュが別の場所です。

```text
~/Library/Caches/Google/Chrome
    HTTP キャッシュ。Chrome 終了後に再生成できます

~/Library/Application Support/Google/Chrome/<プロファイル>/
    Service Worker/CacheStorage   サイトが再取得できます
    IndexedDB                     内容をサイトごとに判断します
    Cookies / Login Data / Bookmarks / History
                                  利用者の状態なので触りません
```

`/private/var/folders/.../X/com.google.Chrome.code_sign_clone/` は、Chrome が起動時に作る自分の複製です。落ちた場合や強制終了後に残ることがあります。スクリーンショットや PDF 化など、ヘッドレス Chrome を繰り返し起動する道具で急に増えることがあります。

複製は APFS で中身を共有するため、`du` の見かけの量は実際の使用量になりません。古い版の複製ほど容量を使うことがあります。Chrome を終了してから削除候補にできます。ヘッドレス側へ `--disable-features=MacAppCodeSignClone` を付ける方法がありますが、効果は環境ごとに確認してください。

## DriveFS は索引

Google Drive の `Application Support/Google/DriveFS` には `metadata_sqlite_db` などの索引があります。キャッシュではなく、消すと全再構築になるため触りません。

整理候補は `Logs` です。削除する場合も最新の2本は残します。`-wal` は Google Drive を終了すると縮むことがあるため、直接消しません。

## ログの暴走

周辺機器の常駐アプリなどが短期間に多数のログを書く場合があります。一つのフォルダーに一万件を超えるファイルがあるときは、作成元と使用中かを確認します。整理するときは、たとえば `find <フォルダー> -type f -mtime +1 -delete` のように直近一日分を残す方法を、対象と量を示して了解後に使います。

## ホーム以外と APFS

ホームだけではディスク使用量と合いません。`/Applications`、`/Library`、`/private/var`、システム領域も確認します。`diskutil apfs list` では、OS 更新準備などの Preboot も確認できます。

APFS の複製は `du` で二重に数えられることがあります。実際に空いた量は、作業前後の `df` の差で確認します。

削除したキャッシュや依存は使うと戻ります。何が増えたかを調べる場合、更新日時ではなく作成日時を `find -newerBt` で確認します。
