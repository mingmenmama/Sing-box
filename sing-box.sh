#!/bin/bash

#====================================================
#	System Request:Linux
#	Author:	yonggekkk
#	Dscription:sing-box-yg
#	Version: 1.0.0
#	email:yonggekkk@gmail.com
#	Official document: https://sing-box.sagernet.org/
#====================================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# Add the following functions for version comparison
version_lt() { test "$(echo "$1 $2" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }
version_le() { test "$(echo "$1 $2" | tr " " "\n" | sort -rV | head -n 1)" == "$2"; }
version_gt() { test "$(echo "$1 $2" | tr " " "\n" | sort -rV | head -n 1)" == "$1"; }
version_ge() { test "$(echo "$1 $2" | tr " " "\n" | sort -rV | head -n 1)" != "$2"; }


function check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${red}错误：${plain} 本脚本必须以 root 用户身份运行！\n"
        exit 1
    fi
}

function check_operating_system() {
    # Check if the operating system is Ubuntu or Debian, and if it's 64-bit
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
            if [[ $(uname -m) != "x86_64" ]]; then
                echo -e "${red}错误：${plain} 本脚本只支持 64 位的 Ubuntu 或 Debian 系统！\n"
                exit 1
            fi
        else
            echo -e "${red}错误：${plain} 本脚本只支持 Ubuntu 或 Debian 系统！\n"
            exit 1
        fi
    else
        echo -e "${red}错误：${plain} 无法检测操作系统！\n"
        exit 1
    fi
}

function get_latest_singbox_version() {
    local version_list=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=100")
    
    # 提取最新的非预发布版本
    latest_stable_version=$(echo "$version_list" | grep '"tag_name":' | grep -v 'beta' | grep -v 'rc' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
    latest_stable_version_without_v=$(echo "$latest_stable_version" | sed 's/^v//')

    # 提取最新的预发布版本
    latest_pre_release_version=$(echo "$version_list" | grep '"tag_name":' | grep -E 'beta|rc' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
    latest_pre_release_version_without_v=$(echo "$latest_pre_release_version" | sed 's/^v//')

    if [ -z "$latest_stable_version_without_v" ] && [ -z "$latest_pre_release_version_without_v" ]; then
        echo -e "${red}错误：${plain} 无法获取最新的 sing-box 版本！\n"
        exit 1
    fi
}

function install_singbox() {
    echo -e "${green}开始安装 sing-box...${plain}"

    get_latest_singbox_version

    echo -e "${yellow}请选择要安装的 sing-box 内核版本：${plain}"
    if [ -n "$latest_stable_version_without_v" ]; then
        echo "1. 稳定版 (${latest_stable_version_without_v})"
    fi
    if [ -n "$latest_pre_release_version_without_v" ]; then
        echo "2. 最新测试版 (${latest_pre_release_version_without_v})"
    fi

    local version_choice
    read -p "请输入你的选择 [1-2]:" version_choice

    if [ "$version_choice" == "1" ] && [ -n "$latest_stable_version_without_v" ]; then
        singbox_version_chosen="$latest_stable_version_without_v"
    elif [ "$version_choice" == "2" ] && [ -n "$latest_pre_release_version_without_v" ]; then
        singbox_version_chosen="$latest_pre_release_version_without_v"
    else
        echo -e "${red}无效的选择，请重新输入。${plain}"
        exit 1
    fi

    echo -e "${yellow}你选择的 sing-box 版本是：${singbox_version_chosen}${plain}"

    local download_url="https://github.com/SagerNet/sing-box/releases/download/v${singbox_version_chosen}/sing-box-${singbox_version_chosen}-linux-amd64.tar.gz"
    echo -e "${green}正在下载 sing-box ${singbox_version_chosen}...${plain}"

    wget -O /tmp/sing-box.tar.gz "$download_url"
    if [ $? -ne 0 ]; then
        echo -e "${red}错误：${plain} 下载 sing-box 失败！请检查网络连接或 URL。\n"
        exit 1
    fi

    tar -xzf /tmp/sing-box.tar.gz -C /tmp/
    if [ $? -ne 0 ]; then
        echo -e "${red}错误：${plain} 解压 sing-box 失败！\n"
        exit 1
    fi

    mv /tmp/sing-box-${singbox_version_chosen}-linux-amd64/sing-box /usr/local/bin/sing-box
    chmod +x /usr/local/bin/sing-box

    # Create systemd service file
    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box Service
Documentation=https://sing-box.sagernet.org/
After=network.target nss-lookup.target systemd-resolved.service

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/sing-box run -C /etc/sing-box
LimitNOFILE=infinity
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

    mkdir -p /etc/sing-box

    systemctl daemon-reload
    systemctl enable sing-box
    echo -e "${green}sing-box ${singbox_version_chosen} 安装成功！${plain}"

    # Check if the chosen version is 1.12.0 or higher to enable anytls
    is_latest_beta_kernel=false
    # Remove 'v' prefix for comparison if it exists, and handle potential patch/rc versions
    # For robust comparison, we ensure that both are in a comparable format
    chosen_version_numeric=$(echo "$singbox_version_chosen" | sed 's/^v//' | cut -d'-' -f1) # Remove 'v' and any '-rc' suffixes
    
    if version_ge "$chosen_version_numeric" "1.12.0"; then
        is_latest_beta_kernel=true
    fi
    
    echo -e "${yellow}请选择你想要使用的协议：${plain}"
    echo "1. vless"
    echo "2. tuic"
    echo "3. hysteria2"
    echo "4. wireguard"
    echo "5. ss"
    echo "6. trojan"
    echo "7. naive"
    echo "8. ssh"
    echo "9. shadowsocks-plugin"

    local max_protocol_choice=9
    if [ "$is_latest_beta_kernel" = true ]; then
        echo "10. anytls"
        max_protocol_choice=10
    fi

    local protocol_choice
    read -p "请输入你的选择 [1-${max_protocol_choice}]:" protocol_choice

    case "$protocol_choice" in
        1) protocol="vless" ;;
        2) protocol="tuic" ;;
        3) protocol="hysteria2" ;;
        4) protocol="wireguard" ;;
        5) protocol="ss" ;;
        6) protocol="trojan" ;;
        7) protocol="naive" ;;
        8) protocol="ssh" ;;
        9) protocol="shadowsocks-plugin" ;;
        10)
            if [ "$is_latest_beta_kernel" = true ]; then
                protocol="anytls"
            else
                echo -e "${red}无效的选择，你当前选择的内核版本不支持 anytls 协议。${plain}"
                exit 1
            fi
            ;;
        *)
            echo -e "${red}无效的选择，请重新输入。${plain}"
            exit 1
            ;;
    esac

    echo -e "${yellow}你选择的协议是：${protocol}${plain}"

    # Generate configuration based on the chosen protocol
    generate_config "$protocol"
}

function generate_config() {
    local protocol=$1
    local port=$(shuf -i 10000-65535 -n 1) # Random port
    local uuid=$(uuidgen) # Generate UUID

    cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "$protocol",
      "listen": "::",
      "listen_port": $port,
      "sniff": true
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    },
    {
      "type": "block"
    }
  ]
}
EOF

    echo -e "${green}配置文件 /etc/sing-box/config.json 已生成！${plain}"
    echo -e "${yellow}请注意，此为基础配置，你可能需要根据实际需求进行更详细的配置。${plain}"
    echo -e "${yellow}sing-box 服务已启动，或尝试使用 'systemctl start sing-box' 启动。${plain}"
    echo -e "${green}以下是你的配置信息概要：${plain}"
    echo -e "协议: ${protocol}"
    echo -e "端口: ${port}"
    if [[ "$protocol" == "vless" ]]; then
        echo -e "UUID: ${uuid}"
    fi
    echo -e "配置文件路径: /etc/sing-box/config.json"
}

function uninstall_singbox() {
    echo -e "${red}开始卸载 sing-box...${plain}"
    systemctl stop sing-box
    systemctl disable sing-box
    rm -f /etc/systemd/system/sing-box.service
    rm -f /usr/local/bin/sing-box
    rm -rf /etc/sing-box
    systemctl daemon-reload
    echo -e "${green}sing-box 已成功卸载！${plain}"
}

function start_singbox() {
    echo -e "${green}正在启动 sing-box...${plain}"
    systemctl start sing-box
    if [ $? -eq 0 ]; then
        echo -e "${green}sing-box 启动成功！${plain}"
    else
        echo -e "${red}sing-box 启动失败，请检查日志！${plain}"
    fi
}

function stop_singbox() {
    echo -e "${yellow}正在停止 sing-box...${plain}"
    systemctl stop sing-box
    if [ $? -eq 0 ]; then
        echo -e "${green}sing-box 已停止。${plain}"
    else
        echo -e "${red}sing-box 停止失败，请检查日志！${plain}"
    fi
}

function restart_singbox() {
    echo -e "${green}正在重启 sing-box...${plain}"
    systemctl restart sing-box
    if [ $? -eq 0 ]; then
        echo -e "${green}sing-box 重启成功！${plain}"
    else
        echo -e "${red}sing-box 重启失败，请检查日志！${plain}"
    fi
}

function show_status() {
    echo -e "${green}sing-box 状态：${plain}"
    systemctl status sing-box
}

function show_menu() {
    check_root
    check_operating_system
    
    echo -e "${green}sing-box 脚本 ${plain}"
    echo -e "${green}--------------------${plain}"
    echo -e "1. 安装 sing-box"
    echo -e "2. 卸载 sing-box"
    echo -e "3. 启动 sing-box"
    echo -e "4. 停止 sing-box"
    echo -e "5. 重启 sing-box"
    echo -e "6. 查看 sing-box 状态"
    echo -e "0. 退出"
    echo -e "${green}--------------------${plain}"

    local choice
    read -p "请输入你的选择 [0-6]:" choice
    case "$choice" in
        1) install_singbox ;;
        2) uninstall_singbox ;;
        3) start_singbox ;;
        4) stop_singbox ;;
        5) restart_singbox ;;
        6) show_status ;;
        0) exit 0 ;;
        *) echo -e "${red}无效的选择，请重新输入！${plain}" ;;
    esac
}

# Main
show_menu
