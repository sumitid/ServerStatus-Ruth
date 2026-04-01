#!/bin/bash
# ServerStatus 服务端停止脚本

cd /usr/local/ServerStatus/server

if [ -f server.pid ]; then
    PID=$(cat server.pid)
    if ps -p $PID > /dev/null 2>&1; then
        kill $PID
        echo "服务端已停止 (PID: $PID)"
    fi
    rm -f server.pid
fi

pkill -f "python3 server.py" 2>/dev/null
echo "服务端已停止"