# 認証・お気に入り・Push 通知

## ログインフロー

Twitter アカウントで Firebase Authentication にサインインし、その ID トークンを Rails に渡してセッションを張る。

```
[ブラウザ]                                  [Rails]                        [Google]
 1. firebaseui (Twitter popup) でサインイン
 2. onAuthStateChanged(user)
 3. user.getIdToken(true) ─────────────────────────────────────────────▶ 新しい ID トークン
 4. POST /api/v1/accounts
      Authorization: Bearer <idToken>
      X-CSRF-TOKEN: <meta csrf-token>   ──▶ 5. FirebaseHelper::Auth.verify_id_token
                                              - JWT を検証なしデコードして kid を取得
                                              - Google の x509 公開鍵一覧を取得 ────▶ CLIENT_CERT_URL
                                              - RS256 で署名検証 (verify_iat)
                                           6. User.find_or_create_by!(uid, name, photo_url)
                                           7. session[:uid] = uid
 8. Redux user を更新 (uid, displayName, photoURL)
 9. /api/v1/channels を再取得 (favorited を反映)
```

### フロント (`app.tsx`, `SignInScreen.tsx`, `LoginDialog.tsx`)

- Firebase 設定: `firebase/config.ts`（プロジェクト `peca-live`）。`firebase/auth` のみ import。
- firebaseui の設定: `signInFlow: 'popup'`, `signInSuccessUrl: '/'`, プロバイダは **Twitter のみ**。
- `onAuthStateChanged` は **ログアウト時 (`user == null`) を考慮していない**。`user.getIdToken` で `TypeError` が投げられる（`.catch` は Promise 用なので拾えない）。実害はコンソールエラーのみ。
- ログアウト: `firebase.auth().signOut()` + Redux `signOutUser`。**Rails の `/api/v1/accounts/sign_out` は呼ばない**ため、Rails セッションはブラウザを閉じるか Cookie が消えるまで残る。
  再読込すると `onAuthStateChanged` が発火せず Redux 上は未ログインだが、`/api/v1/channels` には `favorited` が付いたままになる。

### サーバ (`Api::V1::AccountsController`, `FirebaseHelper::Auth`, `SessionsHelper`)

- 既に `current_user` がいれば何もしない（トークンを再検証しない）。
- `authenticate_with_http_token` で Bearer トークンを取り出す。無ければ何もせず 204。
- `verify_id_token`:
  1. `JWT.decode(token, nil, false)` でヘッダの `kid` を取得
  2. `https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com` から公開鍵一覧を **毎回** 取得（キャッシュなし）
  3. `kid` に対応する証明書で `JWT.decode(token, public_key, true, algorithm: 'RS256', verify_iat: true)`
  4. `{ 'uid' => payload['sub'], 'decoded_token' => { payload:, header: } }` を返す
  - `aud` / `iss` の検証 (`validate`) はコメントアウトされており **実行されない**。`FirebaseHelper::CONFIG` も未定義。
  - 期限切れは `JWT::ExpiredSignature` → `RuntimeError`（500）。
- ユーザー作成: `User.find_or_create_by!(uid:, name: payload['name'], photo_url: payload['picture'])`。
  `name` / `photo_url` も一致条件に入るため、Twitter 側で表示名やアイコンを変更すると `uid` UNIQUE 違反で 500 になる（[data-model.md](data-model.md)）。
- `pp uid:, name:, photo_url:` でログに出力している。
- セッション: `session[:uid]`。`current_user` は `User.find_by(uid:)` をリクエスト内でメモ化。
- `SessionsHelper` には `store_location` / `redirect_back_or` / `logged_in_user` もあるが未使用（`login_url` は存在しない）。

## お気に入り

- チャンネル名単位で登録（`favorites.channel_name`）。streamId は配信ごとに変わるため名前で紐づける。
- 登録/解除 UI はプレイヤーのコントロールバーのハートアイコン（`Video.tsx`）。未ログインならログインダイアログを開く。
- API: `POST /api/v1/favorites` / `DELETE /api/v1/favorites`（body `channel_name=`）。完了後 `/api/v1/channels` を再取得して表示に反映。
- 一覧側の反映: `/api/v1/channels` の各要素に `favorited` が付き、フロントのソートで **お気に入りが上、その中で uptime 昇順**。
- `GET /api/v1/favorites` は起動時に 1 回取得して Redux `favorites` に入れるが、**現在の UI ではこのステートを参照していない**（`favorited` フラグで足りている）。

## Push 通知（WebPush / FCM）

お気に入りチャンネルの配信開始を通知する。送信は FCM **legacy HTTP API** (`https://fcm.googleapis.com/fcm/send`) を `curl` で叩く。

### デバイス登録

1. AppBar のベルアイコン（iOS 以外で表示）。未ログインならログインダイアログ、ログイン済みなら **外部サイト `https://peca-live.netlify.app/` へ遷移**。
   このサイト（本リポジトリ外）が Service Worker と FCM トークン取得を担当し、`http://peca.live/user_devices?token=<fcmToken>` に戻す想定。
2. `GET /user_devices?token=`（`HomeController#user_devices`）:
   - ログイン中かつ `token` あり → `current_user.devices.create(token:)`（重複トークンはバリデーションで無視され、`create` なので例外にならない）
   - そのユーザーの **全デバイス** に「お気に入り配信を通知します！ / by ぺからいぶ！ / url: http://peca.live/」を送る
   - `/` へリダイレクト

### 配信開始通知 (`GET /api/v1/channels/notification_broadcasting`)

外部から 10 分ごとに叩く前提。詳細は [scheduled-jobs.md](scheduled-jobs.md)。

- 対象: 掲載中チャンネルのうち `uptime < 30 * 60`（30 分以内に開始）。
- `Rails.cache.fetch("notification_broadcasting/#{channelId}", expires_in: 30.minute)` で **channelId ごとに 1 回だけ** 送信。
  「10 分間隔の実行 + 30 分以内の配信 + 30 分キャッシュ」で漏れと重複を防ぐ設計。
- 送信先: `Favorite.where(channel_name:)` → 各ユーザーの `devices.token`。
- 通知内容 (`data` メッセージ):

| キー | 値 |
| --- | --- |
| `title` | `"<channel_name> の 配信がはじまった！"` |
| `body` | `genre` + ` - ` + `description`（ステータス除去済み）。どちらか空なら区切りなし |
| `icon` | `pecalive.png` |
| `badge` | `favicon.png` |
| `url` | `http://peca.live/channels/<channelId>?utm_medium=push`（→ `/:name` へリダイレクト） |

- 実装は `Api::V1::ChannelsController#notify_broadcasting` 内で `curl` を直接組み立てている。`lib/notification_push.rb` の `NotificationPush#notify_broadcasting` にほぼ同じ実装があるが、こちらはコントローラからは使われていない（`HomeController#user_devices` が `NotificationPush#notify` だけ使う）。
  なお `NotificationPush#notify_broadcasting` は `map` を使っているため `send_tos` が二次元配列になり、そのまま使うと壊れる（`flat_map` が正）。
- `title` / `body` を JSON にシェルのシングルクォート内で埋め込むため、チャンネル名や説明に `'` や `"` が含まれると curl が失敗するか JSON が壊れる。
- FCM legacy API のサーバキーがソースにハードコードされている。
- キャッシュがファイルストアなので、複数 dyno 構成では dyno ごとに重複送信されうる。
