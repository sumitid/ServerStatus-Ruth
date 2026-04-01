// serverstatus.js - 适配Python Flask API
var error = 0;
var d = 0;
var server_status = new Array();

function timeSince(date) {
    if(date == 0) return "从未.";
    var seconds = Math.floor((new Date() - date) / 1000);
    var interval = Math.floor(seconds / 86400);
    if (interval > 1) return interval + "天前.";
    interval = Math.floor(seconds / 3600);
    if (interval > 1) return interval + "小时前.";
    interval = Math.floor(seconds / 60);
    if (interval > 1) return interval + "分钟前.";
    return "几秒前.";
}

function bytesToSize(bytes, precision, si) {
    if(!bytes) return "0 B";
    var kilobyte = si ? 1000 : 1024;
    var megabyte = kilobyte * 1000;
    var gigabyte = megabyte * 1000;
    var terabyte = gigabyte * 1000;
    if (bytes < kilobyte) return bytes + ' B';
    else if (bytes < megabyte) return (bytes / kilobyte).toFixed(precision) + (si ? 'K' : 'K');
    else if (bytes < gigabyte) return (bytes / megabyte).toFixed(precision) + (si ? 'M' : 'M');
    else if (bytes < terabyte) return (bytes / gigabyte).toFixed(precision) + (si ? 'G' : 'G');
    else return (bytes / terabyte).toFixed(precision) + (si ? 'T' : 'T');
}

function formatSpeed(bps) {
    if(!bps) return '0';
    if(bps < 1024) return bps.toFixed(0) + 'B';
    if(bps < 1024*1024) return (bps/1024).toFixed(1) + 'K';
    return (bps/(1024*1024)).toFixed(1) + 'M';
}

function formatBytes(bytes) {
    if(!bytes) return '0';
    if(bytes < 1024) return bytes.toFixed(0) + 'B';
    if(bytes < 1024*1024) return (bytes/1024).toFixed(1) + 'K';
    if(bytes < 1024*1024*1024) return (bytes/(1024*1024)).toFixed(1) + 'M';
    return (bytes/(1024*1024*1024)).toFixed(1) + 'G';
}

function getDelayClass(d) {
    if(!d || d == '--') return '';
    if(d < 50) return 'delay-good';
    if(d < 150) return 'delay-fair';
    return 'delay-bad';
}

function uptime() {
    fetch('/api/nodes')
        .then(res => res.json())
        .then(function(result) {
            $("#loading-notice").fadeOut();
            
            for (var i = 0; i < result.length; i++) {
                var n = result[i];
                var TableRow = $("#servers tr#r" + i);
                var ExpandRow = $("#servers #rt" + i);
                var hack = (i%2) ? "odd" : "even";
                
                if (!TableRow.length) {
                    $("#servers").append(
                        '<tr id="r' + i + '" data-toggle="collapse" data-target="#rt' + i + '" class="accordion-toggle ' + hack + '">' +
                        '<td id="online4"><div class="progress"><div style="width:100%" class="progress-bar"><small>加载</small></div></div></td>' +
                        '<td id="month_traffic"><div class="progress"><div style="width:100%" class="progress-bar"><small>加载</small></div></div></td>' +
                        '<td id="name">加载</td>' +
                        '<td id="type">加载</td>' +
                        '<td id="location">加载</td>' +
                        '<td id="uptime">加载</td>' +
                        '<td id="load">加载</td>' +
                        '<td id="network">加载</td>' +
                        '<td id="traffic">加载</td>' +
                        '<td id="cpu"><div class="progress"><div style="width:100%" class="progress-bar"><small>加载</small></div></div></td>' +
                        '<td id="memory"><div class="progress"><div style="width:100%" class="progress-bar"><small>加载</small></div></div></td>' +
                        '<td id="hdd"><div class="progress"><div style="width:100%" class="progress-bar"><small>加载</small></div></div></td>' +
                        '<td id="ping"><div class="progress"><div style="width:100%" class="progress-bar"><small>加载</small></div></div></td>' +
                        '</tr>' +
                        '<tr class="expandRow ' + hack + '"><td colspan="16"><div class="accordian-body collapse" id="rt' + i + '">' +
                        '<div id="expand_mem">加载中</div>' +
                        '<div id="expand_swap">加载中</div>' +
                        '<div id="expand_hdd">加载中</div>' +
                        '<div id="expand_tupd">加载中</div>' +
                        '<div id="expand_ping">加载中</div>' +
                        '<div id="expand_custom">加载中</div>' +
                        '</div></td></tr>'
                    );
                    TableRow = $("#servers tr#r" + i);
                    ExpandRow = $("#servers #rt" + i);
                    server_status[i] = true;
                }
                
                TableRow = TableRow[0];
                if(error) {
                    TableRow.setAttribute("data-target", "#rt" + i);
                    server_status[i] = true;
                }
                
                // 协议状态
                var protocol = n.protocol || '--';
                if (protocol == 'v4/v6') {
                    TableRow.children["online4"].children[0].children[0].className = "progress-bar progress-bar-success";
                    TableRow.children["online4"].children[0].children[0].innerHTML = "<small>双栈</small>";
                } else if (protocol == 'v4') {
                    TableRow.children["online4"].children[0].children[0].className = "progress-bar progress-bar-success";
                    TableRow.children["online4"].children[0].children[0].innerHTML = "<small>IPv4</small>";
                } else if (protocol == 'v6') {
                    TableRow.children["online4"].children[0].children[0].className = "progress-bar progress-bar-success";
                    TableRow.children["online4"].children[0].children[0].innerHTML = "<small>IPv6</small>";
                } else {
                    TableRow.children["online4"].children[0].children[0].className = "progress-bar progress-bar-danger";
                    TableRow.children["online4"].children[0].children[0].innerHTML = "<small>关闭</small>";
                }
                
                // 月流量
                var monthlyRx = n.monthly_rx || 0;
                var monthlyTx = n.monthly_tx || 0;
                TableRow.children["month_traffic"].innerHTML = '↓' + formatBytes(monthlyRx) + '<br>↑' + formatBytes(monthlyTx);
                
                // 节点名
                TableRow.children["name"].innerHTML = n.name;
                
                // 虚拟化
                TableRow.children["type"].innerHTML = n.virt || 'KVM';
                
                // 位置
                TableRow.children["location"].innerHTML = n.location || '默认';
                
                if (n.online == 1) {
                    TableRow.children["uptime"].innerHTML = n.uptime || '--';
                    TableRow.children["load"].innerHTML = n.load ? n.load[0].toFixed(2) : '0.00';
                    TableRow.children["network"].innerHTML = "↓" + formatSpeed(n.rx_speed) + "<br>↑" + formatSpeed(n.tx_speed);
                    TableRow.children["traffic"].innerHTML = "↓" + formatBytes(n.rx_total) + "<br>↑" + formatBytes(n.tx_total);
                    
                    var cpu = n.cpu || 0;
                    TableRow.children["cpu"].children[0].children[0].className = cpu >= 90 ? "progress-bar progress-bar-danger" : (cpu >= 80 ? "progress-bar progress-bar-warning" : "progress-bar progress-bar-success");
                    TableRow.children["cpu"].children[0].children[0].style.width = cpu + "%";
                    TableRow.children["cpu"].children[0].children[0].innerHTML = cpu + "%";
                    
                    var mem = n.memory || 0;
                    TableRow.children["memory"].children[0].children[0].className = mem >= 90 ? "progress-bar progress-bar-danger" : (mem >= 80 ? "progress-bar progress-bar-warning" : "progress-bar progress-bar-success");
                    TableRow.children["memory"].children[0].children[0].style.width = mem + "%";
                    TableRow.children["memory"].children[0].children[0].innerHTML = mem + "%";
                    
                    var disk = n.disk || 0;
                    TableRow.children["hdd"].children[0].children[0].className = disk >= 90 ? "progress-bar progress-bar-danger" : (disk >= 80 ? "progress-bar progress-bar-warning" : "progress-bar progress-bar-success");
                    TableRow.children["hdd"].children[0].children[0].style.width = disk + "%";
                    TableRow.children["hdd"].children[0].children[0].innerHTML = disk + "%";
                    
                    var telecom = n.telecom || '--';
                    var unicom = n.unicom || '--';
                    var mobile = n.mobile || '--';
                    TableRow.children["ping"].innerHTML = '<span class="' + getDelayClass(unicom) + '">联通' + unicom + '</span> | <span class="' + getDelayClass(telecom) + '">电信' + telecom + '</span> | <span class="' + getDelayClass(mobile) + '">移动' + mobile + '</span>';
                    
                    if(ExpandRow.length) {
                        ExpandRow[0].children["expand_mem"].innerHTML = "内存: " + mem + "%";
                        ExpandRow[0].children["expand_hdd"].innerHTML = "硬盘: " + disk + "%";
                        ExpandRow[0].children["expand_tupd"].innerHTML = "IP: " + (n.ipv4 || '--');
                        ExpandRow[0].children["expand_ping"].innerHTML = "联通: " + unicom + "ms | 电信: " + telecom + "ms | 移动: " + mobile + "ms";
                        ExpandRow[0].children["expand_custom"].innerHTML = "主机名: " + (n.hostname || '--');
                    }
                    
                    if (!server_status[i]) {
                        TableRow.setAttribute("data-target", "#rt" + i);
                        server_status[i] = true;
                    }
                } else {
                    TableRow.children["uptime"].innerHTML = "–";
                    TableRow.children["load"].innerHTML = "–";
                    TableRow.children["network"].innerHTML = "–";
                    TableRow.children["traffic"].innerHTML = "–";
                    TableRow.children["cpu"].children[0].children[0].className = "progress-bar progress-bar-danger";
                    TableRow.children["cpu"].children[0].children[0].style.width = "100%";
                    TableRow.children["cpu"].children[0].children[0].innerHTML = "<small>离线</small>";
                    TableRow.children["memory"].children[0].children[0].className = "progress-bar progress-bar-danger";
                    TableRow.children["memory"].children[0].children[0].style.width = "100%";
                    TableRow.children["memory"].children[0].children[0].innerHTML = "<small>离线</small>";
                    TableRow.children["hdd"].children[0].children[0].className = "progress-bar progress-bar-danger";
                    TableRow.children["hdd"].children[0].children[0].style.width = "100%";
                    TableRow.children["hdd"].children[0].children[0].innerHTML = "<small>离线</small>";
                    TableRow.children["ping"].innerHTML = "–";
                    
                    if(ExpandRow.hasClass && ExpandRow.hasClass("in")) {
                        ExpandRow.collapse("hide");
                    }
                    if(server_status[i]) {
                        TableRow.setAttribute("data-target", "");
                        server_status[i] = false;
                    }
                }
            }
            d = new Date();
            error = 0;
        })
        .fail(function() {
            error = 1;
            $("#updated").html("更新错误.");
        });
}

function updateTime() {
    if (!error) $("#updated").html("最后更新: " + timeSince(d));
}

uptime();
updateTime();
setInterval(uptime, 5000);
setInterval(updateTime, 1000);

// 手动绑定折叠展开事件
$(document).ready(function() {
    // 为所有带 accordion-toggle 的行绑定点击事件
    $(document).on('click', '.accordion-toggle', function() {
        var target = $(this).attr('data-target');
        if (target) {
            $(target).collapse('toggle');
        }
    });
});
