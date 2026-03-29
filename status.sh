#!/bin/bash
# ServerStatus 一键管理脚本 v3.0
# 风格: doubi 菜单 + cppla 界面 + 三网中文延迟 + 强制 Caddy
# 通信端口: 35601 (cppla/doubi 标准)
# Web端口: 8880 (可修改)
# 支持: CentOS 6+/Debian 8+/Ubuntu 16+

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[36m'
PLAIN='\033[0m'

# 安装路径
INSTALL_PATH="/usr/local/ServerStatus"
SERVER_PATH="${INSTALL_PATH}/server"
CLIENT_PATH="${INSTALL_PATH}/clients"
WEB_PATH="${INSTALL_PATH}/web"
CADDY_PATH="/usr/local/caddy"
CADDY_CONF="${CADDY_PATH}/Caddyfile"

# 默认端口 (通信端口固定35601，Web端口可修改)
DEFAULT_SERVER_PORT=35601
CURRENT_WEB_PORT=8880

# 颜色函数
red() { echo -e "${RED}$1${PLAIN}"; }
green() { echo -e "${GREEN}$1${PLAIN}"; }
yellow() { echo -e "${YELLOW}$1${PLAIN}"; }
blue() { echo -e "${BLUE}$1${PLAIN}"; }

# 检查root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        red "错误: 此脚本必须以root权限运行!"
        exit 1
    fi
}

# 检测系统
detect_os() {
    if [ -f /etc/redhat-release ]; then
        OS="centos"
        OS_VERSION=$(rpm -q --qf "%{VERSION}" $(rpm -q --whatprovides redhat-release) | cut -d. -f1)
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        OS_VERSION=$(cat /etc/debian_version | cut -d. -f1)
    else
        OS="unknown"
    fi
}

# 读取当前Web端口配置
load_web_port() {
    if [ -f ${SERVER_PATH}/config.json ]; then
        CURRENT_WEB_PORT=$(grep -o '"web_port":[0-9]*' ${SERVER_PATH}/config.json | cut -d: -f2)
        [ -z "$CURRENT_WEB_PORT" ] && CURRENT_WEB_PORT=8880
    fi
}

# 检查服务端状态
check_server_status() {
    if [ -f ${SERVER_PATH}/server.pid ]; then
        PID=$(cat ${SERVER_PATH}/server.pid 2>/dev/null)
        if ps -p $PID > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# 检查客户端状态
check_client_status() {
    if [ -f ${CLIENT_PATH}/client.pid ]; then
        PID=$(cat ${CLIENT_PATH}/client.pid 2>/dev/null)
        if ps -p $PID > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# 检查Caddy状态
check_caddy_status() {
    if pgrep -x "caddy" > /dev/null; then
        return 0
    fi
    return 1
}

# 安装Python环境
install_python() {
    yellow "正在配置Python环境..."
    
    if command -v python3 &> /dev/null; then
        PY_CMD="python3"
        PIP_CMD="pip3"
        PY_VERSION=3
    elif command -v python2 &> /dev/null; then
        PY_CMD="python2"
        PIP_CMD="pip2"
        PY_VERSION=2
    else
        if [ "$OS" = "centos" ]; then
            if [ "$OS_VERSION" -eq 6 ]; then
                yum install -y centos-release-scl
                yum install -y python27 python27-python-pip
                ln -sf /opt/rh/python27/root/usr/bin/python2.7 /usr/bin/python2
                PY_CMD="python2"
                PIP_CMD="pip2"
            else
                yum install -y python3 python3-pip
                PY_CMD="python3"
                PIP_CMD="pip3"
            fi
        else
            apt-get update
            apt-get install -y python3 python3-pip
            PY_CMD="python3"
            PIP_CMD="pip3"
        fi
    fi
    
    $PIP_CMD install flask psutil requests 2>/dev/null
    green "Python环境配置完成 (使用 $PY_CMD)"
}

# 安装Caddy
install_caddy() {
    yellow "正在安装Caddy..."
    
    mkdir -p ${CADDY_PATH}
    cd ${CADDY_PATH}
    
    # 下载Caddy
    if [ "$OS" = "centos" ] && [ "$OS_VERSION" -eq 6 ]; then
        wget -O caddy.tar.gz https://github.com/caddyserver/caddy/releases/download/v1.0.5/caddy_v1.0.5_linux_amd64.tar.gz
        tar -xzf caddy.tar.gz
        rm -f caddy.tar.gz
        chmod +x caddy
    else
        curl -s https://getcaddy.com | bash -s personal
        cp /usr/local/bin/caddy ${CADDY_PATH}/ 2>/dev/null
    fi
    
    green "Caddy下载完成"
}

# 配置Caddy (根据当前Web端口)
config_caddy() {
    cat > ${CADDY_CONF} << EOF
:${CURRENT_WEB_PORT} {
    gzip
    root ${WEB_PATH}
    proxy /api localhost:5000 {
        without /api
    }
    log ${CADDY_PATH}/caddy.log
    errors ${CADDY_PATH}/caddy-errors.log
}
EOF

    # 重启Caddy
    if [ -f /etc/systemd/system/caddy.service ]; then
        systemctl restart caddy
    else
        pkill caddy 2>/dev/null
        nohup ${CADDY_PATH}/caddy -conf ${CADDY_CONF} -agree -email admin@localhost > ${CADDY_PATH}/caddy.log 2>&1 &
        echo $! > ${CADDY_PATH}/caddy.pid
    fi
    
    green "Caddy配置完成，Web端口: ${CURRENT_WEB_PORT}"
}

# 创建服务端文件
create_server_files() {
    mkdir -p ${SERVER_PATH}
    mkdir -p ${WEB_PATH}
    
    # 创建配置文件
    cat > ${SERVER_PATH}/config.json << EOF
{
    "listen_port": ${DEFAULT_SERVER_PORT},
    "web_port": ${CURRENT_WEB_PORT},
    "database": "${SERVER_PATH}/server.db",
    "admin_user": "admin",
    "admin_pass": "$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-12)"
}
EOF
    
    # 创建Python服务端
    cat > ${SERVER_PATH}/server.py << 'PYEOF'
#!/usr/bin/env python
# -*- coding: utf-8 -*-
import os
import sys
import json
import sqlite3
import time
from datetime import datetime
from flask import Flask, request, jsonify, render_template_string

CONFIG_FILE = "/usr/local/ServerStatus/server/config.json"
with open(CONFIG_FILE, 'r') as f:
    CONFIG = json.load(f)

DB_PATH = CONFIG['database']
SERVER_PORT = CONFIG['listen_port']

app = Flask(__name__)

def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS nodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        last_update TIMESTAMP,
        data TEXT
    )''')
    conn.commit()
    conn.close()

def save_node_data(name, data):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''INSERT OR REPLACE INTO nodes (name, last_update, data)
                 VALUES (?, ?, ?)''', (name, datetime.now(), json.dumps(data)))
    conn.commit()
    conn.close()

def get_all_nodes():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT name, data FROM nodes ORDER BY name')
    rows = c.fetchall()
    conn.close()
    nodes = []
    for row in rows:
        try:
            nodes.append(json.loads(row[1]))
        except:
            pass
    return nodes

@app.route('/api/update', methods=['POST'])
def update():
    data = request.get_json()
    if not data:
        return jsonify({'status': 'error'})
    name = data.get('name')
    if name:
        save_node_data(name, data)
    return jsonify({'status': 'ok'})

@app.route('/api/nodes', methods=['GET'])
def get_nodes():
    nodes = get_all_nodes()
    return jsonify(nodes)

@app.route('/')
def index():
    html = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ServerStatus 探针</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: #2c3e50;
            font-family: 'Courier New', 'Monaco', monospace;
            padding: 20px;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: #ecf0f1;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        .header {
            background: #34495e;
            color: #ecf0f1;
            padding: 15px 20px;
            border-bottom: 3px solid #e67e22;
        }
        .header h1 { font-size: 20px; font-weight: normal; }
        .header small { font-size: 12px; color: #95a5a6; }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
        }
        th {
            background: #bdc3c7;
            padding: 10px 8px;
            text-align: center;
            font-weight: bold;
            border-bottom: 1px solid #7f8c8d;
        }
        td {
            padding: 8px;
            text-align: center;
            border-bottom: 1px solid #ddd;
        }
        .online { color: #27ae60; font-weight: bold; }
        .offline { color: #e74c3c; font-weight: bold; }
        .delay-good { color: #27ae60; }
        .delay-fair { color: #f39c12; }
        .delay-bad { color: #e74c3c; }
        .footer {
            background: #34495e;
            color: #95a5a6;
            padding: 8px;
            text-align: center;
            font-size: 11px;
        }
        .refresh-time {
            background: #ecf0f1;
            text-align: right;
            padding: 5px 10px;
            font-size: 11px;
            color: #7f8c8d;
        }
    </style>
</head>
<body>
<div class="container">
    <div class="header">
        <h1>ServerStatus 探针 <small>实时监控 | 三网延迟</small></h1>
    </div>
    <div class="refresh-time" id="refreshTime">加载中...</div>
    <table id="nodeTable">
        <thead>
            <tr><th>节点名称</th><th>状态</th><th>负载(1/5/15)</th><th>内存</th><th>硬盘</th><th>网络(上/下)</th><th>电信延迟</th><th>联通延迟</th><th>移动延迟</th</tr>
        </thead>
        <tbody id="nodeBody"><tr><td colspan="9" style="text-align:center;">等待数据...</td></tr></tbody>
    </table>
    <div class="footer">数据实时更新 | 三网延迟基于ICMP探测</div>
</div>
<script>
    function formatSpeed(bps) {
        if (!bps) return '0';
        if (bps < 1024) return bps.toFixed(0) + 'B';
        if (bps < 1024*1024) return (bps/1024).toFixed(1) + 'K';
        return (bps/(1024*1024)).toFixed(1) + 'M';
    }
    function getDelayClass(d) {
        if (!d || d === '--') return '';
        if (d < 50) return 'delay-good';
        if (d < 150) return 'delay-fair';
        return 'delay-bad';
    }
    function renderTable(nodes) {
        var tbody = document.getElementById('nodeBody');
        if (!nodes || nodes.length === 0) {
            tbody.innerHTML = '<tr><td colspan="9" style="text-align:center;">暂无节点数据</td></tr>';
            return;
        }
        var html = '';
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i];
            var statusClass = (n.online === 1) ? 'online' : 'offline';
            var statusText = (n.online === 1) ? '在线' : '离线';
            var load = n.load || [0,0,0];
            var telecom = n.telecom || '--';
            var unicom = n.unicom || '--';
            var mobile = n.mobile || '--';
            html += '<tr>';
            html += '<td>' + (n.name || 'unknown') + '</td>';
            html += '<td class="' + statusClass + '">' + statusText + '</td>';
            html += '<td>' + load[0] + ' / ' + load[1] + ' / ' + load[2] + '</td>';
            html += '<td>' + (n.memory || 0) + '%</td>';
            html += '<td>' + (n.disk || 0) + '%</td>';
            html += '<td>↑' + formatSpeed(n.tx_speed) + '/↓' + formatSpeed(n.rx_speed) + '</td>';
            html += '<td class="' + getDelayClass(telecom) + '">' + (telecom === '--' ? '--' : telecom + 'ms') + '</td>';
            html += '<td class="' + getDelayClass(unicom) + '">' + (unicom === '--' ? '--' : unicom + 'ms') + '</td>';
            html += '<td class="' + getDelayClass(mobile) + '">' + (mobile === '--' ? '--' : mobile + 'ms') + '</td>';
            html += '</tr>';
        }
        tbody.innerHTML = html;
        document.getElementById('refreshTime').innerHTML = '最后更新: ' + new Date().toLocaleTimeString();
    }
    function fetchData() {
        fetch('/api/nodes').then(res=>res.json()).then(renderTable).catch(e=>console.log(e));
    }
    fetchData();
    setInterval(fetchData, 5000);
</script>
</body>
</html>
'''
    return render_template_string(html)

if __name__ == '__main__':
    init_db()
    print("ServerStatus 服务端启动，通信端口: %d" % SERVER_PORT)
    app.run(host='127.0.0.1', port=5000, debug=False)
PYEOF
    
    chmod +x ${SERVER_PATH}/server.py
    
    cat > ${SERVER_PATH}/start.sh << EOF
#!/bin/bash
cd ${SERVER_PATH}
nohup python server.py > ${SERVER_PATH}/server.log 2>&1 &
echo \$! > ${SERVER_PATH}/server.pid
EOF

    cat > ${SERVER_PATH}/stop.sh << EOF
#!/bin/bash
if [ -f ${SERVER_PATH}/server.pid ]; then
    kill \$(cat ${SERVER_PATH}/server.pid)
    rm -f ${SERVER_PATH}/server.pid
else
    pkill -f "python.*server.py"
fi
EOF
    
    chmod +x ${SERVER_PATH}/start.sh ${SERVER_PATH}/stop.sh
    green "服务端文件创建完成"
}

# 创建客户端文件
create_client_files() {
    mkdir -p ${CLIENT_PATH}
    
    cat > ${CLIENT_PATH}/client.py << 'CLIENTEOF'
#!/usr/bin/env python
# -*- coding: utf-8 -*-
import psutil
import socket
import requests
import json
import time
import platform
import subprocess
import re
import sys

class StatusClient:
    def __init__(self, server_ip, server_port, name):
        self.server_url = "http://%s:%s" % (server_ip, server_port)
        self.name = name
        self.interval = 10
        self.last_net = psutil.net_io_counters()
        self.last_time = time.time()
    
    def ping_node(self, ip):
        try:
            result = subprocess.Popen(['ping', '-c', '1', '-W', '2', ip], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            output, _ = result.communicate(timeout=3)
            output_str = output.decode('utf-8', errors='ignore')
            match = re.search(r'time[=<](\d+\.?\d*)\s*ms', output_str)
            if match:
                return float(match.group(1))
        except:
            pass
        return None
    
    def get_delays(self):
        nodes = {'telecom': ['114.114.114.114', '180.153.28.5'],
                 'unicom': ['123.125.126.99', '202.102.128.68'],
                 'mobile': ['211.136.28.66', '221.130.33.52']}
        delays = {}
        for isp, ips in nodes.items():
            best = None
            for ip in ips:
                d = self.ping_node(ip)
                if d and (best is None or d < best):
                    best = d
            delays[isp] = best if best else '--'
        return delays
    
    def collect(self):
        current_net = psutil.net_io_counters()
        current_time = time.time()
        dt = current_time - self.last_time
        rx_speed = (current_net.bytes_recv - self.last_net.bytes_recv) / dt if dt > 0 else 0
        tx_speed = (current_net.bytes_sent - self.last_net.bytes_sent) / dt if dt > 0 else 0
        self.last_net = current_net
        self.last_time = current_time
        
        try:
            load = list(psutil.getloadavg())
        except:
            load = [0, 0, 0]
        
        ipv4 = ''
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(('8.8.8.8', 80))
            ipv4 = s.getsockname()[0]
            s.close()
        except:
            pass
        
        delays = self.get_delays()
        
        return {
            'name': self.name,
            'online': 1,
            'hostname': socket.gethostname(),
            'cpu': psutil.cpu_percent(interval=1),
            'memory': psutil.virtual_memory().percent,
            'disk': psutil.disk_usage('/').percent,
            'load': [round(x, 2) for x in load],
            'rx_speed': rx_speed,
            'tx_speed': tx_speed,
            'rx_total': current_net.bytes_recv,
            'tx_total': current_net.bytes_sent,
            'ipv4': ipv4,
            'telecom': delays.get('telecom', '--'),
            'unicom': delays.get('unicom', '--'),
            'mobile': delays.get('mobile', '--')
        }
    
    def run(self):
        print("客户端启动: %s -> %s" % (self.name, self.server_url))
        while True:
            try:
                data = self.collect()
                requests.post(self.server_url + "/api/update", json=data, timeout=5)
                time.sleep(self.interval)
            except KeyboardInterrupt:
                break
            except Exception as e:
                print("错误: %s" % str(e))
                time.sleep(30)

if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("用法: python client.py <服务端IP> <端口> <节点名>")
        sys.exit(1)
    client = StatusClient(sys.argv[1], int(sys.argv[2]), sys.argv[3])
    client.run()
CLIENTEOF
    
    chmod +x ${CLIENT_PATH}/client.py
    
    cat > ${CLIENT_PATH}/start.sh << EOF
#!/bin/bash
cd ${CLIENT_PATH}
nohup python client.py \$(cat config.txt) > ${CLIENT_PATH}/client.log 2>&1 &
echo \$! > ${CLIENT_PATH}/client.pid
EOF

    cat > ${CLIENT_PATH}/stop.sh << EOF
#!/bin/bash
if [ -f ${CLIENT_PATH}/client.pid ]; then
    kill \$(cat ${CLIENT_PATH}/client.pid)
    rm -f ${CLIENT_PATH}/client.pid
else
    pkill -f "client.py"
fi
EOF
    
    chmod +x ${CLIENT_PATH}/start.sh ${CLIENT_PATH}/stop.sh
    green "客户端文件创建完成"
}

# 修改Web端口
change_web_port() {
    check_root
    load_web_port
    echo ""
    blue "当前Web端口: ${CURRENT_WEB_PORT}"
    read -p "请输入新的Web端口: " new_port
    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        red "端口无效，请输入1-65535之间的数字"
        return
    fi
    
    CURRENT_WEB_PORT=$new_port
    # 更新配置文件
    sed -i "s/\"web_port\":[0-9]*/\"web_port\":${CURRENT_WEB_PORT}/" ${SERVER_PATH}/config.json
    
    # 重新配置Caddy
    config_caddy
    
    # 重启服务端
    ${SERVER_PATH}/stop.sh 2>/dev/null
    sleep 1
    ${SERVER_PATH}/start.sh
    
    green "Web端口已修改为 ${CURRENT_WEB_PORT}"
    IP_ADDR=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    green "请访问: http://${IP_ADDR}:${CURRENT_WEB_PORT}"
}

# 安装服务端
install_server() {
    check_root
    detect_os
    blue "========================================="
    blue "开始安装 ServerStatus 服务端"
    blue "通信端口: ${DEFAULT_SERVER_PORT} (固定)"
    blue "========================================="
    
    read -p "请输入Web访问端口 [默认: 8880]: " input_web
    CURRENT_WEB_PORT=${input_web:-8880}
    
    install_python
    create_server_files
    install_caddy
    config_caddy
    ${SERVER_PATH}/start.sh
    
    IP_ADDR=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    ADMIN_PASS=$(grep admin_pass ${SERVER_PATH}/config.json | cut -d'"' -f4)
    
    green """
========================================
服务端安装完成!
========================================
通信端口: ${DEFAULT_SERVER_PORT} (客户端连接用)
Web访问地址: http://${IP_ADDR}:${CURRENT_WEB_PORT}
管理账号: admin
管理密码: ${ADMIN_PASS}
========================================
客户端安装命令:
在需要监控的机器上运行: ./status.sh c
========================================
"""
}

# 安装客户端
install_client() {
    check_root
    blue "========================================="
    blue "开始安装 ServerStatus 客户端"
    blue "========================================="
    
    read -p "请输入服务端IP地址: " server_ip
    read -p "请输入服务端通信端口 [默认: ${DEFAULT_SERVER_PORT}]: " server_port
    server_port=${server_port:-${DEFAULT_SERVER_PORT}}
    read -p "请输入节点名称 [默认: 当前主机名]: " node_name
    node_name=${node_name:-$(hostname)}
    
    install_python
    create_client_files
    echo "$server_ip $server_port $node_name" > ${CLIENT_PATH}/config.txt
    ${CLIENT_PATH}/start.sh
    
    green """
========================================
客户端安装完成!
========================================
服务端: ${server_ip}:${server_port}
节点名: ${node_name}
========================================
"""
}

# 卸载服务端
uninstall_server() {
    check_root
    yellow "正在卸载服务端..."
    ${SERVER_PATH}/stop.sh 2>/dev/null
    pkill caddy 2>/dev/null
    rm -rf ${INSTALL_PATH}
    rm -rf ${CADDY_PATH}
    green "服务端卸载完成"
}

# 卸载客户端
uninstall_client() {
    check_root
    yellow "正在卸载客户端..."
    ${CLIENT_PATH}/stop.sh 2>/dev/null
    rm -rf ${CLIENT_PATH}
    green "客户端卸载完成"
}

# 启动/停止/重启
start_server() { ${SERVER_PATH}/start.sh; green "服务端已启动"; }
stop_server() { ${SERVER_PATH}/stop.sh; green "服务端已停止"; }
restart_server() { stop_server; sleep 2; start_server; }
start_client() { ${CLIENT_PATH}/start.sh; green "客户端已启动"; }
stop_client() { ${CLIENT_PATH}/stop.sh; green "客户端已停止"; }
restart_client() { stop_client; sleep 2; start_client; }

# 查看状态
status_server() {
    if check_server_status; then green "服务端: 运行中"; else red "服务端: 未运行"; fi
    if check_caddy_status; then green "Caddy: 运行中"; else red "Caddy: 未运行"; fi
    load_web_port
    echo "Web端口: ${CURRENT_WEB_PORT}"
}
status_client() { if check_client_status; then green "客户端: 运行中"; else red "客户端: 未运行"; fi; }
view_log() { tail -50 ${SERVER_PATH}/server.log 2>/dev/null || red "日志不存在"; }
view_client_log() { tail -50 ${CLIENT_PATH}/client.log 2>/dev/null || red "日志不存在"; }

# 服务端菜单
server_menu() {
    load_web_port
    while true; do
        clear
        blue "========================================="
        blue " ServerStatus 服务端管理菜单 [v3.0]"
        blue " -- 通信端口: ${DEFAULT_SERVER_PORT} | Web端口: ${CURRENT_WEB_PORT} --"
        blue "========================================="
        green "1. 安装 服务端"
        green "2. 卸载 服务端"
        green "————————————"
        green "3. 启动 服务端"
        green "4. 停止 服务端"
        green "5. 重启 服务端"
        green "————————————"
        green "6. 修改 Web端口"
        green "7. 查看 服务端状态"
        green "8. 查看 服务端日志"
        green "————————————"
        green "9. 切换为 客户端菜单"
        red "0. 退出脚本"
        blue "========================================="
        if [ -f ${SERVER_PATH}/server.py ]; then
            check_server_status && green "当前状态: 服务端 已安装 并 已启动" || yellow "当前状态: 服务端 已安装 未启动"
        else
            red "当前状态: 服务端 未安装"
        fi
        blue "========================================="
        read -p "请输入数字 [0-9]: " choice
        case "$choice" in
            1) install_server ;;
            2) uninstall_server ;;
            3) start_server ;;
            4) stop_server ;;
            5) restart_server ;;
            6) change_web_port ;;
            7) status_server ;;
            8) view_log ;;
            9) client_menu ;;
            0) exit 0 ;;
            *) red "请输入正确的数字" ;;
        esac
    done
}

# 客户端菜单
client_menu() {
    while true; do
        clear
        blue "========================================="
        blue " ServerStatus 客户端管理菜单 [v3.0]"
        blue " -- 单文件部署 | 三网延迟探测 --"
        blue "========================================="
        green "1. 安装 客户端"
        green "2. 卸载 客户端"
        green "————————————"
        green "3. 启动 客户端"
        green "4. 停止 客户端"
        green "5. 重启 客户端"
        green "————————————"
        green "6. 查看 客户端状态"
        green "7. 查看 客户端日志"
        green "————————————"
        green "8. 切换为 服务端菜单"
        red "0. 退出脚本"
        blue "========================================="
        if [ -f ${CLIENT_PATH}/client.py ]; then
            check_client_status && green "当前状态: 客户端 已安装 并 已启动" || yellow "当前状态: 客户端 已安装 未启动"
        else
            red "当前状态: 客户端 未安装"
        fi
        blue "========================================="
        read -p "请输入数字 [0-8]: " choice
        case "$choice" in
            1) install_client ;;
            2) uninstall_client ;;
            3) start_client ;;
            4) stop_client ;;
            5) restart_client ;;
            6) status_client ;;
            7) view_client_log ;;
            8) server_menu ;;
            0) exit 0 ;;
            *) red "请输入正确的数字" ;;
        esac
    done
}

# 主入口
if [ "$1" = "c" ]; then
    client_menu
elif [ "$1" = "s" ]; then
    server_menu
else
    server_menu
fi