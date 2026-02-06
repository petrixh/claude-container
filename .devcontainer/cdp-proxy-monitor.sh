#!/bin/bash
# Monitors Chrome's remote-debugging-port and keeps socat proxy on 9222 pointed at it.
# Automatically reconnects when Chrome restarts with a new port.
# Usage: cdp-proxy-monitor        (runs in foreground, Ctrl+C to stop)
#        cdp-proxy-monitor &      (runs in background)
#        nohup cdp-proxy-monitor > /tmp/cdp-proxy.log 2>&1 &

CURRENT_PORT=""
SOCAT_PID=""

cleanup() {
  echo "Stopping CDP proxy monitor..."
  [ -n "$SOCAT_PID" ] && kill "$SOCAT_PID" 2>/dev/null
  exit 0
}
trap cleanup EXIT INT TERM

kill_socat() {
  local pids
  pids=$(ps aux | grep 'socat.*TCP-LISTEN:9222' | grep -v grep | awk '{print $2}')
  if [ -n "$pids" ]; then
    echo "$pids" | xargs kill 2>/dev/null
  fi
  SOCAT_PID=""
}

start_socat() {
  local port=$1
  kill_socat
  socat TCP-LISTEN:9222,fork,reuseaddr,bind=0.0.0.0 "TCP:127.0.0.1:${port}" &
  SOCAT_PID=$!
}

get_chrome_port() {
  local port
  for port in $(ps aux | grep -oP 'chrome.*--remote-debugging-port=\K\d+' 2>/dev/null | sort -u); do
    if curl -s --max-time 1 "http://127.0.0.1:${port}/json/version" > /dev/null 2>&1; then
      echo "$port"
      return
    fi
  done
}

echo "CDP proxy monitor started — watching for Chrome debug port changes..."

while true; do
  CHROME_PORT=$(get_chrome_port)

  if [ -z "$CHROME_PORT" ]; then
    if [ -n "$CURRENT_PORT" ]; then
      echo "$(date +%H:%M:%S) Chrome gone (was on port $CURRENT_PORT) — waiting for restart..."
      kill_socat
      CURRENT_PORT=""
    fi
  elif [ "$CHROME_PORT" != "$CURRENT_PORT" ]; then
    start_socat "$CHROME_PORT"
    sleep 0.5
    if curl -s --max-time 1 "http://127.0.0.1:9222/json/version" > /dev/null 2>&1; then
      echo "$(date +%H:%M:%S) CDP proxy: 0.0.0.0:9222 -> 127.0.0.1:${CHROME_PORT} [OK]"
    else
      echo "$(date +%H:%M:%S) CDP proxy: 0.0.0.0:9222 -> 127.0.0.1:${CHROME_PORT} [VERIFY FAILED]"
    fi
    CURRENT_PORT="$CHROME_PORT"
  fi

  sleep 1
done
