#!/bin/bash
# ServerStatus 一键管理脚本 v3.0
# 支持 CentOS 6+/Debian 8+/Ubuntu 16+

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[36m'
PLAIN='\033[0m'

SERVER_PATH="/usr/local/ServerStatus"
GITHUB_URL="https://raw.githubusercontent.com/你的用户名/ServerStatus/main"

red() { echo -e "${RED}$1${PLAIN}"; }
green() { echo -e "${GREEN}$1${PLAIN}"; }
yellow() { echo -e "${YELLOW}$1${PLAIN}"; }
blue() { echo -e "${BLUE}$1${PLAIN}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        red "错误: 必须以root权限运行!"
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/redhat-release ]; then
        OS="centos"
    else
        OS="debian"
    fi
}

# 安装服务端
install_server() {
    check_root
    detect_os
    blue "========================================="
    blue "开始安装 ServerStatus 服务端"
    blue "========================================="
    
    # 安装Python3
    if [ "$OS" = "centos" ]; then
        yum install -y python3 python3-pip
    else
        apt-get update
        apt-get install -y python3 python3-pip
    fi
    pip3 install flask psutil requests
    
    # 创建目录
    mkdir -p ${SERVER_PATH}/server
    mkdir -p ${SERVER_PATH}/web/css
    mkdir -p ${SERVER_PATH}/web/js
    
    # 下载服务端文件
    wget -O ${SERVER_PATH}/server/server.py ${GITHUB_URL}/server/server.py
    wget -O ${SERVER_PATH}/server/config.json ${GITHUB_URL}/server/config.json
    
    # 下载Web文件
    wget -O ${SERVER_PATH}/web/index.html ${GITHUB_URL}/web/index.html
    wget -O ${SERVER_PATH}/web/admin.html ${GITHUB_URL}/web/admin.html
    wget -O ${SERVER_PATH}/web/login.html ${GITHUB_URL}/web/login.html
    wget -O ${SERVER_PATH}/web/css/style.css ${GITHUB_URL}/web/css/style.css
    wget -O ${SERVER_PATH}/web/js/main.js ${GITHUB_URL}/web/js/main.js
    
    # 创建links.json
    echo '[]' > ${SERVER_PATH}/web/links.json
    
    # 生成随机密码
    ADMIN_PASS=$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-12)
    sed -i "s/admin123/${ADMIN_PASS}/" ${SERVER_PATH}/server/config.json
    
    # 创建启动脚本
    cat > ${SERVER_PATH}/server/start.sh << 'SHEOF'
#!/bin/bash
cd /usr/local/ServerStatus/server
nohup python3 server.py > server.log 2>&1 &
echo $! > server.pid
echo "服务端已启动"
SHEOF
    
    cat > ${SERVER_PATH}/server/stop.sh << 'SHEOF'
#!/bin/bash
if [ -f /usr/local/ServerStatus/server/server.pid ]; then
    kill $(cat /usr/local/ServerStatus/server/server.pid) 2>/dev/null
    rm -f /usr/local/ServerStatus/server/server.pid
fi
pkill -f "python3 server.py" 2>/dev/null
echo "服务端已停止"
SHEOF
    
    chmod +x ${SERVER_PATH}/server/start.sh
    chmod +x ${SERVER_PATH}/server/stop.sh
    
    # 启动
    cd ${SERVER_PATH}/server
    nohup python3 server.py > server.log 2>&1 &
    echo $! > server.pid
    
    IP_ADDR=$(curl -s ifconfig.me)
    green ""
    green "========================================="
    green "服务端安装完成!"
    green "========================================="
    green "前台: http://${IP_ADDR}:8880"
    green "后台: http://${IP_ADDR}:8880/admin"
    green "账号: admin"
    green "密码: ${ADMIN_PASS}"
    green "========================================="
}

# 安装客户端
install_client() {
    check_root
    detect_os
    blue "========================================="
    blue "开始安装 ServerStatus 客户端"
    blue "========================================="
    
    read -p "服务端IP地址: " server_ip
    read -p "节点名称 [默认: $(hostname)]: " node_name
    node_name=${node_name:-$(hostname)}
    read -p "位置 [默认: 默认]: " location
    location=${location:-默认}
    
    # 安装Python3
    if [ "$OS" = "centos" ]; then
        yum install -y python3 python3-pip
    else
        apt-get update
        apt-get install -y python3 python3-pip
    fi
    pip3 install psutil requests
    
    # 创建目录
    mkdir -p ${SERVER_PATH}/clients
    
    # 下载客户端
    wget -O ${SERVER_PATH}/clients/client.py ${GITHUB_URL}/client/client.py
    
    # 创建配置
    echo "${server_ip} 8880 ${node_name} ${location}" > ${SERVER_PATH}/clients/config.txt
    
    # 创建启动脚本
    cat > ${SERVER_PATH}/clients/start.sh << 'SHEOF'
#!/bin/bash
cd /usr/local/ServerStatus/clients
if [ -f config.txt ]; then
    nohup python3 client.py $(cat config.txt) > client.log 2>&1 &
    echo $! > client.pid
    echo "客户端已启动"
else
    echo "配置文件不存在"
fi
SHEOF
    
    cat > ${SERVER_PATH}/clients/stop.sh << 'SHEOF'
#!/bin/bash
if [ -f /usr/local/ServerStatus/clients/client.pid ]; then
    kill $(cat /usr/local/ServerStatus/clients/client.pid) 2>/dev/null
    rm -f /usr/local/ServerStatus/clients/client.pid
fi
pkill -f "python3 client.py" 2>/dev/null
echo "客户端已停止"
SHEOF
    
    chmod +x ${SERVER_PATH}/clients/start.sh
    chmod +x ${SERVER_PATH}/clients/stop.sh
    
    # 启动
    cd ${SERVER_PATH}/clients
    nohup python3 client.py ${server_ip} 8880 ${node_name} ${location} > client.log 2>&1 &
    echo $! > client.pid
    
    green ""
    green "========================================="
    green "客户端安装完成!"
    green "========================================="
    green "服务端: ${server_ip}:8880"
    green "节点名: ${node_name}"
    green "位置: ${location}"
    green "========================================="
}

# 服务端菜单
server_menu() {
    while true; do
        clear
        blue "========================================="
        blue " ServerStatus 服务端管理菜单"
        blue "========================================="
        green "1. 安装 服务端"
        green "2. 卸载 服务端"
        green "————————————"
        green "3. 启动 服务端"
        green "4. 停止 服务端"
        green "5. 重启 服务端"
        green "————————————"
        green "6. 查看 日志"
        green "7. 查看 状态"
        green "0. 退出"
        blue "========================================="
        
        if [ -f ${SERVER_PATH}/server/server.py ]; then
            if ps aux | grep -v grep | grep "python3 server.py" > /dev/null; then
                green "当前状态: 服务端 已安装 并 已启动"
            else
                yellow "当前状态: 服务端 已安装 未启动"
            fi
        else
            red "当前状态: 服务端 未安装"
        fi
        blue "========================================="
        
        read -p "请选择 [0-7]: " choice
        case $choice in
            1) install_server ;;
            2) pkill -f "python3 server.py"; rm -rf ${SERVER_PATH}; green "卸载完成" ;;
            3) cd ${SERVER_PATH}/server && nohup python3 server.py > server.log 2>&1 & echo $! > server.pid && green "服务端已启动" ;;
            4) cd ${SERVER_PATH}/server && ./stop.sh ;;
            5) cd ${SERVER_PATH}/server && ./stop.sh; sleep 1; ./start.sh ;;
            6) tail -50 ${SERVER_PATH}/server/server.log 2>/dev/null || red "日志不存在" ;;
            7) if ps aux | grep -v grep | grep "python3 server.py" > /dev/null; then green "服务端运行中"; else red "服务端未运行"; fi ;;
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
        blue " ServerStatus 客户端管理菜单"
        blue "========================================="
        green "1. 安装 客户端"
        green "2. 卸载 客户端"
        green "————————————"
        green "3. 启动 客户端"
        green "4. 停止 客户端"
        green "5. 重启 客户端"
        green "————————————"
        green "6. 查看 日志"
        green "7. 查看 状态"
        green "0. 退出"
        blue "========================================="
        
        if [ -f ${SERVER_PATH}/clients/client.py ]; then
            if ps aux | grep -v grep | grep "python3 client.py" > /dev/null; then
                green "当前状态: 客户端 已安装 并 已启动"
            else
                yellow "当前状态: 客户端 已安装 未启动"
            fi
        else
            red "当前状态: 客户端 未安装"
        fi
        blue "========================================="
        
        read -p "请选择 [0-7]: " choice
        case $choice in
            1) install_client ;;
            2) pkill -f "python3 client.py"; rm -rf ${SERVER_PATH}/clients; green "客户端卸载完成" ;;
            3) cd ${SERVER_PATH}/clients && ./start.sh ;;
            4) cd ${SERVER_PATH}/clients && ./stop.sh ;;
            5) cd ${SERVER_PATH}/clients && ./stop.sh; sleep 1; ./start.sh ;;
            6) tail -50 ${SERVER_PATH}/clients/client.log 2>/dev/null || red "日志不存在" ;;
            7) if ps aux | grep -v grep | grep "python3 client.py" > /dev/null; then green "客户端运行中"; else red "客户端未运行"; fi ;;
            0) exit 0 ;;
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