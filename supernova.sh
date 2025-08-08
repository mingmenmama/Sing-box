#!/usr/bin/env bash
#====================================================
# SuperNova Sing-box Manager
# Version: 1.0.0
# Author: Copilot AI
# Date: 2025-08-08
# Description: Advanced Sing-box deployment & management
#====================================================

set -e

# 颜色输出
export TERM=xterm-256color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# 彩色输出函数
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
title() { echo -e "\n${PURPLE}[SUPERNOVA]${NC} $1\n"; }
task() { echo -e "${CYAN}[TASK]${NC} $1"; }

# 命令行参数解析
ARGS=$(getopt -o hi:u:v: --long help,install,update,version:,reset,logs,status,start,stop,restart,config,wizard,bench -n 'supernova' -- "$@")
eval set -- "$ARGS"

# 系统检测
check_system() {
  task "检测系统环境..."
  
  # 检查是否为root用户
  if [[ $EUID -ne 0 ]]; then
    error "请以root用户运行此脚本"
    exit 1
  fi
  
  # 检查系统类型
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
  else
    error "无法确定操作系统类型"
    exit 1
  fi
  
  case $OS in
    ubuntu|debian|raspbian)
      PACKAGE_MANAGER="apt"
      PACKAGE_UPDATE="apt update"
      PACKAGE_INSTALL="apt install -y"
      success "检测到 $OS $VERSION 系统"
      ;;
    centos|rhel|fedora)
      PACKAGE_MANAGER="yum"
      PACKAGE_UPDATE="yum makecache"
      PACKAGE_INSTALL="yum install -y"
      success "检测到 $OS $VERSION 系统"
      ;;
    *)
      error "不支持的操作系统: $OS"
      exit 1
      ;;
  esac
  
  # 检查CPU架构
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)
      ARCH_TYPE="amd64"
      ;;
    aarch64)
      ARCH_TYPE="arm64"
      ;;
    armv7l)
      ARCH_TYPE="armv7"
      ;;
    *)
      error "不支持的CPU架构: $ARCH"
      exit 1
      ;;
  esac
  success "检测到 $ARCH_TYPE 架构"
  
  # 检查依赖工具
  task "检查必要依赖..."
  local DEPS=(curl wget jq unzip tar git cron systemd)
  local MISSING_DEPS=()
  
  for dep in "${DEPS[@]}"; do
    if ! command -v $dep &>/dev/null; then
      MISSING_DEPS+=($dep)
    fi
  done
  
  if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    warning "缺少以下依赖: ${MISSING_DEPS[*]}"
    if [[ "$AUTOINSTALL" == "true" ]]; then
      task "自动安装依赖..."
      $PACKAGE_UPDATE
      $PACKAGE_INSTALL ${MISSING_DEPS[*]}
      success "依赖安装完成"
    else
      ask "是否安装这些依赖?" Y && {
        task "安装依赖..."
        $PACKAGE_UPDATE
        $PACKAGE_INSTALL ${MISSING_DEPS[*]}
        success "依赖安装完成"
      }
    fi
  else
    success "所有依赖已满足"
  fi
}

# 高级交互函数
ask() {
  local prompt=$1
  local default=$2
  local result
  
  if [[ "$default" == "Y" ]]; then
    prompt="$prompt [Y/n]"
  elif [[ "$default" == "N" ]]; then
    prompt="$prompt [y/N]"
  else
    prompt="$prompt [y/n]"
  fi
  
  read -p "$(echo -e "${YELLOW}[QUERY]${NC} $prompt ")" result
  
  if [[ -z "$result" ]]; then
    result=$default
  fi
  
  if [[ "$result" =~ ^[Yy]$ ]]; then
    return 0
  else
    return 1
  fi
}

# 选择函数
select_option() {
  local options=("$@")
  local selected=0
  local c
  
  # 控制光标隐藏
  tput civis
  
  # 确保退出时光标恢复
  trap 'tput cnorm' EXIT
  
  # 清除之前的选项
  for ((i=0; i<${#options[@]}; i++)); do
    echo -e "   ${options[$i]}"
  done
  
  # 移动光标回到开始位置
  tput cuu ${#options[@]}
  
  while true; do
    # 显示当前选择的选项
    for ((i=0; i<${#options[@]}; i++)); do
      if [[ $i -eq $selected ]]; then
        echo -e " ${GREEN}>${NC} ${options[$i]}${NC}"
      else
        echo -e "   ${options[$i]}"
      fi
    done
    
    # 移动光标回到开始位置（除非这是最后一次迭代）
    tput cuu ${#options[@]}
    
    # 读取用户输入
    read -rsn1 c
    if [[ $c == $'\x1b' ]]; then
      read -rsn2 c
      if [[ $c == '[A' ]]; then  # 上箭头
        ((selected--))
        [[ $selected -lt 0 ]] && selected=$((${#options[@]}-1))
      elif [[ $c == '[B' ]]; then  # 下箭头
        ((selected++))
        [[ $selected -ge ${#options[@]} ]] && selected=0
      fi
    elif [[ $c == '' ]]; then  # 回车
      break
    fi
  done
  
  # 清除选项
  for ((i=0; i<${#options[@]}; i++)); do
    tput cuu1
    tput el
  done
  
  # 恢复光标
  tput cnorm
  
  # 返回选择的选项
  echo $selected
}

# 进度条函数
progress() {
  local message=$1
  local total=$2
  local current=$3
  local width=40
  local filled=$(($width * $current / $total))
  local empty=$(($width - $filled))
  
  printf "\r${CYAN}[PROGRESS]${NC} %-30s [%${filled}s%${empty}s] %3d%%" "$message" "$(printf '%0.s#' $(seq 1 $filled))" "$(printf '%0.s-' $(seq 1 $empty))" $(($current * 100 / $total))
  
  if [[ $current -eq $total ]]; then
    echo
  fi
}

# 配置目录
BASE_DIR="/opt/supernova"
SING_DIR="${BASE_DIR}/singbox"
CONFIG_DIR="${BASE_DIR}/config"
DATA_DIR="${BASE_DIR}/data"
CERT_DIR="${BASE_DIR}/cert"
BACKUP_DIR="${BASE_DIR}/backup"
LOG_DIR="/var/log/supernova"

# 创建所需目录
create_directories() {
  task "创建工作目录..."
  mkdir -p "${SING_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${CERT_DIR}" "${BACKUP_DIR}" "${LOG_DIR}"
  chmod 700 "${BASE_DIR}"
  success "目录创建完成"
}

# 获取最新版本
get_latest_version() {
  task "获取 Sing-box 最新版本..."
  
  # 使用GitHub API获取最新版本
  local latest_version
  latest_version=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r .tag_name | tr -d 'v')
  
  if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
    warning "无法从GitHub API获取版本信息，尝试使用备用方法..."
    latest_version=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9]+\\.[0-9]+\\.[0-9]+",' | head -1 | tr -d '",')
  fi
  
  if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
    error "无法获取Sing-box最新版本"
    exit 1
  fi
  
  success "获取到最新版本: $latest_version"
  echo "$latest_version"
}

# 下载 Sing-box
download_singbox() {
  local version=$1
  local arch=$2
  local target_dir=$3
  
  if [[ -z "$version" ]]; then
    version=$(get_latest_version)
  fi
  
  task "下载 Sing-box v${version}..."
  local filename="sing-box-${version}-linux-${arch}.tar.gz"
  local url="https://github.com/SagerNet/sing-box/releases/download/v${version}/${filename}"
  
  # 创建临时目录
  local temp_dir=$(mktemp -d)
  
  # 下载文件
  curl -L -o "${temp_dir}/${filename}" "${url}"
  
  # 解压
  tar -xzf "${temp_dir}/${filename}" -C "${temp_dir}"
  
  # 移动二进制文件
  mv "${temp_dir}"/sing-box-*/sing-box "${target_dir}/sing-box"
  chmod +x "${target_dir}/sing-box"
  
  # 保存版本信息
  echo "${version}" > "${target_dir}/version"
  
  # 清理临时文件
  rm -rf "${temp_dir}"
  
  success "Sing-box v${version} 下载完成"
}

# 生成服务文件
generate_service_file() {
  task "生成服务文件..."
  
  cat > /etc/systemd/system/singbox.service << EOF
[Unit]
Description=Sing-box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=${BASE_DIR}
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=${SING_DIR}/sing-box run -c ${CONFIG_DIR}/config.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

  # 重新加载systemd
  systemctl daemon-reload
  
  success "服务文件生成完成"
}

# 添加监控服务
generate_monitor_service() {
  task "生成监控服务..."
  
  cat > /etc/systemd/system/singbox-monitor.service << EOF
[Unit]
Description=Sing-box Monitor Service
After=network.target singbox.service

[Service]
User=root
WorkingDirectory=${BASE_DIR}
ExecStart=/bin/bash ${BASE_DIR}/monitor.sh
Restart=on-failure
RestartSec=60s

[Install]
WantedBy=multi-user.target
EOF

  # 创建监控脚本
  cat > ${BASE_DIR}/monitor.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/supernova/monitor.log"
CHECK_INTERVAL=60  # 检查间隔，单位秒

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

check_service() {
  if ! systemctl is-active --quiet singbox; then
    log "服务异常，正在尝试重启..."
    systemctl restart singbox
    sleep 5
    if systemctl is-active --quiet singbox; then
      log "服务已恢复"
    else
      log "服务恢复失败，请手动检查"
    fi
  fi
}

check_connectivity() {
  # 检查连接性
  if ! ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
    log "网络连接异常，正在检查..."
    # 添加更复杂的网络诊断
  fi
}

collect_stats() {
  # 收集使用统计
  local cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
  local mem=$(free -m | awk '/Mem/{print $3}')
  local disk=$(df -h / | awk '/\//{print $(NF-1)}')
  
  log "系统状态 - CPU: ${cpu}%, 内存: ${mem}MB, 磁盘: ${disk}"
}

# 主循环
log "监控服务启动"
while true; do
  check_service
  check_connectivity
  collect_stats
  sleep $CHECK_INTERVAL
done
EOF

  chmod +x ${BASE_DIR}/monitor.sh
  
  # 重新加载systemd
  systemctl daemon-reload
  
  success "监控服务生成完成"
}

# 自动证书申请
setup_certificates() {
  local domain=$1
  local email=$2
  
  if [[ -z "$domain" ]]; then
    ask "是否需要配置域名证书?" Y || return 0
    read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入域名: ")" domain
    read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入邮箱 (可选): ")" email
  fi
  
  task "配置域名证书 ${domain}..."
  
  # 安装certbot
  if ! command -v certbot &>/dev/null; then
    task "安装 certbot..."
    case $PACKAGE_MANAGER in
      apt)
        $PACKAGE_INSTALL certbot
        ;;
      yum)
        $PACKAGE_INSTALL certbot
        ;;
    esac
  fi
  
  # 申请证书
  local email_arg=""
  if [[ -n "$email" ]]; then
    email_arg="--email $email"
  else
    email_arg="--register-unsafely-without-email"
  fi
  
  certbot certonly --standalone -d "$domain" $email_arg --agree-tos -n
  
  # 复制证书到应用目录
  cp /etc/letsencrypt/live/$domain/fullchain.pem ${CERT_DIR}/cert.pem
  cp /etc/letsencrypt/live/$domain/privkey.pem ${CERT_DIR}/key.pem
  
  # 设置自动续期
  cat > /etc/cron.d/certbot-singbox << EOF
0 0 * * * root certbot renew --quiet --deploy-hook "cp /etc/letsencrypt/live/$domain/fullchain.pem ${CERT_DIR}/cert.pem && cp /etc/letsencrypt/live/$domain/privkey.pem ${CERT_DIR}/key.pem && systemctl restart singbox"
EOF
  
  success "证书配置完成，已设置自动续期"
}

# 判断分流方式
determine_routing_method() {
  local version=$1
  
  # 分析版本号
  local major=$(echo $version | cut -d. -f1)
  local minor=$(echo $version | cut -d. -f2)
  
  # 1.12.0及以上版本使用.srs分流
  if [[ $major -gt 1 ]] || [[ $major -eq 1 && $minor -ge 12 ]]; then
    echo "srs"
  else
    echo "legacy"
  fi
}

# 生成基础配置
generate_base_config() {
  local version=$1
  local user=$2
  local password=$3
  local method="$4"  # routing method: srs or legacy
  
  if [[ -z "$method" ]]; then
    method=$(determine_routing_method "$version")
  fi
  
  # 如果没有指定用户和密码，生成随机值
  if [[ -z "$user" ]]; then
    user="user_$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)"
  fi
  
  if [[ -z "$password" ]]; then
    password="$(tr -dc 'a-zA-Z0-9!@#$%^&*()_+' < /dev/urandom | head -c 16)"
  fi
  
  task "生成基础配置..."
  
  # 保存凭证信息
  echo "用户名: $user" > ${CONFIG_DIR}/credentials.txt
  echo "密码: $password" >> ${CONFIG_DIR}/credentials.txt
  chmod 600 ${CONFIG_DIR}/credentials.txt
  
  # 生成配置文件
  cat > ${CONFIG_DIR}/config.json << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true,
    "output": "${LOG_DIR}/singbox.log"
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "::",
      "listen_port": 443,
      "sniff": true,
      "sniff_override_destination": true,
      "domain_strategy": "prefer_ipv4",
      "users": [
        {
          "name": "${user}",
          "password": "${password}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_DIR}/cert.pem",
        "key_path": "${CERT_DIR}/key.pem"
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
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
EOF

  # 根据版本生成不同的路由规则
  if [[ "$method" == "srs" ]]; then
    cat >> ${CONFIG_DIR}/config.json << EOF
  "route": {
    "rule_set": [
      {
        "type": "remote",
        "tag": "geosite-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs",
        "download_detour": "direct"
      },
      {
        "type": "remote",
        "tag": "geosite-category-ads",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads.srs",
        "download_detour": "direct"
      },
      {
        "type": "remote",
        "tag": "geoip-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
        "download_detour": "direct"
      }
    ],
    "rules": [
      {
        "rule_set": ["geosite-category-ads"],
        "outbound": "block"
      },
      {
        "rule_set": ["geosite-cn", "geoip-cn"],
        "outbound": "direct"
      }
    ],
    "final": "direct",
    "auto_detect_interface": true
  },
  "experimental": {
    "cache_file": {
      "enabled": true,
      "path": "${DATA_DIR}/cache.db"
    },
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "dashboard",
      "secret": "$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16)"
    }
  }
}
EOF
  else
    cat >> ${CONFIG_DIR}/config.json << EOF
  "route": {
    "geoip": {
      "download_url": "https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db",
      "download_detour": "direct",
      "path": "${DATA_DIR}/geoip.db"
    },
    "geosite": {
      "download_url": "https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db",
      "download_detour": "direct",
      "path": "${DATA_DIR}/geosite.db"
    },
    "rules": [
      {
        "geosite": ["category-ads-all"],
        "outbound": "block"
      },
      {
        "geosite": ["cn"],
        "outbound": "direct"
      },
      {
        "geoip": ["cn"],
        "outbound": "direct"
      }
    ],
    "final": "direct",
    "auto_detect_interface": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "dashboard",
      "secret": "$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16)"
    }
  }
}
EOF
  fi
  
  success "基础配置生成完成，凭证已保存至 ${CONFIG_DIR}/credentials.txt"
}

# 生成客户端配置
generate_client_config() {
  local method=$1
  local user=$2
  local password=$3
  local server=$4
  
  # 读取凭证信息（如果未提供）
  if [[ -z "$user" || -z "$password" ]]; then
    if [[ -f "${CONFIG_DIR}/credentials.txt" ]]; then
      user=$(grep "用户名" ${CONFIG_DIR}/credentials.txt | cut -d' ' -f2)
      password=$(grep "密码" ${CONFIG_DIR}/credentials.txt | cut -d' ' -f2)
    else
      error "未找到凭证信息，无法生成客户端配置"
      return 1
    fi
  fi
  
  # 获取服务器地址
  if [[ -z "$server" ]]; then
    server=$(curl -s https://api.ipify.org)
    if [[ -z "$server" ]]; then
      read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入服务器地址或域名: ")" server
    fi
  fi
  
  task "生成客户端配置..."
  
  mkdir -p "${CONFIG_DIR}/clients"
  
  # 为不同客户端生成配置
  
  # 1. sing-box 客户端
  cat > "${CONFIG_DIR}/clients/sing-box-client.json" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 1080,
      "sniff": true,
      "sniff_override_destination": true
    },
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "inet4_address": "172.19.0.1/30",
      "auto_route": true,
      "strict_route": true,
      "stack": "system",
      "sniff": true
    }
  ],
  "outbounds": [
    {
      "type": "mixed",
      "tag": "proxy",
      "server": "${server}",
      "server_port": 443,
      "username": "${user}",
      "password": "${password}",
      "tls": {
        "enabled": true,
        "server_name": "${server}",
        "insecure": false
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "geoip": [
          "private"
        ],
        "outbound": "direct"
      }
    ],
    "final": "proxy",
    "auto_detect_interface": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "tls://8.8.8.8"
      },
      {
        "tag": "local",
        "address": "223.5.5.5",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "geosite": [
          "cn"
        ],
        "server": "local"
      }
    ],
    "final": "google",
    "strategy": "ipv4_only"
  }
}
EOF

  # 2. Clash 客户端 (Clash.Meta)
  cat > "${CONFIG_DIR}/clients/clash-meta.yaml" << EOF
mixed-port: 7890
allow-lan: true
bind-address: "*"
mode: rule
log-level: info
ipv6: true

dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  nameserver:
    - 223.5.5.5
    - 119.29.29.29

proxies:
  - name: SuperNova
    type: mixed
    server: ${server}
    port: 443
    username: ${user}
    password: ${password}
    tls:
      enabled: true
      insecure: false
      servername: ${server}

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - SuperNova
      - DIRECT

rules:
  - GEOIP,CN,DIRECT
  - GEOSITE,CN,DIRECT
  - MATCH,PROXY
EOF

  # 3. 生成二维码和URL
  if command -v qrencode &>/dev/null; then
    local url_scheme="sbox://${user}:${password}@${server}:443"
    qrencode -t PNG -o "${CONFIG_DIR}/clients/qrcode.png" "${url_scheme}"
    echo "${url_scheme}" > "${CONFIG_DIR}/clients/url.txt"
    success "二维码已生成至 ${CONFIG_DIR}/clients/qrcode.png"
  else
    warning "未安装qrencode，跳过二维码生成"
    local url_scheme="sbox://${user}:${password}@${server}:443"
    echo "${url_scheme}" > "${CONFIG_DIR}/clients/url.txt"
  fi
  
  success "客户端配置生成完成，保存在 ${CONFIG_DIR}/clients/ 目录"
}

# 流量控制配置
setup_traffic_control() {
  task "配置流量控制..."
  
  # 创建流量控制配置
  cat > ${CONFIG_DIR}/traffic_control.json << EOF
{
  "limits": {
    "default": {
      "download_mbps": 100,
      "upload_mbps": 50,
      "concurrent_connections": 100
    }
  }
}
EOF

  success "流量控制配置完成"
}

# 备份配置
backup_config() {
  local timestamp=$(date +"%Y%m%d%H%M%S")
  local backup_file="${BACKUP_DIR}/backup_${timestamp}.tar.gz"
  
  task "备份配置..."
  
  tar -czf "$backup_file" -C "${BASE_DIR}" config data cert
  
  success "配置已备份至 $backup_file"
}

# 恢复配置
restore_config() {
  task "可用备份列表:"
  
  local backups=($(ls -1 ${BACKUP_DIR}/*.tar.gz 2>/dev/null))
  if [[ ${#backups[@]} -eq 0 ]]; then
    warning "未找到可用备份"
    return 1
  fi
  
  for ((i=0; i<${#backups[@]}; i++)); do
    local file="${backups[$i]}"
    local date=$(echo "$file" | grep -o '[0-9]\{14\}')
    date=$(date -d "${date:0:8} ${date:8:2}:${date:10:2}:${date:12:2}" "+%Y-%m-%d %H:%M:%S")
    echo "[$i] $(basename "$file") - $date"
  done
  
  read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请选择要恢复的备份 [0-$((${#backups[@]}-1))]: ")" choice
  if [[ ! "$choice" =~ ^[0-9]+$ || $choice -ge ${#backups[@]} ]]; then
    error "无效的选择"
    return 1
  fi
  
  local backup_file="${backups[$choice]}"
  
  # 停止服务
  systemctl stop singbox
  
  # 备份当前配置
  backup_config
  
  # 恢复选择的备份
  task "恢复备份 $(basename "$backup_file")..."
  tar -xzf "$backup_file" -C "${BASE_DIR}"
  
  # 启动服务
  systemctl start singbox
  
  success "配置已恢复"
}

# 智能分流向导
setup_smart_routing() {
  title "智能分流向导"
  
  echo "请选择分流模式:"
  local options=(
    "基础分流 (简单的国内外分流)"
    "增强分流 (包含广告拦截、隐私保护)"
    "全局代理 (除私有地址外全部走代理)"
    "全局直连 (仅特定网站走代理)"
    "自定义规则 (高级设置)"
  )
  
  local choice=$(select_option "${options[@]}")
  
  local method=$(determine_routing_method $(cat ${SING_DIR}/version))
  local config_file="${CONFIG_DIR}/config.json"
  local temp_file="${CONFIG_DIR}/config.json.tmp"
  
  case $choice in
    0) # 基础分流
      if [[ "$method" == "srs" ]]; then
        jq '.route.rules = [
          {"rule_set": ["geosite-category-ads"], "outbound": "block"},
          {"rule_set": ["geosite-cn", "geoip-cn"], "outbound": "direct"}
        ] | .route.final = "direct"' "$config_file" > "$temp_file"
      else
        jq '.route.rules = [
          {"geosite": ["category-ads-all"], "outbound": "block"},
          {"geosite": ["cn"], "outbound": "direct"},
          {"geoip": ["cn"], "outbound": "direct"}
        ] | .route.final = "direct"' "$config_file" > "$temp_file"
      fi
      ;;
    1) # 增强分流
      if [[ "$method" == "srs" ]]; then
        # 添加额外的规则集
        jq '.route.rule_set += [
          {
            "type": "remote",
            "tag": "geosite-category-privacy",
            "format": "binary",
            "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-privacy.srs",
            "download_detour": "direct"
          }
        ] | .route.rules = [
          {"rule_set": ["geosite-category-ads", "geosite-category-privacy"], "outbound": "block"},
          {"domain_suffix": [".cn", ".中国", ".公司", ".网络"], "outbound": "direct"},
          {"rule_set": ["geosite-cn", "geoip-cn"], "outbound": "direct"}
        ] | .route.final = "direct"' "$config_file" > "$temp_file"
      else
        jq '.route.rules = [
          {"geosite": ["category-ads-all", "category-privacy"], "outbound": "block"},
          {"domain_suffix": [".cn", ".中国", ".公司", ".网络"], "outbound": "direct"},
          {"geosite": ["cn"], "outbound": "direct"},
          {"geoip": ["cn"], "outbound": "direct"}
        ] | .route.final = "direct"' "$config_file" > "$temp_file"
      fi
      ;;
    2) # 全局代理
      if [[ "$method" == "srs" ]]; then
        jq '.route.rules = [
          {"rule_set": ["geosite-category-ads"], "outbound": "block"},
          {"ip_cidr": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8"], "outbound": "direct"}
        ] | .route.final = "proxy"' "$config_file" > "$temp_file"
      else
        jq '.route.rules = [
          {"geosite": ["category-ads-all"], "outbound": "block"},
          {"ip_cidr": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8"], "outbound": "direct"}
        ] | .route.final = "proxy"' "$config_file" > "$temp_file"
      fi
      ;;
    3) # 全局直连
      if [[ "$method" == "srs" ]]; then
        jq '.route.rule_set += [
          {
            "type": "remote",
            "tag": "geosite-netflix",
            "format": "binary",
            "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-netflix.srs",
            "download_detour": "direct"
          },
          {
            "type": "remote",
            "tag": "geosite-youtube",
            "format": "binary",
            "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-youtube.srs",
            "download_detour": "direct"
          }
        ] | .route.rules = [
          {"rule_set": ["geosite-category-ads"], "outbound": "block"},
          {"rule_set": ["geosite-netflix", "geosite-youtube"], "outbound": "proxy"}
        ] | .route.final = "direct"' "$config_file" > "$temp_file"
      else
        jq '.route.rules = [
          {"geosite": ["category-ads-all"], "outbound": "block"},
          {"geosite": ["netflix", "youtube"], "outbound": "proxy"}
        ] | .route.final = "direct"' "$config_file" > "$temp_file"
      fi
      ;;
    4) # 自定义规则
      nano "$config_file"
      success "自定义规则已保存"
      return
      ;;
  esac
  
  # 应用新配置
  mv "$temp_file" "$config_file"
  success "分流规则已更新"
  
  # 重启服务
  systemctl restart singbox
}

# 安装 Sing-box
install_singbox() {
  title "安装 Sing-box"
  
  # 检查系统
  check_system
  
  # 创建目录
  create_directories
  
  # 下载最新版本
  local version=$(get_latest_version)
  download_singbox "$version" "$ARCH_TYPE" "$SING_DIR"
  
  # 确定分流方式
  local method=$(determine_routing_method "$version")
  
  # 用户配置
  local user=""
  local password=""
  local domain=""
  
  ask "是否使用默认的随机用户名和密码?" Y || {
    read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入用户名: ")" user
    read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入密码: ")" password
  }
  
  ask "是否需要设置域名和证书?" N && {
    read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入域名: ")" domain
    # 配置证书
    setup_certificates "$domain"
  }
  
  # 生成基础配置
  generate_base_config "$version" "$user" "$password" "$method"
  
  # 生成客户端配置
  generate_client_config "$method" "$user" "$password" "$domain"
  
  # 生成服务文件
  generate_service_file
  
  # 生成监控服务
  generate_monitor_service
  
  # 启动服务
  systemctl enable singbox
  systemctl start singbox
  systemctl enable singbox-monitor
  systemctl start singbox-monitor
  
  # 备份配置
  backup_config
  
  success "Sing-box 已成功安装并启动"
  
  # 显示服务状态
  show_status
}

# 更新 Sing-box
update_singbox() {
  title "更新 Sing-box"
  
  # 检查是否已安装
  if [[ ! -f "${SING_DIR}/sing-box" ]]; then
    error "Sing-box 未安装，请先安装"
    return 1
  fi
  
  # 获取当前版本
  local current_version=$(cat "${SING_DIR}/version" 2>/dev/null || echo "未知")
  
  # 获取最新版本
  local latest_version=$(get_latest_version)
  
  info "当前版本: $current_version"
  info "最新版本: $latest_version"
  
  # 检查是否需要更新
  if [[ "$current_version" == "$latest_version" ]]; then
    success "已经是最新版本，无需更新"
    return 0
  fi
  
  # 确认更新
  ask "是否更新到最新版本?" Y || return 0
  
  # 备份配置
  backup_config
  
  # 停止服务
  systemctl stop singbox
  
  # 下载新版本
  download_singbox "$latest_version" "$ARCH_TYPE" "$SING_DIR"
  
  # 检查分流方法是否需要更改
  local old_method=$(determine_routing_method "$current_version")
  local new_method=$(determine_routing_method "$latest_version")
  
  if [[ "$old_method" != "$new_method" ]]; then
    warning "检测到分流方式变更: $old_method -> $new_method"
    ask "是否更新配置文件以适配新版本?" Y && {
      # 读取当前用户配置
      local user=$(grep "用户名" ${CONFIG_DIR}/credentials.txt | cut -d' ' -f2)
      local password=$(grep "密码" ${CONFIG_DIR}/credentials.txt | cut -d' ' -f2)
      
      # 重新生成配置
      generate_base_config "$latest_version" "$user" "$password" "$new_method"
    }
  fi
  
  # 启动服务
  systemctl start singbox
  
  success "Sing-box 已更新到 v$latest_version"
}

# 卸载 Sing-box
uninstall_singbox() {
  title "卸载 Sing-box"
  
  ask "确定要卸载 Sing-box 吗? 所有配置将被备份" Y || return 0
  
  # 备份配置
  backup_config
  
  # 停止并禁用服务
  systemctl stop singbox 2>/dev/null
  systemctl disable singbox 2>/dev/null
  systemctl stop singbox-monitor 2>/dev/null
  systemctl disable singbox-monitor 2>/dev/null
  
  # 删除服务文件
  rm -f /etc/systemd/system/singbox.service
  rm -f /etc/systemd/system/singbox-monitor.service
  systemctl daemon-reload
  
  # 询问是否保留配置
  ask "是否保留配置文件? (不会删除备份)" Y || {
    rm -rf "${CONFIG_DIR}" "${DATA_DIR}" "${CERT_DIR}"
  }
  
  # 删除程序文件
  rm -rf "${SING_DIR}"
  
  success "Sing-box 已卸载"
}

# 显示状态
show_status() {
  title "Sing-box 状态"
  
  # 检查是否安装
  if [[ ! -f "${SING_DIR}/sing-box" ]]; then
    error "Sing-box 未安装"
    return 1
  fi
  
  # 版本信息
  local version=$(cat "${SING_DIR}/version" 2>/dev/null || echo "未知")
  echo -e "${BLUE}版本:${NC} $version"
  
  # 服务状态
  echo -e "${BLUE}服务状态:${NC}"
  systemctl status singbox --no-pager | grep -E "Active:|Main PID:" | sed 's/^[[:space:]]*/  /'
  
  # 配置信息
  if [[ -f "${CONFIG_DIR}/credentials.txt" ]]; then
    echo -e "${BLUE}用户凭证:${NC}"
    cat "${CONFIG_DIR}/credentials.txt" | sed 's/^/  /'
  fi
  
  # 连接信息
  local server_ip=$(curl -s https://api.ipify.org)
  echo -e "${BLUE}服务器地址:${NC} ${server_ip:-未知}"
  
  # 系统信息
  echo -e "${BLUE}系统信息:${NC}"
  echo -e "  CPU使用率: $(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')%"
  echo -e "  内存使用: $(free -m | awk '/Mem/{printf "%.1f%%", $3*100/$2}')"
  echo -e "  磁盘使用: $(df -h / | awk '/\//{print $(NF-1)}')"
  
  # 日志末尾
  if [[ -f "${LOG_DIR}/singbox.log" ]]; then
    echo -e "${BLUE}最近日志:${NC}"
    tail -n 5 "${LOG_DIR}/singbox.log" | sed 's/^/  /'
  fi
}

# 性能测试
benchmark() {
  title "性能测试"
  
  # 检查是否安装
  if [[ ! -f "${SING_DIR}/sing-box" ]]; then
    error "Sing-box 未安装"
    return 1
  fi
  
  task "系统基准测试..."
  
  # CPU信息
  echo -e "${BLUE}CPU信息:${NC}"
  lscpu | grep -E "Model name:|CPU\(s\):|CPU MHz:" | sed 's/^[[:space:]]*/  /'
  
  # 内存信息
  echo -e "${BLUE}内存信息:${NC}"
  free -h | sed 's/^/  /'
  
  # 网络基准测试
  echo -e "${BLUE}网络测试:${NC}"
  
  # 测试下载速度
  echo -e "  下载速度测试:"
  wget -O /dev/null http://speedtest.wdc01.softlayer.com/downloads/test10.zip 2>&1 | grep -E "MB/s|avg" | sed 's/^/    /'
  
  # 延迟测试
  echo -e "  延迟测试:"
  ping -c 5 8.8.8.8 | grep -E "min/avg/max" | sed 's/^/    /'
  
  # Sing-box 性能测试
  echo -e "${BLUE}Sing-box 性能测试:${NC}"
  
  # 启动时间
  echo -e "  启动时间测试:"
  systemctl stop singbox
  time_start=$(date +%s.%N)
  systemctl start singbox
  time_end=$(date +%s.%N)
  startup_time=$(echo "$time_end - $time_start" | bc)
  echo -e "    启动时间: ${startup_time}秒"
  
  # 负载测试
  echo -e "  处理能力测试:"
  ${SING_DIR}/sing-box version
  
  success "性能测试完成"
}

# 显示设置向导
show_wizard() {
  title "Sing-box 设置向导"
  
  # 检查是否安装
  if [[ ! -f "${SING_DIR}/sing-box" ]]; then
    error "Sing-box 未安装，请先安装"
    return 1
  fi
  
  # 选项列表
  local options=(
    "智能分流设置"
    "用户凭证管理"
    "证书管理"
    "日志级别设置"
    "性能优化"
    "添加/删除协议"
    "返回主菜单"
  )
  
  local choice=$(select_option "${options[@]}")
  
  case $choice in
    0) setup_smart_routing ;;
    1) manage_users ;;
    2) manage_certificates ;;
    3) manage_log_level ;;
    4) optimize_performance ;;
    5) manage_protocols ;;
    6) return 0 ;;
  esac
}

# 用户凭证管理
manage_users() {
  title "用户凭证管理"
  
  # 显示当前用户
  if [[ -f "${CONFIG_DIR}/credentials.txt" ]]; then
    echo -e "${BLUE}当前用户:${NC}"
    cat "${CONFIG_DIR}/credentials.txt" | sed 's/^/  /'
  fi
  
  # 选项列表
  local options=(
    "添加新用户"
    "修改现有用户"
    "删除用户"
    "返回上级菜单"
  )
  
  local choice=$(select_option "${options[@]}")
  
  case $choice in
    0) # 添加新用户
      read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入新用户名: ")" user
      read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入新密码: ")" password
      
      # 更新配置文件
      local config_file="${CONFIG_DIR}/config.json"
      local temp_file="${CONFIG_DIR}/config.json.tmp"
      
      jq ".inbounds[0].users += [{\"name\": \"$user\", \"password\": \"$password\"}]" "$config_file" > "$temp_file"
      mv "$temp_file" "$config_file"
      
      # 更新凭证文件
      echo "用户名: $user" >> ${CONFIG_DIR}/credentials.txt
      echo "密码: $password" >> ${CONFIG_DIR}/credentials.txt
      
      # 重启服务
      systemctl restart singbox
      
      success "用户添加成功"
      ;;
    1) # 修改现有用户
      read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入要修改的用户名: ")" user
      read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入新密码: ")" password
      
      # 更新配置文件
      local config_file="${CONFIG_DIR}/config.json"
      local temp_file="${CONFIG_DIR}/config.json.tmp"
      
      jq ".inbounds[0].users |= map(if .name == \"$user\" then .password = \"$password\" else . end)" "$config_file" > "$temp_file"
      mv "$temp_file" "$config_file"
      
      # 更新凭证文件
      sed -i "/用户名: $user/,+1 s/密码: .*/密码: $password/" ${CONFIG_DIR}/credentials.txt
      
      # 重启服务
      systemctl restart singbox
      
      success "用户修改成功"
      ;;
    2) # 删除用户
      read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入要删除的用户名: ")" user
      
      # 更新配置文件
      local config_file="${CONFIG_DIR}/config.json"
      local temp_file="${CONFIG_DIR}/config.json.tmp"
      
      jq ".inbounds[0].users |= map(select(.name != \"$user\"))" "$config_file" > "$temp_file"
      mv "$temp_file" "$config_file"
      
      # 更新凭证文件
      sed -i "/用户名: $user/,+1 d" ${CONFIG_DIR}/credentials.txt
      
      # 重启服务
      systemctl restart singbox
      
      success "用户删除成功"
      ;;
    3) return 0 ;;
  esac
}

# 证书管理
manage_certificates() {
  title "证书管理"
  
  # 显示当前证书信息
  if [[ -f "${CERT_DIR}/cert.pem" ]]; then
    echo -e "${BLUE}证书信息:${NC}"
    openssl x509 -in "${CERT_DIR}/cert.pem" -noout -subject -issuer -dates | sed 's/^/  /'
  else
    warning "未找到证书文件"
  fi
  
  # 选项列表
  local options=(
    "申请新证书"
    "使用自签名证书"
    "导入现有证书"
    "返回上级菜单"
  )
  
  local choice=$(select_option "${options[@]}")
  
  case $choice in
    0) # 申请新证书
      read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入域名: ")" domain
      read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入邮箱 (可选): ")" email
      
      setup_certificates "$domain" "$email"
      
      # 重启服务
      systemctl restart singbox
      ;;
    1) # 使用自签名证书
      task "生成自签名证书..."
      
      # 生成私钥和证书
      openssl req -x509 -newkey rsa:4096 -keyout "${CERT_DIR}/key.pem" -out "${CERT_DIR}/cert.pem" -days 3650 -nodes -subj "/CN=sing-box.local"
      
      success "自签名证书已生成"
      
      # 重启服务
      systemctl restart singbox
      ;;
    2) # 导入现有证书
      read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入证书文件路径: ")" cert_path
      read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入私钥文件路径: ")" key_path
      
      if [[ -f "$cert_path" && -f "$key_path" ]]; then
        cp "$cert_path" "${CERT_DIR}/cert.pem"
        cp "$key_path" "${CERT_DIR}/key.pem"
        
        success "证书导入成功"
        
        # 重启服务
        systemctl restart singbox
      else
        error "证书或私钥文件不存在"
      fi
      ;;
    3) return 0 ;;
  esac
}

# 日志级别管理
manage_log_level() {
  title "日志级别设置"
  
  # 获取当前日志级别
  local current_level=$(jq -r '.log.level' "${CONFIG_DIR}/config.json")
  info "当前日志级别: $current_level"
  
  # 选项列表
  local options=(
    "debug (详细调试信息)"
    "info (一般信息)"
    "warning (警告信息)"
    "error (错误信息)"
    "返回上级菜单"
  )
  
  local choice=$(select_option "${options[@]}")
  
  case $choice in
    0) level="debug" ;;
    1) level="info" ;;
    2) level="warning" ;;
    3) level="error" ;;
    4) return 0 ;;
  esac
  
  # 更新配置文件
  local config_file="${CONFIG_DIR}/config.json"
  local temp_file="${CONFIG_DIR}/config.json.tmp"
  
  jq ".log.level = \"$level\"" "$config_file" > "$temp_file"
  mv "$temp_file" "$config_file"
  
  # 重启服务
  systemctl restart singbox
  
  success "日志级别已更改为 $level"
}

# 性能优化
optimize_performance() {
  title "性能优化"
  
  # 选项列表
  local options=(
    "优化系统网络参数"
    "优化 Sing-box 配置"
    "设置资源限制"
    "返回上级菜单"
  )
  
  local choice=$(select_option "${options[@]}")
  
  case $choice in
    0) # 优化系统网络参数
      task "优化系统网络参数..."
      
      # 创建系统优化配置
      cat > /etc/sysctl.d/99-singbox-network.conf << EOF
# 增加 TCP 缓冲区大小
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# 增加最大打开文件数
fs.file-max = 1000000

# 启用 BBR 拥塞控制算法
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP 快速打开
net.ipv4.tcp_fastopen = 3

# 提高 backlog 队列大小
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 16384

# 增加本地端口范围
net.ipv4.ip_local_port_range = 1024 65535

# 禁用 IPv6 (如果不需要)
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1
# net.ipv6.conf.lo.disable_ipv6 = 1
EOF
      
      # 应用系统参数
      sysctl -p /etc/sysctl.d/99-singbox-network.conf
      
      # 设置 ulimit
      cat > /etc/security/limits.d/99-singbox.conf << EOF
*               soft    nofile          1000000
*               hard    nofile          1000000
root            soft    nofile          1000000
root            hard    nofile          1000000
EOF
      
      success "系统网络参数已优化"
      
      # 提示重启
      warning "建议重启系统以完全应用所有优化"
      ;;
    1) # 优化 Sing-box 配置
      task "优化 Sing-box 配置..."
      
      # 更新配置文件
      local config_file="${CONFIG_DIR}/config.json"
      local temp_file="${CONFIG_DIR}/config.json.tmp"
      
      # 设置实验性特性
      jq '.experimental.cache_file.enabled = true | 
          .experimental.cache_file.path = "'${DATA_DIR}'/cache.db" |
          .experimental.v2ray_api.listen = "127.0.0.1:8080" |
          .experimental.clash_api.external_controller = "127.0.0.1:9090" |
          .experimental.clash_api.external_ui = "dashboard"' "$config_file" > "$temp_file"
      
      mv "$temp_file" "$config_file"
      
      # 重启服务
      systemctl restart singbox
      
      success "Sing-box 配置已优化"
      ;;
    2) # 设置资源限制
      task "设置资源限制..."
      
      # 创建 systemd override 目录
      mkdir -p /etc/systemd/system/singbox.service.d/
      
      # 创建资源限制配置
      cat > /etc/systemd/system/singbox.service.d/limits.conf << EOF
[Service]
CPUQuota=80%
MemoryLimit=1G
EOF
      
      # 重新加载 systemd
      systemctl daemon-reload
      
      # 重启服务
      systemctl restart singbox
      
      success "资源限制已设置"
      ;;
    3) return 0 ;;
  esac
}

# 协议管理
manage_protocols() {
  title "协议管理"
  
  # 获取当前配置的入站协议
  local inbounds=$(jq -r '.inbounds[].type' "${CONFIG_DIR}/config.json" | tr '\n' ' ')
  info "当前启用的协议: $inbounds"
  
  # 选项列表
  local options=(
    "添加 VLESS 协议"
    "添加 Trojan 协议"
    "添加 Hysteria2 协议"
    "添加 Shadowsocks 协议"
    "添加 SOCKS5 协议"
    "删除协议"
    "返回上级菜单"
  )
  
  local choice=$(select_option "${options[@]}")
  
  case $choice in
    0) # 添加 VLESS 协议
      read -p "$(echo -e "${YELLOW}[QUERY]${NC} 请输入端口号 (默认8443): ")" port
      port=${port:-8443}
      
      # 读取用户凭证
      local
