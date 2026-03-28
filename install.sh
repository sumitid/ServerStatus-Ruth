#!/bin/bash
# ServerStatus 一键安装脚本
# 支持 CentOS 6+/Debian 8+/Ubuntu 16+
# 兼容 Python 2.7 / 3.4+

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[36m'
PLAIN='\033[0m'

# 服务端路径
SERVER_PATH="/opt/ServerStatus"
SERVER_PORT=8888
WEB_PORT=8080

# 颜色输出函数
red() { echo -e "${RED}$1${PLAIN}"; }
green() { echo -e "${GREEN}$1${PLAIN}"; }
yellow() { echo -e "${YELLOW}$1${PLAIN}"; }
blue() { echo -e "${BLUE}$1${PLAIN}"; }

# 检查root权限
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
    green "检测到系统: $OS $OS_VERSION"
}

# 检测Python版本并安装
install_python() {
    yellow "检测Python环境..."
    
    # 检查Python版本
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
        PY_VERSION=$(python3 -c 'import sys; print(sys.version_info[0])')
        green "使用 Python 3"
    elif command -v python2 &> /dev/null; then
        PYTHON_CMD="python2"
        PY_VERSION=2
        # 检查Python 2.7
        PY_MINOR=$(python2 -c 'import sys; print(sys.version_info[1])')
        if [ $PY_MINOR -lt 7 ]; then
            yellow "Python 2.6 检测到，部分功能可能受限"
        fi
        green "使用 Python 2.7"
    else
        yellow "未检测到Python，开始安装..."
        if [ "$OS" = "centos" ]; then
            if [ "$OS_VERSION" -eq 6 ]; then
                # CentOS 6 安装Python 2.7
                yum install -y centos-release-scl
                yum install -y python27 python27-python-pip
                ln -sf /opt/rh/python27/root/usr/bin/python2.7 /usr/bin/python2.7
                PYTHON_CMD="/opt/rh/python27/root/usr/bin/python2.7"
                # 安装pip
                curl https://bootstrap.pypa.io/pip/2.7/get-pip.py | $PYTHON_CMD
            else
                yum install -y python3 python3-pip
                PYTHON_CMD="python3"
            fi
        else
            apt-get update
            apt-get install -y python3 python3-pip
            PYTHON_CMD="python3"
        fi
    fi
    
    # 安装pip依赖（兼容低版本）
    yellow "安装Python依赖..."
    $PYTHON_CMD -c "import sqlite3" 2>/dev/null
    if [ $? -ne 0 ]; then
        if [ "$OS" = "centos" ]; then
            yum install -y sqlite-devel
        else
            apt-get install -y sqlite3 libsqlite3-dev
        fi
    fi
    
    # 安装pip包（兼容语法）
    if $PYTHON_CMD -c "import sys; sys.exit(0 if sys.version_info[0]==3 else 1)" 2>/dev/null; then
        # Python 3
        pip3 install flask flask-socketio psutil netifaces requests
    else
        # Python 2.7
        pip install flask flask-socketio psutil netifaces requests futures
    fi
    
    green "Python环境配置完成"
}

# 创建目录结构
create_dirs() {
    yellow "创建目录结构..."
    mkdir -p ${SERVER_PATH}
    mkdir -p ${SERVER_PATH}/static/css
    mkdir -p ${SERVER_PATH}/static/js
    mkdir -p ${SERVER_PATH}/templates
    mkdir -p ${SERVER_PATH}/tools
    green "目录创建完成: ${SERVER_PATH}"
}

# 生成配置文件
create_config() {
    cat > ${SERVER_PATH}/config.json << EOF
{
    "server_port": ${SERVER_PORT},
    "web_port": ${WEB_PORT},
    "database": "${SERVER_PATH}/probe.db",
    "log_file": "${SERVER_PATH}/server.log",
    "admin_user": "admin",
    "admin_pass": "$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-12)",
    "debug": false
}
EOF
    green "配置文件创建完成"
}

# 创建数据库模块 (兼容Python 2.7/3.x)
create_database() {
    cat > ${SERVER_PATH}/database.py << 'EOF'
#!/usr/bin/env python
# -*- coding: utf-8 -*-
# ServerStatus 数据库模块 - 兼容 Python 2.7/3.x

from __future__ import print_function, absolute_import
import sqlite3
import json
import time
from datetime import datetime

class Database:
    def __init__(self, db_path):
        self.db_path = db_path
        self.init_db()
    
    def _get_now(self):
        """获取当前时间戳（兼容Python 2/3）"""
        return datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    def init_db(self):
        """初始化数据库表"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        # 客户端表
        c.execute('''CREATE TABLE IF NOT EXISTS clients (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_id TEXT UNIQUE NOT NULL,
            name TEXT,
            group_name TEXT DEFAULT 'default',
            status TEXT DEFAULT 'offline',
            last_seen TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )''')
        
        # 监控数据表
        c.execute('''CREATE TABLE IF NOT EXISTS metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_id TEXT NOT NULL,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            cpu REAL,
            memory REAL,
            disk REAL,
            load1 REAL,
            load5 REAL,
            load15 REAL,
            rx_speed REAL,
            tx_speed REAL,
            rx_total INTEGER,
            tx_total INTEGER,
            ipv4 TEXT,
            ipv6 TEXT,
            os TEXT,
            hostname TEXT,
            delays TEXT
        )''')
        
        # 命令表
        c.execute('''CREATE TABLE IF NOT EXISTS commands (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_id TEXT NOT NULL,
            command TEXT NOT NULL,
            status TEXT DEFAULT 'pending',
            output TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )''')
        
        conn.commit()
        conn.close()
        print("数据库初始化完成")
    
    def register_client(self, client_id, name=None, group='default'):
        """注册客户端"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        try:
            c.execute('''INSERT OR REPLACE INTO clients 
                         (client_id, name, group_name, status, last_seen)
                         VALUES (?, ?, ?, 'online', ?)''',
                      (client_id, name or client_id, group, self._get_now()))
            conn.commit()
            return True
        except Exception as e:
            print("注册失败: %s" % str(e))
            return False
        finally:
            conn.close()
    
    def save_metrics(self, client_id, data):
        """保存监控数据"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        try:
            # 更新客户端最后在线时间
            c.execute('''UPDATE clients SET status='online', last_seen=?
                         WHERE client_id=?''', (self._get_now(), client_id))
            
            # 解析数据
            cpu = data.get('performance', {}).get('cpu_usage', 0)
            memory = data.get('performance', {}).get('memory', {}).get('percent', 0)
            disk = data.get('performance', {}).get('disk', {}).get('percent', 0)
            load = data.get('performance', {}).get('load', [0, 0, 0])
            network = data.get('network', {})
            system = data.get('system', {})
            delays = data.get('delays', {})
            
            c.execute('''INSERT INTO metrics 
                         (client_id, cpu, memory, disk, load1, load5, load15,
                          rx_speed, tx_speed, rx_total, tx_total, ipv4, ipv6,
                          os, hostname, delays)
                         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                      (client_id, cpu, memory, disk, 
                       load[0] if len(load) > 0 else 0,
                       load[1] if len(load) > 1 else 0,
                       load[2] if len(load) > 2 else 0,
                       network.get('rx_speed', 0), network.get('tx_speed', 0),
                       network.get('rx_total', 0), network.get('tx_total', 0),
                       network.get('ipv4', ''), network.get('ipv6', ''),
                       system.get('os', ''), system.get('hostname', ''),
                       json.dumps(delays)))
            
            conn.commit()
            return True
        except Exception as e:
            print("保存数据失败: %s" % str(e))
            return False
        finally:
            conn.close()
    
    def get_clients(self):
        """获取客户端列表"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        c.execute('''SELECT client_id, name, group_name, status, last_seen 
                     FROM clients ORDER BY group_name, name''')
        rows = c.fetchall()
        conn.close()
        
        clients = []
        for row in rows:
            clients.append({
                'client_id': row[0],
                'name': row[1],
                'group': row[2],
                'status': row[3],
                'last_seen': row[4]
            })
        return clients
    
    def get_latest_metrics(self, client_id):
        """获取客户端最新数据"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        c.execute('''SELECT cpu, memory, disk, load1, load5, load15,
                            rx_speed, tx_speed, rx_total, tx_total,
                            ipv4, ipv6, os, hostname, delays, timestamp
                     FROM metrics WHERE client_id=? 
                     ORDER BY timestamp DESC LIMIT 1''', (client_id,))
        row = c.fetchone()
        conn.close()
        
        if row:
            return {
                'cpu': row[0],
                'memory': row[1],
                'disk': row[2],
                'load': [row[3], row[4], row[5]],
                'network': {
                    'rx_speed': row[6],
                    'tx_speed': row[7],
                    'rx_total': row[8],
                    'tx_total': row[9],
                    'ipv4': row[10],
                    'ipv6': row[11]
                },
                'system': {'os': row[12], 'hostname': row[13]},
                'delays': json.loads(row[14]) if row[14] else {},
                'timestamp': row[15]
            }
        return {}
    
    def add_command(self, client_id, command):
        """添加命令"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        c.execute('''INSERT INTO commands (client_id, command) 
                     VALUES (?, ?)''', (client_id, command))
        conn.commit()
        cmd_id = c.lastrowid
        conn.close()
        return cmd_id
    
    def get_pending_commands(self, client_id):
        """获取待执行命令"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        c.execute('''SELECT id, command FROM commands 
                     WHERE client_id=? AND status='pending'
                     ORDER BY created_at''', (client_id,))
        rows = c.fetchall()
        conn.close()
        return [{'id': row[0], 'command': row[1]} for row in rows]
    
    def update_command_result(self, cmd_id, output, status='completed'):
        """更新命令执行结果"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        c.execute('''UPDATE commands SET output=?, status=?
                     WHERE id=?''', (output, status, cmd_id))
        conn.commit()
        conn.close()
EOF
    green "数据库模块创建完成"
}

# 创建主服务端程序 (兼容低版本Python)
create_server() {
    cat > ${SERVER_PATH}/server.py << 'EOF'
#!/usr/bin/env python
# -*- coding: utf-8 -*-
# ServerStatus 服务端主程序 - 兼容 Python 2.7/3.x

from __future__ import print_function, absolute_import
import os
import sys
import json
import time
import threading
from datetime import datetime

# 尝试导入Flask（兼容不同版本）
try:
    from flask import Flask, render_template, request, jsonify
except ImportError:
    print("错误: 未安装Flask，请运行: pip install flask")
    sys.exit(1)

try:
    from flask_socketio import SocketIO
except ImportError:
    SocketIO = None
    print("提示: flask-socketio未安装，WebSocket功能不可用")

# 导入数据库模块
sys.path.insert(0, '/opt/ServerStatus')
from database import Database

# 读取配置
CONFIG_FILE = "/opt/ServerStatus/config.json"
with open(CONFIG_FILE, 'r') as f:
    CONFIG = json.load(f)

WEB_PORT = CONFIG.get('web_port', 8080)
DATABASE = CONFIG.get('database', '/opt/ServerStatus/probe.db')
ADMIN_USER = CONFIG.get('admin_user', 'admin')
ADMIN_PASS = CONFIG.get('admin_pass', 'admin123')

# 初始化Flask
app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24)

if SocketIO:
    socketio = SocketIO(app, cors_allowed_origins="*")
else:
    socketio = None

# 初始化数据库
db = Database(DATABASE)

# ============= API路由 =============

@app.route('/api/client/register', methods=['POST'])
def register_client():
    """客户端注册"""
    try:
        data = request.get_json()
        client_id = data.get('client_id')
        name = data.get('name', client_id)
        group = data.get('group', 'default')
        
        if db.register_client(client_id, name, group):
            return jsonify({'status': 'ok'})
        return jsonify({'status': 'error'}), 400
    except Exception as e:
        return jsonify({'status': 'error', 'msg': str(e)}), 500

@app.route('/api/client/report', methods=['POST'])
def report_metrics():
    """客户端上报数据"""
    try:
        data = request.get_json()
        client_id = data.get('client_id')
        metrics = data.get('metrics', {})
        
        # 保存数据
        db.save_metrics(client_id, metrics)
        
        # 检查是否有待执行命令
        pending = db.get_pending_commands(client_id)
        if pending:
            return jsonify({'commands': pending})
        
        return jsonify({'status': 'ok'})
    except Exception as e:
        return jsonify({'status': 'error', 'msg': str(e)}), 500

@app.route('/api/clients')
def get_clients():
    """获取客户端列表"""
    clients = db.get_clients()
    # 添加最新数据
    for client in clients:
        client['metrics'] = db.get_latest_metrics(client['client_id'])
    return jsonify(clients)

@app.route('/api/client/<client_id>/latest')
def get_latest(client_id):
    """获取客户端最新数据"""
    data = db.get_latest_metrics(client_id)
    return jsonify(data)

@app.route('/api/command', methods=['POST'])
def send_command():
    """发送命令"""
    try:
        data = request.get_json()
        client_id = data.get('client_id')
        command = data.get('command')
        
        cmd_id = db.add_command(client_id, command)
        return jsonify({'command_id': cmd_id})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ============= 页面路由 =============

@app.route('/')
def index():
    """前台监控页面"""
    return render_template('index.html')

@app.route('/admin')
def admin():
    """后台管理页面"""
    return render_template('admin.html')

# ============= 启动服务 =============

if __name__ == '__main__':
    # 获取本机IP
    try:
        import socket
        hostname = socket.gethostname()
        ip = socket.gethostbyname(hostname)
    except:
        ip = '0.0.0.0'
    
    print("""
========================================
ServerStatus 服务端已启动
========================================
Web访问: http://%s:%d
管理账号: %s
管理密码: %s
数据端口: %d
========================================
    """ % (ip, WEB_PORT, ADMIN_USER, ADMIN_PASS, CONFIG.get('server_port', 8888)))
    
    if socketio:
        socketio.run(app, host='0.0.0.0', port=WEB_PORT, debug=False)
    else:
        app.run(host='0.0.0.0', port=WEB_PORT, debug=False)
EOF
    chmod +x ${SERVER_PATH}/server.py
    green "服务端主程序创建完成"
}

# 创建HTML模板 (简化版)
create_templates() {
    # 创建前台模板
    cat > ${SERVER_PATH}/templates/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ServerStatus 监控面板</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        .header {
            background: rgba(255,255,255,0.95);
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
            gap: 20px;
        }
        .client-card {
            background: rgba(255,255,255,0.95);
            border-radius: 10px;
            padding: 15px;
            transition: transform 0.2s;
            cursor: pointer;
        }
        .client-card:hover { transform: translateY(-2px); }
        .client-online { border-left: 4px solid #2ecc71; }
        .client-offline { border-left: 4px solid #e74c3c; opacity: 0.6; }
        .client-name { font-size: 18px; font-weight: bold; margin-bottom: 10px; }
        .client-stats { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; font-size: 12px; }
        .stat { display: flex; justify-content: space-between; }
        .stat-label { color: #666; }
        .stat-value { font-weight: bold; }
        .progress-bar {
            height: 4px;
            background: #e0e0e0;
            border-radius: 2px;
            overflow: hidden;
            margin-top: 4px;
        }
        .progress-fill { height: 100%; background: #3498db; width: 0%; }
        .refresh-time {
            text-align: center;
            color: white;
            margin-top: 20px;
            font-size: 12px;
        }
        .delay-green { color: #2ecc71; }
        .delay-yellow { color: #f39c12; }
        .delay-red { color: #e74c3c; }
        @media (max-width: 768px) {
            .stats-grid { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 ServerStatus 监控面板</h1>
            <div>实时服务器状态监控 | 三网延迟动态刷新</div>
        </div>
        <div id="clients" class="stats-grid"></div>
        <div class="refresh-time" id="refreshTime"></div>
    </div>
    <script>
        function formatBytes(bytes) {
            if (!bytes) return '0 B';
            var k = 1024;
            var sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
            var i = Math.floor(Math.log(bytes) / Math.log(k));
            return (bytes / Math.pow(k, i)).toFixed(1) + ' ' + sizes[i];
        }
        
        function formatSpeed(bytesPerSec) {
            if (!bytesPerSec) return '0 B/s';
            if (bytesPerSec < 1024) return bytesPerSec.toFixed(0) + ' B/s';
            if (bytesPerSec < 1024 * 1024) return (bytesPerSec / 1024).toFixed(1) + ' KB/s';
            return (bytesPerSec / (1024 * 1024)).toFixed(1) + ' MB/s';
        }
        
        function getDelayClass(delay) {
            if (!delay) return '';
            if (delay < 50) return 'delay-green';
            if (delay < 150) return 'delay-yellow';
            return 'delay-red';
        }
        
        function renderCard(client, data) {
            var online = client.status === 'online';
            var cpu = data.cpu || 0;
            var mem = data.memory || 0;
            var disk = data.disk || 0;
            var rxSpeed = data.network ? data.network.rx_speed : 0;
            var txSpeed = data.network ? data.network.tx_speed : 0;
            var delays = data.delays || {};
            
            return '<div class="client-card ' + (online ? 'client-online' : 'client-offline') + '">' +
                '<div class="client-name">' + (client.name || client.client_id) + '</div>' +
                '<div class="client-stats">' +
                    '<div class="stat"><span class="stat-label">💻 CPU</span><span class="stat-value">' + cpu + '%</span></div>' +
                    '<div class="progress-bar"><div class="progress-fill" style="width: ' + cpu + '%; background: #3498db;"></div></div>' +
                    '<div class="stat"><span class="stat-label">🧠 内存</span><span class="stat-value">' + mem + '%</span></div>' +
                    '<div class="progress-bar"><div class="progress-fill" style="width: ' + mem + '%; background: #2ecc71;"></div></div>' +
                    '<div class="stat"><span class="stat-label">💾 磁盘</span><span class="stat-value">' + disk + '%</span></div>' +
                    '<div class="progress-bar"><div class="progress-fill" style="width: ' + disk + '%; background: #f39c12;"></div></div>' +
                    '<div class="stat"><span class="stat-label">📤 上行</span><span class="stat-value">' + formatSpeed(txSpeed) + '</span></div>' +
                    '<div class="stat"><span class="stat-label">📥 下行</span><span class="stat-value">' + formatSpeed(rxSpeed) + '</span></div>' +
                    '<div class="stat"><span class="stat-label">电信延迟</span><span class="stat-value ' + getDelayClass(delays.telecom) + '">' + (delays.telecom ? delays.telecom + 'ms' : '--') + '</span></div>' +
                    '<div class="stat"><span class="stat-label">联通延迟</span><span class="stat-value ' + getDelayClass(delays.unicom) + '">' + (delays.unicom ? delays.unicom + 'ms' : '--') + '</span></div>' +
                    '<div class="stat"><span class="stat-label">移动延迟</span><span class="stat-value ' + getDelayClass(delays.mobile) + '">' + (delays.mobile ? delays.mobile + 'ms' : '--') + '</span></div>' +
                '</div>' +
                '<div style="font-size: 10px; color: #999; margin-top: 10px;">' + (data.system ? data.system.hostname : '') + ' | ' + (online ? '在线' : '离线') + '</div>' +
            '</div>';
        }
        
        function fetchData() {
            fetch('/api/clients')
                .then(function(res) { return res.json(); })
                .then(function(clients) {
                    var container = document.getElementById('clients');
                    container.innerHTML = '';
                    for (var i = 0; i < clients.length; i++) {
                        var client = clients[i];
                        var data = client.metrics || {};
                        container.innerHTML += renderCard(client, data);
                    }
                });
            document.getElementById('refreshTime').innerHTML = '最后更新: ' + new Date().toLocaleTimeString();
        }
        
        fetchData();
        setInterval(fetchData, 5000);
    </script>
</body>
</html>
EOF

    # 创建后台模板
    cat > ${SERVER_PATH}/templates/admin.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ServerStatus 后台管理</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #1a1a2e;
            padding: 20px;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        .header {
            background: #16213e;
            color: white;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
        }
        .admin-content {
            background: white;
            border-radius: 10px;
            padding: 20px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background: #f5f5f5;
        }
        .online { color: #2ecc71; font-weight: bold; }
        .offline { color: #e74c3c; }
        .btn {
            padding: 5px 10px;
            background: #3498db;
            color: white;
            border: none;
            border-radius: 3px;
            cursor: pointer;
        }
        .btn:hover { background: #2980b9; }
        textarea {
            width: 100%;
            padding: 10px;
            margin: 10px 0;
            font-family: monospace;
        }
        .command-output {
            background: #1e1e1e;
            color: #d4d4d4;
            padding: 15px;
            border-radius: 5px;
            font-family: monospace;
            white-space: pre-wrap;
            margin-top: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>⚙️ ServerStatus 后台管理</h1>
            <p>客户端管理 | 命令执行 | 实时监控</p>
        </div>
        <div class="admin-content">
            <h2>客户端列表</h2>
            <div id="clientsList"></div>
        </div>
    </div>
    <script>
        var currentClient = null;
        
        function renderClients(clients) {
            var html = '<table><tr><th>客户端ID</th><th>名称</th><th>状态</th><th>最后在线</th><th>操作</th></tr>';
            for (var i = 0; i < clients.length; i++) {
                var c = clients[i];
                var statusClass = c.status === 'online' ? 'online' : 'offline';
                html += '<tr>' +
                    '<td>' + c.client_id + '</td>' +
                    '<td>' + c.name + '</td>' +
                    '<td class="' + statusClass + '">' + (c.status === 'online' ? '在线' : '离线') + '</td>' +
                    '<td>' + (c.last_seen || '--') + '</td>' +
                    '<td><button class="btn" onclick="selectClient(\'' + c.client_id + '\')">执行命令</button></td>' +
                '</tr>';
            }
            html += '</table>';
            document.getElementById('clientsList').innerHTML = html;
        }
        
        function selectClient(clientId) {
            currentClient = clientId;
            var html = '<h3>向 ' + clientId + ' 发送命令</h3>' +
                '<textarea id="commandInput" rows="4" placeholder="输入要执行的Shell命令..."></textarea><br>' +
                '<button class="btn" onclick="sendCommand()">执行命令</button>' +
                '<div id="commandOutput" class="command-output"></div>';
            document.getElementById('clientsList').innerHTML = html;
        }
        
        function sendCommand() {
            var command = document.getElementById('commandInput').value;
            if (!command) return;
            
            fetch('/api/command', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({client_id: currentClient, command: command})
            })
            .then(function(res) { return res.json(); })
            .then(function(data) {
                document.getElementById('commandOutput').innerHTML = '命令已发送，ID: ' + data.command_id;
                pollResult(data.command_id);
            });
        }
        
        function pollResult(cmdId) {
            var count = 0;
            var interval = setInterval(function() {
                fetch('/api/command/' + cmdId + '/result')
                    .then(function(res) { return res.json(); })
                    .then(function(data) {
                        if (data.status !== 'pending') {
                            clearInterval(interval);
                            document.getElementById('commandOutput').innerHTML = '<pre>' + (data.output || '执行完成') + '</pre>';
                        }
                    });
                count++;
                if (count > 30) clearInterval(interval);
            }, 2000);
        }
        
        function fetchClients() {
            fetch('/api/clients')
                .then(function(res) { return res.json(); })
                .then(function(data) {
                    if (!currentClient) {
                        renderClients(data);
                    }
                });
        }
        
        fetchClients();
        setInterval(fetchClients, 10000);
    </script>
</body>
</html>
EOF
    green "HTML模板创建完成"
}

# 创建启动/停止脚本
create_scripts() {
    cat > ${SERVER_PATH}/start.sh << 'EOF'
#!/bin/bash
cd /opt/ServerStatus
nohup python server.py > server.log 2>&1 &
echo $! > server.pid
echo "ServerStatus 服务端已启动 (PID: $(cat server.pid))"
EOF

    cat > ${SERVER_PATH}/stop.sh << 'EOF'
#!/bin/bash
if [ -f /opt/ServerStatus/server.pid ]; then
    kill $(cat /opt/ServerStatus/server.pid)
    rm -f /opt/ServerStatus/server.pid
    echo "ServerStatus 服务端已停止"
else
    pkill -f "python.*server.py"
    echo "ServerStatus 服务端已停止"
fi
EOF

    cat > ${SERVER_PATH}/status.sh << 'EOF'
#!/bin/bash
if [ -f /opt/ServerStatus/server.pid ]; then
    PID=$(cat /opt/ServerStatus/server.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo "服务端运行中 (PID: $PID)"
        exit 0
    fi
fi
echo "服务端未运行"
exit 1
EOF

    chmod +x ${SERVER_PATH}/start.sh
    chmod +x ${SERVER_PATH}/stop.sh
    chmod +x ${SERVER_PATH}/status.sh
    green "启动脚本创建完成"
}

# 创建客户端安装脚本
create_client_installer() {
    cat > ${SERVER_PATH}/static/client.sh << 'EOF'
#!/bin/bash
# ServerStatus 客户端一键安装脚本

RED='\033[31m'
GREEN='\033[32m'
PLAIN='\033[0m'

SERVER_IP=$1
SERVER_PORT=$2

if [ -z "$SERVER_IP" ] || [ -z "$SERVER_PORT" ]; then
    echo -e "${RED}用法: bash client.sh <服务端IP> <服务端端口>${PLAIN}"
    exit 1
fi

# 安装Python依赖
if command -v yum &> /dev/null; then
    yum install -y python3 python3-pip 2>/dev/null || yum install -y python2 python2-pip
else
    apt-get update
    apt-get install -y python3 python3-pip 2>/dev/null || apt-get install -y python python-pip
fi

# 安装pip包
pip install psutil requests 2>/dev/null || pip3 install psutil requests

# 下载客户端到/root
cd /root
cat > /root/status-client.py << 'INNEREOF'
#!/usr/bin/env python
# -*- coding: utf-8 -*-
import psutil
import socket
import requests
import json
import time
import platform
import subprocess
import sys
import os
from datetime import datetime

class StatusClient:
    def __init__(self, server_ip, server_port, client_id):
        self.server_url = "http://%s:%s" % (server_ip, server_port)
        self.client_id = client_id
        self.interval = 5
        self.last_net = psutil.net_io_counters()
        self.last_time = time.time()
    
    def ping_node(self, ip):
        """执行ping测试"""
        try:
            result = subprocess.Popen(
                ['ping', '-c', '1', '-W', '1', ip],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            output, _ = result.communicate(timeout=3)
            output_str = output.decode('utf-8', errors='ignore')
            
            import re
            match = re.search(r'time[=<](\d+\.?\d*)\s*ms', output_str)
            if match:
                return float(match.group(1))
            return None
        except:
            return None
    
    def get_delays(self):
        """获取三网延迟"""
        nodes = {
            'telecom': ['114.114.114.114', '180.153.28.5'],
            'unicom': ['123.125.126.99', '202.102.128.68'],
            'mobile': ['211.136.28.66', '221.130.33.52']
        }
        
        delays = {}
        for isp, ips in nodes.items():
            best = None
            for ip in ips:
                d = self.ping_node(ip)
                if d and (best is None or d < best):
                    best = d
            delays[isp] = best
        return delays
    
    def collect(self):
        current_net = psutil.net_io_counters()
        current_time = time.time()
        time_diff = current_time - self.last_time
        rx_speed = (current_net.bytes_recv - self.last_net.bytes_recv) / time_diff if time_diff > 0 else 0
        tx_speed = (current_net.bytes_sent - self.last_net.bytes_sent) / time_diff if time_diff > 0 else 0
        self.last_net = current_net
        self.last_time = current_time
        
        ipv4 = None
        try:
            for iface, addrs in psutil.net_if_addrs().items():
                for addr in addrs:
                    if addr.family == socket.AF_INET and not ipv4:
                        ipv4 = addr.address
        except:
            pass
        
        return {
            'client_id': self.client_id,
            'metrics': {
                'timestamp': datetime.now().isoformat(),
                'system': {
                    'hostname': socket.gethostname(),
                    'os': platform.platform()
                },
                'performance': {
                    'cpu_usage': psutil.cpu_percent(interval=1),
                    'memory': {'percent': psutil.virtual_memory().percent},
                    'disk': {'percent': psutil.disk_usage('/').percent},
                    'load': list(psutil.getloadavg()) if hasattr(psutil, 'getloadavg') else [0,0,0]
                },
                'network': {
                    'rx_speed': rx_speed,
                    'tx_speed': tx_speed,
                    'rx_total': current_net.bytes_recv,
                    'tx_total': current_net.bytes_sent,
                    'ipv4': ipv4
                },
                'delays': self.get_delays()
            }
        }
    
    def register(self):
        try:
            data = {'client_id': self.client_id, 'name': socket.gethostname()}
            requests.post(self.server_url + "/api/client/register", json=data, timeout=5)
            return True
        except:
            return False
    
    def report(self):
        try:
            data = self.collect()
            r = requests.post(self.server_url + "/api/client/report", json=data, timeout=5)
            return True
        except:
            return False
    
    def run(self):
        print("客户端启动: %s -> %s" % (self.client_id, self.server_url))
        self.register()
        while True:
            try:
                self.report()
                time.sleep(self.interval)
            except KeyboardInterrupt:
                break
            except Exception as e:
                print("错误: %s" % str(e))
                time.sleep(10)

if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("用法: python status-client.py <服务端IP> <端口> <客户端ID>")
        sys.exit(1)
    client = StatusClient(sys.argv[1], int(sys.argv[2]), sys.argv[3])
    client.run()
INNEREOF

chmod +x /root/status-client.py

# 获取客户端ID
CLIENT_NAME=$(hostname)
echo -e "${GREEN}请输入客户端标识 [默认: $CLIENT_NAME]:${PLAIN}"
read input_name
CLIENT_NAME=${input_name:-$CLIENT_NAME}

# 创建启动脚本
cat > /root/start-client.sh << EOF
#!/bin/bash
cd /root
nohup python status-client.py $SERVER_IP $SERVER_PORT $CLIENT_NAME > client.log 2>&1 &
echo \$! > client.pid
echo "客户端已启动"
EOF

cat > /root/stop-client.sh << EOF
#!/bin/bash
if [ -f /root/client.pid ]; then
    kill \$(cat /root/client.pid)
    rm -f /root/client.pid
else
    pkill -f "status-client.py"
fi
echo "客户端已停止"
EOF

chmod +x /root/start-client.sh /root/stop-client.sh

# 启动客户端
/root/start-client.sh

echo -e "${GREEN}
========================================
客户端安装完成!
========================================
服务端: $SERVER_IP:$SERVER_PORT
客户端ID: $CLIENT_NAME
客户端文件: /root/status-client.py
启动命令: /root/start-client.sh
停止命令: /root/stop-client.sh
查看日志: tail -f /root/client.log
========================================
${PLAIN}"
EOF
    chmod +x ${SERVER_PATH}/static/client.sh
    green "客户端安装脚本创建完成"
}

# 创建系统服务（可选）
create_systemd() {
    if [ -d /etc/systemd/system ]; then
        cat > /etc/systemd/system/serverstatus.service << EOF
[Unit]
Description=ServerStatus Service
After=network.target

[Service]
Type=forking
User=root
WorkingDirectory=/opt/ServerStatus
ExecStart=/opt/ServerStatus/start.sh
ExecStop=/opt/ServerStatus/stop.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        green "systemd服务已创建，可使用: systemctl {start|stop|restart} serverstatus"
    fi
}

# 显示安装信息
show_info() {
    IP_ADDR=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    ADMIN_PASS=$(grep admin_pass ${SERVER_PATH}/config.json | cut -d'"' -f4)
    
    green """
========================================
ServerStatus 安装完成!
========================================
服务端路径: ${SERVER_PATH}
Web访问地址: http://${IP_ADDR}:${WEB_PORT}
管理账号: admin
管理密码: ${ADMIN_PASS}
数据端口: ${SERVER_PORT} (客户端连接用)
========================================
客户端安装命令:
在需要监控的服务器上运行:
  bash <(curl -s http://${IP_ADDR}:${WEB_PORT}/static/client.sh) ${IP_ADDR} ${SERVER_PORT}
========================================
管理命令:
  启动: ${SERVER_PATH}/start.sh
  停止: ${SERVER_PATH}/stop.sh
  状态: ${SERVER_PATH}/status.sh
========================================
    """
}

# 主函数
main() {
    clear
    blue "========================================"
    blue "ServerStatus 一键安装脚本 v3.0"
    blue "兼容 CentOS 6+ / Debian 8+"
    blue "支持 Python 2.7 / 3.x"
    blue "========================================"
    
    check_root
    detect_os
    create_dirs
    install_python
    create_config
    create_database
    create_server
    create_templates
    create_scripts
    create_client_installer
    
    # 启动服务
    ${SERVER_PATH}/start.sh
    sleep 2
    
    create_systemd
    show_info
}

main "$@"