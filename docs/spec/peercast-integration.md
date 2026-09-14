# PeerCastStation 連携

本サービスは自前でサーバ上に PeerCastStation を常駐させ、それを **YP のインデックス取得・視聴用リレー** の両方に使う。

参考: [PeerCastStation - JSON RPC API メモ](https://github.com/kumaryu/peercaststation/wiki/JSON-RPC-API-%E3%83%A1%E3%83%A2)

## 接続先

- `ENV['PEERCAST_TIP']` = `host:port`（例: `150.9.163.29:7144`）
- JSON-RPC エンドポイント: `http://#{PEERCAST_TIP}/api/1`
- 認証: `Authorization: Basic #{ENV['PEERCAST_BASIC_TOKEN']}`（トークンは Base64 済みの値をそのまま入れる）

## JSON-RPC クライアント (`lib/json_rpc.rb`)

`JsonRpc.peercast_api` でインスタンスを得る。リクエストは **`curl` をバッククォートでシェル実行** して行う。

```
curl -H "Authorization: Basic <token>" \
     -H "X-Requested-With: XMLHttpRequest" \
     -H "Content-Type: application/json" \
     -X POST -d '{"jsonrpc":"2.0","id":6412,"method":"<method>","params":{...}}' \
     http://<tip>/api/1
```

- `id` は固定で `6412`。
- `X-Requested-With: XMLHttpRequest` は PeerCastStation 側の CSRF 対策のために必要。
- レスポンスは `JSON.parse` して `result` を返す。curl が失敗して空文字だと `JSON::ParserError` になる（リトライなし）。
- `params` は JSON 文字列をシングルクォートで囲んで渡すため、値に `'` を含めるとシェル的に壊れる（現状 `channelId` しか渡さないので実害なし）。

### 使用しているメソッド

| メソッド | ラッパ | 用途 |
| --- | --- | --- |
| `getStatus` | `get_status` / `get_peercast_status` | `globalRelayEndPoint` と `uptime` を取り出して `/api/v1/peercast` で返す |
| `updateYPChannels` | `update_yp_channels` | YP からチャンネル一覧を再取得して返す。1 分キャッシュ (`Api::V1::ChannelsController/get_channels`) |
| `bumpChannel` | `bump_channel(channel_id)` | `params: { channelId: }`。再接続 |

### `updateYPChannels` の 1 要素（本サービスが利用するキー）

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

- `channelId == "00000000000000000000000000000000"` は YP 自身のエントリ。すべての処理で除外する。
- `listeners` / `relays` は YP が公開していない場合 `-1`。
- `description` には YP が付与する `<Open>` `<Free>` `<2M Over>` `<Over>` などのリレー状態が末尾に付く。表示時に除去する。
- `contentType` は `FLV` / `WMV` など。ブラウザ再生できるのは `FLV` のみ。

## 視聴用ストリーム URL（フロントで組み立て）

`types/Channel.ts`。`peercastTip` はユーザーの設定（既定はサーバ側 `PEERCAST_TIP` のホスト + ポート `8144`）。

| 用途 | URL |
| --- | --- |
| ブラウザ再生 (flv.js) | `http://<peercastTip>/stream/<streamId>.flv?tip=<tracker>` |
| VLC (FLV) | `rtmp://<peercastTip>/stream/<streamId>.flv?tip=<tracker>` |
| VLC (WMV) | `mms://<peercastTip>/stream/<streamId>.wmv?tip=<tracker>` |
| それ以外の contentType | `null` |

`?tip=` に配信者の `tracker` を渡すことで、視聴用 PeerCastStation が YP を介さず直接接続先を知ることができる。

### 視聴先 PeerCast のデフォルト (`types/PeerCast.ts`)

- ホスト: `<meta name="peercast-tip">` の内容の `:` より前。meta が無ければ `150.9.163.29`。
- ポート: **固定 `8144`**（`PEERCAST_TIP` のポートは JSON-RPC 用で、視聴用ポートとは別と想定）。
- ユーザーは設定ダイアログで上書きでき、`localStorage` の `pecaHost` / `pecaPortNo` に保存される（[frontend.md](frontend.md)）。
  自分の PC で PeerCast を動かしている人が `127.0.0.1:7144` などに向ける用途。

## ポート開放チェック (`lib/peer_cast.rb`)

`PeerCast.port_opened?(host, port_no, timeout_sec = 3)`

1. `TCPSocket.open(host, port_no)`
2. PCP の `helo` パケット `"pcp\x0a\x04\x00\x00\x00\x01\x00\x00\x00helo\x00\x00\x00\x80"` を送信
3. 応答を全読みし、`"oleh"` で始まれば `true`
4. タイムアウト・例外はすべて `false`

`GET /api/v1/channels/check_port` から使う。フロントに UI はない。

## 実験用 rake タスク (`lib/tasks/peercast_station.rake`)

`rake peercast_station:get_channels`: 全 FLV 配信を `rtmpdump` で 10 秒ずつ `channels/<name>.flv` にダンプする。サムネイル生成の試作と思われる。
`JsonRpc.new` を引数 1 つで呼んでおり現在のシグネチャ（2 引数）と合わないため、そのままでは動かない。`flv_dump.rb` も同系統の実験スクリプト。
