# HTTP エンドポイント仕様

ルーティングは `config/routes.rb`。全コントローラは `ApplicationController` を継承する。

## 共通仕様

### ドメイン / HTTPS リダイレクト (`ApplicationController#ensure_domain`)

すべてのリクエストで、リクエスト URL を次の順で書き換えた URL と一致しなければそこへ `redirect_to` する。

1. `https://` → `http://` （ブラウザが PeerCast ノードと HTTP 通信するため HTTPS を使わない）
2. `peca-live.herokuapp.com` → `peca.live`
3. `www.peca.live` → `peca.live`

API も例外ではない。開発環境 (`localhost`) では何も置換されないため影響しない。

### 認証

- ログイン状態は Rails の Cookie セッション `session[:uid]`（Firebase UID）で保持する。
- `current_user` は `User.find_by(uid: session[:uid])`（`SessionsHelper`）。
- 認証が必要な API で未ログインの場合は、エラーではなく **空レスポンス / 空配列** を返す（下記参照）。
- CSRF: `ActionController::Base` 標準の `protect_from_forgery`（Rails 6 デフォルトで `with: :exception` 相当）。POST/DELETE には `X-CSRF-TOKEN` ヘッダが必要。フロントはレイアウトの `<meta name="csrf-token">` から取る。

### CORS

`Rack::Cors` で `origins "*"`、メソッド GET/POST/OPTIONS/HEAD を全パスに許可。credentials は許可していないので、他オリジンからはログイン状態を伴うリクエストはできない。

### クライアント IP の決定

`Api::V1::ChannelsController#broadcasting` / `#check_port` と `Api::V1::Channels::PrivateController#show` は **`request.remote_ip`** を「配信者の IP」として使う。

`request.remote_ip` (`ActionDispatch::RemoteIp`) は `X-Forwarded-For` を解釈するが、**信頼するのは private アドレス (10/8, 172.16/12, 192.168/16, 127/8, fc00::/7 など) からのホップだけ**。

| 構成 | 得られる IP |
| --- | --- |
| `web` を直接公開 | 実際の接続元。クライアントが `X-Forwarded-For` を付けても送信元がグローバル IP なので無視される |
| 同一ホスト / Docker ネットワーク上のプロキシ経由 | プロキシは private なので信頼され、`X-Forwarded-For` のクライアント IP になる |
| Cloudflare など外部プロキシ経由 | プロキシの IP がグローバルなので信頼されず、プロキシの IP になる。`config.action_dispatch.trusted_proxies` の設定が必要 |

以前は `X-Forwarded-For` の先頭を無条件に使っていた (Heroku ルータ前提)。プロキシ無しで公開するとヘッダを偽装して他の配信者の掲載設定を操作できたため、`remote_ip` に変更した。

### レスポンス

`render json:` で返す JSON。`render` を呼ばないアクション（`accounts#create`, `favorites#create` 等）は Rails のデフォルト挙動により **204 No Content** を返す。

---

## ページ (HTML)

| メソッド | パス | コントローラ | 説明 |
| --- | --- | --- | --- |
| GET | `/` | `home#index` | SPA のエントリ。`layouts/application.html.erb` + `home/index.html.erb` |
| GET | `/:channel_name` | `channels#show` | 同じ SPA を返すが、`ChannelHistory` から `title` / `description` を組み立てて OGP を出す。`@history = ChannelHistory.where(name:).order(latest_lived_at: :desc).first`、`@title = "#{name} - ぺからいぶ！"`、`@description = @history.detail` |
| GET | `/channels/:stream_id` | `channels#stream_id` | `stream_id` の履歴があれば `/#{history.name}` へリダイレクト、なければ `/`。Push 通知のリンク先に使う |
| GET | `/user_devices?token=` | `home#user_devices` | ログイン中かつ `token` があれば `current_user.devices.create(token:)` し、**そのユーザーの全デバイス** に「お気に入り配信を通知します！」というテスト通知を送る。最後に `/` へリダイレクト。外部の WebPush 登録サイト (`https://peca-live.netlify.app/`) からの戻り先 |
| GET | `/user_icons/:jpnkn_id` | `user_icons#show` | 現在は `/images/mouneyou.png` へリダイレクトするだけ。（jpnkn の掲示板ページから Twitter ID を抽出し unavatar.io 経由でアイコンを取る実装は残っているが無効化） |

ルート順序の注意: `get ':channel_name'` は `namespace :api` より前に定義されているが、`api/v1/...` は複数セグメントなので `:channel_name` にはマッチしない。

### レイアウトが出力する meta

- `<meta name="peercast-tip" content="<%= ENV['PEERCAST_TIP'] %>">` — フロントのデフォルト視聴先ホストを渡す
- `csrf_meta_tags`
- OGP: `og:title`, `og:description`, `og:image`(`http://peca.live/images/live-chuu.png`), `og:type=video.movie`, `twitter:card=summary`
- デフォルト description: 「パソコンでも、スマホでも。もっと気軽にピアキャスライフを！ どこからでも簡単にPeerCastが見ることができます！」

---

## `api/v1` 一覧

| メソッド | パス | 認証 | 説明 |
| --- | --- | --- | --- |
| GET | `/api/v1/csrf_token` | - | CSRF トークン取得 |
| POST | `/api/v1/accounts` | Bearer | Firebase ID トークンでログイン |
| GET | `/api/v1/accounts/sign_out` | - | ログアウト |
| GET | `/api/v1/channels` | 任意 | 配信中チャンネル一覧 |
| GET | `/api/v1/channels/notification_broadcasting` | - | 【定期実行】配信開始 Push 通知 |
| GET | `/api/v1/channels/record_history` | - | 【定期実行】配信履歴の記録 |
| GET | `/api/v1/channels/broadcasting` | - | 自分 (IP) が配信した履歴 |
| GET | `/api/v1/channels/check_port` | - | ポート開放チェック |
| GET | `/api/v1/channels/bump?streamId=` | - | 再接続 (ノードの `stopChannel`) |
| GET | `/api/v1/channels/private/:channel_name` | IP | 掲載/非掲載トグル |
| DELETE | `/api/v1/channels/private/:channel_name` | - | ルートは存在するがアクション未実装 (→ 500) |
| GET | `/api/v1/favorites` | 任意 | お気に入り一覧 |
| GET | `/api/v1/favorites/:id` | 任意 | お気に入り 1 件 |
| POST | `/api/v1/favorites` | 要 | お気に入り登録 |
| DELETE | `/api/v1/favorites` | 要 | お気に入り解除 (collection) |
| DELETE | `/api/v1/favorites/:id` | 要 | 同上（`:id` は使わず `channel_name` で削除） |
| GET | `/api/v1/bbs?url=` | - | 掲示板情報 |
| GET | `/api/v1/bbs/threads?url=` | - | スレッド一覧 |
| GET | `/api/v1/bbs/comments?url=` | - | コメント一覧 |

`resources :channels` / `resources :favorites` により `show/create/update/destroy` などのルートも生成されるが、対応するアクションがないものは `AbstractController::ActionNotFound` になる。

---

## 詳細

### GET `/api/v1/csrf_token`

- レスポンスヘッダ `X-CSRF-Token: <form_authenticity_token>`、ボディなし (200)。
- 現在のフロントは使っていない（`<meta name="csrf-token">` を使用）。

### POST `/api/v1/accounts`

- ヘッダ `Authorization: Bearer <Firebase ID token>`、`X-CSRF-TOKEN` 必須。
- 既にログイン済みなら何もしない。
- トークン検証後、`User.find_or_create_by!(uid:, name:, photo_url:)` して `session[:uid]` を設定。
- 常に 204。検証失敗時は例外 (500) になる。詳細は [auth-and-notification.md](auth-and-notification.md)。

### GET `/api/v1/accounts/sign_out`

`session.delete(:uid)`。204。

### GET `/api/v1/channels`

配信中のチャンネル一覧。フロントの主データ源。

- `fetch_channels`（1 分キャッシュ）: `YellowPage.fetch_channels`（各 YP の `index.txt`）の結果から YP 自身のエントリと非掲載チャンネルを除いたもの（ルールは [channel-visibility.md](channel-visibility.md)）。
- ログイン中の場合、各要素に `favorited: true/false` を付与する。**未ログイン、またはお気に入りが 0 件のときは `favorited` キー自体が付かない**。
- レスポンスは `YellowPage` が整形したハッシュをそのまま返す（キー一覧は [peercast-integration.md](peercast-integration.md)）。
- キャッシュされた配列オブジェクトに `favorited` を書き込むため、ファイルキャッシュでは影響しないが、メモリキャッシュを使う場合はキャッシュ内容が汚染される。

### GET `/api/v1/channels/notification_broadcasting`

[scheduled-jobs.md](scheduled-jobs.md) 参照。10 分ごとの実行前提。`uptime < 1800` のチャンネルを対象に、`channelId` ごとに 30 分キャッシュで一度だけ `notify_broadcasting` を実行する。レスポンスは対象チャンネルの配列。

### GET `/api/v1/channels/record_history`

[scheduled-jobs.md](scheduled-jobs.md) 参照。`get_channels`（フィルタなし、1 分キャッシュ）から YP エントリだけ除いて `ChannelHistory.record_channels`。**非掲載チャンネルも履歴には記録される**（掲載トグルの判定に必要なため）。レスポンスは記録したチャンネルの配列。

### GET `/api/v1/channels/broadcasting`

リクエスト元 IP から配信された `ChannelHistory`（`broadcast_from(ip)`）を返す。設定ダイアログの「配信の掲載」に使う。

```json
[
  { "channelId": "0C1A...", "name": "しっかりシュールｃｈ", "private": false }
]
```

`private` は `PrivateChannel.secret?(name)`。

### GET `/api/v1/channels/check_port`

| パラメータ | 既定 |
| --- | --- |
| `host` | `request.remote_ip` |
| `port_no` | `"7144"` |

`PeerCast.port_opened?(host, port_no)`（PCP `helo` を送って `oleh` が返るか。3 秒タイムアウト）。デバッグ情報つきで返す:

```json
{ "result": true, "check_ip": "...", "check_port": "7144",
  "request_remote_ip": "...", "forward": "<X-Forwarded-For>", "remote_addr": "..." }
```

フロントからは使っていない。

### GET `/api/v1/channels/bump?streamId=`

`streamId` があればノードの `stopChannel` を実行してリレーチャンネルを消す。ノードにそのチャンネルが無ければ何もしない。204。フロントの「再接続(Bump)」ボタンから呼ばれ、直後にページをリロードすることで `/stream/?tip=` から新しいリレーが張られる。同じチャンネルを見ている他の視聴者も一度切れる。

### GET `/api/v1/channels/private/:channel_name`

配信の掲載/非掲載トグル。詳細は [channel-visibility.md](channel-visibility.md)。

- リクエスト元 IP から `channel_name` を配信した履歴がなければ **403**。
- `PrivateChannel` が存在すれば `secret ⇄ open` を反転、存在しなければ `secret` で作成（= 非掲載にする）。
- 200、ボディなし。

チャンネル名は URL のパスセグメントに入る（日本語はパーセントエンコード）。`param: :channel_name` 指定のため `params[:channel_name]` で受ける。

### GET `/api/v1/favorites`

未ログインなら `[]`。ログイン中は `[{ "id": 1, "channel_name": "..." }, ...]`。

### GET `/api/v1/favorites/:id`

未ログインなら `{}`。ログイン中は該当 `id` の **配列**（`where(...).select(...)` の結果をそのまま `to_json`）。

### POST `/api/v1/favorites`

- body: `channel_name=<name>` (form-urlencoded)、`X-CSRF-TOKEN` 必須。
- 未ログインなら何もしない (204)。
- `current_user.favorite!(channel_name)` (find_or_create)。204。

### DELETE `/api/v1/favorites` / `/api/v1/favorites/:id`

- body: `channel_name=<name>`。`:id` は無視され、`channel_name` で `find_by` して `destroy!`。存在しなければ何もしない。204。

### GET `/api/v1/bbs?url=`

[bbs.md](bbs.md) 参照。1 日キャッシュ。

```json
{ "top_image_url": "http://.../img.png", "title": "掲示板タイトル" }
```

### GET `/api/v1/bbs/threads?url=`

10 秒キャッシュ。`[{ "no": "1600986660", "url": "...", "title": "...", "comments_size": 123 }, ...]`

### GET `/api/v1/bbs/comments?url=`

10 秒キャッシュ。

```json
{ "thread_title": "...", "comment_count": 456,
  "comments": [ { "no": 456, "name": "...", "mail": "...", "writed_at": "...", "body": "..." }, ... ] }
```

`comments` は **新しい順に最大 30 件**。

---

## ルーティングされていないコントローラ

- `Api::V1::UserDevicesController#create` — `routes.rb` にエントリがなく到達不能。実装も `User.find(uid:)` で誤り。
