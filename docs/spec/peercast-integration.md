# PeerCast 連携

本サービスは 2 つの外部要素と連携する。

1. **YP (イエローページ)** — 配信中チャンネルの一覧を `index.txt` で取得する (`lib/yellow_page.rb`)
2. **PeerCast ノード (peercast-mi)** — 視聴用リレーノード。ブラウザが直接ストリームを取得し、Rails は JSON-RPC で再接続を指示する (`lib/json_rpc.rb`)

参考:
- [peercast-mi JSON-RPC API](https://github.com/titagaki/peercast-mi/blob/main/docs/spec/api/jsonrpc.md)
- [peercast-0yp `docs/yp/player.md`](https://github.com/titagaki/peercast-0yp/blob/main/docs/yp/player.md) — `index.txt` の形式

## 環境変数

| 変数 | 用途 | 例 |
| --- | --- | --- |
| `YELLOW_PAGES` | チャンネル一覧を取る YP。`名前=index.txtのURL` を空白区切り | `SP=http://bayonet.ddo.jp:7146/index.txt TP=http://temp.orz.hm:7144/index.txt` |
| `PEERCAST_RPC_URL` | Rails → ノードの JSON-RPC エンドポイント | `http://peercast-mi:7144/api/1` |
| `PEERCAST_BASIC_TOKEN` | 同上の Basic 認証。`base64("user:pass")` をそのまま `Authorization: Basic` に入れる | |
| `PEERCAST_TIP` | **ブラウザ** がストリームを開くノードの公開 `host:port`。レイアウトの `<meta name="peercast-tip">` で渡す | `peca.live:7144` |

`PEERCAST_RPC_URL` と `PEERCAST_TIP` は同じノードを指すが、前者は内部ネットワーク、後者は公開アドレスになるため分けている。

## YP チャンネル一覧 (`lib/yellow_page.rb`)

`YellowPage.fetch_channels` が `YELLOW_PAGES` の各 YP から `index.txt` を取得し、結合して返す。
`Api::V1::ChannelsController#get_channels` で 1 分キャッシュされる。

### 取得

- `HTTPClient#get`、リダイレクト追従、接続 5 秒 / 受信 10 秒タイムアウト
- 200 以外・タイムアウト・接続エラーは空 (その YP のチャンネルは 0 件)。ログに warn を出す
- ボディは UTF-8 として扱い、不正バイトは `scrub`

### `index.txt` のパース

1 行 1 チャンネル、`<>` 区切り 19 項目。空行は飛ばす。項目が足りない行はある分だけ読む (PeerCastStation と同じ)。

| index | 内容 | 出力キー | 変換 |
| --- | --- | --- | --- |
| 0 | チャンネル名 | `name` | HTML デコード |
| 1 | チャンネル ID | `channelId` | 32 桁 hex なら大文字化、それ以外は全ゼロ |
| 2 | tracker `host:port` | `tracker` | HTML デコード |
| 3 | コンタクト URL | `contactUrl` | HTML デコード |
| 4 | ジャンル | `genre` | HTML デコード |
| 5 | 説明 | `description` | HTML デコード (`&lt;Open&gt;` → `<Open>`) |
| 6 | リスナー数 | `listeners` | 整数。非公開は `-1`。整数でなければ `nil` |
| 7 | リレー数 | `relays` | 同上 |
| 8 | ビットレート kbps | `bitrate` | 整数 / `nil` |
| 9 | コンテンツタイプ | `contentType` | HTML デコード |
| 10 | トラック: アーティスト | `creator` | HTML デコード |
| 11 | トラック: アルバム | `album` | HTML デコード |
| 12 | トラック: タイトル | `trackTitle` | HTML デコード |
| 13 | トラック: URL | `trackUrl` | HTML デコード |
| 14 | チャンネル名 (URL エンコード) | — | 未使用 |
| 15 | 配信時間 `H:MM` | `uptime` | `(h*60+m)*60` 秒。`:` が無ければ整数そのまま。不正・空は `nil` |
| 16 | `click` | — | 未使用 |
| 17 | コメント | `comment` | HTML デコード |
| 18 | direct フラグ | — | 未使用 |

さらに `yellowPage` に取得元 YP の名前 (`YELLOW_PAGES` の `名前`) を入れる。フロントはこれが `SP` / `TP` のときアイコンを出し分ける。

出力例 (キーは文字列):

```json
{
  "yellowPage": "SP",
  "name": "A.ch",
  "channelId": "0C1A6C6959CEB2A8BF9598BC9185FF32",
  "tracker": "14.13.42.64:5184",
  "contactUrl": "http://jbbs.shitaraba.net/bbs/read.cgi/game/52685/1567349533/",
  "genre": "PS4",
  "description": "モンスターハンターワールド - <Open>",
  "comment": "",
  "bitrate": 1500,
  "contentType": "FLV",
  "trackTitle": "", "album": "", "creator": "", "trackUrl": "",
  "listeners": 12,
  "relays": 3,
  "uptime": 1234
}
```

- `channelId == "00000000000000000000000000000000"` は YP 自身のエントリ (お知らせ行など)。呼び出し側で除外する
- `listeners` / `relays` / `bitrate` が `nil` の行は `ChannelHistory` の NOT NULL 制約で記録に失敗する (`record_channels` が例外で止まる)。現状の YP は整数を返すので起きていない
- `description` の末尾には YP が付けるリレー状態 `<Open>` `<Free>` `<2M Over>` `<Over>` が付く。表示時に除去する
- `contentType` が `FLV` のものだけブラウザ再生できる

テスト: `spec/lib/yellow_page_spec.rb`

## JSON-RPC クライアント (`lib/json_rpc.rb`)

`JsonRpc.peercast_api` でインスタンスを得る。`Net::HTTP` で `PEERCAST_RPC_URL` に POST する。

```
POST <PEERCAST_RPC_URL>
Authorization: Basic <PEERCAST_BASIC_TOKEN>
Content-Type: application/json

{"jsonrpc":"2.0","id":6412,"method":"<method>","params":[...]}
```

- `id` は固定 `6412`
- 接続 5 秒 / 読み取り 10 秒タイムアウト。接続失敗は例外 (呼び出し側で rescue していない → 500)
- HTTP ステータスが 2xx 以外 (Basic 認証失敗の 401 など) は `JsonRpc::HTTPError`
- レスポンスに `error` があれば `JsonRpc::Error` (`code` を持つ)

### 使用しているメソッド

| メソッド | ラッパ | 用途 |
| --- | --- | --- |
| `stopChannel` `[channelId]` | `stop_channel(channel_id)` | 「再接続(Bump)」。ノードからリレーチャンネルを消す。直後にフロントがリロードして `/stream/?tip=` を開くと新しくリレーが張られる。ノードにチャンネルが無い (`-32603`) 場合は `false` を返して何もしない |

peercast-mi の `bumpChannel` は配信者向け (YP へ bcst 送信) でリレーには効かないため使わない。

## 視聴用ストリーム URL (フロントで組み立て)

`types/Channel.ts`。`peercastTip` はユーザーの設定 (既定は `PEERCAST_TIP`)。

| 用途 | URL |
| --- | --- |
| ブラウザ再生 (flv.js) | `http://<peercastTip>/stream/<streamId>.flv?tip=<tracker>` |
| VLC (FLV) | `rtmp://<peercastTip>/stream/<streamId>.flv?tip=<tracker>` |
| VLC (WMV) | `mms://<peercastTip>/stream/<streamId>.wmv?tip=<tracker>` |
| それ以外の contentType | `null` |

- `?tip=` に配信者の `tracker` を渡すと、ノードが YP を介さず直接接続先を知ることができる
- ノードに未登録のチャンネルへの要求はオンデマンドでリレーを開始する (peercast-mi ADR 0014)。要求元はブラウザ (グローバル IP) なので、peercast-mi 側は `relay_request_from = "any"` が必要 (ADR 0016)
- 登録済みチャンネルへの要求では `tip` は無視される

### 視聴先の既定値 (`types/PeerCast.ts`)

- `<meta name="peercast-tip">` の `host:port` をそのまま既定にする (`defaultHost` / `defaultPortNo`)
- meta が無い・`:` を含まない場合のフォールバックは `150.9.163.29:8144` (旧 PeerCastStation)
- ユーザーは設定ダイアログで上書きでき、`localStorage` の `pecaHost` / `pecaPortNo` に保存される ([frontend.md](frontend.md))

## ポート開放チェック (`lib/peer_cast.rb`)

`PeerCast.port_opened?(host, port_no, timeout_sec = 3)`

1. `TCPSocket.open(host, port_no)`
2. PCP の `helo` パケット `"pcp\x0a\x04\x00\x00\x00\x01\x00\x00\x00helo\x00\x00\x00\x80"` を送信
3. 応答を全読みし、`"oleh"` で始まれば `true`
4. タイムアウト・例外はすべて `false`

`GET /api/v1/channels/check_port` から使う。フロントに UI はない。

## peercast-mi の設定 (`docker/peercast-mi/config.toml`)

| 項目 | 値 | 理由 |
| --- | --- | --- |
| `peercast_port` | 7144 | 視聴・JSON-RPC 共通 |
| `relay_request_from` | `"any"` | ブラウザからの `/stream/?tip=` でリレーを開始させる |
| `max_relay_channels` | 16 | 任意の tip へ接続できる露出を上限で抑える |
| `channel_cleanup_minutes` | 20 | 視聴者ゼロのリレーを自動削除 |
| `admin_user` / `admin_pass` | 要変更 | Rails コンテナは非 localhost なので必須。`PEERCAST_BASIC_TOKEN` と対応させる |
| `[[yp]]` | SP, TP | tip なし要求時の tracker 探索先 (フォールバック) |

`stream_keys.json` は設定ファイルと同じディレクトリに書かれるが、peca-live では使わないため read-only マウントでよい (起動時の読み込み失敗は warn のみ)。
