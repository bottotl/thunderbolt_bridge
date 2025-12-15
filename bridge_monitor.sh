#!/bin/bash
# 雷雳桥接网络实时监控和自动修复脚本
# 提供实时监控、问题检测和自动修复功能

set -e

# 配置参数
LOG_FILE="/var/log/thunderbolt_bridge_monitor.log"
CHECK_INTERVAL=30  # 检查间隔（秒）
MAX_REPAIR_ATTEMPTS=3  # 最大修复尝试次数
REPAIR_COOLDOWN=300  # 修复冷却时间（秒）
PING_TIMEOUT=5  # ping超时时间
STATE_FILE="/var/run/thunderbolt_bridge_state"

# 状态跟踪
REPAIR_COUNT=0
LAST_REPAIR_TIME=0
MONITOR_PID=$$

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log_message "INFO" "$1"
}

log_warn() {
    log_message "WARN" "$1"
}

log_error() {
    log_message "ERROR" "$1"
}

log_success() {
    log_message "SUCCESS" "$1"
}

# 彩色输出函数
print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        "OK")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "WARN")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  $message${NC}"
            ;;
    esac
}

# 检查权限
check_permissions() {
    if [[ $EUID -ne 0 ]]; then
        log_error "监控脚本需要root权限，请使用 sudo 运行"
        exit 1
    fi
}

# 保存状态
save_state() {
    local state="$1"
    local timestamp=$(date +%s)
    echo "STATE=$state" > "$STATE_FILE"
    echo "TIMESTAMP=$timestamp" >> "$STATE_FILE"
    echo "REPAIR_COUNT=$REPAIR_COUNT" >> "$STATE_FILE"
    echo "LAST_REPAIR_TIME=$LAST_REPAIR_TIME" >> "$STATE_FILE"
}

# 加载状态
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE" 2>/dev/null || true
    fi
}

# 检查雷雳连接状态
check_thunderbolt_connection() {
    local connected=false

    # 检查雷雳设备
    if system_profiler SPThunderboltDataType 2>/dev/null | grep -q "Device connected"; then
        connected=true
    fi

    # 检查网络接口
    if networksetup -listallnetworkservices | grep -qE "(雷雳网桥|Thunderbolt Bridge)"; then
        local service_name=""
        if networksetup -listallnetworkservices | grep -q "雷雳网桥"; then
            service_name="雷雳网桥"
        elif networksetup -listallnetworkservices | grep -q "Thunderbolt Bridge"; then
            service_name="Thunderbolt Bridge"
        fi

        if [[ -n "$service_name" ]]; then
            local service_status=$(networksetup -getinfo "$service_name" | grep "IP address" | awk '{print $3}')
            if [[ "$service_status" == "192.168.200.1" ]]; then
                connected=true
            fi
        fi
    fi

    if $connected; then
        return 0
    else
        return 1
    fi
}

# 检查桥接接口状态
check_bridge_interface() {
    if ifconfig bridge0 >/dev/null 2>&1; then
        local bridge_ip=$(ifconfig bridge0 | grep "inet " | awk '{print $2}')
        local bridge_status=$(ifconfig bridge0 | grep "status:" | awk '{print $2}')

        if [[ "$bridge_ip" == "192.168.200.1" ]] && [[ "$bridge_status" == "active" ]]; then
            return 0
        fi
    fi
    return 1
}

# 检查NAT规则状态
check_nat_rules() {
    # 方法1：检查NAT规则输出
    if pfctl -s nat 2>/dev/null | grep -q "192.168.200.0/24"; then
        return 0
    fi

    # 方法2：检查所有规则中是否包含NAT规则
    if pfctl -s all 2>/dev/null | grep -q "192.168.200.0/24"; then
        return 0
    fi

    # 方法3：检查anchor规则文件是否被加载
    if [[ -f "/etc/pf.anchors/thunderbolt_bridge" ]] && pfctl -s Anchors 2>/dev/null | grep -q "thunderbolt_bridge"; then
        return 0
    fi

    # 方法4：检查规则文件内容和pfctl状态
    if [[ -f "/etc/pf.anchors/thunderbolt_bridge" ]] && pfctl -e >/dev/null 2>&1; then
        # 如果文件存在且pfctl启用，认为规则有效
        return 0
    fi

    return 1
}

# 检查IP转发状态
check_ip_forwarding() {
    local forwarding=$(sysctl -n net.inet.ip.forwarding 2>/dev/null)
    if [[ "$forwarding" == "1" ]]; then
        return 0
    fi
    return 1
}

# 检查网络连通性
check_connectivity() {
    # 检查桥接网络本地连通性
    if ping -c 1 -t "$PING_TIMEOUT" 192.168.200.1 >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# 检查互联网连接状态（优先检查有线，其次WiFi）
check_internet_status() {
    # 先检测所有类型的有线网卡接口
    # 支持：Ethernet、以太网、USB LAN、Thunderbolt Ethernet等
    local has_active_ethernet=false
    networksetup -listallhardwareports | while IFS= read -r line; do
        if [[ "$line" =~ ^Hardware\ Port:\ (.+)$ ]]; then
            local port_name="${BASH_REMATCH[1]}"
            # 排除无线和虚拟接口
            if [[ ! "$port_name" =~ (Wi-Fi|Bluetooth|雷雳网桥|Thunderbolt Bridge|Thunderbolt [0-9]) ]]; then
                # 读取下一行获取设备名
                read -r device_line
                if [[ "$device_line" =~ Device:\ (.+)$ ]]; then
                    local device="${BASH_REMATCH[1]}"
                    # 检查接口是否活跃
                    if ifconfig "$device" 2>/dev/null | grep -q "status: active"; then
                        echo "found"
                        break
                    fi
                fi
            fi
        fi
    done | grep -q "found" && return 0

    # 如果没有活跃的有线网卡，检查WiFi
    local wifi_interface=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
    if [[ -n "$wifi_interface" ]]; then
        local wifi_status=$(ifconfig "$wifi_interface" 2>/dev/null | grep "status:" | awk '{print $2}')
        if [[ "$wifi_status" == "active" ]]; then
            return 0
        fi
    fi
    return 1
}

# 综合健康检查
perform_health_check() {
    local issues=0
    local status_report=""

    print_status "INFO" "开始网络健康检查..."

    # 1. 检查雷雳连接
    if check_thunderbolt_connection; then
        print_status "OK" "雷雳连接正常"
        status_report+="[✅] 雷雳连接\n"
    else
        print_status "ERROR" "雷雳连接异常"
        status_report+="[❌] 雷雳连接\n"
        ((issues++))
    fi

    # 2. 检查桥接接口
    if check_bridge_interface; then
        print_status "OK" "桥接接口正常"
        status_report+="[✅] 桥接接口\n"
    else
        print_status "ERROR" "桥接接口异常"
        status_report+="[❌] 桥接接口\n"
        ((issues++))
    fi

    # 3. 检查IP转发
    if check_ip_forwarding; then
        print_status "OK" "IP转发正常"
        status_report+="[✅] IP转发\n"
    else
        print_status "ERROR" "IP转发异常"
        status_report+="[❌] IP转发\n"
        ((issues++))
    fi

    # 4. 检查NAT规则
    if check_nat_rules; then
        print_status "OK" "NAT规则正常"
        status_report+="[✅] NAT规则\n"
    else
        print_status "ERROR" "NAT规则异常"
        status_report+="[❌] NAT规则\n"
        ((issues++))
    fi

    # 5. 检查互联网连接（有线优先）
    if check_internet_status; then
        print_status "OK" "互联网连接正常"
        status_report+="[✅] 互联网连接\n"
    else
        print_status "WARN" "互联网连接异常"
        status_report+="[⚠️] 互联网连接\n"
    fi

    # 6. 检查网络连通性
    if check_connectivity; then
        print_status "OK" "网络连通性正常"
        status_report+="[✅] 网络连通性\n"
    else
        print_status "ERROR" "网络连通性异常"
        status_report+="[❌] 网络连通性\n"
        ((issues++))
    fi

    log_info "健康检查完成，发现 $issues 个问题"
    echo -e "\n📊 状态报告:\n$status_report"

    return $issues
}

# 修复网络配置
repair_network() {
    local current_time=$(date +%s)

    # 检查冷却时间
    if [[ $((current_time - LAST_REPAIR_TIME)) -lt $REPAIR_COOLDOWN ]]; then
        log_warn "修复冷却时间未到，跳过修复"
        return 1
    fi

    # 检查修复次数限制
    if [[ $REPAIR_COUNT -ge $MAX_REPAIR_ATTEMPTS ]]; then
        log_error "达到最大修复次数限制 ($MAX_REPAIR_ATTEMPTS)，停止自动修复"
        return 1
    fi

    log_info "开始网络修复，第 $((REPAIR_COUNT + 1)) 次尝试"
    print_status "INFO" "正在修复网络配置..."

    # 运行自动修复脚本
    if [[ -x "/usr/local/bin/thunderbolt/bridge_repair.sh" ]]; then
        if /usr/local/bin/thunderbolt/bridge_repair.sh; then
            log_success "自动修复脚本执行成功"
            REPAIR_COUNT=0  # 重置修复计数
            LAST_REPAIR_TIME=$current_time
            save_state "REPAIRED"
            return 0
        else
            log_error "自动修复脚本执行失败"
        fi
    else
        log_error "自动修复脚本不存在或无执行权限"
    fi

    ((REPAIR_COUNT++))
    LAST_REPAIR_TIME=$current_time
    save_state "REPAIR_FAILED"
    return 1
}

# 显示监控状态
show_status() {
    clear
    echo "=================================================="
    echo "        雷雳桥接网络实时监控"
    echo "=================================================="
    echo "监控PID: $MONITOR_PID"
    echo "开始时间: $(date)"
    echo "检查间隔: ${CHECK_INTERVAL}秒"
    echo "修复计数: $REPAIR_COUNT/$MAX_REPAIR_ATTEMPTS"
    echo "=================================================="
    echo ""

    perform_health_check

    echo ""
    echo "=================================================="
    echo "按 Ctrl+C 停止监控"
    echo "=================================================="
}

# 监控主循环
monitor_loop() {
    log_info "启动雷雳桥接网络监控 (PID: $MONITOR_PID)"
    save_state "MONITORING"

    while true; do
        show_status

        # 进行健康检查
        if ! perform_health_check > /dev/null 2>&1; then
            log_warn "检测到网络问题，尝试自动修复"
            if repair_network; then
                log_success "网络修复成功"
                print_status "OK" "网络已修复"
            else
                log_error "网络修复失败"
                print_status "ERROR" "网络修复失败"
            fi
        else
            save_state "HEALTHY"
        fi

        # 等待下次检查
        sleep $CHECK_INTERVAL
    done
}

# 清理函数
cleanup() {
    log_info "停止雷雳桥接网络监控"
    save_state "STOPPED"
    rm -f "$STATE_FILE"
    exit 0
}

# 信号处理
trap cleanup SIGINT SIGTERM

# 显示帮助信息
show_help() {
    echo "雷雳桥接网络监控脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help         显示帮助信息"
    echo "  -c, --check        执行一次健康检查"
    echo "  -r, --repair       执行一次修复"
    echo "  -m, --monitor      启动实时监控（默认）"
    echo "  -s, --status       显示当前状态"
    echo "  -i, --interval N   设置检查间隔（秒，默认30）"
    echo ""
    echo "示例:"
    echo "  sudo $0 --check          # 执行一次健康检查"
    echo "  sudo $0 --repair         # 执行一次修复"
    echo "  sudo $0 --monitor        # 启动实时监控"
    echo "  sudo $0 -i 60 --monitor  # 60秒间隔监控"
}

# 主函数
main() {
    local action="monitor"

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--check)
                action="check"
                shift
                ;;
            -r|--repair)
                action="repair"
                shift
                ;;
            -m|--monitor)
                action="monitor"
                shift
                ;;
            -s|--status)
                action="status"
                shift
                ;;
            -i|--interval)
                CHECK_INTERVAL="$2"
                shift 2
                ;;
            *)
                echo "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    check_permissions
    load_state

    case "$action" in
        check)
            perform_health_check
            ;;
        repair)
            repair_network
            ;;
        status)
            show_status
            ;;
        monitor)
            monitor_loop
            ;;
    esac
}

# 仅在脚本直接执行时运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi