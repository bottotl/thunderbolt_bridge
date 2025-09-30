#!/bin/bash
# 雷雳桥接网络系统服务安装脚本

set -e

DAEMON_PLIST="com.thunderbolt.bridge.plist"
DAEMON_PATH="/Library/LaunchDaemons/$DAEMON_PLIST"
SERVICE_NAME="com.thunderbolt.bridge"

echo "=== 雷雳桥接网络系统服务安装 ==="

# 检查权限
if [[ $EUID -ne 0 ]]; then
    echo "此脚本需要root权限，请使用 sudo 运行"
    exit 1
fi

# 检查文件是否存在
if [[ ! -f "$DAEMON_PLIST" ]]; then
    echo "❌ 错误: 找不到 $DAEMON_PLIST 文件"
    echo "请确保在包含plist文件的目录中运行此脚本"
    exit 1
fi

# 检查bridge_repair.sh是否存在
if [[ ! -f "/usr/local/bin/thunderbolt/bridge_repair.sh" ]]; then
    echo "❌ 错误: 找不到 /usr/local/bin/thunderbolt/bridge_repair.sh"
    echo "请先运行 persistent_bridge_setup.sh 创建自动修复脚本"
    exit 1
fi

echo "1. 停止现有服务（如果存在）..."
if launchctl list | grep -q "$SERVICE_NAME"; then
    echo "停止现有服务: $SERVICE_NAME"
    launchctl stop "$SERVICE_NAME" 2>/dev/null || true
    launchctl unload "$DAEMON_PATH" 2>/dev/null || true
else
    echo "未找到运行中的服务"
fi

echo ""
echo "2. 安装服务配置文件..."
# 复制plist文件到系统目录
cp "$DAEMON_PLIST" "$DAEMON_PATH"
echo "已复制 $DAEMON_PLIST 到 $DAEMON_PATH"

# 设置正确的权限
chown root:wheel "$DAEMON_PATH"
chmod 644 "$DAEMON_PATH"
echo "已设置正确的文件权限"

echo ""
echo "3. 验证配置文件..."
# 验证plist文件格式
if plutil -lint "$DAEMON_PATH" >/dev/null 2>&1; then
    echo "✅ plist文件格式验证通过"
else
    echo "❌ plist文件格式验证失败"
    plutil -lint "$DAEMON_PATH"
    exit 1
fi

echo ""
echo "4. 加载并启动服务..."
# 加载服务
if launchctl load "$DAEMON_PATH"; then
    echo "✅ 服务加载成功"
else
    echo "❌ 服务加载失败"
    exit 1
fi

# 等待服务启动
sleep 2

echo ""
echo "5. 验证服务状态..."
# 检查服务是否运行
if launchctl list | grep -q "$SERVICE_NAME"; then
    echo "✅ 服务已启动: $SERVICE_NAME"
    echo ""
    echo "服务详细信息:"
    launchctl list "$SERVICE_NAME"
else
    echo "❌ 服务启动失败"
    echo ""
    echo "检查系统日志:"
    tail -10 /var/log/system.log | grep -i thunderbolt || echo "未找到相关日志"
    exit 1
fi

echo ""
echo "6. 测试自动修复功能..."
# 运行一次自动修复脚本进行测试
if /usr/local/bin/thunderbolt/bridge_repair.sh; then
    echo "✅ 自动修复脚本测试通过"
else
    echo "⚠️ 自动修复脚本测试失败，但服务已安装"
fi

echo ""
echo "=== 系统服务安装完成! ==="
echo ""
echo "🎯 服务功能:"
echo "✅ 系统启动时自动配置雷雳桥接网络"
echo "✅ 网络状态变化时自动修复配置"
echo "✅ 每5分钟定期检查网络状态"
echo "✅ 系统休眠唤醒后自动修复"
echo ""
echo "📋 服务管理命令:"
echo "• 查看服务状态: sudo launchctl list $SERVICE_NAME"
echo "• 停止服务: sudo launchctl stop $SERVICE_NAME"
echo "• 启动服务: sudo launchctl start $SERVICE_NAME"
echo "• 卸载服务: sudo launchctl unload $DAEMON_PATH"
echo "• 重载服务: sudo launchctl unload $DAEMON_PATH && sudo launchctl load $DAEMON_PATH"
echo ""
echo "📝 日志文件:"
echo "• 服务日志: /var/log/thunderbolt_bridge_daemon.log"
echo "• 修复日志: /var/log/thunderbolt_bridge.log"
echo ""
echo "🔧 如需手动检查："
echo "sudo /usr/local/bin/thunderbolt/bridge_repair.sh"