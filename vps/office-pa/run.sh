#!/bin/sh
# (re)start perantara Onel PA
cd "$(dirname "$0")"
[ -f pa.pid ] && kill "$(cat pa.pid)" 2>/dev/null && sleep 2
setsid nohup ~/marketing-bot/venv/bin/python pa_link.py >> pa.log 2>&1 < /dev/null &
echo $! > pa.pid
