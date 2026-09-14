# システム概要

## サービスの目的

「ぺからいぶ！」(http://peca.live/) は、PeerCast の配信を **PCでもスマホでもブラウザだけで視聴できる** ようにするWebサービス。
ユーザーは PeerCast をローカルにインストールしなくても、サーバ側で動いている PeerCast ノード (peercast-mi) を経由して FLV 配信をブラウザ上で再生できる。

主な機能:

- 現在配信中のチャンネル一覧表示（YP から取得）
- ブラウザ内でのFLV再生（flv.js）、iOS は VLC へハンドオフ
- コンタクトURL（したらば / jpnkn）のコメント表示
- Twitterログイン（Firebase Auth）によるお気に入り登録
- お気に入り配信の開始をWebPushで通知
- 配信者が自分の配信を一覧に掲載しない設定

## アーキテクチャ

```
[ブラウザ]
  React + Redux (TypeScript, Material-UI, flv.js)
     │  fetch /api/v1/...   (同一オリジン, Cookieセッション)
     │  http://<PEERCAST_TIP>/stream/<id>.flv?tip=<tracker>   (動画は peercast-mi から直接取得)
     ▼
[Rails 6.1 (peca.live, Docker)]
  ├─ HTTP GET index.txt ─▶ [YP (SP / TP)]     ENV: YELLOW_PAGES
  ├─ JSON-RPC ──────────▶ [peercast-mi]       ENV: PEERCAST_RPC_URL / PEERCAST_BASIC_TOKEN
  ├─ HTTP ──────────────▶ [したらば / jpnkn 掲示板]
  ├─ HTTPS ───────────▶ [Google 公開鍵 (Firebase IDトークン検証)]
  ├─ HTTPS ───────────▶ [FCM legacy API (Push通知)]
  └─ PostgreSQL
```

- ページ表示は Rails の `home#index` が 1 枚のHTMLを返し、React (react-router) がクライアントサイドでルーティングする。
- すべての API は同一オリジンで、Rails の Cookie セッション（`session[:uid]`）でログイン状態を保持する。
- **動画ストリームは Rails を経由しない**。ブラウザが peercast-mi に直接 HTTP で接続する。
- そのため `peca.live` は **HTTP のみ** で提供する（HTTPS だとページ内から HTTP の peercast-mi に接続できない）。詳細は [api.md の共通仕様](api.md#共通仕様) を参照。

## 技術スタック

### バックエンド

| 項目 | 内容 |
| --- | --- |
| 言語 | Ruby 3.4.4 (`.ruby-version`) |
| フレームワーク | Rails 6.1.7 |
| DB | PostgreSQL (`pg`) |
| スキーマ管理 | ridgepole (`db/ridgepole.rb` が正。`db/schema.rb` は生成物) |
| Webサーバ | puma |
| アセット | webpacker 5 (`app/javascript/packs`) |
| 認証 | `jwt` gem で Firebase IDトークンを自前検証 (`app/helpers/firebase_helper.rb`) |
| HTTP クライアント | `httpclient` (掲示板・YP 取得)、`Net::HTTP` (JSON-RPC)、**`curl` コマンドのシェル実行** (FCM) |
| エラー監視 | Bugsnag (`BUGSNAG_API_KEY`) |
| テスト | rspec-rails が入っているが、テストファイルは実質空 (`test/controllers/api/v1/channels_controller_test.rb` は空クラス) |

### フロントエンド

| 項目 | 内容 |
| --- | --- |
| 言語 | TypeScript 4.5 (`tsconfig.json`)、`.tsx` |
| UI | React 16、Material-UI v4、styled-components |
| 状態管理 | Redux Toolkit (`createSlice`)、react-redux |
| ルーティング | react-router-dom v5 (`BrowserRouter`) |
| 動画 | flv.js 1.5 |
| 認証 | firebase 7 + firebaseui / react-firebaseui (Twitter プロバイダのみ) |
| 端末判定 | react-device-detect (`isMobile`, `isIOS`) |
| 計測 | react-ga (Universal Analytics `UA-46281082-3`) |
| メタタグ | react-helmet |

## ディレクトリ構成（主要部分）

```
app/
  controllers/
    application_controller.rb      ドメイン/HTTPS→HTTP リダイレクト、SessionsHelper
    home_controller.rb             index (SPAのエントリ), user_devices
    channels_controller.rb         /:channel_name, /channels/:stream_id (SEO用メタ生成)
    user_icons_controller.rb       /user_icons/:jpnkn_id (現在は無効化済み)
    api/v1/
      channels_controller.rb       チャンネル一覧・通知・履歴記録・bump・ポートチェック
      channels/private_controller.rb  配信の掲載/非掲載トグル
      favorites_controller.rb      お気に入り CRUD
      accounts_controller.rb       Firebase トークンでログイン / ログアウト
      bbs_controller.rb / threads_controller.rb / comments_controller.rb  掲示板
      csrf_tokens_controller.rb    CSRF トークン取得
      user_devices_controller.rb   (ルーティングされていない)
  models/                          User, Favorite, UserDevice, PrivateChannel, ChannelHistory
  helpers/
    sessions_helper.rb             log_in / log_out / current_user
    firebase_helper.rb             Firebase IDトークン検証
  javascript/packs/
    application.js                 Rails UJS/Turbolinks 等（Railsレイアウト側）
    pecalive.tsx                   React のマウント
    app.tsx                        ルート・初期化・Firebase onAuthStateChanged
    store.ts, modules/             Redux
    types/                         Channel, PeerCast, User などのドメインクラス
    apis/BbsApi.ts                 掲示板 API クライアント
    components/                    画面コンポーネント
    firebase/                      Firebase 初期化と設定
lib/
  yellow_page.rb                   YP の index.txt 取得・パース
  json_rpc.rb                      peercast-mi JSON-RPC クライアント (stopChannel)
  peer_cast.rb                     PCP ハンドシェイクによるポート開放チェック
  bbs.rb                           したらば / jpnkn パーサ
  notification_push.rb             FCM Push 送信
db/ridgepole.rb                    スキーマ定義
config/routes.rb                   ルーティング
public/images/                     ロゴ・YPアイコン等の静的画像
```

## 環境変数

| 変数 | 必須 | 用途 |
| --- | --- | --- |
| `PEERCAST_TIP` | 必須 | ブラウザがストリームを開く peercast-mi の公開 `host:port`。`<meta name="peercast-tip">` 経由でフロントのデフォルト視聴先になる |
| `PEERCAST_RPC_URL` | 必須 | Rails → peercast-mi の JSON-RPC エンドポイント（内部ネットワーク） |
| `PEERCAST_BASIC_TOKEN` | 必須 | JSON-RPC の Basic 認証トークン（`base64("user:pass")` をそのまま `Authorization: Basic` に渡す） |
| `YELLOW_PAGES` | 必須 | チャンネル一覧を取る YP。`名前=index.txtのURL` を空白区切り |
| `SECRET_KEY_BASE` | 本番 | Rails のセッション署名鍵 |
| `BUGSNAG_API_KEY` | 任意 | Bugsnag |
| `RAILS_MAX_THREADS` / `RAILS_MIN_THREADS` / `PORT` / `RAILS_ENV` / `PIDFILE` | 任意 | puma 標準 |
| `RAILS_SERVE_STATIC_FILES` / `RAILS_LOG_TO_STDOUT` | 任意 | Docker イメージでは有効 |
| `DATABASE_URL` | 本番 | PostgreSQL（`config/database.yml` は DB名のみ定義。compose では `db` サービスを指す） |

開発環境は `dotenv-rails` により `.env` から読み込む（`example.env` をコピーする）。

### コードに直書きされている秘密情報・固定値

- FCM のサーバキー (`AUTH_KEY`) が `lib/notification_push.rb` と `app/controllers/api/v1/channels_controller.rb` にハードコードされている。
- peercast-mi の `admin_user` / `admin_pass` は `docker/peercast-mi/config.toml` に平文で書く（`.env` の `PEERCAST_BASIC_TOKEN` と対応させる）。
- Firebase Web 設定 (`apiKey` 等) が `app/javascript/packs/firebase/config.ts` にある（Web公開前提の値）。
- Google Analytics ID `UA-46281082-3` が `PageViewTracker.tsx` にある。
- フロントのフォールバック視聴先 `150.9.163.29:8144` が `types/PeerCast.ts` にある（meta タグが読めない場合のみ使用）。

## デプロイ / 運用

- Docker Compose で `web` (Rails) / `db` (PostgreSQL) / `peercast-mi` / `scheduler` を起動する（`docker-compose.yml`、`Dockerfile`、`docker/`）。手順は `README.md`。
  - `peercast-mi` はリポジトリ外のクローンをビルドする（`PEERCAST_MI_CONTEXT`、既定 `../go/peercast-mi`）。設定は `docker/peercast-mi/config.toml`
  - `web` は 3000、`peercast-mi` は 7144 を公開する。7144 はブラウザが直接開くので HTTP のまま外部に出す
- `ApplicationController#ensure_domain` の `herokuapp.com` → `peca.live` リダイレクトは Heroku 時代の名残で、そのまま残っている。
- スキーマ変更は `rake ridgepole:apply_dry_run` → `rake ridgepole:apply`（`config/database.for.heroku.ridgepole.yml`。`DATABASE_URL` を使う）。
- Rails 側には cron 相当の仕組みがなく、[scheduled-jobs.md](scheduled-jobs.md) に記載の GET エンドポイントを `scheduler` コンテナが 10 分ごとに叩く。
- キャッシュは `Rails.cache`（`cache_store` の明示設定なし = Rails デフォルト。本番では `tmp/cache` のファイルストア）。コンテナ間で共有されない点に注意。

## 開発環境

```
bundle
cp example.env .env   # PEERCAST_TIP, PEERCAST_RPC_URL, PEERCAST_BASIC_TOKEN, YELLOW_PAGES を設定
yarn install
yarn start            # bin/rails s & bin/webpack-dev-server
```

ローカルの peercast-mi (`go run .`) に向ける場合は `PEERCAST_TIP=localhost:7144`、`PEERCAST_RPC_URL=http://localhost:7144/api/1`（localhost からの JSON-RPC は Basic 認証不要）。

- テスト: `bundle exec rspec spec/lib` (`YellowPage` のパース。DB 不要)
- Lint: ESLint + Prettier (`.eslintrc.json`, `.prettierrc`: セミコロンなし、シングルクォート、printWidth 120)
- モデルの先頭コメントは `annotate` gem による自動生成 (`lib/tasks/auto_annotate_models.rake`)
