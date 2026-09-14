# チャンネル一覧の掲載ルール・配信履歴・非公開設定

## 一覧に載る条件 (`Api::V1::ChannelsController#visible_channel?`)

YP の `index.txt` から取得した一覧 (`YellowPage.fetch_channels`) から、次のいずれかに該当するチャンネルを **除外** する。

| 条件 | 判定 |
| --- | --- |
| YP 自身のエントリ | `channelId == "00000000000000000000000000000000"` |
| 配信者が非掲載に設定 | `PrivateChannel.secret.pluck(:name)` に `name` が含まれる |
| 「隠し」マーカー | `description + comment + trackTitle + album + creator + trackUrl` を連結した文字列に `__`（アンダーバー 2 つ）が含まれる |

`__` マーカーは配信者側が PeerCast の配信設定に書くだけで済む、アカウント不要の非掲載手段。設定ダイアログにも案内文がある。
`genre` と `name` はマーカー判定の対象外。

この結果は `Rails.cache` に 1 分キャッシュされ (`Api::V1::ChannelsController/fetch_channels`)、`/api/v1/channels` と `notification_broadcasting` が共有する。

## 配信履歴 (`ChannelHistory`)

- `GET /api/v1/channels/record_history` を定期的（10 分ごと想定）に叩くことで記録される。
- 記録対象は YP エントリを除いた **全チャンネル**（非掲載設定や `__` マーカーのものも含む）。
- `stream_id` ごとに 1 行。同じ配信を見るたびに `listeners` / `uptime` 等を上書きし、`latest_lived_at` を更新する。
- 用途:
  - `/:channel_name` の OGP タイトル・説明（最新の `latest_lived_at` の行）
  - `/channels/:stream_id` → `/:name` へのリダイレクト（Push 通知のリンク）
  - 「この IP からの配信」の判定（`broadcast_from`）

## 「配信の掲載」トグル（非公開設定）

設定ダイアログの「配信の掲載」セクション。ログイン不要で、**リクエスト元 IP が配信者の IP と一致すること** を認可の根拠にする。

### 一覧取得: `GET /api/v1/channels/broadcasting`

```
ip = X-Forwarded-For の先頭 || request.ip
ChannelHistory.broadcast_from(ip)          # tracker LIKE 'ip%' OR creator LIKE 'ip%'
→ [{ channelId, name, private: PrivateChannel.secret?(name) }]
```

- 過去に一度でも `record_history` で記録された配信が対象。履歴が無ければ空配列で「このIPからの配信履歴はありません。」と表示される。
- `LIKE 'ip%'` の前方一致のため、IP が別 IP のプレフィックスになる場合（`10.0.0.1` と `10.0.0.12` など）に誤マッチする。
- 同じ IP を共有する環境（同一 NAT 配下）の別人からも操作できる。

### トグル: `GET /api/v1/channels/private/:channel_name`

```
ip から channel_name を配信した履歴がない → 403
PrivateChannel.find_by(name)
  あり: secret → open / open → secret  （反転）
  なし: secret で作成               （非掲載にする）
→ 200
```

- UI 上は「『<name>』を掲載する」スイッチ。`checked = !channel.private`。
- 状態遷移:

```
(レコードなし = 掲載中) ──toggle──▶ secret (非掲載) ──toggle──▶ open (掲載中) ──toggle──▶ secret ...
```

- 反映は最長 1 分後（`fetch_channels` キャッシュ）。フロントは `/api/v1/channels/broadcasting` を再取得してスイッチ表示だけ即時更新する。
- `DELETE` ルートもあるが `destroy` アクションは未実装。

## `description` のステータス除去

YP は `description` の末尾に ` - <Open>` などを付ける。表示・通知では次を除去する。

| 実装 | 対象 |
| --- | --- |
| `ChannelHistory#description_no_status` | 正規表現 `/[ -]*<(Open|Free|2M Over|Over)>/` |
| `Api::V1::ChannelsController#notify_broadcasting`, `NotificationPush#notify_broadcasting` | ` - <Open>`, `<Open>`, ` - <Free>`, `<Free>`, ` - <2M Over>`, `<2M Over>`, ` - <Over>`, `<Over>` を順に `gsub` |
| `Channel#detailsLabel` (フロント) | 同上を `replace`（最初の 1 箇所のみ） |
