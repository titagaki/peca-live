import React, { useState } from 'react'
import styled from 'styled-components'
import Channel from '../types/Channel'
import { Helmet } from 'react-helmet'
import Video from './Video'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import Button from '@material-ui/core/Button'
import { useHistory } from 'react-router-dom'
import Tooltip from '@material-ui/core/Tooltip'
import { updateChannels, useSelectorChannels } from '../modules/channelsModule'
import { useSelectorPeerCast } from '../modules/peercastModule'
import { useDispatch } from 'react-redux'
import { useSelectorUser } from '../modules/userModule'
import LoginDialog from './LoginDialog'
import { IconProp } from '@fortawesome/fontawesome-svg-core'

type Props = {
  streamId: string
  isHls: boolean
  local: boolean
}

type IconButtonProps = {
  title: string
  icon: IconProp
  onClick: () => void
}

const IconButton = (props: IconButtonProps) => {
  const { title, icon, onClick } = props

  return (
    <Tooltip title={title} arrow>
      <Button
        variant="outlined"
        size="small"
        color="primary"
        onClick={() => onClick()}
        style={{ marginRight: '5px' }}
      >
        <FontAwesomeIcon icon={icon} style={{ height: '22px' }} />
      </Button>
    </Tooltip>
  )
}

const ChannelPlayer = (props: Props) => {
  const dispatch = useDispatch()
  const { streamId, isHls, local } = props

  const channels = useSelectorChannels()
  const peercast = useSelectorPeerCast()
  const currentUser = useSelectorUser()

  const [loginDialogOpen, setLoginDialogOpen] = useState(false)

  const channel =
    channels.find(channel => channel.streamId === streamId) ||
    Channel.nullObject(
      channels.length > 0 ? '配信は終了しました。' : 'チャンネル情報を取得中...'
    )
  const index = channels.findIndex(item => item === channel)
  const nextChannel = channels[(index + 1) % channels.length]
  const nextChannelUrl = nextChannel
    ? `/channels/${nextChannel.streamId}`
    : null
  const prevChannel = channels[(index - 1 + channels.length) % channels.length]
  const prevChannelUrl = prevChannel
    ? `/channels/${prevChannel.streamId}`
    : null

  window.scrollTo(0, 0)

  const history = useHistory()

  let vlcUrl = null
  if (channel.isFlv) {
    vlcUrl = `rtmp://${peercast.tip}/stream/${channel.streamId}.flv?tip=${channel.tip}`
  } else if (channel.isWmv) {
    vlcUrl = `mms://${peercast.tip}/stream/${channel.streamId}.wmv?tip=${channel.tip}`
  }

  return (
    <>
      <Helmet title={`${channel.name} - ぺからいぶ！`} />
      <Video channel={channel} isHls={isHls} local={local} />
      <ChannelItemStyle>
        <ButtonPanelStyle>
          {prevChannelUrl && (
            <IconButton
              title="前の配信へ"
              icon={['fas', 'arrow-left']}
              onClick={() => {
                history.push(prevChannelUrl)
              }}
            />
          )}

          {nextChannelUrl && (
            <IconButton
              title="次の配信へ"
              icon={['fas', 'arrow-right']}
              onClick={() => {
                history.push(nextChannelUrl)
              }}
            />
          )}

          <Tooltip
            title={
              channel.isFavorited ? 'お気に入りの解除' : 'お気に入りに登録'
            }
            arrow
          >
            <Button
              variant="outlined"
              size="small"
              color="primary"
              style={{ marginRight: '5px' }}
              onClick={() => {
                const favoriteChannel = async () => {
                  const token = document.getElementsByName('csrf-token')[0][
                    'content'
                  ]
                  const headers = {
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'X-CSRF-TOKEN': token
                  }
                  const body = `channel_name=${channel.name}`

                  await fetch('/api/v1/favorites', {
                    credentials: 'same-origin',
                    method: channel.isFavorited ? 'DELETE' : 'POST',
                    headers: headers,
                    body
                  })

                  await updateChannels(dispatch) // 画面に反映
                  // TODO: setFavoriteChannel(channels, channel.name, false, dispatch)
                }
                if (currentUser.isLogin) {
                  favoriteChannel()
                } else {
                  // ログインしていない場合は、ログインを促す
                  setLoginDialogOpen(true)
                }
              }}
            >
              {channel.isFavorited ? (
                <FontAwesomeIcon
                  icon={['fas', 'heart']}
                  style={{ height: '22px' }}
                />
              ) : (
                <FontAwesomeIcon
                  icon={['far', 'heart']}
                  style={{ height: '22px' }}
                />
              )}
            </Button>
          </Tooltip>

          <IconButton
            title="再接続"
            icon={['fas', 'redo-alt']}
            onClick={() => {
              fetch(`/api/v1/channels/bump?streamId=${streamId}`, {
                credentials: 'same-origin'
              })
              location.reload()
            }}
          />

          {vlcUrl && (
            <IconButton
              title="VLCで再生"
              icon={['fas', 'play-circle']}
              onClick={() => {
                window.location.href = vlcUrl
              }}
            />
          )}
        </ButtonPanelStyle>

        <LoginDialog
          open={loginDialogOpen}
          onClose={() => setLoginDialogOpen(false)}
        />

        <ChannelDetail>
          <Title>{channel.explanation}</Title>
          <ListenerStyle>
            <Tooltip title="リスナー数" aria-label="listener">
              <span>
                <FontAwesomeIcon icon="headphones" />
                <ListenerCountStyle title="リスナー数">
                  {channel.listenerCount}
                </ListenerCountStyle>
              </span>
            </Tooltip>
          </ListenerStyle>
          <Details>
            {channel.name}
            <div>
              <a href={channel.contactUrl}>{channel.contactUrl}</a>
            </div>
            {channel.isWmv && '※WMV配信のためVLCで再生してください。'}
          </Details>
        </ChannelDetail>
      </ChannelItemStyle>
    </>
  )
}

const ButtonPanelStyle = styled.div`
  padding-bottom: 2px;
`

const ChannelDetail = styled.div`
`

const Title = styled.div`
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  width: 347px;

  font-size: 14px;
  font-weight: 600;
  line-height: 16.8px;
  color: rgb(25, 23, 28);
  font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
  margin-top: 5px;
  margin-bottom: 2px;
  float: left;
`

const Details = styled.div`
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  width: 347px;
  font-size: 12px;
  font-weight: 400;
  line-height: 18px;
  color: rgb(50, 47, 55);
  font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
`

const ChannelItemStyle = styled.div`
  float: left;
  padding: 3px 10px;
`

const ListenerStyle = styled.div`
  display: block;
  text-align: right;
`

const ListenerCountStyle = styled.span`
  margin-left: 4px;
`

export default ChannelPlayer
