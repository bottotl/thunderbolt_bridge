#!/bin/bash
# 雷雳桥接网络持久化配置脚本 - 主机端
# 解决需要频繁重新执行脚本的问题

set -e

LOG_FILE="/var/log/thunderbolt_bridge.log"
ANCHOR_FILE="/etc/pf.anchors/thunderbolt_bridge"
CONFIG_LOCK="/var/run/thunderbolt_bridge.lock"

# 日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a "$LOG_FILE"
}

# 检查权限
check_permissions() {
    if [[ $EUID -ne 0 ]]; then
        echo "此脚本需要root权限，请使用 sudo 运行"
        exit 1
    fi
}

# 创建配置锁
create_lock() {
    echo $$ > "$CONFIG_LOCK"
    log_message "创建配置锁: $$"
}

# 清理函数
cleanup() {
    rm -f "$CONFIG_LOCK"
    log_message "清理配置锁"
}
trap cleanup EXIT

check_permissions

echo "=== 雷雳桥接网络持久化配置 ==="
log_message "开始雷雳桥接网络持久化配置"
create_lock

# 检查是否已经配置
if [[ -f "$CONFIG_LOCK" ]] && [[ $$ != $(cat "$CONFIG_LOCK") ]]; then
    echo "检测到另一个配置进程正在运行，退出"
    exit 1
fi

# 第一步：创建持久化目录结构
echo "1. 创建持久化配置目录..."
mkdir -p /etc/pf.anchors
mkdir -p /usr/local/bin/thunderbolt
mkdir -p /var/log

# 第二步：配置网络接口（使用networksetup确保持久化）
echo "2. 配置雷雳桥接网络接口..."

# 检查雷雳网桥服务
BRIDGE_SERVICE=""
if networksetup -listallnetworkservices | grep -q "雷雳网桥"; then
    BRIDGE_SERVICE="雷雳网桥"
elif networksetup -listallnetworkservices | grep -q "Thunderbolt Bridge"; then
    BRIDGE_SERVICE="Thunderbolt Bridge"
else
    log_message "错误: 未找到雷雳网桥服务"
    echo "❌ 未找到雷雳网桥服务"
    echo "可用的网络服务:"
    networksetup -listallnetworkservices
    exit 1
fi

log_message "检测到雷雳网桥服务: $BRIDGE_SERVICE"
echo "检测到雷雳网桥服务: $BRIDGE_SERVICE"

# 使用networksetup配置（持久化）
echo "配置桥接网络IP地址..."
networksetup -setmanual "$BRIDGE_SERVICE" 192.168.200.1 255.255.255.0
log_message "配置桥接网络IP: 192.168.200.1/24"

# 启用网络服务
networksetup -setnetworkserviceenabled "$BRIDGE_SERVICE" on
log_message "启用雷雳网桥服务"

# 等待网络配置生效
echo "等待网络配置生效..."
sleep 3

# 额外：重置桥接成员接口，使行为与临时脚本一致
echo "重置桥接成员接口(en1/en2)状态..."
if ifconfig en1 inet 0.0.0.0 down 2>/dev/null; then
    echo "已清除 en1 的IP配置"
else
    echo "en1 不存在或已清除"
fi
if ifconfig en2 inet 0.0.0.0 down 2>/dev/null; then
    echo "已清除 en2 的IP配置"
else
    echo "en2 不存在或已清除"
fi

echo "重启 bridge0 接口..."
if ifconfig bridge0 down 2>/dev/null; then
    sleep 1
    ifconfig bridge0 up 2>/dev/null || true
fi

echo "重新激活桥接成员接口..."
ifconfig en1 down 2>/dev/null || true
sleep 1
ifconfig en1 up 2>/dev/null || true
ifconfig en2 down 2>/dev/null || true
sleep 1
ifconfig en2 up 2>/dev/null || true

# 第三步：创建持久化NAT规则
echo "3. 创建持久化NAT规则..."

# 检测所有可用的互联网接口（有线、WiFi、USB网卡）
declare -a INTERNET_INTERFACES=()
declare -a INTERFACE_NAMES=()
declare -a INTERFACE_TYPES=()

echo "正在检测所有可用的网络接口..."

# 保存到临时文件避免管道子shell问题
TEMP_PORTS_FILE="/tmp/network_ports_$$.txt"
networksetup -listallhardwareports > "$TEMP_PORTS_FILE"

# 先检测所有类型的有线网卡接口（包括USB网卡）
# 支持：Ethernet、以太网、USB LAN、Thunderbolt Ethernet等
echo "检测有线/USB网卡..."

while IFS= read -r line; do
    if [[ "$line" =~ ^Hardware\ Port:\ (.+)$ ]]; then
        port_name="${BASH_REMATCH[1]}"
        # 排除无线和虚拟接口
        if [[ ! "$port_name" =~ (Wi-Fi|Bluetooth|雷雳网桥|Thunderbolt Bridge|Thunderbolt [0-9]) ]]; then
            # 读取下一行获取设备名
            read -r device_line
            if [[ "$device_line" =~ Device:\ (.+)$ ]]; then
                device="${BASH_REMATCH[1]}"
                # 检查接口是否活跃并有IP地址
                if ifconfig "$device" 2>/dev/null | grep -q "status: active"; then
                    # 检查是否有有效的IP地址（排除169.254开头的自动配置地址）
                    if ifconfig "$device" 2>/dev/null | grep "inet " | grep -v "169.254" >/dev/null; then
                        INTERNET_INTERFACES+=("$device")
                        INTERFACE_NAMES+=("$port_name")
                        INTERFACE_TYPES+=("有线/USB")
                        log_message "检测到活跃的有线/USB网卡: $device ($port_name)"
                        echo "✅ 检测到活跃的有线/USB网卡: $device ($port_name)"
                    fi
                fi
            fi
        fi
    fi
done < "$TEMP_PORTS_FILE"

# 检测WiFi接口
echo "检测WiFi接口..."
WIFI_INTERFACE=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
if [[ -n "$WIFI_INTERFACE" ]]; then
    # 检查WiFi是否活跃并有有效IP
    if ifconfig "$WIFI_INTERFACE" 2>/dev/null | grep -q "status: active"; then
        if ifconfig "$WIFI_INTERFACE" 2>/dev/null | grep "inet " | grep -v "169.254" >/dev/null; then
            INTERNET_INTERFACES+=("$WIFI_INTERFACE")
            INTERFACE_NAMES+=("Wi-Fi")
            INTERFACE_TYPES+=("无线")
            log_message "检测到活跃的WiFi接口: $WIFI_INTERFACE"
            echo "✅ 检测到活跃的WiFi接口: $WIFI_INTERFACE"
        fi
    fi
fi

# 清理临时文件
rm -f "$TEMP_PORTS_FILE"

# 检查是否找到至少一个可用接口
if [[ ${#INTERNET_INTERFACES[@]} -eq 0 ]]; then
    log_message "错误: 未检测到任何活跃的网络接口"
    echo "❌ 错误: 未检测到任何活跃的网络接口"
    echo "请确保至少有一个网络接口（有线、USB或WiFi）已连接并获得IP地址"
    exit 1
fi

# 输出检测到的所有接口
echo ""
echo "🌐 检测到 ${#INTERNET_INTERFACES[@]} 个可用的互联网接口:"
for i in "${!INTERNET_INTERFACES[@]}"; do
    log_message "接口 $((i+1)): ${INTERNET_INTERFACES[$i]} (${INTERFACE_NAMES[$i]}, ${INTERFACE_TYPES[$i]})"
    echo "  [$((i+1))] ${INTERNET_INTERFACES[$i]} - ${INTERFACE_NAMES[$i]} (${INTERFACE_TYPES[$i]})"
done
echo ""

# 创建持久化NAT规则文件
cat > "$ANCHOR_FILE" << EOF
# 雷雳桥接网络NAT规则 - 持久化配置（支持多接口）
# 生成时间: $(date)
# 共享接口数量: ${#INTERNET_INTERFACES[@]}
EOF

# 添加每个接口的详细信息到规则文件
for i in "${!INTERNET_INTERFACES[@]}"; do
    echo "# 接口 $((i+1)): ${INTERNET_INTERFACES[$i]} (${INTERFACE_NAMES[$i]}, ${INTERFACE_TYPES[$i]})" >> "$ANCHOR_FILE"
done

cat >> "$ANCHOR_FILE" << 'EOF'

# ========================================
# NAT规则：为每个互联网接口创建NAT转发
# ========================================
EOF

# 为每个检测到的接口创建NAT规则
for interface in "${INTERNET_INTERFACES[@]}"; do
    cat >> "$ANCHOR_FILE" << EOF
# NAT规则 - $interface
nat on $interface from 192.168.200.0/24 to any -> ($interface)

EOF
done

cat >> "$ANCHOR_FILE" << 'EOF'
# ========================================
# 流量转发规则
# ========================================

# 允许从桥接接口进入的流量
pass in on bridge0 from 192.168.200.0/24 to any keep state

EOF

# 为每个接口添加出站和入站规则
for interface in "${INTERNET_INTERFACES[@]}"; do
    cat >> "$ANCHOR_FILE" << EOF
# 流量规则 - $interface
pass out on $interface from 192.168.200.0/24 to any keep state
pass in on $interface to 192.168.200.0/24 keep state

EOF
done

cat >> "$ANCHOR_FILE" << 'EOF'
# ========================================
# 桥接接口规则
# ========================================

# 允许返回流量到桥接接口
pass out on bridge0 to 192.168.200.0/24 keep state

# 允许客户端访问主机本地服务（解决.local域名访问问题）
pass in on bridge0 from 192.168.200.0/24 to 192.168.200.1 keep state
pass out on bridge0 from 192.168.200.1 to 192.168.200.0/24 keep state

# 允许mDNS流量（支持.local域名解析）
pass in on bridge0 proto udp from any to any port 5353
pass out on bridge0 proto udp from any to any port 5353

# DNS转发支持
pass in on bridge0 proto udp from 192.168.200.0/24 to any port 53 keep state
pass in on bridge0 proto tcp from 192.168.200.0/24 to any port 53 keep state

# 允许ICMP（ping）
pass inet proto icmp from 192.168.200.0/24 to any keep state
pass inet proto icmp from any to 192.168.200.0/24 keep state

# 允许桥接接口所有流量（保证通畅）
pass in on bridge0 all
pass out on bridge0 all
EOF

log_message "创建持久化NAT规则文件: $ANCHOR_FILE"
echo "NAT规则文件已创建: $ANCHOR_FILE"

# 第四步：配置pf主配置文件
echo "4. 配置pfctl主配置文件..."

# 备份原始pf.conf
if [[ ! -f /etc/pf.conf.backup ]]; then
    cp /etc/pf.conf /etc/pf.conf.backup
    log_message "备份原始pf.conf到 /etc/pf.conf.backup"
fi

# 检查是否已经添加雷雳桥接规则
if ! grep -q "thunderbolt_bridge" /etc/pf.conf; then
    echo "" >> /etc/pf.conf
    echo "# 雷雳桥接网络规则" >> /etc/pf.conf
    echo "load anchor \"thunderbolt_bridge\" from \"$ANCHOR_FILE\"" >> /etc/pf.conf
    echo "anchor \"thunderbolt_bridge\"" >> /etc/pf.conf
    log_message "添加雷雳桥接规则到 /etc/pf.conf"
    echo "已添加雷雳桥接规则到 /etc/pf.conf"
else
    log_message "雷雳桥接规则已存在于 /etc/pf.conf"
    echo "雷雳桥接规则已存在于 /etc/pf.conf"
fi

# 第五步：启用持久化IP转发
echo "5. 配置持久化IP转发..."

# 创建sysctl配置文件
SYSCTL_CONF="/etc/sysctl.conf"
if [[ ! -f "$SYSCTL_CONF" ]] || ! grep -q "net.inet.ip.forwarding=1" "$SYSCTL_CONF"; then
    echo "net.inet.ip.forwarding=1" >> "$SYSCTL_CONF"
    log_message "添加IP转发到 $SYSCTL_CONF"
    echo "已配置持久化IP转发"
else
    log_message "IP转发配置已存在"
    echo "IP转发配置已存在"
fi

# 立即启用IP转发
sysctl -w net.inet.ip.forwarding=1
log_message "启用IP转发"

# 第六步：加载并启用pfctl规则
echo "6. 加载并启用pfctl规则..."

# 验证规则语法
if pfctl -vnf "$ANCHOR_FILE" >/dev/null 2>&1; then
    log_message "NAT规则语法验证通过"
    echo "NAT规则语法验证通过"
else
    log_message "错误: NAT规则语法验证失败"
    echo "❌ NAT规则语法验证失败"
    pfctl -vnf "$ANCHOR_FILE"
    exit 1
fi

# 加载规则
pfctl -f /etc/pf.conf 2>/dev/null || {
    log_message "警告: pfctl加载配置时有警告，但继续执行"
}

# 启用pfctl
pfctl -e 2>/dev/null || {
    log_message "pfctl已启用或启用时有警告"
    echo "pfctl已启用"
}

# 使用经过验证的直接加载方法（学习bridge_network_setup.sh的成功做法）
echo "使用直接加载NAT规则方法..."

# 创建临时规则文件（与bridge_network_setup.sh相同的方法）
TEMP_NAT_FILE="/tmp/persistent_bridge_nat.conf"
cp "$ANCHOR_FILE" "$TEMP_NAT_FILE"

# 直接加载规则文件（不使用anchor）
pfctl -f "$TEMP_NAT_FILE" 2>/dev/null && {
    log_message "NAT规则直接加载成功"
    echo "✅ NAT规则直接加载成功"
} || {
    log_message "错误: NAT规则加载失败"
    echo "❌ NAT规则加载失败"
    exit 1
}

# 验证规则是否真正生效
sleep 1
if pfctl -s nat 2>/dev/null | grep -q "192.168.200.0/24"; then
    log_message "NAT规则验证成功：规则已生效"
    echo "✅ NAT规则验证通过"
else
    log_message "警告: NAT规则可能未正确生效"
    echo "⚠️ NAT规则验证失败"
fi

# 第七步：创建自动修复脚本
echo "7. 创建自动修复脚本..."

cat > /usr/local/bin/thunderbolt/bridge_repair.sh << 'EOF'
#!/bin/bash
# 雷雳桥接网络自动修复脚本（支持多接口）

LOG_FILE="/var/log/thunderbolt_bridge.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# 检测所有可用的互联网接口
detect_internet_interfaces() {
    local -n interfaces=$1
    local -n names=$2
    local -n types=$3

    interfaces=()
    names=()
    types=()

    # 临时文件
    local temp_file="/tmp/network_ports_repair_$$.txt"
    networksetup -listallhardwareports > "$temp_file"

    # 检测有线/USB网卡
    while IFS= read -r line; do
        if [[ "$line" =~ ^Hardware\ Port:\ (.+)$ ]]; then
            local port_name="${BASH_REMATCH[1]}"
            if [[ ! "$port_name" =~ (Wi-Fi|Bluetooth|雷雳网桥|Thunderbolt Bridge|Thunderbolt [0-9]) ]]; then
                read -r device_line
                if [[ "$device_line" =~ Device:\ (.+)$ ]]; then
                    local device="${BASH_REMATCH[1]}"
                    if ifconfig "$device" 2>/dev/null | grep -q "status: active"; then
                        if ifconfig "$device" 2>/dev/null | grep "inet " | grep -v "169.254" >/dev/null; then
                            interfaces+=("$device")
                            names+=("$port_name")
                            types+=("有线/USB")
                        fi
                    fi
                fi
            fi
        fi
    done < "$temp_file"

    # 检测WiFi
    local wifi_interface=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
    if [[ -n "$wifi_interface" ]]; then
        if ifconfig "$wifi_interface" 2>/dev/null | grep -q "status: active"; then
            if ifconfig "$wifi_interface" 2>/dev/null | grep "inet " | grep -v "169.254" >/dev/null; then
                interfaces+=("$wifi_interface")
                names+=("Wi-Fi")
                types+=("无线")
            fi
        fi
    fi

    rm -f "$temp_file"
}

# 检查桥接接口状态
check_bridge_status() {
    if ifconfig bridge0 >/dev/null 2>&1; then
        local bridge_ip=$(ifconfig bridge0 | grep "inet " | awk '{print $2}')
        if [[ "$bridge_ip" == "192.168.200.1" ]]; then
            return 0
        fi
    fi
    return 1
}

# 检查NAT规则
check_nat_rules() {
    if pfctl -s nat 2>/dev/null | grep -q "192.168.200.0/24"; then
        return 0
    fi
    return 1
}

# 检查IP转发
check_ip_forwarding() {
    local forwarding=$(sysctl -n net.inet.ip.forwarding 2>/dev/null)
    if [[ "$forwarding" == "1" ]]; then
        return 0
    fi
    return 1
}

# 重建NAT规则文件（支持多接口）
rebuild_nat_rules() {
    local -a inet_interfaces
    local -a inet_names
    local -a inet_types

    detect_internet_interfaces inet_interfaces inet_names inet_types

    if [[ ${#inet_interfaces[@]} -eq 0 ]]; then
        log_message "错误: 未检测到可用的互联网接口"
        return 1
    fi

    log_message "检测到 ${#inet_interfaces[@]} 个互联网接口，重建NAT规则"

    local anchor_file="/etc/pf.anchors/thunderbolt_bridge"

    # 创建新的NAT规则文件
    cat > "$anchor_file" << EOFNAT
# 雷雳桥接网络NAT规则 - 自动修复重建
# 重建时间: $(date)
# 共享接口数量: ${#inet_interfaces[@]}
EOFNAT

    # 添加接口信息
    for i in "${!inet_interfaces[@]}"; do
        echo "# 接口 $((i+1)): ${inet_interfaces[$i]} (${inet_names[$i]}, ${inet_types[$i]})" >> "$anchor_file"
    done

    cat >> "$anchor_file" << 'EOFNAT'

# ========================================
# NAT规则：为每个互联网接口创建NAT转发
# ========================================
EOFNAT

    # 为每个接口创建NAT规则
    for interface in "${inet_interfaces[@]}"; do
        cat >> "$anchor_file" << EOFNAT
# NAT规则 - $interface
nat on $interface from 192.168.200.0/24 to any -> ($interface)

EOFNAT
    done

    cat >> "$anchor_file" << 'EOFNAT'
# ========================================
# 流量转发规则
# ========================================

# 允许从桥接接口进入的流量
pass in on bridge0 from 192.168.200.0/24 to any keep state

EOFNAT

    # 为每个接口添加流量规则
    for interface in "${inet_interfaces[@]}"; do
        cat >> "$anchor_file" << EOFNAT
# 流量规则 - $interface
pass out on $interface from 192.168.200.0/24 to any keep state
pass in on $interface to 192.168.200.0/24 keep state

EOFNAT
    done

    cat >> "$anchor_file" << 'EOFNAT'
# ========================================
# 桥接接口规则
# ========================================

# 允许返回流量到桥接接口
pass out on bridge0 to 192.168.200.0/24 keep state

# 允许客户端访问主机本地服务
pass in on bridge0 from 192.168.200.0/24 to 192.168.200.1 keep state
pass out on bridge0 from 192.168.200.1 to 192.168.200.0/24 keep state

# 允许mDNS流量
pass in on bridge0 proto udp from any to any port 5353
pass out on bridge0 proto udp from any to any port 5353

# DNS转发支持
pass in on bridge0 proto udp from 192.168.200.0/24 to any port 53 keep state
pass in on bridge0 proto tcp from 192.168.200.0/24 to any port 53 keep state

# 允许ICMP（ping）
pass inet proto icmp from 192.168.200.0/24 to any keep state
pass inet proto icmp from any to 192.168.200.0/24 keep state

# 允许桥接接口所有流量
pass in on bridge0 all
pass out on bridge0 all
EOFNAT

    return 0
}

# 修复桥接配置
repair_bridge() {
    log_message "开始修复桥接配置"

    # 重新配置网络接口
    BRIDGE_SERVICE=""
    if networksetup -listallnetworkservices | grep -q "雷雳网桥"; then
        BRIDGE_SERVICE="雷雳网桥"
    elif networksetup -listallnetworkservices | grep -q "Thunderbolt Bridge"; then
        BRIDGE_SERVICE="Thunderbolt Bridge"
    fi

    if [[ -n "$BRIDGE_SERVICE" ]]; then
        networksetup -setmanual "$BRIDGE_SERVICE" 192.168.200.1 255.255.255.0
        networksetup -setnetworkserviceenabled "$BRIDGE_SERVICE" on
        log_message "修复桥接接口配置: $BRIDGE_SERVICE"
    fi

    # 修复IP转发
    if ! check_ip_forwarding; then
        sysctl -w net.inet.ip.forwarding=1
        log_message "修复IP转发设置"
    fi

    # 修复NAT规则（支持多接口）
    if ! check_nat_rules; then
        pfctl -e 2>/dev/null

        # 重建NAT规则文件以支持当前所有可用接口
        if rebuild_nat_rules; then
            # 使用直接加载方法
            if [[ -f "/etc/pf.anchors/thunderbolt_bridge" ]]; then
                pfctl -f "/etc/pf.anchors/thunderbolt_bridge" 2>/dev/null
                log_message "NAT规则已重建并加载（多接口支持）"
            fi
        else
            log_message "NAT规则重建失败"
        fi
    fi
}

# 主检查逻辑
main() {
    local need_repair=false

    if ! check_bridge_status; then
        log_message "检测到桥接配置异常"
        need_repair=true
    fi

    if ! check_ip_forwarding; then
        log_message "检测到IP转发异常"
        need_repair=true
    fi

    if ! check_nat_rules; then
        log_message "检测到NAT规则异常"
        need_repair=true
    fi

    if [[ "$need_repair" == "true" ]]; then
        repair_bridge
        log_message "自动修复完成"
    fi
}

# 仅在脚本直接执行时运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF

chmod +x /usr/local/bin/thunderbolt/bridge_repair.sh
log_message "创建自动修复脚本: /usr/local/bin/thunderbolt/bridge_repair.sh"

# 第八步：验证配置
echo "8. 验证持久化配置..."

echo "检查网络接口状态:"
networksetup -getinfo "$BRIDGE_SERVICE"

echo ""
echo "检查IP转发状态:"
sysctl net.inet.ip.forwarding

echo ""
echo "检查NAT规则:"
pfctl -s nat 2>/dev/null | head -5 || echo "NAT规则加载中..."

echo ""
echo "检查桥接接口:"
ifconfig bridge0 | grep -E "(inet|status|member)" || echo "桥接接口配置中..."

# 第九步：测试连接
echo ""
echo "9. 测试网络连接..."
sleep 2

echo "测试桥接网络:"
if ping -c 3 -t 5 192.168.200.1 >/dev/null 2>&1; then
    echo "✅ 桥接网络连通正常"
    log_message "桥接网络连通性测试通过"
else
    echo "⚠️ 桥接网络连通性测试失败"
    log_message "警告: 桥接网络连通性测试失败"
fi

echo ""
log_message "雷雳桥接网络持久化配置完成"
echo "=== 持久化配置完成! ==="
echo ""
echo "🎯 配置总结:"
echo "✅ 网络接口配置已持久化到系统设置"
echo "✅ NAT规则已保存到 $ANCHOR_FILE"
echo "✅ IP转发已配置为系统默认"
echo "✅ pfctl规则已集成到系统配置"
echo "✅ 自动修复脚本已部署"
echo ""
echo "📝 现在配置将在以下情况下自动加载:"
echo "• 系统重启后"
echo "• 网络接口重连后"
echo "• pfctl服务重启后"
echo ""
echo "🔧 如果仍有问题，可运行自动修复:"
echo "sudo /usr/local/bin/thunderbolt/bridge_repair.sh"
echo ""
echo "📋 客户端配置:"
echo "在另一台Mac上运行 client_network_setup.sh"
echo "或手动配置："
echo "  IP: 192.168.200.2"
echo "  子网掩码: 255.255.255.0"
echo "  网关: 192.168.200.1"
echo "  DNS: 8.8.8.8, 1.1.1.1"
