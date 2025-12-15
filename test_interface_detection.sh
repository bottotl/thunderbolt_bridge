#!/bin/bash
# 测试网络接口检测逻辑
# 用于验证有线网卡优先选择功能

echo "=== 网络接口检测测试 ==="
echo ""

# 检测以太网接口（有线网卡）
echo "1. 检测以太网接口..."
ETHERNET_INTERFACE=$(networksetup -listallhardwareports | awk '/Ethernet|以太网/{getline; print $2}' | head -1)
if [[ -n "$ETHERNET_INTERFACE" ]]; then
    echo "找到以太网接口: $ETHERNET_INTERFACE"

    # 检查状态
    if ifconfig "$ETHERNET_INTERFACE" 2>/dev/null | grep -q "status: active"; then
        echo "✅ 以太网接口状态: 活跃"
        ETHERNET_ACTIVE=true
    else
        echo "⚠️  以太网接口状态: 未活跃"
        ETHERNET_ACTIVE=false
    fi

    # 显示详细信息
    echo "接口详情:"
    ifconfig "$ETHERNET_INTERFACE" 2>/dev/null | grep -E "(status|inet )"
else
    echo "❌ 未找到以太网接口"
    ETHERNET_ACTIVE=false
fi

echo ""
echo "2. 检测WiFi接口..."
WIFI_INTERFACE=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
if [[ -n "$WIFI_INTERFACE" ]]; then
    echo "找到WiFi接口: $WIFI_INTERFACE"

    # 检查状态
    if ifconfig "$WIFI_INTERFACE" 2>/dev/null | grep -q "status: active"; then
        echo "✅ WiFi接口状态: 活跃"
        WIFI_ACTIVE=true
    else
        echo "⚠️  WiFi接口状态: 未活跃"
        WIFI_ACTIVE=false
    fi

    # 显示详细信息
    echo "接口详情:"
    ifconfig "$WIFI_INTERFACE" 2>/dev/null | grep -E "(status|inet )"
else
    echo "❌ 未找到WiFi接口"
    WIFI_ACTIVE=false
fi

echo ""
echo "3. 使用新的智能检测逻辑..."

# 模拟脚本中的选择逻辑
INTERNET_INTERFACE=""
INTERFACE_TYPE=""
INTERFACE_NAME=""

echo "正在检测所有有线网卡（支持USB LAN、Ethernet Adapter等）..."

# 保存到临时文件避免管道子shell问题
TEMP_PORTS_FILE="/tmp/network_ports_test_$$.txt"
networksetup -listallhardwareports > "$TEMP_PORTS_FILE"

# 逐行读取并检测
while IFS= read -r line; do
    if [[ "$line" =~ ^Hardware\ Port:\ (.+)$ ]]; then
        port_name="${BASH_REMATCH[1]}"
        # 排除无线和虚拟接口
        if [[ ! "$port_name" =~ (Wi-Fi|Bluetooth|雷雳网桥|Thunderbolt Bridge|Thunderbolt [0-9]) ]]; then
            echo "  检查端口: $port_name"
            # 读取下一行获取设备名
            read -r device_line
            if [[ "$device_line" =~ Device:\ (.+)$ ]]; then
                device="${BASH_REMATCH[1]}"
                echo "    设备: $device"
                # 检查接口是否活跃
                if ifconfig "$device" 2>/dev/null | grep -q "status: active"; then
                    echo "    状态: ✅ 活跃"
                    INTERNET_INTERFACE="$device"
                    INTERFACE_NAME="$port_name"
                    INTERFACE_TYPE="以太网(有线)"
                    echo "🎯 选择有线网卡: $INTERNET_INTERFACE ($INTERFACE_NAME)"
                    break
                else
                    echo "    状态: ⚠️  未活跃或无状态"
                fi
            fi
        fi
    fi
done < "$TEMP_PORTS_FILE"

# 清理临时文件
rm -f "$TEMP_PORTS_FILE"

# 如果没有找到活跃的有线网卡，使用WiFi
if [[ -z "$INTERNET_INTERFACE" ]]; then
    echo "未找到活跃的有线网卡，检查WiFi..."
    if [[ -n "$WIFI_INTERFACE" ]]; then
        INTERNET_INTERFACE="$WIFI_INTERFACE"
        INTERFACE_NAME="Wi-Fi"
        INTERFACE_TYPE="WiFi(无线)"
        echo "🎯 选择WiFi: $INTERNET_INTERFACE"
    else
        INTERNET_INTERFACE="en0"
        INTERFACE_NAME="默认接口"
        INTERFACE_TYPE="默认"
        echo "🎯 使用默认接口: $INTERNET_INTERFACE"
    fi
fi

echo ""
echo "=== 测试结果 ==="
echo "共享网络接口: $INTERNET_INTERFACE ($INTERFACE_TYPE)"
echo ""

if [[ "$INTERFACE_TYPE" == "以太网(有线)" ]]; then
    echo "✅ 优先级测试通过：成功选择有线网卡"
elif [[ "$INTERFACE_TYPE" == "WiFi(无线)" ]] && [[ "$ETHERNET_ACTIVE" == "false" ]]; then
    echo "✅ 优先级测试通过：无活跃有线网卡时正确回退到WiFi"
elif [[ "$INTERFACE_TYPE" == "默认" ]]; then
    echo "⚠️  使用默认接口：未检测到有线或WiFi"
else
    echo "❌ 优先级测试失败：选择逻辑可能有问题"
fi

echo ""
echo "=== 所有网络服务 ==="
networksetup -listallnetworkservices
