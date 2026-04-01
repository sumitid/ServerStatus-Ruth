// 主题切换
function setTheme(theme) {
    if (theme === 'dark') {
        document.body.classList.add('dark-theme');
        localStorage.setItem('theme', 'dark');
        var btn = document.getElementById('themeToggleBtn');
        if (btn) btn.innerHTML = '<i class="fas fa-sun"></i> 白天模式';
    } else {
        document.body.classList.remove('dark-theme');
        localStorage.setItem('theme', 'light');
        var btn = document.getElementById('themeToggleBtn');
        if (btn) btn.innerHTML = '<i class="fas fa-moon"></i> 黑夜模式';
    }
}

function toggleTheme() {
    var current = localStorage.getItem('theme');
    if (current === 'dark') setTheme('light');
    else setTheme('dark');
}

function toggleExpand(rowId) {
    var detailRow = document.getElementById('detail-' + rowId);
    if (detailRow) detailRow.classList.toggle('show');
}

function formatBytes(b) {
    if (!b) return '0';
    if (b < 1024) return b + 'B';
    if (b < 1048576) return (b / 1024).toFixed(1) + 'K';
    if (b < 1073741824) return (b / 1048576).toFixed(1) + 'M';
    return (b / 1073741824).toFixed(1) + 'G';
}

function formatSpeed(b) {
    if (!b) return '0';
    if (b < 1024) return b + 'B';
    if (b < 1048576) return (b / 1024).toFixed(1) + 'K';
    return (b / 1048576).toFixed(1) + 'M';
}

function getDelayClass(d) {
    if (!d || d === '--') return '';
    if (d < 50) return 'delay-good';
    if (d < 150) return 'delay-fair';
    return 'delay-bad';
}

function maskIp(ip) {
    if (!ip || ip === '--') return '--';
    var parts = ip.split('.');
    if (parts.length !== 4) return ip;
    return '*.' + parts[1] + '.*.*';
}

function maskIpv6(ipv6) {
    if (!ipv6 || ipv6 === '--') return '--';
    var parts = ipv6.split(':');
    if (parts.length < 4) return ipv6;
    return parts[0] + ':' + parts[1] + ':*:*:*:*:*:*';
}

function loadData() {
    fetch('/api/nodes')
        .then(function(res) { return res.json(); })
        .then(function(data) {
            var loadingDiv = document.getElementById('loading-notice');
            if (loadingDiv) loadingDiv.style.display = 'none';
            
            var html = '';
            for (var i = 0; i < data.length; i++) {
                var n = data[i];
                var statusClass = (n.online === 1) ? 'online' : 'offline';
                var statusText = (n.online === 1) ? '在线' : '离线';
                var protocol = n.protocol || '--';
                var monthlyRx = n.monthly_rx || 0;
                var monthlyTx = n.monthly_tx || 0;
                var telecom = n.telecom || '--';
                var unicom = n.unicom || '--';
                var mobile = n.mobile || '--';
                var uptime = n.uptime || '--';
                
                html += '<tr class="accordion-toggle" onclick="toggleExpand(\'' + i + '\')">';
                html += '<td>' + protocol + '<\/td>';
                html += '<td>↓' + formatBytes(monthlyRx) + '<br>↑' + formatBytes(monthlyTx) + '<\/td>';
                html += '<td>' + (n.name || '--') + '<\/td>';
                html += '<td class="mobile-hidden">' + (n.virt || 'KVM') + '<\/td>';
                html += '<td class="mobile-hidden">' + (n.location || '默认') + '<\/td>';
                html += '<td class="' + statusClass + '">' + statusText + '<\/td>';
                html += '<td>' + uptime + '<\/td>';
                html += '<td>' + (n.load ? n.load[0].toFixed(2) : '0') + '<\/td>';
                html += '<td>↓' + formatSpeed(n.rx_speed) + '<br>↑' + formatSpeed(n.tx_speed) + '<\/td>';
                html += '<td class="mobile-hidden">↓' + formatBytes(n.rx_total) + '<br>↑' + formatBytes(n.tx_total) + '<\/td>';
                html += '<td><div class="progress"><div class="progress-bar bg-success" style="width:' + (n.cpu || 0) + '%">' + (n.cpu || 0) + '%</div></div><\/td>';
                html += '<td><div class="progress"><div class="progress-bar bg-info" style="width:' + (n.memory || 0) + '%">' + (n.memory || 0) + '%</div></div><\/td>';
                html += '<td class="mobile-hidden"><div class="progress"><div class="progress-bar bg-warning" style="width:' + (n.disk || 0) + '%">' + (n.disk || 0) + '%</div></div><\/td>';
                html += '<td class="' + getDelayClass(unicom) + '">' + unicom + 'ms<\/td>';
                html += '<td class="' + getDelayClass(telecom) + '">' + telecom + 'ms<\/td>';
                html += '<td class="' + getDelayClass(mobile) + '">' + mobile + 'ms<\/td>';
                html += '<\/tr>';
                
                // 详情行
                html += '<tr id="detail-' + i + '" class="expandRow">';
                html += '<td colspan="15" style="text-align:left; padding:10px;">';
                html += '<i class="fas fa-info-circle"></i> 主机名: ' + (n.hostname || '--') + ' &nbsp;|&nbsp; ';
                
                if (protocol === 'v4') {
                    html += '<i class="fas fa-network-wired"></i> IPv4: ' + maskIp(n.ipv4) + ' &nbsp;|&nbsp; ';
                } else if (protocol === 'v6') {
                    html += '<i class="fas fa-network-wired"></i> IPv6: ' + maskIpv6(n.ipv6) + ' &nbsp;|&nbsp; ';
                } else if (protocol === 'v4/v6') {
                    html += '<i class="fas fa-network-wired"></i> IPv4: ' + maskIp(n.ipv4) + ' &nbsp;|&nbsp; ';
                    html += '<i class="fas fa-network-wired"></i> IPv6: ' + maskIpv6(n.ipv6) + ' &nbsp;|&nbsp; ';
                }
                
                html += '<i class="fas fa-microchip"></i> CPU: ' + (n.cpu || 0) + '% &nbsp;|&nbsp; ';
                html += '<i class="fas fa-memory"></i> 内存: ' + (n.memory || 0) + '% &nbsp;|&nbsp; ';
                html += '<i class="fas fa-hdd"></i> 硬盘: ' + (n.disk || 0) + '%';
                html += '<\/td><\/tr>';
            }
            document.getElementById('servers').innerHTML = html;
            var updatedDiv = document.getElementById('updated');
            if (updatedDiv) {
                updatedDiv.innerHTML = '<i class="fas fa-sync me-2"></i>最后更新: ' + new Date().toLocaleTimeString();
            }
        })
        .catch(function(e) {
            console.log(e);
        });
}

function closeModal() {
    var modal = document.getElementById('rightClickModal');
    if (modal) modal.style.display = 'none';
}

function loadLinksAndFooter() {
    fetch('/links.html').then(function(r) { return r.text(); }).then(function(html) {
        var linksDiv = document.getElementById('links-container');
        if (linksDiv) linksDiv.innerHTML = html;
    }).catch(function() {});
    fetch('/footer.html').then(function(r) { return r.text(); }).then(function(html) {
        var footerDiv = document.getElementById('footer-container');
        if (footerDiv) footerDiv.innerHTML = html;
    }).catch(function() {});
}

function setupAntiScraping() {
    var isBot = /bot|googlebot|baiduspider|yandex|sogou|360spider|bingbot|slurp/i.test(navigator.userAgent);
    if (!isBot) {
        document.addEventListener('contextmenu', function(e) {
            e.preventDefault();
            var modal = document.getElementById('rightClickModal');
            if (modal) modal.style.display = 'flex';
            return false;
        });
        document.addEventListener('keydown', function(e) {
            if (e.key === 'F12' || e.keyCode === 123) {
                e.preventDefault();
                return false;
            }
            if (e.ctrlKey && e.shiftKey && (e.key === 'I' || e.key === 'J' || e.key === 'C')) {
                e.preventDefault();
                return false;
            }
        });
    }
}

document.addEventListener('DOMContentLoaded', function() {
    var saved = localStorage.getItem('theme');
    if (saved === 'dark') setTheme('dark');
    else setTheme('light');
    
    var btn = document.getElementById('themeToggleBtn');
    if (btn) btn.addEventListener('click', toggleTheme);
    
    setupAntiScraping();
    loadData();
    loadLinksAndFooter();
    setInterval(loadData, 5000);
});
