class Api::V1::Channels::PrivateController < ApplicationController
  # api/v1/channels/private/しっかりシュールｃｈ
  def show
    ip = request.remote_ip # 配信者の IP (プロキシ経由でも偽装されない。channels_controller#broadcasting と同じ)
    head :forbidden and return unless ChannelHistory.where(name: params[:channel_name]).broadcast_from(ip).exists?

    channel = PrivateChannel.find_by(name: params[:channel_name])

    if channel.present?
      if channel.secret?
        channel.open!
      else
        channel.secret!
      end
    else
      PrivateChannel.find_or_create_by!(name: params[:channel_name])
    end

    head :ok
  end
end
