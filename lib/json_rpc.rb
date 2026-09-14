require 'net/http'
require 'json'

# PeerCast ノード (peercast-mi) の JSON-RPC クライアント
class JsonRpc
  OPEN_TIMEOUT_SEC = 5
  READ_TIMEOUT_SEC = 10

  # JSON-RPC の error レスポンス
  class Error < StandardError
    attr_reader :code

    def initialize(method_name, error)
      @code = error['code']
      super("JSON-RPC #{method_name} failed: #{error}")
    end
  end

  # 401 (Basic 認証失敗) など、JSON-RPC まで届かなかった応答
  class HTTPError < StandardError; end

  ERROR_CODE_INTERNAL = -32603 # チャンネル未発見など

  def self.peercast_api
    JsonRpc.new(ENV.fetch('PEERCAST_RPC_URL'), ENV['PEERCAST_BASIC_TOKEN'])
  end

  def initialize(entry_point, basic_token)
    @entry_point = URI.parse(entry_point)
    @basic_token = basic_token
  end

  # リレーチャンネルを止める。peca-live では「再接続」に使う。
  # (停止するとノードからチャンネルが消え、次の /stream/?tip= 要求で新しくリレーが張られる)
  # ノードにそのチャンネルが無い (誰も見ていない) 場合は何もしない。
  def stop_channel(channel_id)
    command('stopChannel', [channel_id])
    true
  rescue Error => e
    raise unless e.code == ERROR_CODE_INTERNAL
    false
  end

  private

  def command(method_name, params = nil)
    hash = {
        jsonrpc: "2.0",
        id: 6412,
        method: method_name,
    }
    hash[:params] = params if params.present?

    request = Net::HTTP::Post.new(entry_point)
    request['Authorization'] = "Basic #{basic_token}" if basic_token.present?
    request['Content-Type'] = 'application/json'
    request.body = hash.to_json

    response = Net::HTTP.start(entry_point.host, entry_point.port, use_ssl: entry_point.scheme == 'https',
                               open_timeout: OPEN_TIMEOUT_SEC, read_timeout: READ_TIMEOUT_SEC) do |http|
      http.request(request)
    end
    unless response.is_a?(Net::HTTPSuccess)
      raise HTTPError, "JSON-RPC #{method_name}: HTTP #{response.code} #{response.body.to_s.strip.truncate(200)}"
    end
    json = JSON.parse(response.body)
    raise Error.new(method_name, json['error']) if json['error'].present?
    json['result']
  end

  attr_reader :entry_point, :basic_token
end
