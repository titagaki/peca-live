# 掲示板連携（コンタクトURL）

配信の `contactUrl` に設定された掲示板からスレッド一覧・コメントを取得し、プレイヤーの下に表示する。
実装は `lib/bbs.rb`（`Bbs` クラス）。対応サービスは **したらば (jbbs.shitaraba.net / 旧 jbbs.livedoor.jp)** と **jpnkn (bbs.jpnkn.com 等)** の 2 種類。

## URL の解釈

`Bbs.new(url)` に渡された URL を次の正規表現で判定する（先頭一致 `\A`、`http`/`https` どちらも可）。

| 種別 | 正規表現 | キャプチャ |
| --- | --- | --- |
| したらば スレッド | `https?://jbbs\.shitaraba\.net/bbs/read\.cgi/([a-z]+)/(\d+)/(\d+)` | category, board, thread |
| livedoor スレッド | `https?://jbbs\.livedoor\.jp/bbs/read\.cgi/([a-z]+)/(\d+)/(\d+)` | 同上 |
| したらば 板 | `https?://jbbs\.shitaraba\.net/([a-z]+)/(\d+)` | category, board |
| livedoor 板 | `https?://jbbs\.livedoor\.jp/([a-z]+)/(\d+)` | 同上 |
| jpnkn スレッド | `https?://([a-z\.\/]+)/test/read\.cgi/([a-zA-Z0-9]+)/(\d+)` | host, board, thread |
| jpnkn 板 | `https?://([a-z\.]+)/([a-zA-Z0-9]+)` | host, board |

- 判定は「したらば → jpnkn」の順。したらばに一致しなければ jpnkn の正規表現を試す。
- jpnkn の板パターンはホスト名を限定していないため、**`https://example.com/foo` のような任意 URL も jpnkn として扱われ**、`http://example.com/foo/subject.txt` を取りに行く（取得失敗で空になる）。
- URL の末尾（`/l50` や `?` など）は無視される。
- 板 URL（スレッド番号なし）の場合はコメント取得ができず、スレッド一覧から選ばせる。

### 派生 URL

| 名前 | したらば | jpnkn |
| --- | --- | --- |
| `board_url` | `http://jbbs.shitaraba.net/<cat>/<board>/` | `http://<host>/<board>/` |
| `threads_url` | `<board_url>subject.txt` | 同左 |
| `dat_url` (スレッド URL のときのみ) | `http://jbbs.shitaraba.net/bbs/rawmode.cgi/<cat>/<board>/<thread>/` | `http://<host>/<board>/dat/<thread>.dat` |
| `thread_url(no)` | `http://jbbs.shitaraba.net/bbs/read.cgi/<cat>/<board>/<no>/` | `http://<host>/test/read.cgi/<board>/<no>/` |

livedoor ドメインで渡されても、派生 URL は `jbbs.shitaraba.net` に正規化する。取得はすべて **HTTP**。

## 取得 (`Bbs#fetch`)

- `HTTPClient#get`。ステータス 200 以外は `''`。
- `HTTPClient::ReceiveTimeoutError` は `''`（したらばのタイムアウト多発対策）。それ以外の例外は伝播する。
- 文字コードは `NKF.nkf(option, body)` で変換:
  - `-w`: UTF-8 へ（subject.txt / dat）
  - `-e`: EUC-JP へ（板の HTML。したらばは EUC-JP）

## HTML エンティティの復元 (`parse_web_code`)

`&amp; &lt; &gt; &quot; &#39; &nbsp;` を文字に戻し、さらに `&#NNNN;` 形式の数値参照を `chr` で復元する。変換できないコードは無視。

## API ごとの仕様

### 掲示板情報 `fetch_board` → `GET /api/v1/bbs?url=`

- `board_url` の HTML を取得して Nokogiri でパース。
- `top_image_url`: `div > img` の最初の `src`（したらばのバナー画像を想定）。
- `title`: `<title>`。
- 対応外 URL: `{ top_image_url: nil, title: nil }`。
- **1 日キャッシュ**（キー `api/v1/bbs?url=<url>/v2`）。
- フロントはプレイヤーページ下部に `top_image_url` を表示する。

### スレッド一覧 `fetch_threads` → `GET /api/v1/bbs/threads?url=`

`subject.txt` を 1 行ずつパース。

| | したらば | jpnkn |
| --- | --- | --- |
| 行形式 | `1567349533.cgi,タイトル(123)\n` | `1600986660.dat<>タイトル (123)\n` |
| 区切り | `,` | `<>` |
| `no` | `(.*)\.cgi` | `(.*)\.dat` |
| `title` / `comments_size` | `\A(.*)\(([0-9]+)\)\n\z` | `\A(.*) \(([0-9]+)\)\n\z` |
| 後処理 | **最終行を捨てる**（したらばは最新スレが重複して最終行に出る） | なし |

- 各要素: `{ no, url: thread_url(no), title, comments_size }`。
- したらばのタイトルに `,` が含まれると `split(',')` で崩れ、`title` / `comments_size` が `nil` になる。
- 対応外 URL: `[]`。
- **10 秒キャッシュ**。

### コメント `fetch_comments` → `GET /api/v1/bbs/comments?url=`

`dat_url` を取得してパース。返却は `{ thread_title, comments, comment_count }`。

| | したらば (rawmode.cgi) | jpnkn (dat) |
| --- | --- | --- |
| 行形式 | `no<>name<>mail<>date<>body<>title` | `name<>mail<>date<>body<>title` |
| `no` | 1 列目 | **行番号 (1 始まり)** |
| `thread_title` | 1 行目の 6 列目 | 1 行目の 5 列目 |
| 空/404 判定 | 空 or `指定されたページまたはファイルは存在しません` を含む（アーカイブ済み） | 空 |
| `body` | `strip` し `<br>` → `\n` | 同上 (`&.` で nil 安全) |

- `comments`: パース結果を **逆順にして先頭 30 件**（= 最新 30 件、新しい順）。
- `comment_count`: 最後の行の `no`（= 総レス数。したらばの rawmode は全件返すため）。
- 対応外 URL・板 URL・取得失敗: `{ thread_title: nil, comments: [], comment_count: 0 }`。
- **10 秒キャッシュ**。フロントも 10 秒ごとにポーリングする。

## フロント側の表示ロジック (`components/Comments.tsx`)

1. チャンネルが切り替わる (`channel.name` 変化) → `comments/threads` を `null` にし、`contactUrl` を `channel.contactUrl` にセット。
2. `contactUrl` が変わったら `fetchComments` → `fetchThreads` を順に呼び、10 秒間隔のポーリングタイマーを張り直す。
3. 表示分岐:
   - `comments == null` → ローディング
   - `comments` も `threads` も空 → 「対応していないURLです」
   - `comments` が空で `threads` がある（板 URL）→ 「スレッドを選択してください」+ スレッド一覧。クリックで `contactUrl` をそのスレッドに差し替え
   - それ以外 → コメント一覧（番号 + 本文。`\n` で改行）
4. 高さ 200px の枠内スクロール。チャンネル切替時に先頭へ戻す。

`contactUrl` が空の場合は `comments = []`, `threads = []` として「対応していないURLです」になる。
