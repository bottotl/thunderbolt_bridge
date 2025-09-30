# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个完整的雷雳桥接网络配置工具包，解决了macOS上雷雳桥接网络配置不稳定、需要频繁重新执行脚本的问题。项目提供了从临时配置到持久化部署的完整解决方案。

## 核心脚本 (按推荐优先级排序)

### 🚀 推荐使用 - 持久化方案

#### persistent_bridge_setup.sh (主机端持久化配置)
**解决频繁重复执行问题的核心脚本**
- **功能**: 持久化网络配置、自动修复脚本、系统集成
- **特点**: 重启后配置自动保持，大幅减少手动干预
- **配置**: 192.168.200.1/24 (网关)，NAT规则持久化到/etc/pf.anchors/

#### install_daemon.sh (系统监控服务安装)
**自动化监控和修复服务**
- **功能**: 安装LaunchDaemon系统服务，提供自动监控和修复
- **特点**: 系统启动自动配置，网络异常自动修复，定期健康检查
- **依赖**: 需要先运行persistent_bridge_setup.sh

#### bridge_monitor.sh (实时网络监控)
**高级监控和诊断工具**
- **功能**: 实时监控、问题诊断、手动修复、状态报告
- **特点**: 彩色状态显示，智能故障检测，详细健康检查
- **使用**: 可独立运行或配合系统服务使用

### 📜 传统脚本 - 临时配置

#### bridge_network_setup.sh (主机端临时配置)
**原始配置脚本，现已优化为引导用户使用持久化方案**
- **功能**: 临时桥接网络设置，重启后失效
- **特点**: 现在会提示用户使用持久化配置
- **限制**: 重启后需要重新执行，已不推荐作为主要方案

#### client_network_setup.sh (客户端配置)
配置客户端雷雳桥接网络连接：
- **功能**: 自动检测雷雳网桥服务、配置IP和DNS
- **IP配置**: 192.168.200.2/24 (客户端)
- **网关**: 192.168.200.1
- **改进**: 现在会建议主机端使用持久化配置

## 推荐使用流程

```bash
# 第一步：主机端持久化配置（推荐）
chmod +x persistent_bridge_setup.sh
sudo ./persistent_bridge_setup.sh

# 第二步：安装系统监控服务（强烈推荐）
chmod +x install_daemon.sh
sudo ./install_daemon.sh

# 第三步：客户端配置
chmod +x client_network_setup.sh
sudo ./client_network_setup.sh

# 可选：实时监控
chmod +x bridge_monitor.sh
sudo ./bridge_monitor.sh --monitor
```

## 传统流程（不推荐，仅用于快速临时配置）

```bash
# 在主机端执行 (提供网络共享的Mac)
chmod +x bridge_network_setup.sh
sudo ./bridge_network_setup.sh

# 在客户端执行 (连接网络的Mac)
chmod +x client_network_setup.sh
sudo ./client_network_setup.sh
```

## 网络架构

- **物理连接**: 雷雳线缆连接两台Mac
- **逻辑网络**: 192.168.200.0/24网段
- **主机配置**: bridge0接口作为网关，WiFi接口提供internet连接
- **NAT转发**: 通过pfctl实现192.168.200.0/24到WiFi接口的NAT转发
- **桥接成员**: en1/en2接口作为bridge0的成员接口

## 问题解决方案

### 核心问题
主机端需要频繁重新执行脚本的原因：
- **配置不持久化**: 系统重启后网络配置丢失
- **系统干扰**: macOS自动重置网络配置
- **接口状态问题**: 雷雳线缆断开重连导致配置失效
- **pfctl规则不稳定**: 防火墙规则被系统重置

### 解决方案
- **持久化配置**: persistent_bridge_setup.sh 将配置写入系统文件
- **自动监控**: install_daemon.sh 提供系统级服务监控
- **智能修复**: bridge_monitor.sh 提供实时检测和自动修复
- **状态保持**: 配置在重启、休眠唤醒后自动恢复

## 故障排除和监控

### 自动化故障排除
- **实时监控**: bridge_monitor.sh 提供24/7网络状态监控
- **自动修复**: 检测到问题时自动尝试修复
- **健康检查**: 定期验证所有网络组件状态
- **日志记录**: 详细的问题诊断和修复日志

### 手动故障排除
```bash
# 快速状态检查
sudo ./bridge_monitor.sh --check

# 手动修复
sudo ./bridge_monitor.sh --repair

# 查看服务状态
sudo launchctl list com.thunderbolt.bridge

# 查看日志
tail -f /var/log/thunderbolt_bridge.log
```

## 技术要点

- **权限要求**: 所有网络配置操作需要sudo权限
- **系统依赖**: macOS networksetup、ifconfig、pfctl工具
- **网络服务**: 自动检测"雷雳网桥"或"Thunderbolt Bridge"服务
- **配置持久化**: 使用networksetup和系统配置文件确保重启后保持
- **服务集成**: LaunchDaemon系统服务提供自动化管理
- **监控机制**: 多层次状态检查和自动修复机制

## 版本演进

- **v1.0**: 基础临时配置脚本 (bridge_network_setup.sh, client_network_setup.sh)
- **v2.0**: 持久化配置方案 (persistent_bridge_setup.sh)
- **v2.1**: 系统服务集成 (install_daemon.sh, com.thunderbolt.bridge.plist)
- **v2.2**: 高级监控工具 (bridge_monitor.sh)
- **v2.3**: 用户体验优化，引导升级到持久化方案