export type PeerCastInterface = {
  host: string
  portNo: number
}

class PeerCast {
  // 接続先PeerCastは環境変数 PEERCAST_TIP ("host:port") を meta タグ経由で受け取る。
  // 視聴 (/stream/) と JSON-RPC は同じポートなので、ポートもそのまま使う。
  // meta が無い/読めない場合のみ、下記のフォールバックを使う。
  private static fallbackTip = '150.9.163.29:8144' // shule.peca.live (旧 PeerCastStation)

  private static get defaultTip(): string {
    const meta = document.querySelector('meta[name="peercast-tip"]')
    const tip = meta?.getAttribute('content')
    return tip && tip.includes(':') ? tip : PeerCast.fallbackTip
  }

  static get defaultHost(): string {
    return PeerCast.defaultTip.split(':')[0]
  }

  static get defaultPortNo(): number {
    return parseInt(PeerCast.defaultTip.split(':')[1])
  }

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
