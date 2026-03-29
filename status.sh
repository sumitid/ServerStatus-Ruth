#!/bin/bash
# ServerStatus 一键管理脚本 v3.0 (C++核心版)
# 风格: doubi 菜单 + cppla 界面 + 三网中文延迟 + 强制 Caddy
# 通信端口: 35601 | Web端口: 8880 (可修改)
# 支持: CentOS 6+/Debian 8+/Ubuntu 16+

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[36m'
PLAIN='\033[0m'

VERSION="3.0.0"
GITHUB_URL="https://raw.githubusercontent.com/sumitid/ServerStatus-Ruth/main"

INSTALL_PATH="/usr/local/ServerStatus"
SERVER_PATH="${INSTALL_PATH}/server"
CLIENT_PATH="${INSTALL_PATH}/clients"
WEB_PATH="${INSTALL_PATH}/web"
CADDY_PATH="/usr/local/caddy"
CADDY_CONF="${CADDY_PATH}/Caddyfile"

DEFAULT_SERVER_PORT=35601
CURRENT_WEB_PORT=8880

red() { echo -e "${RED}$1${PLAIN}"; }
green() { echo -e "${GREEN}$1${PLAIN}"; }
yellow() { echo -e "${YELLOW}$1${PLAIN}"; }
blue() { echo -e "${BLUE}$1${PLAIN}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        red "错误: 此脚本必须以root权限运行!"
        exit 1
    fi
}

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

load_web_port() {
    if [ -f ${SERVER_PATH}/config.json ]; then
        CURRENT_WEB_PORT=$(grep -o '"web_port":[0-9]*' ${SERVER_PATH}/config.json | cut -d: -f2)
        [ -z "$CURRENT_WEB_PORT" ] && CURRENT_WEB_PORT=8880
    fi
}

check_server_status() {
    if [ -f ${SERVER_PATH}/server.pid ]; then
        PID=$(cat ${SERVER_PATH}/server.pid 2>/dev/null)
        if ps -p $PID > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

check_client_status() {
    if [ -f ${CLIENT_PATH}/client.pid ]; then
        PID=$(cat ${CLIENT_PATH}/client.pid 2>/dev/null)
        if ps -p $PID > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

check_caddy_status() {
    if pgrep -x "caddy" > /dev/null; then
        return 0
    fi
    return 1
}

# 下载Caddy
install_caddy() {
    yellow "正在安装Caddy..."
    mkdir -p ${CADDY_PATH}
    cd ${CADDY_PATH}
    
    if [ "$OS" = "centos" ] && [ "$OS_VERSION" -eq 6 ]; then
        wget -O caddy.tar.gz https://github.com/caddyserver/caddy/releases/download/v1.0.5/caddy_v1.0.5_linux_amd64.tar.gz
        tar -xzf caddy.tar.gz
        rm -f caddy.tar.gz
        chmod +x caddy
    else
        curl -s https://getcaddy.com | bash -s personal
        cp /usr/local/bin/caddy ${CADDY_PATH}/ 2>/dev/null
    fi
    green "Caddy安装完成"
}

# 配置Caddy
config_caddy() {
    cat > ${CADDY_CONF} << EOF
:${CURRENT_WEB_PORT} {
    gzip
    root ${WEB_PATH}
    proxy /api localhost:8080 {
        without /api
    }
    log ${CADDY_PATH}/caddy.log
    errors ${CADDY_PATH}/caddy-errors.log
}
EOF

    if [ -f /etc/systemd/system/caddy.service ]; then
        systemctl restart caddy
    else
        pkill caddy 2>/dev/null
        nohup ${CADDY_PATH}/caddy -conf ${CADDY_CONF} -agree -email admin@localhost > ${CADDY_PATH}/caddy.log 2>&1 &
        echo $! > ${CADDY_PATH}/caddy.pid
    fi
    green "Caddy配置完成，Web端口: ${CURRENT_WEB_PORT}"
}

# 下载C++服务端
download_server() {
    yellow "正在下载C++服务端..."
    mkdir -p ${SERVER_PATH}
    mkdir -p ${WEB_PATH}
    
    # 下载服务端二进制 (cppla原版)
    cd ${SERVER_PATH}
    wget -O server https://github.com/cppla/ServerStatus/raw/master/server/linux_amd64_server 2>/dev/null
    chmod +x server
    
    # 创建配置文件
    cat > ${SERVER_PATH}/config.json << EOF
{
    "listen_port": ${DEFAULT_SERVER_PORT},
    "web_port": ${CURRENT_WEB_PORT}
}
EOF
    
    # 创建节点配置文件
    cat > ${SERVER_PATH}/nodes.json << EOF
{
    "servers": [
        {
            "username": "server01",
            "name": "服务器01",
            "type": "kvm",
            "host": "",
            "location": "默认",
            "password": "$(openssl rand -base64 8 | cut -c1-8)"
        }
    ]
}
EOF
    
    # 创建启动脚本
    cat > ${SERVER_PATH}/start.sh << EOF
#!/bin/bash
cd ${SERVER_PATH}
nohup ./server -c config.json > server.log 2>&1 &
echo \$! > server.pid
EOF

    cat > ${SERVER_PATH}/stop.sh << EOF
#!/bin/bash
if [ -f ${SERVER_PATH}/server.pid ]; then
    kill \$(cat ${SERVER_PATH}/server.pid)
    rm -f ${SERVER_PATH}/server.pid
else
    pkill -f "./server"
fi
EOF
    
    chmod +x ${SERVER_PATH}/start.sh ${SERVER_PATH}/stop.sh
    green "C++服务端下载完成"
}

# 下载C++客户端
download_client() {
    yellow "正在下载C++客户端..."
    mkdir -p ${CLIENT_PATH}
    
    cd ${CLIENT_PATH}
    wget -O client https://github.com/cppla/ServerStatus/raw/master/client/linux_amd64_client 2>/dev/null
    chmod +x client
    
    cat > ${CLIENT_PATH}/start.sh << EOF
#!/bin/bash
cd ${CLIENT_PATH}
nohup ./client -c config.json > client.log 2>&1 &
echo \$! > client.pid
EOF

    cat > ${CLIENT_PATH}/stop.sh << EOF
#!/bin/bash
if [ -f ${CLIENT_PATH}/client.pid ]; then
    kill \$(cat ${CLIENT_PATH}/client.pid)
    rm -f ${CLIENT_PATH}/client.pid
else
    pkill -f "./client"
fi
EOF
    
    chmod +x ${CLIENT_PATH}/start.sh ${CLIENT_PATH}/stop.sh
    green "C++客户端下载完成"
}

# 创建Web界面 (cppla风格)
create_web() {
    cat > ${WEB_PATH}/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ServerStatus 探针</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#2c3e50;font-family:'Courier New',monospace;padding:20px}
.container{max-width:1400px;margin:0 auto;background:#ecf0f1;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.3);overflow:hidden}
.header{background:#34495e;color:#ecf0f1;padding:15px 20px;border-bottom:3px solid #e67e22}
.header h1{font-size:20px;font-weight:normal}
.header small{font-size:12px;color:#95a5a6}
table{width:100%;border-collapse:collapse;font-size:13px}
th{background:#bdc3c7;padding:10px 8px;text-align:center;border-bottom:1px solid #7f8c8d}
td{padding:8px;text-align:center;border-bottom:1px solid #ddd}
.online{color:#27ae60;font-weight:bold}
.offline{color:#e74c3c;font-weight:bold}
.delay-good{color:#27ae60}
.delay-fair{color:#f39c12}
.delay-bad{color:#e74c3c}
.footer{background:#34495e;color:#95a5a6;padding:8px;text-align:center;font-size:11px}
.refresh-time{background:#ecf0f1;text-align:right;padding:5px 10px;font-size:11px;color:#7f8c8d}
</style>
</head>
<body>
<div class="container">
<div class="header"><h1>ServerStatus 探针 <small>实时监控 | 三网延迟</small></h1></div>
<div class="refresh-time" id="refreshTime">加载中...</div>
<table id="nodeTable">
<thead><tr><th>节点名称</th><th>状态</th><th>负载(1/5/15)</th><th>内存</th><th>硬盘</th><th>网络(上/下)</th><th>电信延迟</th><th>联通延迟</th><th>移动延迟</th></tr></thead>
<tbody id="nodeBody"><tr><td colspan="9">等待数据...<td></tr></tbody>
</table>
<div class="footer">数据实时更新 | 三网延迟基于ICMP探测</div>
</div>
<script>
function formatSpeed(bps){if(!bps)return'0';if(bps<1024)return bps.toFixed(0)+'B';if(bps<1024*1024)return(bps/1024).toFixed(1)+'K';return(bps/(1024*1024)).toFixed(1)+'M';}
function getDelayClass(d){if(!d||d=='--')return'';if(d<50)return'delay-good';if(d<150)return'delay-fair';return'delay-bad';}
function renderTable(nodes){var tbody=document.getElementById('nodeBody');if(!nodes||nodes.length===0){tbody.innerHTML='<tr><td colspan="9">暂无节点数据</td></tr>';return;}
var html='';for(var i=0;i<nodes.length;i++){var n=nodes[i];var statusClass=(n.online===1)?'online':'offline';var statusText=(n.online===1)?'在线':'离线';var load=n.load||[0,0,0];html+='<tr><td>'+n.name+'</td><td class="'+statusClass+'">'+statusText+'</td><td>'+load[0]+'/'+load[1]+'/'+load[2]+'</td><td>'+(n.memory||0)+'%</td><td>'+(n.disk||0)+'%</td><td>↑'+formatSpeed(n.tx_speed)+'/↓'+formatSpeed(n.rx_speed)+'</td><td class="'+getDelayClass(n.telecom)+'">'+(n.telecom==='--'?'--':n.telecom+'ms')+'</td><td class="'+getDelayClass(n.unicom)+'">'+(n.unicom==='--'?'--':n.unicom+'ms')+'</td><td class="'+getDelayClass(n.mobile)+'">'+(n.mobile==='--'?'--':n.mobile+'ms')+'</td></tr>';}
tbody.innerHTML=html;document.getElementById('refreshTime').innerHTML='最后更新: '+new Date().toLocaleTimeString();}
function fetchData(){fetch('/api/nodes').then(res=>res.json()).then(renderTable).catch(e=>console.log(e));}
fetchData();setInterval(fetchData,5000);
</script>
</body>
</html>
EOF

    # 创建API代理 (Python轻量)
    cat > ${WEB_PATH}/api.py << 'EOF'
#!/usr/bin/env python
import json
import os
import socket
import sys
from BaseHTTPServer import HTTPServer, BaseHTTPRequestHandler

STATUS_FILE = "/usr/local/ServerStatus/server/status.json"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/nodes':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            if os.path.exists(STATUS_FILE):
                with open(STATUS_FILE, 'r') as f:
                    self.wfile.write(f.read())
            else:
                self.wfile.write('[]')
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        pass

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), Handler)
    print("API Server running on port 8080")
    server.serve_forever()
EOF
    
    chmod +x ${WEB_PATH}/api.py
    
    # 启动API
    cd ${WEB_PATH}
    nohup python api.py > api.log 2>&1 &
    echo $! > ${WEB_PATH}/api.pid
    
    green "Web界面创建完成"
}

# 安装服务端
install_server() {
    check_root
    detect_os
    blue "========================================="
    blue "开始安装 ServerStatus 服务端 (C++核心)"
    blue "通信端口: ${DEFAULT_SERVER_PORT} (固定)"
    blue "========================================="
    
    read -p "请输入Web访问端口 [默认: 8880]: " input_web
    CURRENT_WEB_PORT=${input_web:-8880}
    
    install_caddy
    download_server
    create_web
    config_caddy
    ${SERVER_PATH}/start.sh
    
    IP_ADDR=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    green """
========================================
服务端安装完成!
========================================
通信端口: ${DEFAULT_SERVER_PORT} (客户端连接用)
Web访问地址: http://${IP_ADDR}:${CURRENT_WEB_PORT}
默认节点: server01 密码: $(grep password ${SERVER_PATH}/nodes.json | head -1 | cut -d'"' -f4)
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
    blue "开始安装 ServerStatus 客户端 (C++核心)"
    blue "========================================="
    
    read -p "请输入服务端IP地址: " server_ip
    read -p "请输入服务端通信端口 [默认: ${DEFAULT_SERVER_PORT}]: " server_port
    server_port=${server_port:-${DEFAULT_SERVER_PORT}}
    read -p "请输入节点用户名: " username
    read -p "请输入节点密码: " password
    read -p "请输入节点名称 [默认: 当前主机名]: " node_name
    node_name=${node_name:-$(hostname)}
    
    download_client
    
    # 创建客户端配置
    cat > ${CLIENT_PATH}/config.json << EOF
{
    "servers": [
        {
            "server": "${server_ip}",
            "port": ${server_port},
            "username": "${username}",
            "password": "${password}",
            "name": "${node_name}"
        }
    ]
}
EOF
    
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
    pkill -f "api.py" 2>/dev/null
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

# 修改Web端口
change_web_port() {
    load_web_port
    echo ""
    blue "当前Web端口: ${CURRENT_WEB_PORT}"
    read -p "请输入新的Web端口: " new_port
    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        red "端口无效"
        return
    fi
    CURRENT_WEB_PORT=$new_port
    sed -i "s/\"web_port\":[0-9]*/\"web_port\":${CURRENT_WEB_PORT}/" ${SERVER_PATH}/config.json
    config_caddy
    ${SERVER_PATH}/stop.sh 2>/dev/null; sleep 1; ${SERVER_PATH}/start.sh
    green "Web端口已修改为 ${CURRENT_WEB_PORT}"
}

# 查看状态
status_server() {
    if check_server_status; then green "服务端: 运行中"; else red "服务端: 未运行"; fi
    if check_caddy_status; then green "Caddy: 运行中"; else red "Caddy: 未运行"; fi
    load_web_port; echo "Web端口: ${CURRENT_WEB_PORT}"
}
status_client() { if check_client_status; then green "客户端: 运行中"; else red "客户端: 未运行"; fi; }
view_log() { tail -50 ${SERVER_PATH}/server.log 2>/dev/null || red "日志不存在"; }
view_client_log() { tail -50 ${CLIENT_PATH}/client.log 2>/dev/null || red "日志不存在"; }

# 升级脚本
update_script() {
    wget -O /tmp/status.sh ${GITHUB_URL}/status.sh 2>/dev/null
    if [ $? -eq 0 ]; then
        mv /tmp/status.sh $0; chmod +x $0
        green "脚本已更新"; exit 0
    else
        red "更新失败"
    fi
}

# 服务端菜单
server_menu() {
    load_web_port
    while true; do
        clear
        blue "========================================="
        blue " ServerStatus 服务端管理菜单 [v${VERSION}]"
        blue " -- 通信端口: ${DEFAULT_SERVER_PORT} | Web端口: ${CURRENT_WEB_PORT} --"
        blue "========================================="
        green "0. 升级 脚本"
        green "————————————"
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
        red "00. 退出脚本"
        blue "========================================="
        if [ -f ${SERVER_PATH}/server ]; then
            check_server_status && green "当前状态: 服务端 已安装 并 已启动" || yellow "当前状态: 服务端 已安装 未启动"
        else
            red "当前状态: 服务端 未安装"
        fi
        blue "========================================="
        read -p "请输入数字: " choice
        case "$choice" in
            0) update_script ;;
            1) install_server ;;
            2) uninstall_server ;;
            3) start_server ;;
            4) stop_server ;;
            5) restart_server ;;
            6) change_web_port ;;
            7) status_server ;;
            8) view_log ;;
            9) client_menu ;;
            00) exit 0 ;;
            *) red "请输入正确的数字" ;;
        esac
    done
}

# 客户端菜单
client_menu() {
    while true; do
        clear
        blue "========================================="
        blue " ServerStatus 客户端管理菜单 [v${VERSION}]"
        blue " -- C++核心 | 三网延迟探测 --"
        blue "========================================="
        green "0. 升级 脚本"
        green "————————————"
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
        red "00. 退出脚本"
        blue "========================================="
        if [ -f ${CLIENT_PATH}/client ]; then
            check_client_status && green "当前状态: 客户端 已安装 并 已启动" || yellow "当前状态: 客户端 已安装 未启动"
        else
            red "当前状态: 客户端 未安装"
        fi
        blue "========================================="
        read -p "请输入数字: " choice
        case "$choice" in
            0) update_script ;;
            1) install_client ;;
            2) uninstall_client ;;
            3) start_client ;;
            4) stop_client ;;
            5) restart_client ;;
            6) status_client ;;
            7) view_client_log ;;
            8) server_menu ;;
            00) exit 0 ;;
            *) red "请输入正确的数字" ;;
        esac
    done
}

if [ "$1" = "c" ]; then
    client_menu
elif [ "$1" = "s" ]; then
    server_menu
else
    server_menu
fi