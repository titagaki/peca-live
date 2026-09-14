require 'spec_helper'
require 'active_support'
require 'active_support/core_ext/object/blank'
require_relative '../../lib/yellow_page'

RSpec.describe YellowPage do
  let(:yp) { YellowPage.new('SP', 'http://example.com/index.txt') }

  # peercast-0yp docs/yp/player.md の 19 項目
  let(:line) do
    [
      'A.ch',                                                    # 0 name
      '0c1a6c6959ceb2a8bf9598bc9185ff32',                        # 1 id
      '14.13.42.64:5184',                                        # 2 tracker
      'http://jbbs.shitaraba.net/bbs/read.cgi/game/52685/1567349533/', # 3 contactUrl
      'PS4',                                                     # 4 genre
      'モンハン &amp; テスト - &lt;Open&gt;',                    # 5 description
      '12',                                                      # 6 listeners
      '3',                                                       # 7 relays
      '1500',                                                    # 8 bitrate
      'FLV',                                                     # 9 contentType
      'artist',                                                  # 10 creator
      'album',                                                   # 11 album
      'title',                                                   # 12 trackTitle
      'http://track.example.com/',                               # 13 trackUrl
      'A.ch',                                                    # 14 name (URL encoded)
      '1:23',                                                    # 15 uptime H:MM
      'click',                                                   # 16
      'こめんと',                                                # 17 comment
      '1',                                                       # 18 direct
    ].join('<>')
  end

  describe '#parse' do
    it 'updateYPChannels と同じキーで返す' do
      channel = yp.parse("#{line}\n").first
      expect(channel).to eq(
        'yellowPage'  => 'SP',
        'name'        => 'A.ch',
        'channelId'   => '0C1A6C6959CEB2A8BF9598BC9185FF32',
        'tracker'     => '14.13.42.64:5184',
        'contactUrl'  => 'http://jbbs.shitaraba.net/bbs/read.cgi/game/52685/1567349533/',
        'genre'       => 'PS4',
        'description' => 'モンハン & テスト - <Open>',
        'comment'     => 'こめんと',
        'bitrate'     => 1500,
        'contentType' => 'FLV',
        'trackTitle'  => 'title',
        'album'       => 'album',
        'creator'     => 'artist',
        'trackUrl'    => 'http://track.example.com/',
        'listeners'   => 12,
        'relays'      => 3,
        'uptime'      => (1 * 60 + 23) * 60,
      )
    end

    it '空行を飛ばし、複数行を返す' do
      expect(yp.parse("#{line}\n\n#{line}\n").size).to eq(2)
    end

    it '項目が足りない行はある分だけ読む' do
      channel = yp.parse("name<>0c1a6c6959ceb2a8bf9598bc9185ff32<>1.2.3.4:7144\n").first
      expect(channel['name']).to eq('name')
      expect(channel['tracker']).to eq('1.2.3.4:7144')
      expect(channel['genre']).to be_nil
      expect(channel['listeners']).to be_nil
      expect(channel['uptime']).to be_nil
    end

    it 'YP 自身のエントリ (channelId 全ゼロ) はそのまま返す' do
      channel = yp.parse("YP<>00000000000000000000000000000000<>127.0.0.1\n").first
      expect(channel['channelId']).to eq('0' * 32)
    end

    it '32 桁 hex でない channelId は全ゼロにする' do
      channel = yp.parse("x<>not-a-guid<>\n").first
      expect(channel['channelId']).to eq('0' * 32)
    end

    it 'リスナー数の非公開 (-1) と数値でない値を区別する' do
      fields = Array.new(19, '')
      fields[6] = '-1'
      fields[7] = 'abc'
      channel = yp.parse(fields.join('<>')).first
      expect(channel['listeners']).to eq(-1)
      expect(channel['relays']).to be_nil
    end

    it 'uptime は ":" が無ければ整数、不正なら nil' do
      fields = Array.new(19, '')
      fields[15] = '90'
      expect(yp.parse(fields.join('<>')).first['uptime']).to eq(90)
      fields[15] = 'a:b'
      expect(yp.parse(fields.join('<>')).first['uptime']).to be_nil
      fields[15] = ''
      expect(yp.parse(fields.join('<>')).first['uptime']).to be_nil
    end
  end

  describe '.entries' do
    it '環境変数を 名前=URL の空白区切りとして読む' do
      entries = YellowPage.entries('SP=http://sp.example.com/index.txt TP=http://tp.example.com/index.txt')
      expect(entries.map(&:name)).to eq(%w[SP TP])
      expect(entries.map(&:index_url)).to eq(%w[http://sp.example.com/index.txt http://tp.example.com/index.txt])
    end

    it '未設定なら空' do
      expect(YellowPage.entries(nil)).to eq([])
      expect(YellowPage.entries('SP=')).to eq([])
    end
  end
end
