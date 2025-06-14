# Sing-box 一键多协议共存脚本 (AnyTLS/Reality 集成版)

本项目是基于 [yonggekkk/sing-box-yg](https://github.com/yonggekkk/sing-box-yg) 修改而来，根据 Sing-box 官方文档，集成了 **AnyTLS (Reality)** 作为一种高度伪装的独立协议选项，并优化了其他协议的提示信息。

本脚本旨在帮助用户快速部署 Sing-box 服务端，支持 Vmess、Vless、Trojan、**AnyTLS (Reality)** 和 Hysteria2 等多种协议。

---

## 目录

-   [特性](#特性)
-   [支持的系统](#支持的系统)
-   [使用教程](#使用教程)
    -   [准备工作](#准备工作)
    -   [安装步骤](#安装步骤)
    -   [更新和卸载](#更新和卸载)
-   [AnyTLS (Reality) 协议说明](#anytls-reality-协议说明)
-   [其他协议的 TLS 伪装提示](#其他协议的-tls-伪装提示)
-   [注意事项](#注意事项)
-   [鸣谢](#鸣谢)

---

## 特性

* **一键部署**：简化 Sing-box 服务端部署流程。
* **多协议支持**：Vmess、Vless、Trojan、**AnyTLS (Reality)**、Hysteria2。
* **AnyTLS (Reality) 深度伪装**：利用 Sing-box 的 Reality 特性，提供更高级的流量伪装，**无需域名和证书**，隐蔽性极高。
* **传统 TLS 加密**：对于 Vmess/Vless/Trojan，支持使用 Let's Encrypt 证书自动生成和续期，实现标准 TLS 加密。
* **IPv4/IPv6 双栈支持**：适配不同网络环境。
* **版本选择**：用户可选择安装最新稳定版或其他特定版本的 Sing-box。

---

## 支持的系统

* Debian 9+
* Ubuntu 18.04+
* CentOS 7+

---

## 使用教程

### 准备工作

1.  **一台拥有公网 IP 的 VPS**：建议使用 KVM 架构。
2.  **（仅适用于 Vmess/Vless/Trojan TLS）一个已解析到 VPS IP 的域名**：你需要将你的域名 A 记录或 AAAA 记录指向你的 VPS IP 地址。**如果仅使用 AnyTLS (Reality)，则不需要域名。**
3.  **SSH 客户端**：如 PuTTY, Xshell, Termius 等。
4.  **开放端口**：确保你的 VPS 防火墙（包括云服务商的安全组）开放你将要使用的协议端口（例如：**AnyTLS (Reality) 默认使用 443 端口**，以及你为其他协议设置的端口）。

### 安装步骤

1.  **登录 VPS**

    ```bash
    ssh root@你的VPS_IP地址
    ```
    （请将 `你的VPS_IP地址` 替换为你的实际 VPS IP）

2.  **下载并运行脚本**

    ```bash
    curl -fsSL https://raw.githubusercontent.com/mingmenmama/Sing-box/main/sing-box.sh | bash
    ```

3.  **按照提示操作**

    脚本运行后，会引导你完成以下配置：

    * **选择部署协议**：选择你想要部署的协议，例如 `4` (**AnyTLS (Reality)**)。
        * **注意：AnyTLS (Reality) 协议需要 Sing-box 最新稳定版或支持 Reality 的特定版本。**
    * **输入域名**：如果你选择 Vmess/Vless/Trojan 并启用 TLS，需要输入域名。
    * **（AnyTLS (Reality) 特有）输入 Reality 伪装目标**：例如 `www.google.com:443`。
    * **选择端口**：为你的协议选择或输入监听端口。**AnyTLS (Reality) 默认使用 443 端口。**
    * **选择 Sing-box 版本**：**强烈推荐选择“最新稳定版”**，以确保 AnyTLS (Reality) 等新协议的兼容性。
    * **生成UUID/密码**：脚本会自动生成或让你输入。
    * **安装 SSL 证书**：对于 Vmess/Vless/Trojan TLS，脚本会自动申请和配置 Let's Encrypt 证书。**AnyTLS (Reality) 无需证书。**

    等待脚本执行完成。成功后，它将显示你的 Sing-box 客户端配置信息，包括链接、UUID、端口等。**对于 AnyTLS (Reality)，会额外显示生成的公钥、短 ID 和伪装目标等关键信息，请务必保存！**

### 更新和卸载

* **更新 Sing-box**：
    重新运行脚本，选择更新选项即可。
    ```bash
    ./sing-box.sh
    ```
* **卸载 Sing-box**：
    重新运行脚本，选择卸载选项即可。
    ```bash
    ./sing-box.sh
    ```

---

## AnyTLS (Reality) 协议说明

**AnyTLS (Reality)** 是 Sing-box 中一种非常先进且强大的流量伪装机制。它并非一个独立的数据传输协议，而是作为 **VLESS 协议的一种高度隐蔽的传输方式**。它通过模仿真实的 TLS 握手流量来混淆特征，使其看起来像是正常的 HTTPS 访问。

**工作原理简述**：
当客户端尝试连接到服务端时，Reality 会伪装成正在与一个真实的、全球热门网站（你设定的伪装目标，例如 `www.google.com`）进行 TLS 握手。通过匹配特定的 **公钥 (Public Key)** 和 **短 ID (Short ID)**，Sing-box 服务端能够准确识别出真实的客户端连接，然后将数据流交给内部的 VLESS 协议进行传输。

**主要优势**：
* **无需域名和证书**：不同于传统的 TLS 协议需要你购买域名和申请 SSL 证书，Reality 可以直接利用现有热门网站的 TLS 证书进行伪装。
* **高度伪装与隐蔽性**：流量伪装成访问真实网站的 HTTPS 流量，难以被防火墙识别和拦截，大大降低了被封锁的风险。
* **优异性能**：结合 VLESS 协议和 `xtls-rprx-vision` 流控，可以提供非常好的传输性能。

**重要提示：**
* **版本兼容性**：AnyTLS (Reality) 协议需要 **Sing-box 1.2 或更高版本** 的支持。因此，**强烈建议在安装脚本时选择“最新稳定版”的 Sing-box 客户端**。
* **客户端配置**：客户端也需要支持 Reality 协议，并配置与服务端完全匹配的 `Public Key`、`Short ID`、`伪装目标`、`流控 (Flow)` 以及 **uTLS 指纹 (Fingerprint)**。请务必核对所有参数。
* **伪装目标选择**：选择一个访问量大、服务稳定且不易被墙的真实网站作为伪装目标（例如：`www.google.com:443`、`www.microsoft.com:443`、`cdn.jsdelivr.net:443` 等）。
* **Reality 参数**：脚本会自动生成 `private_key` 和 `short_id`。请务必保存好这些信息，客户端配置需要用到 `public_key`（由私钥生成）和 `short_id`。

---

## 其他协议的 TLS 伪装提示

对于 Vmess、Vless 和 Trojan 协议，当它们启用 TLS 加密时，客户端可以通过配置 **uTLS 指纹 (uTLS Fingerprint)** 来进一步增强伪装效果。

* **uTLS 指纹**：Sing-box 可以模拟不同主流浏览器（如 Chrome、Firefox、Safari 等）的 TLS 握手指纹，这有助于混淆流量，使其更难以被识别。
* **客户端配置**：当你在客户端配置 Vmess、Vless 或 Trojan (TLS) 时，请务必在 TLS 设置中找到并启用 uTLS 指纹选项，并选择与服务端推荐（如果服务端有设置）或你希望伪装的浏览器类型（例如 `chrome`）。

---

## 注意事项

* **AnyTLS (Reality) 无需域名和证书，但仍需确保 443 端口已开放。**
* **端口开放**：确保你的 VPS 防火墙和云服务商的安全组已开放所需端口。对于 AnyTLS (Reality)，默认是 443 端口。
* **SELinux (CentOS)**：如果在 CentOS 上遇到问题，尝试禁用 SELinux：
    ```bash
    setenforce 0
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    ```
* **Sing-box 配置**：脚本生成的 Sing-box 配置文件位于 `/etc/sing-box/config.json`。你可以根据需要手动修改此文件。
* **日志文件**：Sing-box 的日志文件通常位于 `/var/log/sing-box/sing-box.log`。你可以通过查看日志文件来排查问题。
* **服务管理**：
    * 启动 Sing-box：`systemctl start sing-box`
    * 停止 Sing-box：`systemctl stop sing-box`
    * 重启 Sing-box：`systemctl restart sing-box`
    * 查看状态：`systemctl status sing-box`
    * 开机自启：`systemctl enable sing-box`

---

## 鸣谢

本项目基于 [yonggekkk/sing-box-yg](https://github.com/yonggekkk/sing-box-yg) 的优秀工作。

---
