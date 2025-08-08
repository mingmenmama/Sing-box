# 🚀 SuperNova Sing-box

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Last Updated](https://img.shields.io/badge/last%20updated-2025--08--08-brightgreen)

> 一键部署多协议 Sing-box 服务，支持 AnyTLS/Reality 深度伪装

## 📑 目录

- [项目简介](#-项目简介)
- [特性功能](#-特性功能)
- [快速开始](#-快速开始)
- [支持的协议](#-支持的协议)
- [分流功能](#-分流功能)
- [高级配置](#-高级配置)
- [常见问题](#-常见问题)
- [贡献指南](#-贡献指南)
- [许可协议](#-许可协议)

## 🌟 项目简介

SuperNova Sing-box 是一个一键式部署脚本，用于快速搭建基于 [sing-box](https://github.com/SagerNet/sing-box) 的代理服务。本项目整合了多种代理协议，支持 AnyTLS/Reality 深度伪装技术，提供智能分流、多用户管理、自动证书申请等高级功能，让您的网络连接更安全、更高效。

## ✨ 特性功能

- **多协议支持**：支持 Vmess、Vless、Trojan、Hysteria2 等多种协议
- **AnyTLS/Reality 深度伪装**：无需域名和证书，使用与真实网站的 TLS 握手进行伪装
- **智能分流系统**：自动适配最新版本的分流方式（geosite/geoip 或 .srs）
- **自动证书管理**：支持 Let's Encrypt 自动申请和续期
- **多用户管理**：支持多用户配置和权限管理
- **性能监控**：内建流量统计和系统资源监控
- **一键安装/更新**：全自动安装和更新流程
- **备份与恢复**：支持配置备份和恢复功能
- **智能优化**：自动优化系统网络参数
- **TUI 界面**：用户友好的交互式配置界面

## 🚀 快速开始

### 系统要求

- Debian 9+ / Ubuntu 18.04+ / CentOS 7+
- 架构支持：x86_64 / ARM64 / ARMv7
- 至少 512MB 内存
- 至少 10GB 可用磁盘空间

### 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mingmenmama/Sing-box/main/install.sh)
```

或者下载后安装：

```bash
git clone https://github.com/mingmenmama/Sing-box.git
cd Sing-box
chmod +x supernova.sh
./supernova.sh --install
```

### 命令行参数

```
用法: ./supernova.sh [选项]

选项:
  -h, --help           显示帮助信息
  -i, --install        安装 Sing-box
  -u, --update         更新 Sing-box
  -v, --version VER    指定安装版本
  --reset              重置配置
  --logs               查看日志
  --status             查看状态
  --start              启动服务
  --stop               停止服务
  --restart            重启服务
  --config             编辑配置
  --wizard             配置向导
  --bench              性能测试
```

## 📦 支持的协议

- **Vmess**：基本的代理协议，支持 TLS 加密
- **Vless**：类似于 Vmess 但有更低的开销
- **Trojan**：强调安全性的代理协议
- **Hysteria2**：基于 QUIC 的高速协议
- **Shadowsocks**：经典加密代理协议
- **SOCKS5**：标准 SOCKS5 代理
- **Mixed**：多协议统一入口

## 🔄 分流功能

本项目提供多种分流模式：

1. **基础分流**：简单的国内外分流
2. **增强分流**：包含广告拦截、隐私保护
3. **全局代理**：除私有地址外全部走代理
4. **全局直连**：仅特定网站走代理
5. **自定义规则**：支持高级自定义分流配置

根据 Sing-box 版本自动选择最合适的分流方式：
- 1.12.0 及以上版本：使用 .srs 规则集（更高效）
- 1.10.x 及以下版本：使用 geosite/geoip 数据库

## ⚙️ 高级配置

### 性能优化

```bash
# 系统网络参数优化
./supernova.sh --wizard
# 选择 "性能优化" -> "优化系统网络参数"
```

### 多用户管理

```bash
./supernova.sh --wizard
# 选择 "用户凭证管理" -> "添加新用户"
```

### 证书管理

```bash
./supernova.sh --wizard
# 选择 "证书管理" -> "申请新证书"
```

## ❓ 常见问题

### 1. 如何更改分流方式？

通过配置向导可以更改分流方式：
```bash
./supernova.sh --wizard
# 选择 "智能分流设置"
```

### 2. 如何修复服务无法启动？

检查日志找出问题原因：
```bash
./supernova.sh --logs
```

常见解决方法：
- 端口冲突：修改配置中的端口
- 配置错误：检查 JSON 格式是否有误
- 权限问题：确保脚本以 root 权限运行

### 3. 如何在最新版本中启用分流功能？

脚本会自动识别 Sing-box 版本并配置适当的分流方式。如果您需要手动配置：

```bash
./supernova.sh --wizard
# 选择 "智能分流设置" -> 选择您想要的分流模式
```

## 🤝 贡献指南

欢迎提交 Pull Requests 或 Issues 来帮助改进此项目！

1. Fork 本仓库
2. 创建您的特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交您的更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启一个 Pull Request

## 📜 许可协议

本项目采用 MIT 许可协议 - 详见 [LICENSE](LICENSE) 文件。

---

**免责声明**：本项目仅供学习和研究网络技术使用，用户需自行遵守当地法律法规。
```

## 感谢使用

如有任何问题或建议，欢迎提 Issue 或通过以下方式联系：

- GitHub Issues: [提交问题](https://github.com/mingmenmama/Sing-box/issues)
- Discussions: [讨论区](https://github.com/mingmenmama/Sing-box/discussions)
