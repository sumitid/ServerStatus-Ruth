# ServerStatus 云监控系统

轻量级服务器监控系统，支持多节点、三网延迟、月流量统计、后台管理等功能。

## 功能特点

- **前台监控**：16列表格，实时显示CPU/内存/硬盘/网速/流量/三网延迟
- **后台管理**：节点列表、远程命令执行、友情链接管理、操作日志、修改密码
- **三网延迟**：电信/联通/移动三网延迟
- **隐私保护**：前台显示客户端ip地址
- **响应式布局**：手机/平板/电脑自适应
- **主题切换**：黑夜/白天模式
- **安全防护**：防越权、防注入、防XSS

## 更新说明：
2026.03.03, 增加一键部署脚本
2017.03.09, 支持低版本debian8，centos6，ubuntu18.04
2017.03.15, 前台显示主机名，支持ipv4和ipv6模糊显示

### 服务端安装

```bash
# wget 方式
wget -O status.sh https://raw.githubusercontent.com/sumitid/ServerStatus-Ruth/main/status.sh && chmod +x status.sh && ./status.sh s

# curl 方式
curl -o status.sh https://raw.githubusercontent.com/sumitid/ServerStatus-Ruth/main/status.sh && chmod +x status.sh && ./status.sh s
```
安装完成后，访问：
前台：http://你的IP:8880
后台：http://你的IP:8880/admin
账号：admin
密码：查看 /usr/local/ServerStatus/server/config.json

客户端安装
在需要监控的服务器上执行：

bash
wget -O status.sh https://raw.githubusercontent.com/你的用户名/ServerStatus/main/status.sh && chmod +x status.sh && ./status.sh c
按提示输入服务端IP、节点名称、位置即可。

管理命令
```bash
# 服务端管理菜单
./status.sh s

# 客户端管理菜单
./status.sh c
```
菜单选项：
```
ServerStatus 一键安装管理脚本 [v1.0]
 
0. 升级脚本
————————————
1. 安装 服务端
2. 卸载 服务端
————————————
3. 启动 服务端
4. 停止 服务端
5. 重启 服务端
————————————
6. 设置 服务端配置
7. 查看 服务端信息
8. 查看 服务端日志
————————————
9. 切换为 客户端菜单
 
当前状态: 服务端 已安装 并 已启动
请输入数字 [0-9]:
```
系统要求
Python 3.6+
Linux / Windows (暂时不支持)

开源协议
MIT License

感谢
cppla/ServerStatus
ToyoDAdoubiBackup/ServerStatus-Toyo
