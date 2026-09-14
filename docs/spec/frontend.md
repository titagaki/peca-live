# フロントエンド仕様

`app/javascript/packs/` 以下。React 16 + Redux Toolkit + Material-UI v4 + TypeScript。
Rails のレイアウトが `application.js`（UJS / Turbolinks / ActionCable のボイラープレート）を読み、`home/index.html.erb` が `pecalive` パックを読み込んで React を `<body>` 直下の `<div>` にマウントする。

## 起動シーケンス (`pecalive.tsx` → `app.tsx`)

1. `DOMContentLoaded` で Redux store を作り `<App />` をマウント。
2. `App` の `useEffect`（初回のみ）:
   1. `localStorage` の `pecaHost` / `pecaPortNo` から視聴先 PeerCast を復元（無ければ `PeerCast.defaultHost` / `defaultPortNo`）。
   2. `/api/v1/channels` と `/api/v1/favorites` を取得。
   3. `setInterval` で **10 秒ごと** に `/api/v1/channels` を再取得（コメントには「1 分」とあるが実装は 10 秒）。
   4. `firebase.auth().onAuthStateChanged` を登録 → ログイン時は ID トークンで `POST /api/v1/accounts`、完了後にチャンネル再取得（`favorited` 反映）、Redux `user` を更新。

## ルーティング (`react-router-dom`, `BrowserRouter`)

| パス | コンポーネント | 備考 |
| --- | --- | --- |
| `/` | `ChannelList` | チャンネル一覧（カード） |
| `/:channelName` | `ChannelPlayer` | `isHls={isIOS}`, `local={false}`。幅 `min(800, innerWidth)`、高さ `innerHeight - 64` |

- `/hls/:channelName`, `/local/:channelName` はコメントアウト（HLS 再生は未実装）。
- `PageViewTracker` が全ルートを包み、パス変更のたびに Google Analytics へ pageview を送る。
- Rails 側も `/:channel_name` を SPA として返すので、直リンク・リロードでも動作する。

## レイアウト (`app.tsx`)

```
+------------------------------------------------------------+
| PecaLiveAppBar (fixed, 高さ 64)                             |
| [≡] [ロゴ]                          [🔔] [⚙] [ログイン/Avatar] |
+-------------+----------------------------------------------+
| SideBar     | main                                          |
| (Drawer)    |   / → ChannelList                             |
|  リスナーが多い |   /:name → ChannelPlayer                       |
|  最近はじまった |                                              |
|  とは？      |                                              |
|  連絡先      |                                              |
+-------------+----------------------------------------------+
```

- PC (`!isMobile`): Drawer は `permanent`、幅 290px。
- モバイル (`isMobile`): Drawer は `temporary`、幅は画面幅の 80%。AppBar の ≡ で開閉。`keepMounted` で再マウントを避ける。
- ページ背景 `#F5F5F5`。

## Redux ステート (`modules/`, `store.ts`)

`configureStore` + `combineReducers`。devTools 有効。各 slice の reducer は payload で state を丸ごと置き換えるだけ。

| slice | 型 | 初期値 | 更新関数 | selector（クラスにラップして返す） |
| --- | --- | --- | --- | --- |
| `channels` | `ChannelInterface[]` | `[]` | `updateChannels(dispatch)`: `/api/v1/channels` を取得しソートして set | `useSelectorChannels()` → `Channel[]` |
| `favorites` | `FavoriteInterface[]` | `[]` | `updateFavorites(dispatch)`: `/api/v1/favorites` | `useSelectorFavorites()` → `Favorite[]`（未使用） |
| `peercast` | `{ host, portNo }` | `defaultHost`, `defaultPortNo` | `updatePeerCast(dispatch, host, portNo)` | `useSelectorPeerCast()` → `PeerCast` |
| `user` | `{ uid, displayName, photoURL }` | すべて `null` | `updateUser(...)`, `signOutUser(dispatch)` | `useSelectorUser()` → `User`（`isLogin = !!uid`） |
| `dialog` | `{ currentAboutPage }` | `localStorage.aboutVersion === '3'` なら `-1`、それ以外 `0` | `openAboutPage(dispatch)` (=0), `setAboutPage(dispatch, n)` | `useSelectorDialog()` → `Dialog` |

### チャンネルのソート順 (`updateChannels`)

```
お気に入り (favorited=true) が先
同じ favorited 同士は uptime 昇順（最近始まった配信が上）
```

`favorited` が未定義（未ログイン）のときは `undefined == undefined` で同値扱いとなり uptime 昇順のみ。

## ドメインクラス (`types/`)

### `Channel` (`types/Channel.ts`)

API の JSON をラップする getter 群。主要な派生プロパティ:

| プロパティ | 仕様 |
| --- | --- |
| `streamId` | `channelId` |
| `tip` | `tracker` |
| `isSp` / `isTp` | `yellowPage === 'SP'` / `'TP'` |
| `ypIconUrl` | SP → `/images/yp-sp.png`、TP → `/images/yp-tp.png`、他 → `/images/mouneyou.png`。jpnkn ID から `/user_icons/:id` を使う分岐は無効化中 |
| `jpnknId` | `contactUrl` が `bbs.jpnkn.com/<id>/` または `bbs.jpnkn.com/test/read.cgi/<id>/<n>/` のとき `<id>` |
| `startingTime` | `uptime` から「N分前」「N時間前」「N日前」。分は `uptime/60` をそのまま表示（**小数が出る**）。時間・日は `Math.round` |
| `isFlv` / `isWmv` | `contentType` |
| `compactGenre` | `genre` から `game`（大小無視）と全角/半角スペース・`-` を除去 |
| `detailsLabel` | `description` から `<Open>` 等を除去（各 1 回 `replace`）し、`comment` があれば末尾に付加 |
| `compactDetails` | `compactGenre + detailsLabel`（サイドバー用、区切りなし） |
| `explanation` | `compactGenre` と HTML アンエスケープした `detailsLabel` を ` - ` で連結 |
| `flvStreamUrl(tip)` / `vlcStreamUrl(tip)` | [peercast-integration.md](peercast-integration.md) |
| `equal(other)` | 全フィールド比較（`ChannelPlayer` で差分更新に使う） |
| `Channel.nullObject(name)` | `streamId` 空・`listeners: -1` のプレースホルダ。「取得中」「配信は終了しました」表示に使う |

### `PeerCast` (`types/PeerCast.ts`)

- `defaultHost` / `defaultPortNo`: `<meta name="peercast-tip">` の `host:port` を分解したもの。meta が無い・`:` を含まない場合は `150.9.163.29:8144`。
- `tip`: `host:portNo`。

### `Dialog` (`types/Dialog.ts`)

- `CurrentAboutVersion = '3'`。この値を上げると、全ユーザーに「ぺからいぶ！とは」ダイアログが初回表示される。

## コンポーネント

### `PecaLiveAppBar`

- ロゴ (`/images/pecalive.png`) → `/`。
- ≡ ボタン: `sm` 以上では非表示。モバイルで Drawer を開く。
- 🔔 (`NotificationsActiveIcon`): **iOS では非表示**（WebPush 非対応のため）。ログイン済みなら `https://peca-live.netlify.app/` へ遷移、未ログインならログインダイアログ。
- ⚙: `SettingDialog` を開く。
- PC のみ: ログイン済みなら Twitter アイコンの Avatar（クリックでログアウト用ダイアログ）、未ログインなら「ログイン」ボタン。モバイルではログインボタンが無く、お気に入りボタンからログインダイアログを開くしかない。

### `SideBar`

- `About`（初回ダイアログ）を内包。
- モバイルのみ先頭に ≡ + ロゴの行（クリックで閉じる）。
- 「リスナーが多い」: `listenerCount` 降順の上位 4 件。
- 「最近はじまった」: `uptime` 昇順の上位 4 件。右側に `startingTime` から「前」を除いた文字列。
- 各項目: YP アイコン（赤い dot バッジ付き）、名前、`compactDetails`（1 行省略）。ホバーで `explanation` と視聴者数/開始時刻のツールチップ。クリックで `/:name` へ遷移し、モバイルでは Drawer を閉じる。
- `hotChannels` と `newChannels` は同じ配列 `dup` を **その場でソート** するため、`hotChannels` の `slice` 後に `newChannels` の `sort` が走っても結果には影響しない（slice 済み）が、意図的な設計ではない。
- 末尾: 「ぺからいぶ！ とは？」（About を再表示）、「ご連絡は @shule517 まで！」(Twitter リンク)。

### `About`

3 ページ構成のダイアログ。`dialog.currentAboutPage` が `0`/`1`/`2` のときそれぞれのページを表示。

| ページ | タイトル |
| --- | --- |
| 0 | ぺからいぶ！とは |
| 1 | 作りはじめたきっかけ |
| 2 | PeerCast FOREVER |

- ボタンで `currentAboutPage + 1`。ページ 1 以降を閉じたときに `localStorage.aboutVersion = CurrentAboutVersion` を保存し、次回以降は表示しない（`-1`）。
- 途中でダイアログ外をクリックしても同じ `handleClose` が走る。

### `ChannelList` (`/`)

- Redux の `channels` をそのままカード表示（ソートは `updateChannels` 済み）。
- カード: YP アイコン + 視聴者数、チャンネル名 (h5)、`explanation`、右上にハート（`favorited` で塗り/枠）、右下に `startingTime`。
- カードは `Link` で `/:name` へ。`Fade` で表示。
- `Helmet` の description は「このページはGastbyサンプルです。」のまま（ボイラープレート残り）。
- `ChannelItem.tsx` はサムネイル付きの別デザインだが **未使用**。

### `ChannelPlayer` (`/:channelName`)

- Redux `channels` から `name === channelName` を探す。
  - 見つからず `channels` が空 → `nullObject('チャンネル情報を取得中...')`
  - 見つからず `channels` あり → `nullObject('<name> の 配信は終了しました。')`
- チャンネルが切り替わったとき:
  - 前後のチャンネル URL を計算（配列上の隣。端は循環）。
  - `topImageUrl` をリセットし、`contactUrl` があれば `/api/v1/bbs` で板のトップ画像を取得。
- 同じチャンネルで内容だけ変わったとき（`!channel.equal(fetchChannel)`）は state を差し替える。
- 表示: `Helmet`（title/description/og）、`Video`、チャンネル詳細（アイコン、名前、「N人が視聴中 - N分前から」、`explanation`）、`Comments`、コンタクト URL リンク、板トップ画像、WMV の場合は「※WMV配信のためVLCで再生してください。」
- 「再接続(Bump)」: `GET /api/v1/channels/bump?streamId=` を投げて **待たずに** `location.reload()`。

### `Video`

flv.js による再生とカスタムコントロール。

- `useEffect`（依存配列なし = 毎レンダー）で、`streamId` があり非 HLS のとき `flvStreamUrl(peercast.tip)` が前回と異なれば既存プレイヤーを破棄して `FlvJs.createPlayer({ type: 'flv', isLive: true, url })` → `attachMediaElement` → `load` → `play`。
  - `media_info` イベントで動画の実サイズを取り、幅 `min(screen.width, 800)`、高さはアスペクト比から算出（CSS で最大 800×500）。
  - `readyState` を `onplaying` / `onwaiting` で追い、`< 3` の間はスピナー表示。
- HLS (`isHls = isIOS`) のときは flv.js を使わず、再生ボタンを表示。
- クリック挙動:
  - iOS または非 FLV: `location.href = vlcStreamUrl` で VLC を起動（`null` になる contentType だと `"null"` へ遷移）。
  - それ以外: コントロールの表示/非表示をトグル。マウスホバーでも表示。
- コントロール（左）: 前の配信 / 再生 / 次の配信 / 再接続(Bump) / お気に入り（ハート）。iOS では再生・Bump 非表示。
- コントロール（右）: PC のみ音量スライダー（縦）とミュート、Picture-in-Picture（対応ブラウザのみ）、フルスクリーン（iOS 以外）。
- お気に入りボタン: ログイン済みなら `POST`/`DELETE /api/v1/favorites`（form-urlencoded、CSRF ヘッダ）→ `updateChannels`。未ログインなら `LoginDialog`。
- `player.unload()` 等の破棄はチャンネル切替時のみで、コンポーネントのアンマウント時には行わない（一覧に戻ってもストリームを掴んだままになりうる）。

### `Comments`

[bbs.md](bbs.md#フロント側の表示ロジック-componentscommentstsx) を参照。

### `SettingDialog`

「設定」ダイアログ。開くたびに `/api/v1/channels/broadcasting` を取得。

- 「接続先のPeerCast」: IP とポート番号のテキストフィールド。
  - 保存: Redux `peercast` を更新し `localStorage.pecaHost` / `pecaPortNo` に保存（ダイアログを閉じてから）。
  - デフォルトに戻す: `defaultHost` / `defaultPortNo` に戻し `localStorage` を削除。
  - ポートは `parseInt`。数値以外を入れると `NaN`。
- 「配信の掲載」: 案内文「掲載しない場合は、配信のチャンネル詳細に「__」（アンダーバー２つ）を含めてください。」の下に、自 IP からの配信履歴ごとにスイッチ「『<name>』を掲載する」。
  - `checked = !channel.private`。変更で `GET /api/v1/channels/private/<name>` を投げ、`isPrivate` を反転させて `useEffect` を再実行 → 一覧を再取得。
  - 履歴が無ければ「このIPからの配信履歴はありません。配信者と同じIPの端末から設定が変更できます。」

### `LoginDialog` / `SignInScreen`

- 未ログイン: タイトル「ログインしてもっと便利に！」、メリット 2 点（お気に入り共有・配信開始通知）、firebaseui の Twitter ボタン。
- ログイン済み: タイトル「ログイン」、「ログアウト」ボタン（Firebase サインアウト + Redux クリア。Rails セッションは残る）。

### `PageViewTracker`

`ReactGA.initialize('UA-46281082-3')` を初回に実行し、毎レンダーで `pageview(location.pathname)`。

## localStorage キー

| キー | 用途 |
| --- | --- |
| `pecaHost` | 視聴先 PeerCast ホスト |
| `pecaPortNo` | 視聴先 PeerCast ポート |
| `aboutVersion` | About ダイアログを見たバージョン (`'3'`) |

## 端末別の挙動まとめ

| | PC | Android 等 (`isMobile`) | iOS (`isIOS`) |
| --- | --- | --- | --- |
| サイドバー | 常時表示 | Drawer | Drawer |
| 再生 | flv.js | flv.js | VLC へハンドオフ（HLS は未実装） |
| 音量/ミュート | あり | なし | なし |
| 通知ボタン | あり | あり | なし |
| ログインボタン (AppBar) | あり | なし | なし |
| フルスクリーン | あり | あり | なし |
