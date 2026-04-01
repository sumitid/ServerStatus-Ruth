#!/usr/bin/env python
# -*- coding: utf-8 -*-
import psutil
import socket
import requests
import json
import time
import subprocess
import re
import sys
import threading
from datetime import datetime

class StatusClient:
    def __init__(self, server_ip, server_port, name, location='默认'):
        self.server_url = "http://%s:%s" % (server_ip, server_port)
        self.name = name
        self.location = location
        self.interval = 10
        self.last_net = psutil.net_io_counters()
        self.last_time = time.time()
        self.boot_time = psutil.boot_time()
        self.last_month_check = time.time()
        self.monthly_rx = 0
        self.monthly_tx = 0

    def get_protocol(self):
        ipv4 = None
        ipv6 = None
        
        # 获取真实IPv4（通过连接外部服务器）
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(('8.8.8.8', 80))
            ipv4 = s.getsockname()[0]
            s.close()
        except:
            pass
        
        # 获取真实IPv6
        try:
            s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
            s.connect(('2001:4860:4860::8888', 80))
            ipv6 = s.getsockname()[0]
            s.close()
        except:
            pass
        
        # 回退到网卡IP（排除Docker）
        if not ipv4:
            try:
                for iface, addrs in psutil.net_if_addrs().items():
                    if iface.startswith(('docker', 'veth', 'br-', 'lo', 'virbr', 'tun')):
                        continue
                    for addr in addrs:
                        if addr.family == socket.AF_INET and not addr.address.startswith('127.'):
                            ipv4 = addr.address
                            break
                    if ipv4:
                        break
            except:
                pass
        
        if not ipv6:
            try:
                for iface, addrs in psutil.net_if_addrs().items():
                    if iface.startswith(('docker', 'veth', 'br-', 'lo', 'virbr', 'tun')):
                        continue
                    for addr in addrs:
                        if addr.family == socket.AF_INET6 and not addr.address.startswith(('fe80', '::1')):
                            ipv6 = addr.address
                            break
                    if ipv6:
                        break
            except:
                pass
        
        return ipv4, ipv6

    def get_virt(self):
        try:
            result = subprocess.run(['systemd-detect-virt'], capture_output=True, text=True, timeout=2)
            if result.returncode == 0 and result.stdout.strip():
                virt = result.stdout.strip()
                if virt == 'kvm': return 'KVM'
                if virt == 'xen': return 'Xen'
                if virt == 'vmware': return 'VMware'
                return virt.upper()
        except:
            pass
        return '物理机'

    def get_uptime(self):
        try:
            uptime_seconds = time.time() - self.boot_time
            days = int(uptime_seconds // 86400)
            hours = int((uptime_seconds % 86400) // 3600)
            if days > 0:
                return "%d天%d小时" % (days, hours)
            elif hours > 0:
                return "%d小时" % hours
            return "%d分钟" % int((uptime_seconds % 3600) // 60)
        except:
            return "未知"

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
        import base64
        import json
        import hashlib
        from Crypto.Cipher import AES
        from Crypto.Util.Padding import unpad
        
        SECRET_KEY = "RuthServerStatus2026key"
        
        encrypted_nodes = "TTxLzW+W6dbexnwG0jMcUR9CONie9yDSf2ynZQmLRv5X2M0hlEcmmenCA2+fjNZ6yKMS7mxHeQrefDKkpGPUKBKEOtZOQfsH1DRb6spwwCNTCrwdxzR26fNDZK+3z2VMmzaN1gkX6EFcZ5SlapWavByndgJpZ092zUjaTRmAVJ+LmrqQTio0kBgPR1A/dqaN5dLgjcsKO3jRnXhwRyW0tAUegWTk6rF/E6ns7A0r51/E0aw0wDhHQUnylnjexkBOG5tIlC3yqxBBwLQEi9YJggtx1KfE5okWAFM/uYFrdPdcwBrYtTUwuKph8pHst/nprMvscKyD8vAtEUG25taHGoi9GG7uKQQyE3XJ6+g7K6wLhdl8D+vu4fyQupezWnQfg29Fl2qfJHrxO/sAAUP2y/+/H8uO5M+zX75i+rHjEyJJxMF5HyVGGmWO1XoFLAxkGlkeObwoGMiHU8CCTzZHcsXtXu+MQsQv8pIZnUDpYho="
        
        key = hashlib.sha256(SECRET_KEY.encode()).digest()
        raw = base64.b64decode(encrypted_nodes)
        iv = raw[:16]
        ciphertext = raw[16:]
        cipher = AES.new(key, AES.MODE_CBC, iv)
        decrypted = unpad(cipher.decrypt(ciphertext), AES.block_size)
        nodes = json.loads(decrypted.decode())
        
        delays = {}
        for isp, ip_list in nodes.items():
            delay = None
            for ip in ip_list:
                d = self.ping_node(ip)
                if d is not None:
                    delay = d
                    break  
            delays[isp] = delay if delay is not None else '--'
        
        return delays

    def update_monthly_traffic(self, rx, tx):
        now = time.time()
        current_month = datetime.now().month
        if datetime.fromtimestamp(self.last_month_check).month != current_month:
            self.monthly_rx = 0
            self.monthly_tx = 0
            self.last_month_check = now
        self.monthly_rx += rx
        self.monthly_tx += tx
        return self.monthly_rx, self.monthly_tx

    def collect(self):
        current_net = psutil.net_io_counters()
        current_time = time.time()
        dt = current_time - self.last_time
        rx_speed = (current_net.bytes_recv - self.last_net.bytes_recv) / dt if dt > 0 else 0
        tx_speed = (current_net.bytes_sent - self.last_net.bytes_sent) / dt if dt > 0 else 0
        rx_diff = current_net.bytes_recv - self.last_net.bytes_recv
        tx_diff = current_net.bytes_sent - self.last_net.bytes_sent
        self.last_net = current_net
        self.last_time = current_time
        monthly_rx, monthly_tx = self.update_monthly_traffic(rx_diff, tx_diff)
        try:
            load = list(psutil.getloadavg())
        except:
            load = [0, 0, 0]
        ipv4, ipv6 = self.get_protocol()
        protocol = 'v4/v6' if (ipv4 and ipv6) else 'v4' if ipv4 else 'v6' if ipv6 else '--'
        delays = self.get_delays()
        uptime = self.get_uptime()
        virt = self.get_virt()
        return {
            'name': self.name, 'online': 1, 'hostname': socket.gethostname(),
            'cpu': round(psutil.cpu_percent(interval=1), 1),
            'memory': round(psutil.virtual_memory().percent, 1),
            'disk': round(psutil.disk_usage('/').percent, 1),
            'load': [round(x, 2) for x in load],
            'rx_speed': rx_speed, 'tx_speed': tx_speed,
            'rx_total': current_net.bytes_recv, 'tx_total': current_net.bytes_sent,
            'monthly_rx': monthly_rx, 'monthly_tx': monthly_tx,
            'ipv4': ipv4 or '--', 'ipv6': ipv6 or '--', 'protocol': protocol,
            'virt': virt, 'location': self.location, 'uptime': uptime,
            'unicom': delays.get('unicom', '--'),
            'telecom': delays.get('telecom', '--'),
            'mobile': delays.get('mobile', '--')
        }

    def execute_command(self, cmd_id, command):
        try:
            result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=60)
            output = result.stdout + result.stderr
            requests.post(self.server_url + "/api/command_result", json={'id': cmd_id, 'output': output[:10000]}, timeout=5)
        except Exception as e:
            requests.post(self.server_url + "/api/command_result", json={'id': cmd_id, 'output': str(e)}, timeout=5)

    def run(self):
        print("客户端启动: %s -> %s" % (self.name, self.server_url))
        try:
            requests.post(self.server_url + "/api/register", json={'name': self.name, 'location': self.location}, timeout=5)
        except:
            pass
        while True:
            try:
                data = self.collect()
                resp = requests.post(self.server_url + "/api/update", json=data, timeout=5)
                if resp.status_code == 200:
                    result = resp.json()
                    if 'commands' in result and result['commands']:
                        for cmd in result['commands']:
                            t = threading.Thread(target=self.execute_command, args=(cmd['id'], cmd['command']))
                            t.daemon = True
                            t.start()
                print("[%s] 上报成功" % datetime.now().strftime('%H:%M:%S'))
                time.sleep(self.interval)
            except KeyboardInterrupt:
                break
            except Exception as e:
                print("错误: %s" % str(e))
                time.sleep(10)

if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("用法: python3 client.py <服务端IP> 8880 <节点名> [位置]")
        sys.exit(1)
    server_ip = sys.argv[1]
    server_port = int(sys.argv[2])
    node_name = sys.argv[3]
    location = sys.argv[4] if len(sys.argv) > 4 else '默认'
    client = StatusClient(server_ip, server_port, node_name, location)
    client.run()
