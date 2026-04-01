#!/bin/bash
# ServerStatus 服务端启动脚本

cd /usr/local/ServerStatus/server

if [ -f server.pid ]; then
    PID=$(cat server.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo "服务端已在运行中 (PID: $PID)"
        exit 1
    fi
fi

nohup python3 server.py > server.log 2>&1 &
echo $! > server.pid
echo "服务端已启动 (PID: $(cat server.pid))"