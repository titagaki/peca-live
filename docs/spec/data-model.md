# データモデル

スキーマの正本は `db/ridgepole.rb`。`db/schema.rb` はそこから生成されたもの。
ID 列は PostgreSQL の `bigint` シリアル（ridgepole のデフォルト）。すべてのテーブルに `created_at` / `updated_at` がある。

## ER 図

```
users 1 ──< favorites        (users.uid = favorites.user_id)
users 1 ──< user_devices     (users.uid = user_devices.user_id)

channel_histories   (独立。stream_id で一意)
private_channels    (独立。name で一意)
```

**注意:** `favorites.user_id` / `user_devices.user_id` は `string` 型で、`users.id` ではなく **`users.uid` (Firebase UID)** を格納する前提。
ただし ActiveRecord の `belongs_to :user` / `has_many` は `primary_key` を指定していないため、**`users.id` (整数) と文字列比較する** クエリになる。
詳細は [備考: user_id の不整合](#備考-user_id-の不整合) を参照。

## users

Firebase (Twitter) でログインしたユーザー。

| 列 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| id | bigint | no | PK |
| uid | string | no | Firebase Auth の UID。UNIQUE |
| name | string | no | Firebase の `name` クレーム（Twitter 表示名） |
| photo_url | text | no | Firebase の `picture` クレーム（Twitter アイコン URL） |

- `User.find_or_create_by!(uid:, name:, photo_url:)` で作られる（[auth-and-notification.md](auth-and-notification.md)）。
  `uid` だけでなく `name` / `photo_url` も検索条件に含むため、**Twitter の表示名やアイコンを変えると `uid` が重複した INSERT が走り、UNIQUE 制約で例外になる**。
- `favorite!(channel_name)`: `favorites.find_or_create_by!`
- `favorited?(channel_name)`: 存在チェック
- `has_many :favorites`, `has_many :devices, class_name: 'UserDevice'`

## favorites

ユーザーのお気に入りチャンネル。チャンネルは **名前 (`channel_name`)** で識別する（streamId は配信ごとに変わるため）。

| 列 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| id | bigint | no | PK |
| user_id | string | no | ユーザー識別子（設計上は `users.uid`） |
| channel_name | string | no | チャンネル名 |

- UNIQUE (`user_id`, `channel_name`)
- INDEX (`user_id`)
- `belongs_to :user`

## user_devices

WebPush 通知の送信先デバイス (FCM トークン)。

| 列 | 型 | NULL | 説明 |
| --- | --- | --- | --- |
| id | bigint | no | PK |
| user_id | string | no | ユーザー識別子 |
| token | string | no | FCM registration token |

- INDEX (`user_id`)
- モデル側で `validates :token, uniqueness: { scope: [:user_id] }, presence: true`（DB の UNIQUE 制約はない）
- `belongs_to :user`

## private_channels

配信者が「一覧に掲載しない」と設定したチャンネル。チャンネル名で識別する。

| 列 | 型 | NULL | 既定 | 説明 |
| --- | --- | --- | --- | --- |
| id | bigint | no | | PK |
| name | string | no | | チャンネル名。UNIQUE |
| status | integer | no | 0 | enum: `secret: 0`（非掲載）, `open: 1`（掲載） |

- INDEX (`status`)
- `PrivateChannel.secret?(channel_name)`: `secret` 状態のレコードが存在するか
- レコードが存在しない = 掲載（open と同じ扱い）。トグル仕様は [channel-visibility.md](channel-visibility.md)

## channel_histories

配信履歴。`streamId` ごとに1レコードで、同じ streamId が観測されるたびに上書き更新される（時系列ログではなく「最後に見た状態」）。

| 列 | 型 | NULL | 説明 | 由来 (JSON-RPC の項目) |
| --- | --- | --- | --- | --- |
| id | bigint | no | PK | |
| stream_id | string | no | UNIQUE | `channelId` |
| name | string | no | チャンネル名 | `name` |
| yellow_page | string | no | `SP` / `TP` など | `yellowPage` |
| tracker | string | | 配信者の `host:port` | `tracker` |
| contact_url | string | | 掲示板 URL | `contactUrl` |
| genre | string | | | `genre` |
| description | string | | `<Open>` 等のステータス込み | `description` |
| comment | string | | | `comment` |
| bitrate | integer | no | kbps | `bitrate` |
| content_type | string | | `FLV` / `WMV` など | `contentType` |
| track_title | string | | | `trackTitle` |
| album | string | | | `album` |
| creator | string | | | `creator` |
| track_url | string | | | `trackUrl` |
| listeners | integer | no | 記録時点のリスナー数 | `listeners` |
| relays | integer | no | 記録時点のリレー数 | `relays` |
| uptime | integer | no | 記録時点の配信秒数 | `uptime` |
| latest_lived_at | datetime | no | 最後に観測した時刻 (`Time.zone.now`, JST) | |

### バリデーション

`stream_id`(一意・必須), `name`, `listeners`, `relays`, `uptime`, `latest_lived_at`, `yellow_page` が必須。

### スコープ / メソッド

| 名前 | 仕様 |
| --- | --- |
| `broadcast_from(ip)` | `tracker LIKE 'ip%' OR creator LIKE 'ip%'`。指定 IP から配信された履歴。前方一致なので `1.2.3.4` は `1.2.3.45` にもマッチする |
| `record_channels(channels)` | 配列の各要素に `record_channel` |
| `record_channel(channel)` | `stream_id` で `find_by` → あれば `update!`、なければ `create!`。`latest_lived_at` は常に現在時刻 |
| `#description_no_status` | `description` から `<Open>` `<Free>` `<2M Over>` `<Over>` とその直前の ` - ` を除去 |
| `#detail` | `"#{genre} - #{description_no_status}"`。どちらかが空ならセパレータなし。SEO 用 meta description に使う |

## 備考: user_id の不整合

- `favorites.user_id`, `user_devices.user_id` は文字列で、`User#favorites` / `User#devices` を通して作られる。
  `has_many` はデフォルトで `users.id` を外部キー値として使うため、実際に格納される値は **`users.id` の文字列表現**（例: `"12"`）になる。
- 一方 `Api::V1::UserDevicesController#create` は `User.find(uid: ...)` としており、これは `find` の使い方として誤りで動作しない（かつルーティングもされていない）。
- 現状の動作は「`user_id` に `users.id` の文字列が入る」で一貫しているため、UID 前提の名前と食い違うがサービスとしては壊れていない。
