# 定期実行とキャッシュ

Rails アプリ内に cron / ジョブキューはない（`ApplicationJob` は空）。
代わりに **GET エンドポイントを外部から定期的に叩く** 設計になっている。Docker 構成では `scheduler` サービス（`docker/scheduler/run.sh`）が `web` のヘルスチェック成功後、10 分ごと（`INTERVAL_SEC`）に curl する。
どちらも認証なしで誰でも叩けるが、冪等になるようキャッシュで制御している。

## 定期実行エンドポイント

| エンドポイント | 想定間隔 | 処理 | 冪等性 |
| --- | --- | --- | --- |
| `GET /api/v1/channels/record_history` | 10 分 | YP の全チャンネル（YP エントリ除く）を `ChannelHistory` に upsert | `stream_id` で upsert |
| `GET /api/v1/channels/notification_broadcasting` | 10 分 | 30 分以内に始まった掲載中チャンネルについて、お気に入りユーザーへ Push | `channelId` ごとに 30 分キャッシュで 1 回のみ |

### 実行間隔と通知の整合

```
配信開始 t=0
  |----10min----|----10min----|----10min----|
  ^ 実行1        ^ 実行2        ^ 実行3        ^ 実行4 (uptime>=30min で対象外)
  送信 (cache set)  cache hit    cache hit
```

- 間隔が 30 分を超えると対象を取りこぼす。
- 間隔が短くてもキャッシュで重複しない（同一プロセス/ファイルストア内に限る）。
- `uptime` は YP 側の値で、`fetch_channels` の 1 分キャッシュ分ずれる。

## Rails.cache のキー一覧

`cache_store` は未設定（Rails デフォルト）。本番ではファイルストア (`tmp/cache`) で、コンテナ再起動で消える・コンテナ間で共有されない。

| キー | TTL | 内容 | 使用箇所 |
| --- | --- | --- | --- |
| `Api::V1::ChannelsController/get_channels` | 1 分 | 全 YP の `index.txt` を整形した結果 | `record_history`, `fetch_channels` |
| `Api::V1::ChannelsController/fetch_channels` | 1 分 | 上記から非掲載を除いた一覧 | `/api/v1/channels`, `notification_broadcasting` |
| `notification_broadcasting/<channelId>` | 30 分 | 通知送信済みマーカー（値は curl の出力） | `notification_broadcasting` |
| `api/v1/bbs?url=<url>/v2` | 1 日 | 板のタイトル・トップ画像 | `/api/v1/bbs` |
| `api/v1/bbs/threads?url=<url>/v1` | 10 秒 | スレッド一覧 | `/api/v1/bbs/threads` |
| `api/v1/bbs/comments?url=<url>/v1` | 10 秒 | コメント | `/api/v1/bbs/comments` |
| `extract_twitter_id/<jpnkn_id>` | 1 日 | jpnkn 板から抽出した Twitter ID | `UserIconsController`（無効化中） |
| `twitter_profile_image_url(<twitter_id>)` | 1 日 | unavatar の URL | 同上 |

`fetch_channels` はキャッシュされた配列の各ハッシュに `favorited` を書き込む。ファイルストアでは読み出しごとにデシリアライズされるため問題ないが、メモリストアに変えるとログインユーザーの `favorited` が他ユーザーへ漏れる。

## フロント側のポーリング

| 対象 | 間隔 | 場所 |
| --- | --- | --- |
| `/api/v1/channels` | 10 秒（コメントは「1 分」だが実装は `10000ms`） | `app.tsx` |
| `/api/v1/bbs/comments` | 10 秒 | `Comments.tsx` |
| `/api/v1/channels/broadcasting` | 設定ダイアログを開くたび / トグルのたび | `SettingDialog.tsx` |

サーバ側の 1 分キャッシュがあるため、チャンネル一覧の実質的な更新頻度は 1 分。
