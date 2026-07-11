export type PeerCastInterface = {
  host: string
  portNo: number
}

class PeerCast {
  // 接続先PeerCastのIPは環境変数 PEERCAST_TIP を meta タグ経由で受け取る。
  // meta が無い/読めない場合のみ、下記のフォールバックIPを使う。
  // ※ポートは PEERCAST_TIP のポート(config)とは用途が異なるため共有せず、固定値を使う。
  private static fallbackHost = '150.9.163.29' // shule.peca.live

  static get defaultHost() {
    const meta = document.querySelector('meta[name="peercast-tip"]')
    // PEERCAST_TIP は "host:port" 形式。ホスト部分だけ利用する。
    const host = meta?.getAttribute('content')?.split(':')[0]
    return host || PeerCast.fallbackHost
  }

  static defaultPortNo = 8144

  constructor(public json: PeerCastInterface) {}

  get host() {
    return this.json.host
  }

  get portNo() {
    return this.json.portNo
  }

  get tip() {
    return `${this.host}:${this.portNo}`
  }
}

export default PeerCast
