#!/bin/bash

# ========== 环境设置 ==========
export LANG=en_US.UTF-8
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }
blue() { echo -e "\033[36m\033[01m$1\033[0m"; }
readp() { read -p "$(yellow "$1")" $2; }
[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit

# ========== 检查系统版本 ==========
if [[ -f /etc/redhat-release ]]; then
  release="Centos"
elif grep -iqE "alpine" /etc/issue; then
  release="alpine"
elif grep -iqE "debian" /etc/issue; then
  release="Debian"
elif grep -iqE "ubuntu" /etc/issue; then
  release="Ubuntu"
else
  red "脚本不支持当前的系统，请使用 Ubuntu/Debian/CentOS。" && exit
fi

# ========== 下载与安装 ==========
install_singbox() {
  echo
  green "选择 Sing-box 内核版本："
  yellow "1. 使用 1.10 系列（兼容 geosite）"
  yellow "2. 使用 1.12.0 及以上（使用 .srs 分流）"
  readp "请输入选项 [1-2]（默认1）: " ver_choice
  if [[ -z "$ver_choice" || "$ver_choice" == "1" ]]; then
    sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"1\\.10[0-9\\.]*",' | head -1 | tr -d '",')
  else
    sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"1\\.((1[2-9])|([2-9][0-9]))\\.[0-9]+",' | head -1 | tr -d '",')
  fi
  cpu_arch=$(uname -m)
  case $cpu_arch in
    x86_64) cpu=amd64;;
    aarch64) cpu=arm64;;
    armv7l) cpu=armv7;;
    *) red "不支持的CPU架构：$cpu_arch"; exit;;
  esac
  sbfile=sing-box-${sbcore}-linux-${cpu}.tar.gz
  mkdir -p /etc/s-box && cd /etc/s-box
  curl -L -o sing-box.tar.gz https://github.com/SagerNet/sing-box/releases/download/v${sbcore}/${sbfile}
  tar -xzf sing-box.tar.gz
  mv sing-box*/sing-box ./sing-box && chmod +x sing-box
  echo "$sbcore" > /etc/s-box/version.log
  green "Sing-box 安装完成，版本：$sbcore"
}

# ========== 写入配置文件 ==========
write_config() {
  cat > /etc/s-box/sb.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {"name": "test", "password": "testpass"}
      ],
      "padding_scheme": [
        "stop=8",
        "0=30-30",
        "1=100-400"
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/s-box/cert.pem",
        "key_path": "/etc/s-box/private.key"
      }
    }
  ],
  "outbounds": [
    {"type": "direct", "tag": "direct"}
  ],
  "route": {
    "rule_set": [
      {
        "type": "remote",
        "tag": "geosite-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs"
      },
      {
        "type": "remote",
        "tag": "geosite-!cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-!cn.srs"
      },
      {
        "type": "remote",
        "tag": "geoip-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"
      }
    ],
    "rules": [
      {"rule_set": "geosite-cn", "outbound": "direct"},
      {"rule_set": "geosite-!cn", "outbound": "direct"},
      {"rule_set": "geoip-cn", "outbound": "direct"}
    ]
  }
}
EOF
  green "配置文件已写入 /etc/s-box/sb.json"
}

# ========== 启动服务 ==========
create_service() {
  cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=Sing-box Service
After=network.target nss-lookup.target

[Service]
ExecStart=/etc/s-box/sing-box run -c /etc/s-box/sb.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reexec
  systemctl enable sing-box
  systemctl restart sing-box
  green "Sing-box 服务已启动。"
}

# ========== 主执行流程 ==========
install_singbox
write_config
create_service
