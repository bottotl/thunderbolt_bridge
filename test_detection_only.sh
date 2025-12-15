#!/bin/bash
# 仅测试网卡检测逻辑（不需要 sudo）

echo "=== 测试网卡检测逻辑 ==="
echo ""

INTERNET_INTERFACE=""
INTERFACE_TYPE=""
INTERFACE_NAME=""

echo "正在检测有线网卡..."

# 保存到临时文件避免管道子shell问题
TEMP_PORTS_FILE="/tmp/network_ports_$$.txt"
networksetup -listallhardwareports > "$TEMP_PORTS_FILE"

# 逐行读取并检测
while IFS= read -r line; do
    if [[ "$line" =~ ^Hardware\ Port:\ (.+)$ ]]; then
        port_name="${BASH_REMATCH[1]}"
        # 排除无线和虚拟接口
        if [[ ! "$port_name" =~ (Wi-Fi|Bluetooth|雷雳网桥|Thunderbolt Bridge|Thunderbolt [0-9]) ]]; then
            # 读取下一行获取设备名
            read -r device_line
            if [[ "$device_line" =~ Device:\ (.+)$ ]]; then
                device="${BASH_REMATCH[1]}"
                echo "  检查: $port_name -> $device"
                # 检查接口是否活跃
                if ifconfig "$device" 2>/dev/null | grep -q "status: active"; then
                    INTERNET_INTERFACE="$device"
                    INTERFACE_NAME="$port_name"
                    INTERFACE_TYPE="以太网(有线)"
                    echo "✅ 检测到活跃的有线网卡: $INTERNET_INTERFACE ($INTERFACE_NAME)"
                    break
                fi
            fi
        fi
    fi
done < "$TEMP_PORTS_FILE"

# 清理临时文件
rm -f "$TEMP_PORTS_FILE"

# 如果没有找到活跃的有线网卡，使用WiFi
if [[ -z "$INTERNET_INTERFACE" ]]; then
    WIFI_INTERFACE=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
    if [[ -n "$WIFI_INTERFACE" ]]; then
        INTERNET_INTERFACE="$WIFI_INTERFACE"
        INTERFACE_NAME="Wi-Fi"
        INTERFACE_TYPE="WiFi(无线)"
        echo "ℹ️  未检测到活跃的有线网卡，使用WiFi接口: $INTERNET_INTERFACE"
    else
        # 都没有，使用默认值
        INTERNET_INTERFACE="en0"
        INTERFACE_NAME="默认接口"
        INTERFACE_TYPE="默认"
        echo "⚠️  警告: 未检测到有线或WiFi接口，使用默认值 en0"
    fi
fi

echo ""
echo "🌐 最终选择: $INTERNET_INTERFACE ($INTERFACE_NAME, $INTERFACE_TYPE)"
echo ""
echo "✅ 检测逻辑测试完成！"
echo "   此接口将用于 NAT 转发"
echo "   192.168.200.0/24 的流量将通过 $INTERNET_INTERFACE 转发到互联网"
