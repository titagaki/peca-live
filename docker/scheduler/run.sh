#!/bin/sh
# 10 分ごとに定期実行エンドポイントを叩く (Heroku Scheduler の代わり)
# 詳細: docs/spec/scheduled-jobs.md
set -u
WEB_URL="${WEB_URL:-http://web:3000}"
INTERVAL_SEC="${INTERVAL_SEC:-600}"

while true; do
  for path in /api/v1/channels/record_history /api/v1/channels/notification_broadcasting; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 60 "${WEB_URL}${path}")
    echo "$(date -Iseconds) GET ${path} -> ${code}"
  done
  sleep "${INTERVAL_SEC}"
done
