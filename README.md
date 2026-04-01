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

## 一键安装

### 服务端安装

```bash
# wget 方式
wget -O status.sh https://raw.githubusercontent.com/sumitid/ServerStatus-Ruth/main/status.sh && chmod +x status.sh && ./status.sh s

# curl 方式
curl -o status.sh https://raw.githubusercontent.com/sumitid/ServerStatus-Ruth/main/status.sh && chmod +x status.sh && ./status.sh s
