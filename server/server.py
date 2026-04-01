#!/usr/bin/env python
# -*- coding: utf-8 -*-
import os
import sys
import json
import sqlite3
import hashlib
import secrets
import time
import subprocess
import fcntl
import tempfile
from datetime import datetime
from flask import Flask, request, jsonify, render_template_string, session, redirect, url_for, send_from_directory
from functools import wraps

CONFIG_FILE = "/usr/local/ServerStatus/server/config.json"
with open(CONFIG_FILE, 'r') as f:
    CONFIG = json.load(f)

DB_PATH = CONFIG.get('database', '/usr/local/ServerStatus/server/server.db')
ADMIN_USER = CONFIG.get('admin_user', 'admin')
ADMIN_PASS_HASH = hashlib.sha256(CONFIG.get('admin_pass', 'admin123').encode()).hexdigest()

app = Flask(__name__)
app.secret_key = secrets.token_hex(32)

# 静态文件路由
@app.route('/css/<path:filename>')
def serve_css(filename):
    return send_from_directory('/usr/local/ServerStatus/web/css', filename)

@app.route('/js/<path:filename>')
def serve_js(filename):
    return send_from_directory('/usr/local/ServerStatus/web/js', filename)

@app.route('/links.html')
def serve_links():
    return send_from_directory('/usr/local/ServerStatus/web', 'links.html')

@app.route('/footer.html')
def serve_footer():
    return send_from_directory('/usr/local/ServerStatus/web', 'footer.html')

def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS nodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        location TEXT DEFAULT '默认',
        virt TEXT DEFAULT 'KVM',
        online INTEGER DEFAULT 0,
        last_update TIMESTAMP,
        data TEXT
    )''')
    c.execute('''CREATE TABLE IF NOT EXISTS commands (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        node_name TEXT NOT NULL,
        command TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        output TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )''')
    c.execute('''CREATE TABLE IF NOT EXISTS logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        node_name TEXT,
        message TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )''')
    conn.commit()
    conn.close()

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('logged_in'):
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated

def add_log(node_name, message):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('INSERT INTO logs (node_name, message) VALUES (?, ?)', (node_name, message[:500]))
    conn.commit()
    conn.close()

@app.route('/api/update', methods=['POST'])
def update():
    data = request.get_json()
    name = data.get('name')
    if not name:
        return jsonify({'status': 'error'})
    
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''INSERT OR REPLACE INTO nodes (name, location, virt, online, last_update, data)
                 VALUES (?, ?, ?, ?, ?, ?)''',
              (name, data.get('location', '默认'), data.get('virt', 'KVM'),
               1, datetime.now(), json.dumps(data)))
    conn.commit()
    
    c.execute('SELECT id, command FROM commands WHERE node_name=? AND status="pending"', (name,))
    commands = c.fetchall()
    conn.close()
    
    if commands:
        return jsonify({'commands': [{'id': c[0], 'command': c[1]} for c in commands]})
    return jsonify({'status': 'ok'})

@app.route('/api/command_result', methods=['POST'])
def command_result():
    data = request.get_json()
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('UPDATE commands SET status="completed", output=? WHERE id=?', (data.get('output', '')[:10000], data.get('id')))
    conn.commit()
    conn.close()
    return jsonify({'status': 'ok'})

@app.route('/api/nodes', methods=['GET'])
def get_nodes():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT data, online, last_update FROM nodes ORDER BY name')
    rows = c.fetchall()
    conn.close()
    nodes = []
    for row in rows:
        try:
            data = json.loads(row[0])
            data['online'] = row[1]
            data['last_update'] = row[2]
            nodes.append(data)
        except:
            pass
    return jsonify(nodes)

@app.route('/api/command', methods=['POST'])
@login_required
def send_command():
    data = request.get_json()
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('INSERT INTO commands (node_name, command) VALUES (?, ?)', (data.get('node_name'), data.get('command')))
    conn.commit()
    cmd_id = c.lastrowid
    conn.close()
    add_log(data.get('node_name'), '命令已下发: ' + data.get('command', '')[:50])
    return jsonify({'id': cmd_id})

@app.route('/api/command/<int:cmd_id>', methods=['GET'])
def get_command(cmd_id):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT status, output FROM commands WHERE id=?', (cmd_id,))
    row = c.fetchone()
    conn.close()
    if row:
        return jsonify({'status': row[0], 'output': row[1] or ''})
    return jsonify({'status': 'not_found'})

@app.route('/api/logs', methods=['GET'])
@login_required
def get_logs():
    node_name = request.args.get('node')
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    if node_name:
        c.execute('SELECT message, created_at FROM logs WHERE node_name=? ORDER BY created_at DESC LIMIT 100', (node_name,))
    else:
        c.execute('SELECT node_name, message, created_at FROM logs ORDER BY created_at DESC LIMIT 200')
    rows = c.fetchall()
    conn.close()
    logs = []
    for row in rows:
        if node_name:
            logs.append({'message': row[0], 'time': row[1]})
        else:
            logs.append({'node': row[0], 'message': row[1], 'time': row[2]})
    return jsonify(logs)

@app.route('/api/change_password', methods=['POST'])
@login_required
def change_password():
    data = request.get_json()
    old_pwd = data.get('old_password', '')
    new_pwd = data.get('new_password', '')
    
    old_hash = hashlib.sha256(old_pwd.encode()).hexdigest()
    if old_hash != ADMIN_PASS_HASH:
        return jsonify({'error': '原密码错误'}), 401
    
    if len(new_pwd) < 6:
        return jsonify({'error': '新密码至少6位'}), 400
    
    with open(CONFIG_FILE, 'r') as f:
        config = json.load(f)
    config['admin_pass'] = new_pwd
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=4)
    
    add_log('system', '管理员密码已修改')
    
    restart_script = '''#!/bin/bash
sleep 2
cd /usr/local/ServerStatus/server
pkill -f "python.*server.py"
sleep 1
nohup python3 server.py > server.log 2>&1 &
'''
    with open('/tmp/restart_server.sh', 'w') as f:
        f.write(restart_script)
    os.chmod('/tmp/restart_server.sh', 0o755)
    subprocess.Popen(['/tmp/restart_server.sh'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    return jsonify({'status': 'ok', 'message': '密码已修改，服务端即将重启'})

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        user = request.form.get('username')
        pwd = request.form.get('password')
        if user == ADMIN_USER and hashlib.sha256(pwd.encode()).hexdigest() == ADMIN_PASS_HASH:
            session['logged_in'] = True
            return redirect(url_for('admin'))
        return render_template_string(LOGIN_HTML, error='用户名或密码错误')
    return send_from_directory('/usr/local/ServerStatus/web', 'login.html')

@app.route('/logout')
def logout():
    session.pop('logged_in', None)
    return redirect(url_for('login'))

@app.route('/admin')
@login_required
def admin():
    return send_from_directory('/usr/local/ServerStatus/web', 'admin.html')

@app.route('/')
def index():
    return send_from_directory('/usr/local/ServerStatus/web', 'index.html')

# ============= 友情链接管理 =============
LINKS_FILE = "/usr/local/ServerStatus/web/links.json"

def load_links():
    if os.path.exists(LINKS_FILE):
        with open(LINKS_FILE, 'r') as f:
            fcntl.flock(f, fcntl.LOCK_SH)
            data = json.load(f)
            fcntl.flock(f, fcntl.LOCK_UN)
            return data
    return []

def save_links(links):
    temp_fd, temp_path = tempfile.mkstemp(dir=os.path.dirname(LINKS_FILE))
    try:
        with os.fdopen(temp_fd, 'w') as f:
            json.dump(links, f, indent=2, ensure_ascii=False)
        os.chmod(temp_path, 0o644)
        os.rename(temp_path, LINKS_FILE)
        return True
    except Exception as e:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        return False

@app.route('/api/links', methods=['GET'])
def get_links():
    return jsonify(load_links())

@app.route('/api/links', methods=['POST'])
@login_required
def manage_links():
    data = request.get_json()
    action = data.get('action')
    links = load_links()
    
    if action == 'add':
        name = data.get('name', '').strip()
        url = data.get('url', '').strip()
        if not name or not url:
            return jsonify({'error': '名称和地址不能为空'}), 400
        for l in links:
            if l['name'] == name:
                return jsonify({'error': '链接名称已存在'}), 400
        links.append({'name': name, 'url': url})
        if save_links(links):
            add_log('admin', '添加友情链接: ' + name)
            return jsonify({'status': 'ok'})
        return jsonify({'error': '保存失败'}), 500
    
    elif action == 'update':
        old_name = data.get('old_name')
        name = data.get('name', '').strip()
        url = data.get('url', '').strip()
        for i, l in enumerate(links):
            if l.get('name') == old_name:
                links[i] = {'name': name, 'url': url}
                if save_links(links):
                    add_log('admin', '更新友情链接: ' + old_name + ' -> ' + name)
                    return jsonify({'status': 'ok'})
                return jsonify({'error': '保存失败'}), 500
        return jsonify({'error': '链接不存在'}), 404
    
    elif action == 'delete':
        name = data.get('name')
        new_links = [l for l in links if l.get('name') != name]
        if len(new_links) == len(links):
            return jsonify({'error': '链接不存在'}), 404
        if save_links(new_links):
            add_log('admin', '删除友情链接: ' + name)
            return jsonify({'status': 'ok'})
        return jsonify({'error': '保存失败'}), 500
    
    return jsonify({'error': '无效操作'}), 400

LOGIN_HTML = '''<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>登录</title>
<style>body{background:#2c3e50;padding:50px;text-align:center}.box{background:#ecf0f1;width:300px;margin:0 auto;padding:20px;border-radius:8px}input{padding:8px;margin:5px;width:90%}button{padding:8px 20px;background:#27ae60;color:#fff;border:none}</style></head>
<body><div class="box"><h2>后台登录</h2>{% if error %}<p style="color:#e74c3c">{{ error }}</p>{% endif %}
<form method="post"><input type="text" name="username" placeholder="用户名" required><br>
<input type="password" name="password" placeholder="密码" required><br>
<button type="submit">登录</button></form></div></body></html>'''

if __name__ == '__main__':
    init_db()
    print("="*50)
    print("ServerStatus 服务端启动")
    print("前台: http://你的IP:8880")
    print("后台: http://你的IP:8880/admin")
    print("账号: admin")
    print("密码: 查看 /usr/local/ServerStatus/server/config.json 中的 admin_pass")
    print("="*50)
    app.run(host='0.0.0.0', port=8880, debug=False)
@app.route('/links.html')
def serve_links():
    return send_from_directory('/usr/local/ServerStatus/web', 'links.html')

@app.route('/footer.html')
def serve_footer():
    return send_from_directory('/usr/local/ServerStatus/web', 'footer.html')
