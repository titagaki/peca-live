# ぺからいぶ！ 仕様書

このディレクトリは、リポジトリのコードを読み解いて書き起こした「現状の仕様」です。
理想の姿ではなく **コードが実際にどう動いているか** を記述しています。
既知の不具合や未使用コードもそのまま「備考」として残しています。

## 目次

| ファイル | 内容 |
| --- | --- |
| [overview.md](overview.md) | システム概要・アーキテクチャ・技術スタック・環境変数・デプロイ |
| [data-model.md](data-model.md) | DBスキーマ・ActiveRecordモデルの仕様 |
| [api.md](api.md) | HTTPエンドポイント（ページ / `api/v1`）の仕様 |
| [peercast-integration.md](peercast-integration.md) | PeerCastStation JSON-RPC 連携・ストリームURL・ポートチェック |
| [channel-visibility.md](channel-visibility.md) | チャンネル一覧の掲載/非掲載ルール・配信履歴・非公開設定 |
| [bbs.md](bbs.md) | コンタクトURL（したらば / jpnkn）からのスレッド・コメント取得仕様 |
| [auth-and-notification.md](auth-and-notification.md) | Firebase(Twitter)ログイン・セッション・お気に入り・Push通知 |
| [scheduled-jobs.md](scheduled-jobs.md) | 定期実行が前提のエンドポイントとキャッシュTTL一覧 |
| [frontend.md](frontend.md) | 画面構成・ルーティング・Reduxステート・各コンポーネントの挙動 |

## 用語

| 用語 | 意味 |
| --- | --- |
| PeerCast / ピアキャス | P2P配信ソフト。本サービスは PeerCastStation を経由してストリームを再生する |
| PeerCastStation | PeerCast の実装のひとつ。JSON-RPC API を持つ。本サービスのバックエンドが接続する |
| TIP | `host:port` 形式の PeerCast 接続先。配信者の tracker や、視聴用の PeerCastStation を指す |
| YP (イエローページ) | チャンネル一覧を配信するインデックスサーバ。`SP` / `TP` がある |
| streamId / channelId | チャンネルを識別する32桁の16進数 |
| コンタクトURL | 配信者が設定する掲示板スレッドURL。コメント表示に使う |
| したらば / jpnkn | 対応している掲示板サービス |
| Bump | PeerCast に対して接続先を再取得させる操作（再接続） |

## 仕様以外のドキュメント

- [../plans/](../plans/) — 移行計画・検討中の作業

## 外部の参照資料

- [peca-docs `docs/protocol/`](https://github.com/titagaki/peca-docs/tree/main/docs/protocol) — PCP プロトコル、YP 登録、視聴・リレー接続の仕様
- [peercast-0yp `docs/`](https://github.com/titagaki/peercast-0yp/tree/main/docs) — YP サーバ側の仕様。`index.txt` の形式は `yp/player.md`
- [peercast-mi `docs/`](https://github.com/titagaki/peercast-mi/tree/main/docs) — 視聴・配信ノードの JSON-RPC 仕様と設計判断
