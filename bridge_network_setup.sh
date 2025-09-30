#!/bin/bash
# 雷雳桥接网络配置脚本 - 主机端
# 优化版本：支持持久化配置，减少重复执行需求

echo "=== 雷雳桥接网络配置 (优化版) ==="
echo ""
echo "🔄 此脚本现在支持："
echo "• 持久化网络配置"
echo "• 自动修复功能"
echo "• 系统服务监控"
echo ""
echo "💡 建议使用新的持久化配置脚本："
echo "sudo ./persistent_bridge_setup.sh"
echo ""
echo "是否继续使用此脚本？(y/N): "
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "退出脚本。建议运行: sudo ./persistent_bridge_setup.sh"
    exit 0
fi

echo ""
echo "=== 开始雷雳桥接网络临时配置 ==="

# 检查当前状态
echo "0. 检查当前网络状态..."
echo "当前桥接状态:"
ifconfig bridge0 2>/dev/null || echo "桥接接口不存在"
echo ""

# 第一步：重置桥接配置
echo "1. 重置雷雳桥接配置..."

# 清除个别接口的IP配置（这是导致冲突的原因）
echo "清除en1和en2的IP配置..."
sudo ifconfig en1 inet 0.0.0.0 down 2>/dev/null || echo "en1已清除"
sudo ifconfig en2 inet 0.0.0.0 down 2>/dev/null || echo "en2已清除"

# 重新启动桥接接口
echo "重启桥接接口..."
sudo ifconfig bridge0 down 2>/dev/null
sleep 1
sudo ifconfig bridge0 up 2>/dev/null

# 确保桥接接口有正确的IP
echo "配置桥接接口IP..."
sudo networksetup -setmanual "雷雳网桥" 192.168.200.1 255.255.255.0

# 验证桥接配置
echo ""
echo "验证桥接配置:"
ifconfig bridge0 | grep -E "(flags|inet|member)"

# 第二步：重新激活桥接成员接口
echo ""
echo "2. 重新激活桥接成员接口..."

# 重新启动桥接成员接口
echo "重启en1接口..."
sudo ifconfig en1 down
sleep 1
sudo ifconfig en1 up

echo "重启en2接口..."
sudo ifconfig en2 down
sleep 1
sudo ifconfig en2 up

# 检查桥接成员状态
echo "检查桥接成员状态:"
ifconfig bridge0 | grep -A 2 "member:"

# 第三步：配置NAT转发规则
echo ""
echo "3. 配置NAT转发规则..."

# 获取WiFi接口名称（可能是en0）
WIFI_INTERFACE=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
echo "检测到WiFi接口: $WIFI_INTERFACE"

# 创建pfctl规则文件
cat > /tmp/bridge_nat.conf << EOF
# NAT规则：将192.168.200.0/24网段的流量通过WiFi接口转发
nat on $WIFI_INTERFACE from 192.168.200.0/24 to any -> ($WIFI_INTERFACE)

# 允许从桥接接口进入的流量
pass in on bridge0 from 192.168.200.0/24 to any

# 允许通过WiFi接口出去的流量
pass out on $WIFI_INTERFACE from 192.168.200.0/24 to any

# 允许返回的流量
pass in on $WIFI_INTERFACE to 192.168.200.0/24
pass out on bridge0 to 192.168.200.0/24

# 允许客户端访问主机本地服务（解决.local域名访问问题）
pass in on bridge0 from 192.168.200.0/24 to 192.168.200.1
pass out on bridge0 from 192.168.200.1 to 192.168.200.0/24

# 允许mDNS流量（支持.local域名解析）
pass in on bridge0 proto udp from any to any port 5353
pass out on bridge0 proto udp from any to any port 5353

# 允许转发流量
pass in on bridge0 all
pass out on bridge0 all
EOF

echo "NAT规则文件已创建: /tmp/bridge_nat.conf"
echo "内容:"
cat /tmp/bridge_nat.conf

# 第四步：启用IP转发和NAT
echo ""
echo "4. 启用IP转发和NAT..."

# 启用IP转发
echo "启用IP转发..."
sudo sysctl -w net.inet.ip.forwarding=1

# 加载pfctl规则
echo "加载pfctl规则..."
sudo pfctl -f /tmp/bridge_nat.conf

echo "启用pfctl..."
sudo pfctl -e 2>/dev/null || echo "pfctl已启用"

# 验证配置
echo ""
echo "5. 验证配置..."

echo "IP转发状态:"
sysctl net.inet.ip.forwarding

echo ""
echo "NAT规则:"
sudo pfctl -s nat 2>/dev/null || echo "无NAT规则或pfctl未启用"

echo ""
echo "桥接接口状态:"
ifconfig bridge0 | grep -E "(flags|inet|status|member)"

echo ""
echo "=== 雷雳桥接网络临时配置完成! ==="
echo ""
echo "⚠️  重要提醒: 此配置为临时配置，重启后会丢失"
echo ""
echo "6. 测试连接..."
# 测试桥接网络
echo "测试桥接网络本地连通性:"
ping -c 3 192.168.200.1 2>/dev/null && echo "✅ 桥接网络正常" || echo "❌ 桥接网络异常"

echo ""
echo "🔧 避免频繁重复执行的解决方案:"
echo ""
echo "1. 🚀 推荐: 使用持久化配置脚本"
echo "   sudo ./persistent_bridge_setup.sh"
echo "   • 配置在重启后自动保持"
echo "   • 包含自动修复功能"
echo "   • 减少手动干预需求"
echo ""
echo "2. 📊 安装系统监控服务"
echo "   sudo ./install_daemon.sh"
echo "   • 系统启动时自动配置"
echo "   • 网络异常时自动修复"
echo "   • 定期健康检查"
echo ""
echo "3. 🔍 手动监控网络状态"
echo "   sudo ./bridge_monitor.sh --monitor"
echo "   • 实时监控网络状态"
echo "   • 自动检测和修复问题"
echo ""
echo "📝 另一台Mac配置说明:"
echo "在连接的Mac上执行："
echo "  sudo ./client_network_setup.sh"
echo ""
echo "或手动配置："
echo "  系统偏好设置 → 网络 → 雷雳网桥"
echo "  - IP地址: 192.168.200.2"
echo "  - 子网掩码: 255.255.255.0"
echo "  - 路由器: 192.168.200.1"
echo "  - DNS: 8.8.8.8, 1.1.1.1"
echo ""
echo "🎯 当前配置特点（临时）："
echo "- ✅ 清除了en1/en2的IP配置冲突"
echo "- ✅ 重新激活了桥接成员接口"
echo "- ✅ 修正了NAT规则使用bridge0接口"
echo "- ✅ 启用了IP转发功能"
echo "- ✅ 添加了本地服务访问支持"
echo "- ✅ 启用了mDNS流量转发"
echo "- ⚠️  重启后需要重新执行"
echo ""
echo "💡 为了获得最佳体验，建议运行持久化配置："
echo "sudo ./persistent_bridge_setup.sh"