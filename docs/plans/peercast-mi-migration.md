# peercast-mi への移行と Docker 化

- 状態: 実装中 (ブランチ `feature/peercast-mi`)
- 日付: 2026-09-14
- 関連: [../spec/peercast-integration.md](../spec/peercast-integration.md), [../spec/overview.md](../spec/overview.md)

## 背景

peca-live は現在、サーバ上で常駐する PeerCastStation に JSON-RPC で接続し、次の 2 つの役割を任せている。

1. **YP のチャンネル一覧取得** (`updateYPChannels`)
2. **視聴用リレーノード** (ブラウザが `http://<tip>/stream/<id>.flv?tip=` を直接開く)

これを Docker 化にあわせて、Go 製の [peercast-mi](https://github.com/titagaki/peercast-mi) (`/home/megan/src/go/peercast-mi`) に置き換えたい。
peercast-mi は既に peca-live 互換のために `bumpChannel` の名前指定 params (ADR 0010) と `/stream/<id>.flv?tip=` でのオンデマンドリレー (ADR 0014) を実装している。

## ゴール

- `docker compose up` で peca-live (Rails) + PostgreSQL + peercast-mi が起動し、Heroku + 手動運用の PeerCastStation を置き換える
- フロントエンド・`ChannelHistory`・通知など、`updateYPChannels` の結果を消費している側は無変更で済ませる
- peercast-mi 側には手を入れない (peca-live 側で吸収する)

## 現状の依存と peercast-mi の対応状況

| peca-live の利用箇所 | 用途 | peercast-mi | 判定 |
| --- | --- | --- | --- |
| `JsonRpc#update_yp_channels` (`updateYPChannels`) | チャンネル一覧・履歴記録・配信開始通知 | 未実装 | **peca-live 側で YP の `index.txt` を直接取得する** |
| `JsonRpc#bump_channel` (`bumpChannel {channelId}`) | プレイヤーの「再接続(Bump)」 | 実装済みだが意味が異なる (YP へ bcst 送信。リレーチャンネルには no-op) | **`stopChannel` に置き換える** |
| `JsonRpc#get_peercast_status` (`getStatus`) | `GET /api/v1/peercast` | 未実装 | フロント未使用。**エンドポイントごと削除** |
| ブラウザ → `GET /stream/<id>.flv?tip=<tracker>` | flv.js 再生 | 実装済み (ADR 0014) | **`relay_request_from = "any"` が必要** |
| `Authorization: Basic <PEERCAST_BASIC_TOKEN>` | JSON-RPC 認証 | `admin_user` / `admin_pass` (非 localhost は必須) | `base64("user:pass")` を渡せばそのまま動く |
| `X-Requested-With: XMLHttpRequest` ヘッダ | PeerCastStation の CSRF 対策 | 不要 (CORS はオリジン allowlist 方式、ADR 0011) | 付けたままでも害はない |
| `PeerCast.port_opened?` (PCP `helo`) | `GET /api/v1/channels/check_port` | ノード非依存 | 影響なし |
| フロント `PeerCast.defaultPortNo = 8144` | 視聴用ポート | peercast-mi は視聴も RPC も `peercast_port` (既定 7144) の 1 ポート | **固定値を撤去し `PEERCAST_TIP` のポートを使う** |

## 変更方針

### 1. YP チャンネル一覧を peca-live 側で取得する

PeerCastStation の `updateYPChannels` も内部では各 YP の `index.txt` を HTTP GET してパースしているだけで、PCP は使っていない。
peercast-mi は「配信・リレーノード」に責務を絞っているので、一覧取得は peca-live 側に持つ。

- `lib/yellow_page.rb` (仮) を新設し、設定された YP ごとに `index.txt` を取得・パースして、**`updateYPChannels` と同じキーのハッシュ配列** に整形する
- `Api::V1::ChannelsController#get_channels` の呼び先を `JsonRpc#update_yp_channels` から差し替える。1 分キャッシュはそのまま
- YP の一覧は環境変数か `config/yellow_pages.yml` で持つ。各エントリに `name` (`SP` / `TP` など。フロントのアイコン分岐 `Channel#isSp` / `isTp` と一致させる) と `index.txt` の URL

#### `index.txt` の形式

1 行 1 チャンネル、`<>` 区切り、**19 項目固定**、UTF-8。
仕様は [peercast-0yp `docs/yp/player.md`](https://github.com/titagaki/peercast-0yp/blob/main/docs/yp/player.md)、PeerCastStation 側のパースは `PeerCastStation.PCP/PCPYellowPageClient.cs` `GetChannelsAsync` で確認済み。

| index | 内容 | `updateYPChannels` のキー | 備考 |
| --- | --- | --- | --- |
| 0 | チャンネル名 | `name` | |
| 1 | チャンネル ID (32 hex) | `channelId` | PeerCastStation は **大文字** に正規化して返す。制限チャンネルは全ゼロ |
| 2 | tracker `host:port` | `tracker` | Push 配信時は空、制限チャンネルは `127.0.0.1` |
| 3 | コンタクト URL | `contactUrl` | |
| 4 | ジャンル | `genre` | `?` を含むとリスナー数非公開 |
| 5 | 説明 (`<Open>` 等の状態を含む) | `description` | |
| 6 | リスナー数 | `listeners` | 非公開は `-1`。`-1` 未満はサーバのメッセージ、空もあり得る |
| 7 | リレー数 | `relays` | 同上 |
| 8 | ビットレート kbps | `bitrate` | |
| 9 | コンテンツタイプ (`FLV` / `WMV` …) | `contentType` | |
| 10 | トラック: アーティスト | `creator` | |
| 11 | トラック: アルバム | `album` | |
| 12 | トラック: タイトル | `trackTitle` | |
| 13 | トラック: URL | `trackUrl` | |
| 14 | チャンネル名 (URL エンコード) | (未使用) | |
| 15 | 配信時間 `H:MM` | `uptime` | 秒に変換: `(h*60 + m)*60`。`:` が無ければ整数としてそのまま |
| 16 | 固定文字列 `click` | (未使用) | |
| 17 | コメント | `comment` | |
| 18 | direct フラグ `0`/`1` | (未使用) | |

PeerCastStation の変換規則 (同じ出力にするために peca-live 側でも踏襲する):

- 文字列項目は **HTML デコード** する (`WebUtility.HtmlDecode`)。ただし `description` の `<Open>` は index.txt 上で `&lt;Open&gt;` になっているためデコード後に `<Open>` になる。現在のフロント (`Channel#unescapeHTML`) や通知の除去処理は `<Open>` 前提なので整合する
- 数値項目はパース失敗時 `null` (`-1` ではない)。`ChannelHistory` は `listeners` / `relays` / `bitrate` を NOT NULL にしているので、空の場合の扱い (`-1` or `0` に寄せる / スキップ) を決める
- `yellowPage` は取得元 YP の名前
- 項目数が足りない行も、ある分だけ読む
- YP 自身のエントリ (`channelId` 全ゼロ) は現状どおり呼び出し側で除外する

PeerCastStation の「チャンネル一覧 URI」は YP の pcp アドレスから自動導出されるものではなく **YP ごとに別途設定する項目** (`ChannelsUri`)。
設定 UI は `index.txt` で終わる URI かどうかを検証するだけで、実際の URL は運用者が入力している。

#### 取得先 URL の確認結果 (2026-09-14, 開発機から)

| YP | URL | 結果 |
| --- | --- | --- |
| SP | `http://bayonet.ddo.jp:7146/index.txt` | `302 → /html/ja/login.html`。アクセス元制限か認証がある可能性 |
| 0yp | `http://yayaue.me/index.txt` → `https://` | 404 |
| TP | `http://temp.orz.hm:7144/index.txt` | 名前解決不可 |
| p@YP | `http://root.p-at.net/index.txt` | HTML が返る (別 API の可能性) |

→ **現在の PeerCastStation の YP 設定にある「チャンネル一覧 URI」(`ChannelsUri`) をそのまま流用する。** 値は本番サーバの PeerCastStation 設定画面で確認する。開発機から取れないのはアクセス元制限の可能性があるので、本番サーバからも `curl` で確認しておく。

peercast-0yp を YP として使う場合は `GET /yp/index.txt` のほかに JSON の `GET /yp/api/channels` もあるが、複数 YP を同じコードで扱うため index.txt に統一する。

### 2. 「再接続(Bump)」を `stopChannel` で実現する

peercast-mi の `bumpChannel` は配信者向けで、リレーチャンネルに対しては何もしない。また ADR 0014 により、登録済みチャンネルへの `/stream/?tip=` 要求では tip を無視してリレーを作り直さない。
そのため現在の「`bump` → `location.reload()`」では再接続にならない。

- `Api::V1::ChannelsController#bump` の中身を `stopChannel` に変更する。`Manager.Stop` はリレーチャンネルを Manager から消すため、直後のリロードで `/stream/?tip=` が新規にリレーを張り直す
- 他の視聴者がいる場合もそのチャンネルは一度切れる (PeerCastStation の bump も全員が切れるので同じ)
- ルート名 `bump` とフロントの表示は変えない

### 3. `GET /api/v1/peercast` を削除する

`getStatus` は peercast-mi にない。フロントも使っていないため、コントローラ・ルート・`JsonRpc#get_peercast_status` を削除する。

### 4. 環境変数を「内部 RPC 用」と「公開 TIP 用」に分離する

現在は `PEERCAST_TIP` 1 つが次の 2 役を兼ねている。

- Rails → JSON-RPC の接続先 (`http://#{PEERCAST_TIP}/api/1`)
- レイアウトの `<meta name="peercast-tip">` 経由で、**視聴者のブラウザ** がストリームを開く接続先

Docker Compose では前者は内部ネットワーク (`peercast-mi:7144`)、後者は公開アドレス (`peca.live:7144` など) になり一致しない。

| 変数 | 用途 | 例 |
| --- | --- | --- |
| `PEERCAST_RPC_URL` (新) | Rails → JSON-RPC | `http://peercast-mi:7144/api/1` |
| `PEERCAST_BASIC_TOKEN` | 同上の Basic 認証 | `base64("admin:secret")` |
| `PEERCAST_TIP` | ブラウザの視聴先 `host:port` (meta タグ) | `peca.live:7144` |

フロント `types/PeerCast.ts` は `PEERCAST_TIP` の `host` だけ使ってポートを `8144` 固定にしているが、peercast-mi は 1 ポートなので、`host:port` をそのまま既定値にする。`SettingDialog` の「デフォルトに戻す」も同じ値を使う。

### 5. peercast-mi の設定

```toml
peercast_port = 7144
rtmp_port     = 1935            # peca-live では使わないが待ち受けは残る

# ブラウザ (グローバル IP) からの /stream/?tip= でリレーを開始させる
relay_request_from = "any"

# 露出対策
max_relay_channels = 16
max_listeners      = 0          # 必要なら制限
channel_cleanup_minutes = 20    # 視聴者ゼロのリレーを自動削除

# 非 localhost (= Rails コンテナ) からの JSON-RPC に必須
admin_user = "admin"
admin_pass = "<secret>"

[[yp]]                          # tip なしの /stream/ 要求で tracker を探す先
name = "SP"
addr = "pcp://bayonet.ddo.jp:7146/"
```

- `relay_request_from = "any"` はインターネットから任意の `tip` へ PCP 接続を開始できる状態になる。PeerCastStation で同じ用途に使っていた現状と露出範囲は同じだが、`max_relay_channels` は必ず設定する
- `[[yp]]` は peca-live が常に `tip=` を付けるので必須ではないが、tip が古い場合のフォールバックとして設定しておく
- `stream_keys.json` は使わないが書き込み可能なディレクトリが要る

### 6. Docker 構成

```
services:
  web:          Rails (puma)             公開: 80 (リバースプロキシ経由なら内部のみ)
  db:           postgres
  peercast-mi:  peercast-mi              公開: 7144 (ブラウザが直接開く), 1935 は非公開でよい
  scheduler:    (後述)
```

- Rails 用 `Dockerfile` を新規作成 (Ruby 3.4.4, Node, `yarn build` / `assets:precompile`)
- `PEERCAST_TIP` の公開ポート 7144 は **HTTP のまま** 公開する必要がある (ブラウザからの直接接続。HTTPS 化しない現状の理由と同じ)
- peercast-mi の `config.toml` は volume でマウント (`CMD ["-config", "/config/config.toml"]`)

### 7. 定期実行の置き換え

`GET /api/v1/channels/record_history` と `GET /api/v1/channels/notification_broadcasting` は Heroku Scheduler で 10 分ごとに叩く前提 ([../spec/scheduled-jobs.md](../spec/scheduled-jobs.md))。Docker では次のいずれか。

- ホストの cron から `curl http://localhost/api/v1/channels/...`
- `scheduler` コンテナ (alpine + crond) から `web` へ curl
- 将来的には `rails runner` か ActiveJob に寄せる (エンドポイントを外部公開しなくて済む)

`Rails.cache` がファイルストアのままだと `web` を複数レプリカにしたとき通知が重複する。単一コンテナのうちは問題ない。

## 作業手順

- [x] `lib/yellow_page.rb` を実装 (`spec/lib/yellow_page_spec.rb`)。`get_channels` を差し替え。YP は `YELLOW_PAGES` 環境変数で指定
- [x] `bump` → `stopChannel`、`/api/v1/peercast` 削除、`JsonRpc` を `Net::HTTP` 化
- [x] 環境変数を `PEERCAST_RPC_URL` / `PEERCAST_TIP` に分離、フロントのポート固定 (8144) を撤去
- [x] `Dockerfile` / `docker-compose.yml` / `docker/peercast-mi/config.toml` / `docker/scheduler/run.sh`
- [x] 仕様書を実装に合わせて更新
- [ ] 本番の PeerCastStation で YP の「チャンネル一覧 URI」を確認し、`YELLOW_PAGES` に設定。実データで `YellowPage` を確認
- [ ] ローカルで peercast-mi と結合テスト (視聴・再接続・掲載トグル・通知)
- [ ] 本番を Docker 構成へ切り替え。`peca.live:7144` を peercast-mi に向ける

## 要確認事項

- [x] `index.txt` の項目並び — peercast-0yp の仕様書と PeerCastStation の実装で確認済み (19 項目)
- [ ] 現行 PeerCastStation の YP 設定にある「チャンネル一覧 URI」の値
- [ ] SP の `index.txt` がアクセス元制限されているか (開発機からは `login.html` へ 302)
- [ ] `listeners` / `relays` / `bitrate` が空・非数値の行の扱い — 実装は PeerCastStation と同じく `nil` にしている。`ChannelHistory.record_channels` はその行で例外になる (現状の YP では起きない想定)
- [ ] `PEERCAST_TIP` の公開ポートを 7144 にするか、現行の 8144 を維持するか (ユーザーの `localStorage` に旧ポートが残っている場合の扱い)
- [ ] `stopChannel` による再接続で、同一チャンネルの他の視聴者に与える影響を許容するか
- [ ] Docker 化後のホスティング先 (Heroku Container / VPS / 自宅サーバ) と、定期実行の方式

## 参照

- peercast-mi: `docs/spec/api/jsonrpc.md`, `docs/decisions/0010-bump-channel-named-params.md`, `0014-stream-on-demand-relay.md`, `0016-relay-request-source-policy.md`, `0011-cors-policy.md`
- PeerCastStation (`/home/megan/src/peercaststation`): `PeerCastStation.PCP/PCPYellowPageClient.cs` (`GetChannelsAsync`, `ParseUptime`)、`PeerCastStation.UI.HTTP/APIHost.cs` (`YPChannelsToArray` = `updateYPChannels` の JSON 形式)
- PeerCast プロトコル仕様: [peca-docs `docs/protocol/`](https://github.com/titagaki/peca-docs/tree/main/docs/protocol) (`/home/megan/src/peca-docs`)、[peercast-0yp `docs/`](https://github.com/titagaki/peercast-0yp/tree/main/docs) (`/home/megan/src/go/peercast-0yp`)。`index.txt` は peercast-0yp `docs/yp/player.md`、YP 登録は peca-docs `docs/protocol/yp_channel_registration.md`
- peca-live: `lib/json_rpc.rb`, `app/controllers/api/v1/channels_controller.rb`, `app/javascript/packs/types/PeerCast.ts`, `app/views/layouts/application.html.erb`
