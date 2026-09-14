require 'cgi'
require 'httpclient'

# YP の index.txt を取得して、PeerCastStation の updateYPChannels と同じ形式のハッシュ配列にする。
# index.txt の形式は peercast-0yp docs/yp/player.md、変換規則は PeerCastStation の
# PCPYellowPageClient#GetChannelsAsync / APIHost#YPChannelsToArray に合わせている。
#
# 取得先は環境変数 YELLOW_PAGES で「名前=index.txtのURL」を空白区切りで指定する。
#   YELLOW_PAGES="SP=http://example.com:7146/index.txt TP=http://example.net/index.txt"
# 名前はレスポンスの yellowPage に入り、フロントのアイコン分岐 (SP / TP) に使われる。
class YellowPage
  Entry = Struct.new(:name, :index_url)

  EMPTY_CHANNEL_ID = '0' * 32
  CONNECT_TIMEOUT_SEC = 5
  RECEIVE_TIMEOUT_SEC = 10

  class << self
    def entries(env = ENV['YELLOW_PAGES'])
      env.to_s.split.filter_map do |pair|
        name, url = pair.split('=', 2)
        next if name.blank? || url.blank?
        Entry.new(name, url)
      end
    end

    # 設定された全 YP のチャンネルをまとめて返す
    def fetch_channels
      entries.flat_map { |entry| new(entry.name, entry.index_url).fetch_channels }
    end
  end

  attr_reader :name, :index_url

  def initialize(name, index_url)
    @name = name
    @index_url = index_url
  end

  def fetch_channels
    parse(fetch)
  end

  def parse(text)
    text.to_s.each_line.filter_map do |line|
      line = line.chomp
      next if line.blank?
      parse_line(line)
    end
  end

  private

  # 1 行 = 1 チャンネル。<> 区切り 19 項目。足りない行はある分だけ読む (PeerCastStation と同じ)。
  def parse_line(line)
    t = line.split('<>', -1)
    {
      'yellowPage'  => name,
      'name'        => str(t[0]),
      'channelId'   => channel_id(t[1]),
      'tracker'     => str(t[2]),
      'contactUrl'  => str(t[3]),
      'genre'       => str(t[4]),
      'description' => str(t[5]),
      'comment'     => str(t[17]),
      'bitrate'     => int(t[8]),
      'contentType' => str(t[9]),
      'trackTitle'  => str(t[12]),
      'album'       => str(t[11]),
      'creator'     => str(t[10]),
      'trackUrl'    => str(t[13]),
      'listeners'   => int(t[6]),
      'relays'      => int(t[7]),
      'uptime'      => uptime(t[15]),
    }
  end

  # 文字列項目は HTML デコードする (&lt;Open&gt; → <Open>)
  def str(token)
    return token if token.blank?
    CGI.unescapeHTML(token)
  end

  # 32 桁 hex 以外は全ゼロ (Guid.TryParse 失敗時の Guid.Empty 相当)。大文字に揃える。
  def channel_id(token)
    return EMPTY_CHANNEL_ID unless token.to_s.match?(/\A\h{32}\z/)
    token.upcase
  end

  # 整数にできなければ nil (Int32.TryParse 失敗時の null 相当)
  def int(token)
    return nil unless token.to_s.strip.match?(/\A[+-]?\d+\z/)
    token.to_i
  end

  # "H:MM" を秒にする。":" が無ければ整数としてそのまま。
  def uptime(token)
    return nil if token.blank?
    times = token.split(':')
    return int(times[0]) if times.size < 2
    hours = int(times[0])
    minutes = int(times[1])
    return nil if hours.nil? || minutes.nil?
    (hours * 60 + minutes) * 60
  end

  def fetch
    client = HTTPClient.new
    client.connect_timeout = CONNECT_TIMEOUT_SEC
    client.receive_timeout = RECEIVE_TIMEOUT_SEC
    response = client.get(index_url, follow_redirect: true)
    return '' if response.status != 200
    response.body.dup.force_encoding(Encoding::UTF_8).scrub
  rescue HTTPClient::TimeoutError, HTTPClient::BadResponseError, SocketError, SystemCallError => e
    Rails.logger.warn("YellowPage(#{name}): #{e.class}: #{e.message}")
    ''
  end
end
