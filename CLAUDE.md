# peca-live (ぺからいぶ！)

PeerCast の配信をブラウザだけで視聴できるようにする Web サービス (http://peca.live/)。
Rails 6.1 の API + React/Redux (TypeScript) の SPA。動画はサーバ上の PeerCast ノードから **ブラウザが直接** 取得し、Rails は経由しない。

## 主な構成

- `app/controllers/api/v1/` — JSON API (チャンネル一覧、お気に入り、掲示板、ログイン、Push 通知)
- `app/controllers/{home,channels}_controller.rb` — SPA のエントリと OGP 用メタ
- `app/models/` — `User`, `Favorite`, `UserDevice`, `PrivateChannel`, `ChannelHistory`
- `app/helpers/firebase_helper.rb` — Firebase ID トークン検証、`sessions_helper.rb` — Cookie セッション
- `lib/json_rpc.rb` — PeerCast ノードの JSON-RPC クライアント、`lib/bbs.rb` — したらば / jpnkn パーサ、`lib/notification_push.rb` — FCM
- `app/javascript/packs/` — React。`app.tsx` (ルート・初期化)、`modules/` (Redux)、`types/` (ドメインクラス)、`components/`
- `db/ridgepole.rb` — スキーマの正本 (`db/schema.rb` は生成物)
- `config/routes.rb` — ルーティング

詳細は以下を参照する (索引は `docs/spec/README.md`)。

- `docs/spec/overview.md` — アーキテクチャ、技術スタック、環境変数、デプロイ
- `docs/spec/api.md` — HTTP エンドポイント仕様
- `docs/spec/data-model.md` — DB スキーマ
- `docs/spec/peercast-integration.md` — PeerCast ノードとの連携、ストリーム URL
- `docs/spec/channel-visibility.md` — 一覧への掲載/非掲載ルール
- `docs/spec/bbs.md` — 掲示板連携
- `docs/spec/auth-and-notification.md` — ログイン、お気に入り、Push 通知
- `docs/spec/scheduled-jobs.md` — 定期実行エンドポイントとキャッシュ TTL
- `docs/spec/frontend.md` — 画面、Redux、コンポーネント
- `docs/plans/` — 検討中・進行中の計画 (peercast-mi への移行と Docker 化など)

## 実行

```sh
bundle
cp example.env .env      # PEERCAST_TIP, PEERCAST_BASIC_TOKEN
yarn install
yarn start               # bin/rails s & bin/webpack-dev-server
```

- Ruby 3.4.4 (`.ruby-version`)、Node 13.7.0 (`.node-version`)、PostgreSQL
- スキーマ変更: `db/ridgepole.rb` を編集 → `rake ridgepole:apply_dry_run` → `rake ridgepole:apply`。マイグレーションファイルは作らない
- 定期実行 (`record_history`, `notification_broadcasting`) は外部から 10 分ごとに GET する前提。ローカルでは手で叩く

## 関連リポジトリ (ローカルパス)

- `/home/megan/src/go/peercast-mi` — 移行先候補の Go 製 PeerCast ノード。JSON-RPC 仕様は `docs/spec/api/jsonrpc.md`
- `/home/megan/src/peercaststation` — 現在接続している PeerCastStation のソース。`updateYPChannels` は `PeerCastStation.UI.HTTP/APIHost.cs`
- `/home/megan/src/peca-docs/docs/protocol/` — PCP プロトコル、YP、視聴・リレーの仕様
- `/home/megan/src/go/peercast-0yp/docs/` — YP サーバ側の仕様。`index.txt` の形式は `yp/player.md`

PeerCast の挙動や `index.txt` の形式は推測せず、上記の仕様書か実装で確認する。

## 作業ルール

### コード

- TypeScript は Prettier (`.prettierrc`: セミコロンなし、シングルクォート、幅 120、2 スペース) に従う
- Ruby はコメント含め既存のスタイルに合わせる。コメントは日本語
- `Rails.cache` はファイルストア前提 (dyno 間で共有されない)。キャッシュ済みオブジェクトを書き換えない
- 外部への HTTP は `httpclient` / `Net::HTTP` を使う。`lib/json_rpc.rb` と Push 通知はシェルで `curl` を実行しているが、これに倣わない
- 動画は HTTP で PeerCast ノードに直接つなぐため、サイトは HTTPS 化しない (`ApplicationController#ensure_domain`)。この前提を変える変更はユーザーに確認する
- チャンネルの識別: お気に入り・非掲載設定は **チャンネル名**、配信履歴・ストリームは **streamId (channelId)**。混同しない
- 秘密情報 (FCM サーバキー等) がソースに直書きされている箇所がある。新たに増やさない

### ドキュメント

- 実装の動作を変更したら、対応する `docs/spec/` の記述を同じ変更に含める。仕様書には「現在どう動くか」だけを書く
- API のパス・パラメータ・レスポンスを変えたら `docs/spec/api.md` を更新する。スキーマを変えたら `docs/spec/data-model.md` を更新する
- 既知の不具合や仕様の癖は、直さない場合でも仕様書の「備考」に残す
- 計画・検討事項は `docs/plans/` に置く。CLAUDE.md や仕様書に TODO を書かない
- 仕様書と実装が食い違っていたら実装を正とし、仕様書を直す

### 検証

- 自動テストは実質ない (`test/` はほぼ空、`spec/` は設定のみ)。変更後は `bin/rails s` で該当エンドポイントを叩くか、ブラウザで確認する
- 完了前に `bin/rails runner 'puts 1'` 相当で起動できること、TypeScript を触った場合は `bin/webpack` が通ることを確認する
- 外部サービス (YP、掲示板、Firebase、FCM) への実アクセスを伴う確認は、結果と一緒に「何を叩いたか」を報告する
