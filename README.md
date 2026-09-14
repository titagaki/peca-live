![ぺからいぶ！](http://peca.live/images/pecalive.png)

[http://peca.live/](http://peca.live/)
=======================================================

## ぺからいぶ！をつくりだした きっかけ
「限界集落」と呼ばれだして早５年以上が経ちました。<br>
Youtube Liveや、Twitchなど お手軽にゲーム配信ができるサービスが増えました。<br>
そして、配信以外にも Youtube、Netflix、amazon prime videoなどの強敵も登場！<br>

僕も気がついたら、Youtubeばっかり見てました。。。<br>
ぴあきゃすは好きなんだけど、なんとなく離れていってしまう。<br>
あいつらみたいに「お手軽さ」がないとやっていけない時代になってきたんだと思う。<br>
![さみしい](https://pbs.twimg.com/media/EYw0426U4AATCW1?format=jpg&name=small)

## 環境設定
環境変数に設定しておくこと (`example.env` 参照)
- PEERCAST_TIP — ブラウザが動画を取りに行く PeerCast ノードの公開アドレス (host:port)
- PEERCAST_RPC_URL — Rails から PeerCast ノードへの JSON-RPC 接続先
- PEERCAST_BASIC_TOKEN — 上記の Basic 認証 (base64("user:pass"))
- YELLOW_PAGES — チャンネル一覧を取得する YP (「名前=index.txtのURL」を空白区切り)

## 開発環境の準備
```
$ git clone git@github.com:shule517/pecalive.git
$ cd pecalive
$ bundle
$ cp example.env .env
$ yarn install
$ yarn start
```
## Docker で動かす
Rails + PostgreSQL + [peercast-mi](https://github.com/titagaki/peercast-mi) (視聴用ノード) + 定期実行をまとめて起動する。

```
$ cp example.env .env                      # PEERCAST_TIP, SECRET_KEY_BASE, YELLOW_PAGES などを設定
$ vi docker/peercast-mi/config.toml        # admin_user / admin_pass を変更し、.env の PEERCAST_BASIC_TOKEN に base64("user:pass") を設定
$ PEERCAST_MI_CONTEXT=../go/peercast-mi docker compose build   # peercast-mi のクローン先を指定
$ docker compose run --rm web bundle exec rake ridgepole:apply  # 初回のみ: スキーマ適用
$ docker compose up -d
```

- `web`: http://localhost/ (`WEB_PORT` で変更可)
- `peercast-mi`: 7144 を公開 (ブラウザが直接つなぐので HTTP のまま)。`PEERCAST_TIP` にはこのポートの公開アドレスを設定する
- `scheduler`: 10 分ごとに配信履歴の記録と配信開始通知を叩く

## 資料
- [docs/spec/](docs/spec/README.md) — 仕様書
- [docs/plans/](docs/plans/) — 移行計画
- [peercast-mi JSON-RPC API](https://github.com/titagaki/peercast-mi/blob/main/docs/spec/api/jsonrpc.md)
