#!/bin/bash

# ===============================================================================
# Sing-box 一键多协议共存脚本 (AnyTLS/Reality 集成版)
# 基于 yonggekkk/sing-box-yg 修改
# -------------------------------------------------------------------------------
# 本脚本旨在帮助用户快速部署 Sing-box 服务端，支持 Vmess、Vless、Trojan、
# AnyTLS (Reality) 和 Hysteria2 等多种协议。
# 增加 AnyTLS (Reality) 协议选项，并明确版本支持。
# 修复了 read 命令在管道执行时可能导致的无限循环问题。
# ===============================================================================

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本版本
SCRIPT_VERSION="1.1.0-AnyTLS-Reality-final"

# 默认设置
DEFAULT_WEB_PORT=80
DEFAULT_TLS_PORT=443
DEFAULT_VMESS_PORT=10001
DEFAULT_VLESS_PORT=10002
DEFAULT_TROJAN_PORT=10003
DEFAULT_HYSTERIA2_PORT=10004
REALITY_DEST="www.google.com:443" # AnyTLS (Reality) 默认伪装目标，这是必需的

# 函数：检查命令是否存在
command_exists() {
    command -v "$@" > /dev/null 2>&1
}

# 函数：安装依赖
install_dependencies() {
    echo -e "${GREEN}正在安装必要的依赖...${NC}"
    if command_exists apt; then
        apt update && apt install -y curl wget git qrencode uuid-runtime jq
    elif command_exists yum; then
        yum install -y curl wget git qrencode util-linux-ng jq
    else
        echo -e "${RED}不支持的操作系统，请手动安装 curl, wget, git, qrencode, jq 和 uuidgen。${NC}"
        exit 1
    fi
    echo -e "${GREEN}依赖安装完成。${NC}"
}

# 函数：生成 UUID
generate_uuid() {
    if command_exists uuidgen; then
        uuidgen
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# 函数：安装 Sing-box
install_singbox() {
    local version_to_install="$1"
    echo -e "${GREEN}正在下载并安装 Sing-box (版本: ${version_to_install})...${NC}"
    # 更新 Sing-box 官方安装脚本的 URL
    if [[ -z "$version_to_install" || "$version_to_install" == "latest" ]]; then
        bash <(curl -sL https://raw.githubusercontent.com/SagerNet/sing-box/main/install.sh)
    else
        bash <(curl -sL https://raw.githubusercontent.com/SagerNet/sing-box/main/install.sh) -v "$version_to_install"
    fi

    if [ $? -ne 0 ]; then
        echo -e "${RED}Sing-box 安装失败，请检查网络或版本号。${NC}"
        exit 1
    fi
    echo -e "${GREEN}Sing-box 安装完成。${NC}"

    # 检查 sing-box 命令是否存在，确保后续操作可以执行
    if ! command_exists sing-box; then
        echo -e "${RED}sing-box 命令未找到，请确认 Sing-box 是否成功安装并添加到 PATH。${NC}"
        exit 1
    fi
}

# 函数：配置 SSL 证书 (ACME 方式)
setup_ssl() {
    echo -e "${BLUE}开始配置 SSL 证书...${NC}"

    if ! command_exists certbot; then
        echo -e "${YELLOW}Certbot 未安装，正在安装 Certbot...${NC}"
        if command_exists apt; then
            apt install -y certbot || apt install -y python3-certbot-nginx
        elif command_exists yum; then
            yum install -y certbot || yum install -y python3-certbot-nginx
        fi
        if ! command_exists certbot; then
            echo -e "${RED}Certbot 安装失败，请手动安装或检查系统。${NC}"
            exit 1
        fi
    fi

    # 停止占用 80/443 端口的服务，例如 Nginx, Apache
    if command_exists nginx; then systemctl stop nginx; fi
    if command_exists apache2; then systemctl stop apache2; fi
    if command_exists httpd; then systemctl stop httpd; fi

    certbot certonly --standalone --agree-tos --email "$EMAIL" -d "$DOMAIN"

    if [ $? -ne 0 ]; then
        echo -e "${RED}SSL 证书申请失败，请检查域名解析和端口是否开放。${NC}"
        exit 1
    fi

    # 创建证书存放目录
    mkdir -p /etc/sing-box
    ln -sf "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "/etc/sing-box/fullchain.pem"
    ln -sf "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "/etc/sing-box/privkey.pem"

    echo -e "${GREEN}SSL 证书配置完成。${NC}"
}

# 函数：生成随机密码
generate_password() {
    head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 16
}

# 函数：主菜单
main_menu() {
    clear
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${BLUE}  Sing-box 一键多协议共存脚本 v${SCRIPT_VERSION} ${NC}"
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${GREEN}1. 安装 Sing-box 服务端${NC}"
    echo -e "${GREEN}2. 卸载 Sing-box 服务端${NC}"
    echo -e "${GREEN}3. 更新 Sing-box 服务端 (保留配置)${NC}"
    echo -e "${GREEN}4. 查看当前配置信息${NC}"
    echo -e "${RED}0. 退出${NC}"
    echo -e "${BLUE}----------------------------------------------------${NC}"
    echo "" # 添加一个空行，让输入更清晰
    # 强制 read 命令从 /dev/tty (终端) 读取输入，即使脚本通过管道运行
    read -r -p "请选择操作 (0-4): " action_choice </dev/tty

    case ${action_choice} in
        1) install_server;;
        2) uninstall_server;;
        3) update_server;;
        4) show_config;;
        0) echo -e "${YELLOW}退出脚本。${NC}"; exit 0;;
        *)
            echo -e "${RED}无效的选择 '${action_choice}'，请输入 0 到 4 之间的数字。${NC}"
            sleep 1
            main_menu
            ;;
    esac
}

# 函数：安装服务端
install_server() {
    install_dependencies

    echo -e "${BLUE}--------------------------------------------------------${NC}"
    echo -e "请选择要部署的协议："
    echo -e "1. Vmess (TLS)"
    echo -e "2. Vless (TLS)"
    echo -e "3. Trojan (TLS)"
    echo -e "4. AnyTLS (Reality - 推荐，无需域名和证书)"
    echo -e "5. Hysteria2"
    echo -e "${BLUE}--------------------------------------------------------${NC}"
    echo "" # 添加一个空行
    read -r -p "请输入数字选择协议（1-5）：" protocol_choice </dev/tty

    case ${protocol_choice} in
        1) PROTOCOL_NAME="vmess";;
        2) PROTOCOL_NAME="vless";;
        3) PROTOCOL_NAME="trojan";;
        4) PROTOCOL_NAME="anytls_reality_vless";; # 内部使用 AnyTLS (Reality) 组合 VLESS
        5) PROTOCOL_NAME="hysteria2";;
        *) echo -e "${RED}无效的选择，请重新运行脚本。${NC}"; exit 1;;
    esac

    UUID=$(generate_uuid)
    PASSWORD=$(generate_password)

    if [[ "${PROTOCOL_NAME}" != "anytls_reality_vless" && "${PROTOCOL_NAME}" != "hysteria2" ]]; then
        echo "" # 添加一个空行
        read -r -p "请输入你的域名 (例如: example.com): " DOMAIN </dev/tty
        if [[ -z "$DOMAIN" ]]; then
            echo -e "${RED}域名不能为空，请重新运行脚本。${NC}"
            exit 1
        fi
        echo "" # 添加一个空行
        read -r -p "请输入你的邮箱地址 (用于 Let's Encrypt 证书，例如: your@email.com): " EMAIL </dev/tty
        if [[ -z "$EMAIL" ]]; then
            echo -e "${RED}邮箱地址不能为空，请重新运行脚本。${NC}"
            exit 1
        fi
        setup_ssl # 为需要 TLS 的协议设置 SSL
    fi

    if [[ "${PROTOCOL_NAME}" == "anytls_reality_vless" ]]; then
        echo "" # 添加一个空行
        read -r -p "请输入 Reality 伪装目标地址 (例如: www.google.com:443，默认: ${REALITY_DEST}): " input_dest </dev/tty
        if [[ -n "${input_dest}" ]]; then
            REALITY_DEST="${input_dest}"
        fi
        # AnyTLS (Reality) 默认使用 443 端口
        PORT=443

        # 生成 Reality 密钥对
        REALITY_KEY_PAIR=$(sing-box generate reality-key)
        REALITY_PRIVATE_KEY=$(echo "${REALITY_KEY_PAIR}" | grep 'private_key' | awk -F': ' '{print $2}' | tr -d '"')
        REALITY_PUBLIC_KEY=$(echo "${REALITY_KEY_PAIR}" | grep 'public_key' | awk -F': ' '{print $2}' | tr -d '"')
        REALITY_SHORT_ID=$(head /dev/urandom | tr -dc A-F0-9 | head -c 8) # 自动生成短 ID，这里与 README 保持一致

        echo -e "${GREEN}生成的 Reality 短 ID: ${YELLOW}${REALITY_SHORT_ID}${NC}"
        echo -e "${GREEN}生成的 Reality 私钥: ${YELLOW}${REALITY_PRIVATE_KEY}${NC}"
        echo -e "${GREEN}生成的 Reality 公钥: ${YELLOW}${REALITY_PUBLIC_KEY}${NC}"
        echo -e "${YELLOW}请务必记录以上信息，客户端配置需要用到 Reality 公钥和短 ID！${NC}"

    elif [[ "${PROTOCOL_NAME}" == "hysteria2" ]]; then
        echo "" # 添加一个空行
        read -r -p "请输入 Hysteria2 监听端口 (默认: ${DEFAULT_HYSTERIA2_PORT}): " input_port </dev/tty
        PORT=${input_port:-${DEFAULT_HYSTERIA2_PORT}}
        echo -e "${YELLOW}Hysteria2 协议需要你手动生成或提供 SSL 证书。请确保 /etc/sing-box/fullchain.pem 和 /etc/sing-box/privkey.pem 存在。${NC}"
        echo -e "${YELLOW}如果没有，请手动准备证书文件。${NC}"
        # 对于 Hysteria2，这里不自动申请证书，需要用户手动放置或自行处理
    else
        # 其他 TLS 协议的端口选择
        echo "" # 添加一个空行
        read -r -p "请输入 TLS 监听端口 (默认: ${DEFAULT_TLS_PORT}): " input_port </dev/tty
        PORT=${input_port:-${DEFAULT_TLS_PORT}}
    fi

    echo -e "${BLUE}--------------------------------------------------------${NC}"
    echo -e "请选择 Sing-box 客户端版本："
    echo -e "1. 最新稳定版 (强烈推荐，${GREEN}支持 AnyTLS/Reality${NC} 等新协议)"
    echo -e "2. 特定版本 (如果你需要旧版本，可能不支持 AnyTLS/Reality)"
    echo -e "${BLUE}--------------------------------------------------------${NC}"
    echo "" # 添加一个空行
    read -r -p "请输入数字选择版本（1-2）：" version_choice </dev/tty

    SINGBOX_VERSION="latest"
    if [[ "${version_choice}" == "2" ]]; then
        echo "" # 添加一个空行
        read -r -p "请输入要安装的 Sing-box 版本号 (例如: 1.8.0): " custom_version </dev/tty
        if [[ -n "$custom_version" ]]; then
            SINGBOX_VERSION="$custom_version"
        else
            echo -e "${RED}未输入特定版本号，将安装最新稳定版。${NC}"
        fi
    fi

    install_singbox "$SINGBOX_VERSION"

    echo -e "${GREEN}正在生成 Sing-box 配置文件...${NC}"
    mkdir -p /etc/sing-box
    mkdir -p /var/log/sing-box # 确保日志目录存在

    if [[ "${PROTOCOL_NAME}" == "anytls_reality_vless" ]]; then
        cat > /etc/sing-box/config.json << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "output": "/var/log/sing-box/sing-box.log",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "reality",
      "tag": "anytls-reality-vless-in",
      "listen": "0.0.0.0",
      "listen_port": ${PORT},
      "sniff": true,
      "sniff_override_destination": true,
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_DEST%:*}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${REALITY_DEST%:*}",
            "server_port": ${REALITY_DEST##*:},
            "sni": "${REALITY_DEST%:*}",
            "fingerprint": "chrome"
          },
          "private_key": "${REALITY_PRIVATE_KEY}",
          "short_id": [
            "${REALITY_SHORT_ID}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF
        echo -e "${GREEN}Sing-box 配置已生成，服务已启动。${NC}"
        systemctl enable sing-box
        systemctl restart sing-box

        echo -e "${BLUE}--------------------------------------------------------${NC}"
        echo -e "${GREEN}AnyTLS (Reality + VLESS) 客户端配置信息：${NC}"
        echo -e "服务器地址: ${YELLOW}你的VPS_IP${NC}"
        echo -e "端口: ${YELLOW}${PORT}${NC}"
        echo -e "UUID: ${YELLOW}${UUID}${NC}"
        echo -e "传输协议: ${YELLOW}Reality + VLESS${NC}"
        echo -e "伪装目标 (Server Name): ${YELLOW}${REALITY_DEST%:*} ${NC}"
        echo -e "伪装目标端口 (Server Port): ${YELLOW}${REALITY_DEST##*:}${NC}"
        echo -e "公钥 (Public Key): ${YELLOW}${REALITY_PUBLIC_KEY}${NC}"
        echo -e "短 ID (Short ID): ${YELLOW}${REALITY_SHORT_ID}${NC}"
        echo -e "流控 (Flow): ${YELLOW}xtls-rprx-vision${NC}"
        echo -e "指纹 (uTLS Fingerprint): ${YELLOW}chrome${NC}"
        echo -e "${BLUE}--------------------------------------------------------${NC}"

    elif [[ "${PROTOCOL_NAME}" == "vmess" ]]; then
        cat > /etc/sing-box/config.json << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "output": "/var/log/sing-box/sing-box.log",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "0.0.0.0",
      "listen_port": ${PORT},
      "sniff": true,
      "sniff_override_destination": true,
      "users": [
        {
          "uuid": "${UUID}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "certificate_path": "/etc/sing-box/fullchain.pem",
        "key_path": "/etc/sing-box/privkey.pem",
        "strict_sni": true
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF
        echo -e "${GREEN}Sing-box 配置已生成，服务已启动。${NC}"
        systemctl enable sing-box
        systemctl restart sing-box

        echo -e "${BLUE}--------------------------------------------------------${NC}"
        echo -e "${GREEN}VMess (TLS) 客户端配置信息：${NC}"
        echo -e "服务器地址: ${YELLOW}${DOMAIN}${NC}"
        echo -e "端口: ${YELLOW}${PORT}${NC}"
        echo -e "UUID: ${YELLOW}${UUID}${NC}"
        echo -e "传输协议: ${YELLOW}TLS${NC}"
        echo -e "额外提示: ${YELLOW}客户端启用 uTLS 指纹伪装（例如：chrome）可以增强隐蔽性。${NC}"
        echo -e "${BLUE}--------------------------------------------------------${NC}"

    elif [[ "${PROTOCOL_NAME}" == "vless" ]]; then
        cat > /etc/sing-box/config.json << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "output": "/var/log/sing-box/sing-box.log",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "0.0.0.0",
      "listen_port": ${PORT},
      "sniff": true,
      "sniff_override_destination": true,
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "certificate_path": "/etc/sing-box/fullchain.pem",
        "key_path": "/etc/sing-box/privkey.pem",
        "strict_sni": true
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF
        echo -e "${GREEN}Sing-box 配置已生成，服务已启动。${NC}"
        systemctl enable sing-box
        systemctl restart sing-box

        echo -e "${BLUE}--------------------------------------------------------${NC}"
        echo -e "${GREEN}VLESS (TLS) 客户端配置信息：${NC}"
        echo -e "服务器地址: ${YELLOW}${DOMAIN}${NC}"
        echo -e "端口: ${YELLOW}${PORT}${NC}"
        echo -e "UUID: ${YELLOW}${UUID}${NC}"
        echo -e "传输协议: ${YELLOW}TLS${NC}"
        echo -e "流控: ${YELLOW}xtls-rprx-vision${NC}"
        echo -e "额外提示: ${YELLOW}客户端启用 uTLS 指纹伪装（例如：chrome）可以增强隐蔽性。${NC}"
        echo -e "${BLUE}--------------------------------------------------------${NC}"

    elif [[ "${PROTOCOL_NAME}" == "trojan" ]]; then
        cat > /etc/sing-box/config.json << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "output": "/var/log/sing-box/sing-box.log",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "0.0.0.0",
      "listen_port": ${PORT},
      "sniff": true,
      "sniff_override_destination": true,
      "users": [
        {
          "password": "${PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "certificate_path": "/etc/sing-box/fullchain.pem",
        "key_path": "/etc/sing-box/privkey.pem",
        "strict_sni": true
      }
    }
  ]
}
EOF
        echo -e "${GREEN}Sing-box 配置已生成，服务已启动。${NC}"
        systemctl enable sing-box
        systemctl restart sing-box

        echo -e "${BLUE}--------------------------------------------------------${NC}"
        echo -e "${GREEN}Trojan (TLS) 客户端配置信息：${NC}"
        echo -e "服务器地址: ${YELLOW}${DOMAIN}${NC}"
        echo -e "端口: ${YELLOW}${PORT}${NC}"
        echo -e "密码: ${YELLOW}${PASSWORD}${NC}"
        echo -e "传输协议: ${YELLOW}TLS${NC}"
        echo -e "额外提示: ${YELLOW}客户端启用 uTLS 指纹伪装（例如：chrome）可以增强隐蔽性。${NC}"
        echo -e "${BLUE}--------------------------------------------------------${NC}"

    elif [[ "${PROTOCOL_NAME}" == "hysteria2" ]]; then
        cat > /etc/sing-box/config.json << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "output": "/var/log/sing-box/sing-box.log",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hysteria2-in",
      "listen": "0.0.0.0",
      "listen_port": ${PORT},
      "users": [
        {
          "password": "${PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/fullchain.pem",
        "key_path": "/etc/sing-box/privkey.pem"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF
        echo -e "${GREEN}Sing-box 配置已生成，服务已启动。${NC}"
        systemctl enable sing-box
        systemctl restart sing-box

        echo -e "${BLUE}--------------------------------------------------------${NC}"
        echo -e "${GREEN}Hysteria2 客户端配置信息：${NC}"
        echo -e "服务器地址: ${YELLOW}你的VPS_IP${NC}" # Hysteria2 可以直接用 IP
        echo -e "端口: ${YELLOW}${PORT}${NC}"
        echo -e "密码: ${YELLOW}${PASSWORD}${NC}"
        echo -e "传输协议: ${YELLOW}TLS (Hysteria2)${NC}"
        echo -e "${BLUE}--------------------------------------------------------${NC}"
    fi

    echo -e "${GREEN}Sing-box 服务端安装完成！${NC}"
    echo -e "${YELLOW}请确保你的 VPS 防火墙和云服务商安全组已开放相关端口。${NC}"
    read -p "按任意键返回主菜单..." </dev/tty
    main_menu
}

# 函数：卸载服务端
uninstall_server() {
    echo -e "${YELLOW}正在停止并卸载 Sing-box 服务...${NC}"
    systemctl stop sing-box
    systemctl disable sing-box
    rm -f /etc/systemd/system/sing-box.service
    rm -rf /etc/sing-box
    rm -f /usr/local/bin/sing-box
    rm -rf /var/log/sing-box
    systemctl daemon-reload
    systemctl reset-failed

    echo -e "${GREEN}Sing-box 已完全卸载。${NC}"
    read -p "按任意键返回主菜单..." </dev/tty
    main_menu
}

# 函数：更新服务端
update_server() {
    echo -e "${YELLOW}正在更新 Sing-box 服务...${NC}"
    install_singbox "latest" # 更新到最新版本
    systemctl restart sing-box
    echo -e "${GREEN}Sing-box 服务已更新并重启。${NC}"
    read -p "按任意键返回主菜单..." </dev/tty
    main_menu
}

# 函数：显示当前配置
show_config() {
    echo -e "${BLUE}--------------------------------------------------------${NC}"
    echo -e "${GREEN}Sing-box 服务当前状态：${NC}"
    systemctl status sing-box --no-pager || echo -e "${YELLOW}Sing-box 服务未运行或未安装。${NC}"
    echo -e "${BLUE}--------------------------------------------------------${NC}"

    if [ -f "/etc/sing-box/config.json" ]; then
        echo -e "${GREEN}当前 Sing-box 配置：${NC}"
        # 尝试使用 jq 美化输出，如果 jq 不存在，则直接 cat
        jq . /etc/sing-box/config.json 2>/dev/null || cat /etc/sing-box/config.json
        echo -e "${BLUE}--------------------------------------------------------${NC}"
        echo -e "${YELLOW}请注意：这里只显示服务端配置，客户端配置信息请参考安装时的输出。${NC}"
    else
        echo -e "${YELLOW}未找到 Sing-box 配置文件 /etc/sing-box/config.json。${NC}"
    fi
    echo -e "${BLUE}--------------------------------------------------------${NC}"
    read -p "按任意键返回主菜单..." </dev/tty
    main_menu
}

# 脚本入口
main_menu
