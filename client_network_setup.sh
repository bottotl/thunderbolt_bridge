#!/bin/bash
# 雷雳桥接网络客户端配置脚本

echo "=== 雷雳桥接网络客户端配置 ==="

# 检查网络服务
echo "0. 检查可用的网络服务:"
networksetup -listallnetworkservices | grep -E "(雷雳|Thunderbolt)"

# 检查雷雳连接状态
echo ""
echo "1. 检查雷雳连接状态:"
system_profiler SPThunderboltDataType | grep -E "(Device connected|Speed)" | head -4

# 自动检测雷雳网桥服务名称
BRIDGE_SERVICE=""
if networksetup -listallnetworkservices | grep -q "雷雳网桥"; then
    BRIDGE_SERVICE="雷雳网桥"
elif networksetup -listallnetworkservices | grep -q "Thunderbolt Bridge"; then
    BRIDGE_SERVICE="Thunderbolt Bridge"
else
    echo "❌ 未找到雷雳网桥服务"
    echo "可用的网络服务:"
    networksetup -listallnetworkservices
    exit 1
fi

echo "检测到雷雳网桥服务: $BRIDGE_SERVICE"

# 配置网络接口
echo ""
echo "2. 配置雷雳网桥接口..."

# 使用networksetup配置（推荐方法）
echo "配置IP地址..."
sudo networksetup -setmanual "$BRIDGE_SERVICE" 192.168.200.2 255.255.255.0 192.168.200.1

echo "设置DNS服务器..."
sudo networksetup -setdnsservers "$BRIDGE_SERVICE" 8.8.8.8 1.1.1.1

# 等待网络配置生效
echo "等待网络配置生效..."
sleep 2

# 验证配置
echo ""
echo "3. 验证网络配置..."

echo "检查服务状态:"
networksetup -getinfo "$BRIDGE_SERVICE"

echo ""
echo "检查接口状态:"
# 检查桥接接口状态
if ifconfig bridge0 >/dev/null 2>&1; then
    echo "桥接接口状态:"
    ifconfig bridge0 | grep -E "(inet|status)"
else
    echo "检查雷雳接口状态:"
    ifconfig en1 2>/dev/null | grep "inet " || ifconfig en2 2>/dev/null | grep "inet " || echo "❌ 未找到配置的接口"
fi

echo ""
echo "路由表:"
netstat -rn | grep 192.168.200 || echo "❌ 未找到192.168.200网段路由"

echo ""
echo "4. 测试网络连接..."

echo "测试本地桥接网关:"
if ping -c 3 -t 5 192.168.200.1 >/dev/null 2>&1; then
    echo "✅ 桥接网关连通正常"
else
    echo "❌ 桥接网关连接失败"
    echo "请确认主机端桥接配置正确"
fi

echo ""
echo "测试外网连接:"
if ping -c 3 -t 5 8.8.8.8 >/dev/null 2>&1; then
    echo "✅ 外网连接正常"
else
    echo "❌ 外网连接失败"
    echo "可能是NAT配置或主机WiFi问题"
fi

echo ""
echo "测试域名解析:"
if nslookup google.com >/dev/null 2>&1; then
    echo "✅ DNS解析正常"
else
    echo "❌ DNS解析失败"
fi

echo ""
echo "=== 配置总结 ==="
if ping -c 1 -t 3 192.168.200.1 >/dev/null 2>&1 && ping -c 1 -t 3 8.8.8.8 >/dev/null 2>&1; then
    echo "🎉 雷雳桥接网络配置成功！"
    echo "客户端IP: 192.168.200.2"
    echo "网关IP: 192.168.200.1"
    echo "网络状态: 正常"
    echo ""
    echo "💡 为了确保配置稳定，建议主机端使用持久化配置："
    echo "在主机端运行: sudo ./persistent_bridge_setup.sh"
    echo "这将减少主机端需要重复执行脚本的频率"
else
    echo "⚠️ 网络配置可能有问题"
    echo ""
    echo "🔧 故障排除步骤："
    echo "1. 检查雷雳线缆连接"
    echo "2. 确认主机端bridge_network_setup.sh已执行"
    echo "   推荐使用: sudo ./persistent_bridge_setup.sh"
    echo "3. 重启两台Mac后重试"
    echo "4. 检查主机端WiFi连接状态"
    echo ""
    echo "📊 主机端高级配置选项："
    echo "• 持久化配置: sudo ./persistent_bridge_setup.sh"
    echo "• 系统监控服务: sudo ./install_daemon.sh"
    echo "• 实时监控: sudo ./bridge_monitor.sh --monitor"
    echo ""
    echo "📝 手动配置备选方案:"
    echo "如果自动配置失败，可尝试："
    echo "sudo ifconfig bridge0 192.168.200.2/24 2>/dev/null || \\"
    echo "sudo ifconfig en1 192.168.200.2/24 2>/dev/null || \\"
    echo "sudo ifconfig en2 192.168.200.2/24"
fi