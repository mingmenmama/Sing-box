#!/bin/bash
export LANG=en_US.UTF-8
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
bblue='\033[0;34m'
plain='\033[0m'
red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}
white(){ echo -e "\033[37m\033[01m$1\033[0m";}
readp(){ read -p "$(yellow "$1")" $2;}
[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit
#[[ -e /etc/hosts ]] && grep -qE '^ *172.65.251.78 gitlab.com' /etc/hosts || echo -e '\n172.65.251.78 gitlab.com' >> /etc/hosts
if [[ -f /etc/redhat-release ]]; then
 release="Centos"
elif cat /etc/issue | grep -q -E -i "alpine"; then
 release="alpine"
elif cat /etc/issue | grep -q -E -i "debian"; then
 release="Debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
 release="Ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
 release="Centos"
elif cat /proc/version | grep -q -E -i "debian"; then
 release="Debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
 release="Ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
 release="Centos"
else 
red "脚本不支持当前的系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi
export sbfiles="/etc/s-box/sb10.json /etc/s-box/sb11.json /etc/s-box/sb.json"
export sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' | cut -d '.' -f 1,2)
vsid=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
#if [[ $(echo "$op" | grep -i -E "arch|alpine") ]]; then
if [[ $(echo "$op" | grep -i -E "arch") ]]; then
red "脚本不支持当前的 $op 系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi
version=$(uname -r | cut -d "-" -f1)
[[ -z $(systemd-detect-virt 2>/dev/null) ]] && vi=$(virt-what 2>/dev/null) || vi=$(systemd-detect-virt 2>/dev/null)
case $(uname -m) in
armv7l) cpu=armv7;;
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
*) red "目前脚本不支持$(uname -m)架构" && exit;;
esac
#bit=$(uname -m)
#if [[ $bit = "aarch64" ]]; then
#cpu="arm64"
#elif [[ $bit = "x86_64" ]]; then
#amdv=$(cat /proc/cpuinfo | grep flags | head -n 1 | cut -d: -f2)
#[[ $amdv == *avx2* && $amdv == *f16c* ]] && cpu="amd64v3" || cpu="amd64"
#else
#red "目前脚本不支持 $bit 架构" && exit
#fi
if [[ -n $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}') ]]; then
bbr=`sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}'`
elif [[ -n $(ping 10.0.0.2 -c 2 | grep ttl) ]]; then
bbr="Openvz版bbr-plus"
else
bbr="Openvz/Lxc"
fi
hostname=$(hostname)

if [ ! -f sbyg_update ]; then
green "首次安装Sing-box-yg脚本必要的依赖……"
if [[ x"${release}" == x"alpine" ]]; then
apk update
apk add wget curl tar jq tzdata openssl expect git socat iproute2 iptables grep coreutils util-linux dcron
apk add virt-what
apk add qrencode
else
if [[ $release = Centos && ${vsid} =~ 8 ]]; then
cd /etc/yum.repos.d/ && mkdir backup && mv *repo backup/ 
curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-8.repo
sed -i -e "s|mirrors.cloud.aliyuncs.com|mirrors.aliyun.com|g " /etc/yum.repos.d/CentOS-*
sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
yum clean all && yum makecache
cd
fi
if [ -x "$(command -v apt-get)" ]; then
apt update -y
apt install jq cron socat iptables-persistent coreutils util-linux -y
elif [ -x "$(command -v yum)" ]; then
yum update -y && yum install epel-release -y
yum install jq socat coreutils util-linux -y
elif [ -x "$(command -v dnf)" ]; then
dnf update -y
dnf install jq socat coreutils util-linux -y
fi
if [ -x "$(command -v yum)" ] || [ -x "$(command -v dnf)" ]; then
if [ -x "$(command -v yum)" ]; then
yum install -y cronie iptables-services
elif [ -x "$(command -v dnf)" ]; then
dnf install -y cronie iptables-services
fi
systemctl enable iptables >/dev/null 2>&1
systemctl start iptables >/dev/null 2>&1
fi
if [[ -z $vi ]]; then
apt install iputils-ping iproute2 systemctl -y
fi

packages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
inspackages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
for i in "${!packages[@]}"; do
package="${packages[$i]}"
inspackage="${inspackages[$i]}"
if ! command -v "$package" &> /dev/null; then
if [ -x "$(command -v apt-get)" ]; then
apt-get install -y "$inspackage"
elif [ -x "$(command -v yum)" ]; then
yum install -y "$inspackage"
elif [ -x "$(command -v dnf)" ]; then
dnf install -y "$inspackage"
fi
fi
done
fi
touch sbyg_update
fi

if [[ $vi = openvz ]]; then
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
red "检测到未开启TUN，现尝试添加TUN支持" && sleep 4
cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
green "添加TUN支持失败，建议与VPS厂商沟通或后台设置开启" && exit
else
echo '#!/bin/bash' > /root/tun.sh && echo 'cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun' >> /root/tun.sh && chmod +x /root/tun.sh
grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >> /etc/crontab
green "TUN守护功能已启动"
fi
fi
fi

v4v6(){
v4=$(curl -s4m5 icanhazip.com -k)
v6=$(curl -s6m5 icanhazip.com -k)
}

warpcheck(){
wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}

v6(){
v4orv6(){
if [ -z $(curl -s4m5 icanhazip.com -k) ]; then
echo
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
yellow "检测到 纯IPV6 VPS，添加DNS64"
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1\nnameserver 2a01:4f8:c2c:123f::1" > /etc/resolv.conf
endip=2606:4700:d0::a29f:c101
ipv=prefer_ipv6
else
endip=162.159.192.1
ipv=prefer_ipv4
fi
}
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
v4orv6
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
v4orv6
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
}

argopid(){
ym=$(cat /etc/s-box/sbargoympid.log 2>/dev/null)
ls=$(cat /etc/s-box/sbargopid.log 2>/dev/null)
}

close(){
systemctl stop firewalld.service >/dev/null 2>&1
systemctl disable firewalld.service >/dev/null 2>&1
setenforce 0 >/dev/null 2>&1
ufw disable >/dev/null 2>&1
iptables -P INPUT ACCEPT >/dev/null 2>&1
iptables -P FORWARD ACCEPT >/dev/null 2>&1
iptables -P OUTPUT ACCEPT >/dev/null 2>&1
iptables -t mangle -F >/dev/null 2>&1
iptables -F >/dev/null 2>&1
iptables -X >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
if [[ -n $(apachectl -v 2>/dev/null) ]]; then
systemctl stop httpd.service >/dev/null 2>&1
systemctl disable httpd.service >/dev/null 2>&1
service apache2 stop >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
fi
sleep 1
green "执行开放端口，关闭防火墙完毕"
}

openyn(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
readp "是否开放端口，关闭防火墙？\n1、是，执行 (回车默认)\n2、否，跳过！自行处理\n请选择【1-2】：" action
if [[ -z $action ]] || [[ "$action" = "1" ]]; then
close
elif [[ "$action" = "2" ]]; then
echo
else
red "输入错误,请重新选择" && openyn
fi
}

inssb(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "使用哪个内核版本？目前：1.10系列正式版内核支持geosite分流，1.10系列之后最新内核不支持geosite分流"
yellow "1：使用1.10系列正式版内核 (回车默认)"
yellow "2：使用1.10系列之后最新测试版内核 (将启用 anytls 协议)"
readp "请选择【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"1\.10[0-9\.]*",'  | sed -n 1p | tr -d '",')
unset enable_anytls
else
sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+-[^"]*"' | sed -n 1p | tr -d '",')
enable_anytls=true
fi
sbname="sing-box-$sbcore-linux-$cpu"
curl -L -o /etc/s-box/sing-box.tar.gz  -# --retry 2 https://github.com/SagerNet/sing-box/releases/download/v$sbcore/$sbname.tar.gz
if [[ -f '/etc/s-box/sing-box.tar.gz' ]]; then
tar xzf /etc/s-box/sing-box.tar.gz -C /etc/s-box
mv /etc/s-box/$sbname/sing-box /etc/s-box
rm -rf /etc/s-box/{sing-box.tar.gz,$sbname}
if [[ -f '/etc/s-box/sing-box' ]]; then
chown root:root /etc/s-box/sing-box
chmod +x /etc/s-box/sing-box
blue "成功安装 Sing-box 内核版本：$(/etc/s-box/sing-box version | awk '/version/{print $NF}')"
else
red "下载 Sing-box 内核不完整，安装失败，请再运行安装一次" && exit
fi
else
red "下载 Sing-box 内核失败，请再运行安装一次，并检测VPS的网络是否可以访问Github" && exit
fi
}

inscertificate(){
ymzs(){
ym_vl_re=www.yahoo.com
echo
blue "Vless-reality的SNI域名默认为 www.yahoo.com"
blue "Vmess-ws将开启TLS，Hysteria-2、Tuic-v5将使用 $(cat /root/ygkkkca/ca.log 2>/dev/null) 证书，并开启SNI证书验证"
tlsyn=true
ym_vm_ws=$(cat /root/ygkkkca/ca.log 2>/dev/null)
certificatec_vmess_ws='/root/ygkkkca/cert.crt'
certificatep_vmess_ws='/root/ygkkkca/private.key'
certificatec_hy2='/root/ygkkkca/cert.crt'
certificatep_hy2='/root/ygkkkca/private.key'
certificatec_tuic='/root/ygkkkca/cert.crt'
certificatep_tuic='/root/ygkkkca/private.key'
}

zqzs(){
ym_vl_re=www.yahoo.com
echo
blue "Vless-reality的SNI域名默认为 www.yahoo.com"
blue "Vmess-ws将关闭TLS，Hysteria-2、Tuic-v5将使用bing自签证书，并关闭SNI证书验证"
tlsyn=false
ym_vm_ws=www.bing.com
certificatec_vmess_ws='/etc/s-box/cert.pem'
certificatep_vmess_ws='/etc/s-box/private.key'
certificatec_hy2='/etc/s-box/cert.pem'
certificatep_hy2='/etc/s-box/private.key'
certificatec_tuic='/etc/s-box/cert.pem'
certificatep_tuic='/etc/s-box/private.key'
}

red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "二、生成并设置相关证书"
echo
blue "自动生成bing自签证书中……" && sleep 2
openssl ecparam -genkey -name prime256v1 -out /etc/s-box/private.key
openssl req -new -x509 -days 36500 -key /etc/s-box/private.key -out /etc/s-box/cert.pem -subj "/CN=www.bing.com"
echo
if [[ -f /etc/s-box/cert.pem ]]; then
blue "生成bing自签证书成功"
else
red "生成bing自签证书失败" && exit
fi
echo
if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
yellow "经检测，之前已使用Acme-yg脚本申请过Acme域名证书：$(cat /root/ygkkkca/ca.log) "
green "是否使用 $(cat /root/ygkkkca/ca.log) 域名证书？"
yellow "1：否！使用自签的证书 (回车默认)"
yellow "2：是！使用 $(cat /root/ygkkkca/ca.log) 域名证书"
readp "请选择【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
zqzs
else
ymzs
fi
else
green "如果你有解析完成的域名，是否申请一个Acme域名证书？"
yellow "1：否！继续使用自签的证书 (回车默认)"
yellow "2：是！使用Acme-yg脚本申请Acme证书 (支持常规80端口模式与Dns API模式)"
readp "请选择【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
zqzs
else
bash <(curl -Ls https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh)
if [[ ! -f /root/ygkkkca/cert.crt && ! -f /root/ygkkkca/private.key && ! -s /root/ygkkkca/cert.crt && ! -s /root/ygkkkca/private.key ]]; then
red "Acme证书申请失败，继续使用自签证书" 
zqzs
else
ymzs
fi
fi
fi
}

chooseport(){
if [[ -z $port ]]; then
port=$(shuf -i 10000-65535 -n 1)
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] 
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
done
else
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
done
fi
blue "确认的端口：$port" && sleep 2
}

vlport(){
readp "\n设置Vless-reality端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
chooseport
port_vl_re=$port
}
vmport(){
readp "\n设置Vmess-ws端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
chooseport
port_vm_ws=$port
}
hy2port(){
readp "\n设置Hysteria2主端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
chooseport
port_hy2=$port
}
tu5port(){
readp "\n设置Tuic5主端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
chooseport
port_tu=$port
}

insport(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "三、设置各个协议端口"
yellow "1：自动生成每个协议的随机端口 (10000-65535范围内)，回车默认"
yellow "2：自定义每个协议端口"
readp "请输入【1-2】：" port
if [ -z "$port" ] || [ "$port" = "1" ] ; then
ports=()
for i in {1..4}; do
while true; do
port=$(shuf -i 10000-65535 -n 1)
if ! [[ " ${ports[@]} " =~ " $port " ]] && \
[[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && \
[[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
ports+=($port)
break
fi
done
done
port_vm_ws=${ports[0]}
port_vl_re=${ports[1]}
port_hy2=${ports[2]}
port_tu=${ports[3]}
if [[ $tlsyn == "true" ]]; then
numbers=("2053" "2083" "2087" "2096" "8443")
else
numbers=("8080" "8880" "2052" "2082" "2086" "2095")
fi
port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
until [[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port_vm_ws") ]]
do
if [[ $tlsyn == "true" ]]; then
numbers=("2053" "2083" "2087" "2096" "8443")
else
numbers=("8080" "8880" "2052" "2082" "2086" "2095")
fi
port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
done
echo
blue "根据Vmess-ws协议是否启用TLS，随机指定支持CDN优选IP的标准端口：$port_vm_ws"
else
vlport && vmport && hy2port && tu5port
fi
echo
blue "各协议端口确认如下"
blue "Vless-reality端口：$port_vl_re"
blue "Vmess-ws端口：$port_vm_ws"
blue "Hysteria-2端口：$port_hy2"
blue "Tuic-v5端口：$port_tu"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "四、自动生成各个协议统一的uuid (密码)"
uuid=$(/etc/s-box/sing-box generate uuid)
blue "已确认uuid (密码)：${uuid}"
blue "已确认Vmess的path路径：${uuid}-vm"
}

inssbjsonser(){
cat > /etc/s-box/sb10.json <<EOF
{
"log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
          "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
{
        "type": "vmess",
        "sniff": true,
        "sniff_override_destination": true,
        "tag": "vmess-sb",
        "listen": "::",
        "listen_port": ${port_vm_ws},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "${uuid}-vm",
            "max_early_data":2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"    
        },
        "tls":{
                "enabled": ${tlsyn},
                "server_name": "${ym_vm_ws}",
                "certificate_path": "$certificatec_vmess_ws",
                "key_path": "$certificatep_vmess_ws"
            }
    }, 
    {
        "type": "hysteria2",
        "sniff": true,
        "sniff_override_destination": true,
        "tag": "hy2-sb",
        "listen": "::",
        "listen_port": ${port_hy2},
        "users": [
            {
                "password": "${uuid}"
            }
        ],
        "ignore_client_bandwidth":false,
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$certificatec_hy2",
            "key_path": "$certificatep_hy2"
        }
    },
        {
            "type":"tuic",
            "sniff": true,
            "sniff_override_destination": true,
            "tag": "tuic5-sb",
            "listen": "::",
            "listen_port": ${port_tu},
            "users": [
                {
                    "uuid": "${uuid}",
                    "password": "${uuid}"
                }
            ],
            "congestion_control": "bbr",
            "tls":{
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$certificatec_tuic",
                "key_path": "$certificatep_tuic"
            }
        }
$(if [ "$enable_anytls" = "true" ]; then
cat <<EOT
    ,
    {
        "type": "anytls",
        "tag": "anytls-sb",
        "listen": "::",
        "listen_port": 443,
        "tls": {
            "enabled": true,
            "server_name": "example.com",
            "certificate_path": "/etc/s-box/cert.pem",
            "key_path": "/etc/s-box/private.key"
        }
    }
EOT
fi)
],
"outbounds": [
{
"type":"direct",
"tag":"direct",
"domain_strategy": "$ipv"
},
{
"type":"direct",
"tag": "vps-outbound-v4", 
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag": "vps-outbound-v6",
"domain_strategy":"prefer_ipv6"
},
{
"type": "socks",
"tag": "socks-out toegang",
"server": "127.0.0.1",
"server_port": 40000,
"version": "5"
},
{
"type":"direct",
"tag":"socks-IPv4-out",
"detour":"socks-out",
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag":"socks-IPv6-out",
"detour":"socks-out",
"domain_strategy":"prefer_ipv6"
},
{
"type":"direct",
"tag":"warp-IPv4-out",
"detour":"wireguard-out",
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag":"warp-IPv6-out",
"detour":"wireguard-out",
"domain_strategy":"prefer_ipv6"
},
{
"type":"wireguard",
"tag":"wireguard-out",
"server":"$endip",
"server_port":2408,
"local_address":[
"172.16.0.2/32",
"${v6}/128"
],
"private_key":"$pvk",
"peer_public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
"reserved":$res
},
{
"type": "block",
"tag": "block"
}
],
"route":{
"rules":[
{
"protocol": [
"quic",
"stun"
],
"outbound": "block"
},
{
"outbound":"warp-IPv4-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"warp-IPv6-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"socks-IPv4-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"socks-IPv6-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v4",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v6",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound": "direct",
"network": "udp,tcp"
}
]
}
}
EOF

cat > /etc/s-box/sb11.json <<EOF
{
"log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
          "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
{
        "type": "vmess",
        "tag": "vmess-sb",
        "listen": "::",
        "listen_port": ${port_vm_ws},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "${uuid}-vm",
            "max_early_data":2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"    
        },
        "tls":{
                "enabled": ${tlsyn},
                "server_name": "${ym_vm_ws}",
                "certificate_path": "$certificatec_vmess_ws",
                "key_path": "$certificatep_vmess_ws"
            }
    }, 
    {
        "type": "hysteria2",
        "tag": "hy2-sb",
        "listen": "::",
        "listen_port": ${port_hy2},
        "users": [
            {
                "password": "${uuid}"
            }
        ],
        "ignore_client_bandwidth":false,
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$certificatec_hy2",
            "key_path": "$certificatep_hy2"
        }
    },
        {
            "type":"tuic",
            "tag": "tuic5-sb",
            "listen": "::",
            "listen_port": ${port_tu},
            "users": [
                {
                    "uuid": "${uuid}",
                    "password": "${uuid}"
                }
            ],
            "congestion_control": "bbr",
            "tls":{
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$certificatec_tuic",
                "key_path": "$certificatep_tuic"
            }
        }
$(if [ "$enable_anytls" = "true" ]; then
cat <<EOT
    ,
    {
        "type": "anytls",
        "tag": "anytls-sb",
        "listen": "::",
        "listen_port": 443,
        "tls": {
            "enabled": true,
            "server_name": "example.com",
            "certificate_path": "/etc/s-box/cert.pem",
            "key_path": "/etc/s-box/private.key"
        }
    }
EOT
fi)
],
"endpoints":[
{
"type":"wireguard",
"tag":"warp-out",
"address":[
"172.16.0.2/32",
"${v6}/128"
],
"private_key":"$pvk",
"peers": [
{
"address": "$endip",
"port":2408,
"public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
"allowed_ips": [
"0.0.0.0/0",
"::/0"
],
"reserved":$res
}
]
}
],
"outbounds": [
{
"type":"direct",
"tag":"direct",
"domain_strategy": "$ipv"
},
{
"type":"direct",
"tag":"vps-outbound-v4", 
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag":"vps-outbound-v6",
"domain_strategy":"prefer_ipv6"
},
{
"type": "socks",
"tag": "socks-out",
"server": "127.0.0.1",
"server_port": 40000,
"version": "5"
}
],
"route":{
"rules":[
{
 "action": "sniff"
},
{
"action": "resolve",
"domain_suffix":[
"yg_kkk"
],
"strategy": "prefer_ipv4"
},
{
"action": "resolve",
"domain_suffix":[
"yg_kkk"
],
"strategy": "prefer_ipv6"
},
{
"domain_suffix":[
"yg_kkk"
],
"outbound":"socks-out"
},
{
"domain_suffix":[
"yg_kkk"
],
"outbound":"warp-out"
},
{
"outbound":"vps-outbound-v4",
"domain_suffix":[
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v6",
"domain_suffix":[
"yg_kkk"
]
},
{
"outbound": "direct",
"network": "udp,tcp"
}
]
}
}
EOF
sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' | cut -d '.' -f 1,2)
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
}

sbservice(){
if [[ x"${release}" == x"alpine" ]]; then
echo '#!/sbin/openrc-run
description="sing-box service"
command="/etc/s-box/sing-box"
command_args="run -c /etc/s-box/sb.json"
command_background=true
pidfile="/var/run/sing-box.pid"' > /etc/init.d/sing-box
chmod +x /etc/init.d/sing-box
rc-update add sing-box default
rc-service sing-box start
else
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target nss-lookup.target
[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/etc/s-box/sing-box run -c /etc/s-box/sb.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1
systemctl start sing-box
systemctl restart sing-box
fi
}

ipuuid(){
if [[ x"${release}" == x"alpine" ]]; then
status_cmd="rc-service sing-box status"
status_pattern="started"
else
status_cmd="systemctl status sing-box"
status_pattern="active"
fi
if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
v4v6
if [[ -n $v4 && -n $v6 ]]; then
green "双栈VPS需要选择IP配置输出，一般情况下nat vps建议选择IPV6"
yellow "1：使用IPV4配置输出 (回车默认) "
yellow "2：使用IPV6配置输出"
readp "请选择【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ]; then
sbdnsip='tls://8.8.8.8/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="$v4"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$v4"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
else
sbdnsip='tls://[2001:4860:4860::8888]/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="[$v6]"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$v6"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
fi
else
yellow "VPS并不是双栈VPS，不支持IP配置输出的切换"
serip=$(curl -s4m5 icanhazip.com -k || curl -s6m5 icanhazip.com -k)
if [[ "$serip" =~ : ]]; then
sbdnsip='tls://[2001:4860:4860::8888]/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="[$serip]"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$serip"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
else
sbdnsip='tls://8.8.8.8/dns-query'
echo "$sbdnsip" > /etc/s-box/sbdnsip.log
server_ip="$serip"
echo "$server_ip" > /etc/s-box/server_ip.log
server_ipcl="$serip"
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
fi
fi
else
red "Sing-box服务未运行" && exit
fi
}

wgcfgo(){
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
ipuuid
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
ipuuid
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
}

result_vl_vm_hy_tu(){
if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
ym=`bash ~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}'`
echo $ym > /root/ygkkkca/ca.log
fi
rm -rf /etc/s-box/vm_ws_argo.txt /etc/s-box/vm_ws.txt /etc/s-box/vm_ws_tls.txt
sbdnsip=$(cat /etc/s-box/sbdnsip.log)
server_ip=$(cat /etc/s-box/server_ip.log)
server_ipcl=$(cat /etc/s-box/server_ipcl.log)
uuid=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].users[0].uuid')
vl_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].listen_port')
vl_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')
public_key=$(cat /etc/s-box/public.key)
short_id=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.reality.short_id[0]')
argo=$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
ws_path=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')
vm_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
vm_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
if [[ "$tls" = "false" ]]; then
if [[ -f /etc/s-box/cfymjx.txt ]]; then
vm_name=$(cat /etc/s-box/cfymjx.txt 2>/dev/null)
else
vm_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
fi
vmadd_local=$server_ipcl
vmadd_are_local=$server_ip
else
vmadd_local=$vm_name
vmadd_are_local=$vm_name
fi
if [[ -f /etc/s-box/cfvmadd_local.txt ]]; then
vmadd_local=$(cat /etc/s-box/cfvmadd_local.txt 2>/dev/null)
vmadd_are_local=$(cat /etc/s-box/cfvmadd_local.txt 2>/dev/null)
else
if [[ "$tls" = "false" ]]; then
if [[ -f /etc/s-box/cfymjx.txt ]]; then
vm_name=$(cat /etc/s-box/cfymjx.txt 2>/dev/null)
else
vm_name=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.server_name')
fi
vmadd_local=$server_ipcl
vmadd_are_local=$server_ip
else
vmadd_local=$vm_name
vmadd_are_local=$vm_name
fi
fi
if [[ -f /etc/s-box/cfvmadd_argo.txt ]]; then
vmadd_argo=$(cat /etc/s-box/cfvmadd_argo.txt 2>/dev/null)
else
vmadd_argo=www.visa.com.sg
fi
hy2_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$hy2_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
if [[ -n $hy2_ports ]]; then
hy2ports=$(echo $hy2_ports | sed 's/:/-/g')
hyps=$hy2_port,$hy2ports
else
hyps=
fi
ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)
hy2_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
if [[ "$hy2_sniname" = '/etc/s-box/private.key' ]]; then
hy2_name=www.bing.com
sb_hy2_ip=$server_ip
cl_hy2_ip=$server_ipcl
ins_hy2=1
hy2_ins=true
else
hy2_name=$ym
sb_hy2_ip=$ym
cl_hy2_ip=$ym
ins_hy2=0
hy2_ins=false
fi
tu5_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].listen_port')
ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)
tu5_sniname=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
if [[ "$tu5_sniname" = '/etc/s-box/private.key' ]]; then
tu5_name=www.bing.com
sb_tu5_ip=$server_ip
cl_tu5_ip=$server_ipcl
ins=1
tu5_ins=true
else
tu5_name=$ym
sb_tu5_ip=$ym
cl_tu5_ip=$ym
ins=0
tu5_ins=false
fi
}

resvless(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
vl_link="vless://$uuid@$server_ip:$vl_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#vl-reality-$hostname"
echo "$vl_link" > /etc/s-box/vl_reality.txt
red "🚀【 vless-reality-vision 】节点信息如下：" && sleep 2
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$vl_link${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vl_reality.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

resvmess(){
if [[ "$tls" = "false" ]]; then
argopid
if [[ -n $(ps -e | grep -w $ls 2>/dev/null) ]]; then
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws(tls)+Argo 】临时节点信息如下(可选择3-8-3，自定义CDN优选地址)：" && sleep 2
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo'","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo'","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_argols.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_argols.txt)"
fi
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) ]]; then
argogd=$(cat /etc/s-box/sbargoym.log 2>/dev/null)
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws(tls)+Argo 】固定节点信息如下 (可选择3-8-3，自定义CDN优选地址)：" && sleep 2
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_argogd.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_argogd.txt)"
fi
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 2
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws.txt)"
else
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws-tls 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 2
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","psVERIFY":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$vm_name'","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$vm_name'","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_tls.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_tls.txt)"
fi
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

reshy2(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
#hy2_link="hysteria2://$uuid@$sb_hy2_ip:$hy2_port?security=tls&alpn=h3&insecure=$ins_hy2&mport=$hyps&sni=$hy2_name#hy2-$hostname"
hy2_link="hysteria2://$uuid@$sb_hy2_ip:$hy2_port?security=tls&alpn=h3&insecure=$ins_hy2&sni=$hy2_name#hy2-$hostname"
echo "$hy2_link" > /etc/s-box/hy2.txt
red "🚀【 Hysteria-2 】节点信息如下：" && sleep 2
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$hy2_link${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/hy2.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

restu5(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
tuic5_link="tuic://$uuid:$uuid@$sb_tu5_ip:$tu5_port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$tu5_name&allow_insecure=$ins#tu5-$hostname"
echo "$tuic5_link" > /etc/s-box/tuic5.txt
red "🚀【 Tuic-v5 】节点信息如下：" && sleep 2
echo
echo "分享链接【v2rayn、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$tuic5_link${plain}"
echo
echo "二维码【v2rayn、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/tuic5.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

sb_client(){
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
argopid
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) && -n $(ps -e | grep -w $ls 2>/dev/null) && "$tls" = "false" ]]; then
cat > /etc/s-box/sing_box_client.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "external_ui_download_detour": "",
      "secret": "",
      "default_mode": "Rule"
       },
      "cache_file": {
            "enabled": true,
            "path": "cache.db",
            "store_fakeip": true
        }
    },
    "dns": {
        "servers": [
            {
                "tag": "proxydns",
                "address": "$sbdnsip",
                "detour": "select"
            },
            {
                "tag": "local",
                "address": "223.5.5.5",
                "detour": "direct"
            }
        ],
        "rules": [
            {
                "outbound": "any",
                "server": "local"
            }
        ],
        "strategy": "prefer_ipv4"
    },
    "inbounds": [
        {
            "type": "tun",
            "inet4_address": "172.19.0.1/30",
            "inet6_address": "fdfe:6666:6666::1/126",
            "auto_route": true,
            "strict_route": true,
            "sniff": true,
            "sniff_override_destination": true,
            "domain_strategy": "prefer_ipv4",
            "udp_timeout": 300
        },
        {
            "type": "mixed",
            "listen": "127.0.0.1",
            "listen_port": 1080,
            "sniff": true,
            "sniff_override_destination": true,
            "domain_strategy": "prefer_ipv4"
        }
    ],
    "outbounds": [
        {
            "type": "selector",
            "tag": "select",
            "outbounds": [
                "direct",
                "vless-reality",
                "vmess-ws",
                "vmess-ws-argo",
                "hysteria2",
                "tuic5"
            ],
            "default": "vless-reality"
        },
        {
            "type": "vless",
            "tag": "vless-reality",
            "server": "$server_ipcl",
            "server_port": $vl_port,
            "uuid": "$uuid",
            "flow": "xtls-rprx-vision",
            "tls": {
                "enabled": true,
                "server_name": "$vl_name",
                "reality": {
                    "enabled": true,
                    "public_key": "$public_key",
                    "short_id": "$short_id"
                }
            },
            "packet_encoding": "xudp"
        },
        {
            "type": "vmess",
            "tag": "vmess-ws",
            "server": "$vmadd_local",
            "server_port": $vm_port,
            "uuid": "$uuid",
            "security": "auto",
            "alter_id": 0,
            "transport": {
                "type": "ws",
                "path": "$ws_path",
                "headers": {
                    "Host": "$vm_name"
                },
                "max_early_data": 2048,
                "early_data_header_name": "Sec-WebSocket-Protocol"
            }
        },
        {
            "type": "vmess",
            "tag": "vmess-ws-argo",
            "server": "$argo",
            "server_port": 8443,
            "uuid": "$uuid",
            "security": "auto",
            "alter_id": 0,
            "tls": {
                "enabled": true,
                "server_name": "$argo"
            },
            "transport": {
                "type": "ws",
                "path": "$ws_path",
                "headers": {
                    "Host": "$argo"
                },
                "max_early_data": 2048,
                "early_data_header_name": "Sec-WebSocket-Protocol"
            }
        },
        {
            "type": "hysteria2",
            "tag": "hysteria2",
            "server": "$cl_hy2_ip",
            "server_port": $hy2_port,
            "password": "$uuid",
            "tls": {
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "server_name": "$hy2_name",
                "insecure": $hy2_ins
            }
        },
        {
            "type": "tuic",
            "tag": "tuic5",
            "server": "$cl_tu5_ip",
            "server_port": $tu5_port,
            "uuid": "$uuid",
            "password": "$uuid",
            "congestion_control": "bbr",
            "udp_relay_mode": "native",
            "zero_rtt_handshake": true,
            "heartbeat": "10s",
            "tls": {
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "server_name": "$tu5_name",
                "insecure": $tu5_ins
            }
        },
        {
            "type": "direct",
            "tag": "direct"
        },
        {
            "type": "block",
            "tag": "block"
        }
    ],
    "route": {
        "rules": [
            {
                "protocol": "dns",
                "outbound": "direct"
            },
            {
                "ip_is_private": true,
                "outbound": "direct"
            },
            {
                "rule_set": [
                    "geosite-cn"
                ],
                "outbound": "direct"
            },
            {
                "ip_cidr": [
                    "224.0.0.0/3",
                    "ff00::/8"
                ],
                "outbound": "block"
            }
        ],
        "rule_set": [
            {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/main/rule-set/geosite-cn.srs",
                "download_detour": "select"
            }
        ],
        "final": "select",
        "auto_detect_interface": true
    }
}
EOF
else
cat > /etc/s-box/sing_box_client.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "external_ui_download_detour": "",
      "secret": "",
      "default_mode": "Rule"
       },
      "cache_file": {
            "enabled": true,
            "path": "cache.db",
            "store_fakeip": true
        }
    },
    "dns": {
        "servers": [
            {
                "tag": "proxydns",
                "address": "$sbdnsip",
                "detour": "select"
            },
            {
                "tag": "local",
                "address": "223.5.5.5",
                "detour": "direct"
            }
        ],
        "rules": [
            {
                "outbound": "any",
                "server": "local"
            }
        ],
        "strategy": "prefer_ipv4"
    },
    "inbounds": [
        {
            "type": "tun",
            "inet4_address": "172.19.0.1/30",
            "inet6_address": "fdfe:6666:6666::1/126",
            "auto_route": true,
            "strict_route": true,
            "sniff": true,
            "sniff_override_destination": true,
            "domain_strategy": "prefer_ipv4",
            "udp_timeout": 300
        },
        {
            "type": "mixed",
            "listen": "127.0.0.1",
            "listen_port": 1080,
            "sniff": true,
            "sniff_override_destination": true,
            "domain_strategy": "prefer_ipv4"
        }
    ],
    "outbounds": [
        {
            "type": "selector",
            "tag": "select",
            "outbounds": [
                "direct",
                "vless-reality",
                "vmess-ws-tls",
                "hysteria2",
                "tuic5"
            ],
            "default": "vless-reality"
        },
        {
            "type": "vless",
            "tag": "vless-reality",
            "server": "$server_ipcl",
            "server_port": $vl_port,
            "uuid": "$uuid",
            "flow": "xtls-rprx-vision",
            "tls": {
                "enabled": true,
                "server_name": "$vl_name",
                "reality": {
                    "enabled": true,
                    "public_key": "$public_key",
                    "short_id": "$short_id"
                }
            },
            "packet_encoding": "xudp"
        },
        {
            "type": "vmess",
            "tag": "vmess-ws-tls",
            "server": "$vmadd_local",
            "server_port": $vm_port,
            "uuid": "$uuid",
            "security": "auto",
            "alter_id": 0,
            "tls": {
                "enabled": true,
                "server_name": "$vm_name"
            },
            "transport": {
                "type": "ws",
                "path": "$ws_path",
                "headers": {
                    "Host": "$vm_name"
                },
                "max_early_data": 2048,
                "early_data_header_name": "Sec-WebSocket-Protocol"
            }
        },
        {
            "type": "hysteria2",
            "tag": "hysteria2",
            "server": "$cl_hy2_ip",
            "server_port": $hy2_port,
            "password": "$uuid",
            "tls": {
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "server_name": "$hy2_name",
                "insecure": $hy2_ins
            }
        },
        {
            "type": "tuic",
            "tag": "tuic5",
            "server": "$cl_tu5_ip",
            "server_port": $tu5_port,
            "uuid": "$uuid",
            "password": "$uuid",
            "congestion_control": "bbr",
            "udp_relay_mode": "native",
            "zero_rtt_handshake": true,
            "heartbeat": "10s",
            "tls": {
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "server_name": "$tu5_name",
                "insecure": $tu5_ins
            }
        },
        {
            "type": "direct",
            "tag": "direct"
        },
        {
            "type": "block",
            "tag": "block"
        }
    ],
    "route": {
        "rules": [
            {
                "protocol": "dns",
                "outbound": "direct"
            },
            {
                "ip_is_private": true,
                "outbound": "direct"
            },
            {
                "rule_set": [
                    "geosite-cn"
                ],
                "outbound": "direct"
            },
            {
                "ip_cidr": [
                    "224.0.0.0/3",
                    "ff00::/8"
                ],
                "outbound": "block"
            }
        ],
        "rule_set": [
            {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/main/rule-set/geosite-cn.srs",
                "download_detour": "select"
            }
        ],
        "final": "select",
        "auto_detect_interface": true
    }
}
EOF
fi

cat > /etc/s-box/clash_meta_client.yaml <<EOF
port: 7890
socks-port: 7891
allow-lan: false
mode: rule
log-level: info
external-controller: 127.0.0.1:9090
dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  nameserver:
    - $sbdnsip
  fallback:
    - "tls://8.8.4.4:853"
proxies:
  - name: "vless-reality"
    type: vless
    server: $server_ipcl
    port: $vl_port
    uuid: $uuid
    flow: xtls-rprx-vision
    network: tcp
    servername: $vl_name
    reality-opts:
      public-key: $public_key
      short-id: $short_id
    client-fingerprint: chrome
  - name: "vmess-ws$([[ "$tls" = "true" ]] && echo "-tls")"
    type: vmess
    server: $vmadd_local
    port: $vm_port
    uuid: $uuid
    alterId: 0
    cipher: auto
    network: ws
    $([[ "$tls" = "true" ]] && echo "tls: true")
    servername: $vm_name
    ws-opts:
      path: "$ws_path"
      headers:
        Host: $vm_name
      max-early-data: 2048
      early-data-header-name: Sec-WebSocket-Protocol
$(if [[ -n $(ps -e | grep -w $ls 2>/dev/null) && "$tls" = "false" ]]; then
cat <<EOT
  - name: "vmess-ws-argo"
    type: vmess
    server: $argo
    port: 8443
    uuid: $uuid
    alterId: 0
    cipher: auto
    network: ws
    tls: true
    servername: $argo
    ws-opts:
      path: "$ws_path"
      headers:
        Host: $argo
      max-early-data: 2048
      early-data-header-name: Sec-WebSocket-Protocol
EOT
fi)
  - name: "hysteria2"
    type: hysteria2
    server: $cl_hy2_ip
    port: $hy2_port
    password: $uuid
    alpn:
      - h3
    sni: $hy2_name
    skip-cert-verify: $hy2_ins
  - name: "tuic5"
    type: tuic
    server: $cl_tu5_ip
    port: $tu5_port
    uuid: $uuid
    password: $uuid
    alpn:
      - h3
    sni: $tu5_name
    skip-cert-verify: $tu5_ins
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - vless-reality
      - vmess-ws$([[ "$tls" = "true" ]] && echo "-tls")$([[ -n $(ps -e | grep -w $ls 2>/dev/null) && "$tls" = "false" ]] && echo -e "\n      - vmess-ws-argo")
      - hysteria2
      - tuic5
      - DIRECT
rules:
  - GEOIP,private,DIRECT
  - GEOSITE,CN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOF

cat > /etc/s-box/v2rayn_hy2.yaml <<EOF
server: "$cl_hy2_ip:$hy2_port"
auth: "$uuid"
tls:
  enabled: true
  server_name: "$hy2_name"
  insecure: $hy2_ins
  alpn:
    - h3
fast_open: true
lazy: true
transport:
  udp:
    hop_interval: "30s"
EOF

if [[ "$tu5_sniname" != '/etc/s-box/private.key' ]]; then
cat > /etc/s-box/v2rayn_tu5.json <<EOF
{
    "relay": {
        "server": "$cl_tu5_ip",
        "port": $tu5_port,
        "uuid": "$uuid",
        "password": "$uuid",
        "ip_version": "prefer_ipv4",
        "congestion_control": "bbr",
        "udp_relay_mode": "native",
        "zero_rtt_handshake": true,
        "heartbeat": "10s"
    },
    "tls": {
        "enabled": true,
        "server_name": "$tu5_name",
        "alpn": ["h3"],
        "insecure": $tu5_ins
    },
    "mux": {
        "enabled": false
    },
    "fast_open": true,
    "lazy_start": true
}
EOF
fi
}

allports(){
hy2_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[2].listen_port')
hy2zfport=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$hy2_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ' ')
tu5_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[3].listen_port')
tu5zfport=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$tu5_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ' ')
vl_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[0].listen_port')
vm_port=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')
}

instsllsingbox(){
if [[ -f '/etc/s-box/sb.json' ]]; then
yellow "检测到已安装Sing-box，无法重复安装，请选择删除卸载后重新安装，或者选择变更内核版本" && sleep 2 && sb
fi
v6
openyn
mkdir -p /etc/s-box
openssl ecparam -genkey -name prime256v1 -out /etc/s-box/private.key
openssl req -new -x509 -days 36500 -key /etc/s-box/private.key -out /etc/s-box/public.key -subj "/CN=bing.com"
private_key=$(cat /etc/s-box/private.key | head -n -1 | tail -n +2 | tr -d '\n')
public_key=$(cat /etc/s-box/public.key | head -n -1 | tail -n +2 | tr -d '\n')
short_id=$(/etc/s-box/sing-box generate rand --hex 8)
inssb
inscertificate
insport
inssbjsonser
sbservice
cronsb
wgcfgo
sbshare
green "Sing-box已安装完成"
sb
}

changeserv(){
sbactive
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
echo
yellow "1：变更Vmess-ws双证书形式(TLS与自签证书)"
yellow "2：变更所有协议的UUID与Vmess-ws的path路径"
yellow "3：变更Argo临时域名与固定域名"
yellow "4：变更双栈VPS的IP优先级"
yellow "5：变更Telegram通知"
yellow "6：变更Warp出站设置"
yellow "7：变更订阅与Gitlab订阅设置"
yellow "8：变更Vmess-ws的CDN优选IP地址"
yellow "0：返回上层"
readp "请选择【0-8】：" menu
if [ "$menu" = "1" ]; then
inscertificate
inssbjsonser
restartsb
sbshare
green "已成功变更Sing-box证书形式" && sleep 3 && sb
elif [ "$menu" = "2" ]; then
uuid=$(/etc/s-box/sing-box generate uuid)
blue "已确认新的uuid (密码)：${uuid}"
blue "已确认新的Vmess的path路径：${uuid}-vm"
sed -i "s/\"uuid\": \".*\"/\"uuid\": \"${uuid}\"/g" /etc/s-box/sb.json /etc/s-box/sb10.json /etc/s-box/sb11.json
sed -i "s/\"password\": \".*\"/\"password\": \"${uuid}\"/g" /etc/s-box/sb.json /etc/s-box/sb10.json /etc/s-box/sb11.json
sed -i "s#\"path\": \".*\"#\"path\": \"${uuid}-vm\"#g" /etc/s-box/sb.json /etc/s-box/sb10.json /etc/s-box/sb11.json
restartsb
sbshare
green "已成功变更Sing-box所有协议的UUID与Vmess-ws的path路径" && sleep 3 && sb
elif [ "$menu" = "3" ]; then
change_argo
elif [ "$menu" = "4" ]; then
wgcfgo
restartsb
sbshare
green "已成功变更Sing-box双栈VPS的IP优先级" && sleep 3 && sb
elif [ "$menu" = "5" ]; then
tgmt
elif [ "$menu" = "6" ]; then
warpserv
elif [ "$menu" = "7" ]; then
sbsharelink
elif [ "$menu" = "8" ]; then
vmess_cdn
else
sb
fi
}

change_argo(){
sbactive
tls=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
if [[ "$tls" = "true" ]]; then
yellow "当前为Vmess-ws-tls模式，不支持Argo临时域名与固定域名设置" && sleep 2 && sb
fi
echo
yellow "1：重新启动Argo临时域名"
yellow "2：设置Argo固定域名"
yellow "3：自定义Argo的CDN优选地址"
yellow "0：返回上层"
readp "请选择【0-3】：" menu
if [ "$menu" = "1" ]; then
argopid
kill -15 $(cat /etc/s-box/sbargopid.log 2>/dev/null) >/dev/null 2>&1
rm -rf /etc/s-box/argo.log /etc/s-box/sbargopid.log
curl -L -o /etc/s-box/sbargo -# --retry 2 https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu
chmod +x /etc/s-box/sbargo
blue "正在启动Argo临时域名，请稍等……"
/etc/s-box/sbargo --edge-ip-version auto tunnel --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 & echo "$!" > /etc/s-box/sbargopid.log
sleep 10
if [[ -n $(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com) ]]; then
crontab -l > /tmp/crontab.tmp
sed -i '/sbargopid/d' /tmp/crontab.tmp
echo "@reboot /etc/s-box/sbargo --edge-ip-version auto tunnel --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 & echo \$! > /etc/s-box/sbargopid.log" >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
green "Argo临时域名启动成功" && sleep 2
sbshare
else
red "启动失败，请检查VPS网络环境是否正常，或者更换节点后重试" && sleep 2 && change_argo
fi
elif [ "$menu" = "2" ]; then
argopid
if [[ -n $(ps -e | grep -w $ls 2>/dev/null) ]]; then
kill -15 $(cat /etc/s-box/sbargopid.log 2>/dev/null) >/dev/null 2>&1
rm -rf /etc/s-box/argo.log /etc/s-box/sbargopid.log
crontab -l > /tmp/crontab.tmp
sed -i '/sbargopid/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
fi
yellow "请先准备好Cloudflare的Argo固定域名，并确保已解析域名到VPS的IP"
readp "请输入Argo固定域名：" argogd
if [[ -n $(ps -e | grep -w $ym 2>/dev/null) ]]; then
kill -15 $(cat /etc/s-box/sbargoympid.log 2>/dev/null) >/dev/null 2>&1
fi
curl -L -o /etc/s-box/sbargo -# --retry 2 https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu
chmod +x /etc/s-box/sbargo
blue "正在启动Argo固定域名，请稍等……"
/etc/s-box/sbargo --edge-ip-version auto tunnel --no-autoupdate --protocol http2 --url http://localhost:$vm_port > /etc/s-box/sbargoym.log 2>&1 & echo "$!" > /etc/s-box/sbargoympid.log
echo "$argogd" > /etc/s-box/sbargoym.log
sleep 10
if [[ -n $(cat /etc/s-box/sbargoym.log 2>/dev/null | grep -a $argogd) ]]; then
crontab -l > /tmp/crontab.tmp
sed -i '/sbargoympid/d' /tmp/crontab.tmp
echo "@reboot /etc/s-box/sbargo --edge-ip-version auto tunnel --no-autoupdate --protocol http2 --url http://localhost:$vm_port > /etc/s-box/sbargoym.log 2>&1 & echo \$! > /etc/s-box/sbargoympid.log" >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
green "Argo固定域名启动成功" && sleep 2
sbshare
else
red "启动失败，请检查域名是否正确解析到VPS的IP，或者更换节点后重试" && sleep 2 && change_argo
fi
elif [ "$menu" = "3" ]; then
readp "请输入自定义Argo的CDN优选地址 (回车跳过使用默认 www.visa.com.sg )：" vmadd_argo
if [ -z "$vmadd_argo" ]; then
vmadd_argo=www.visa.com.sg
fi
echo "$vmadd_argo" > /etc/s-box/cfvmadd_argo.txt
green "已成功设置Argo的CDN优选地址：$vmadd_argo" && sleep 2
sbshare
else
changeserv
fi
}

tgmt(){
sbactive
echo
yellow "1：设置Telegram通知"
yellow "2：关闭Telegram通知"
yellow "0：返回上层"
readp "请选择【0-2】：" menu
if [ "$menu" = "1" ]; then
yellow "请先关注Telegram的 @BotFather 创建机器人，获取机器人Token"
yellow "然后与机器人对话，获取Chat_ID，或者加入需要通知的群组后通过 https://api.telegram.org/bot<你的机器人Token>/getUpdates 获取Chat_ID"
readp "请输入你的Telegram机器人Token：" tg_token
readp "请输入你的Telegram Chat_ID：" tg_chat_id
sbshare > /dev/null 2>&1
baseurl=$(base64 -w 0 < /etc/s-box/jhdy.txt 2>/dev/null)
curl -s -X POST "https://api.telegram.org/bot$tg_token/sendMessage" -d chat_id="$tg_chat_id" -d text="Sing-box节点配置信息：$baseurl" > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
echo "$tg_token" > /etc/s-box/tg_token.log
echo "$tg_chat_id" > /etc/s-box/tg_chat_id.log
green "Telegram通知设置成功，节点信息已发送到你的Telegram" && sleep 3 && sb
else
red "Telegram通知发送失败，请检查Token和Chat_ID是否正确" && sleep 3 && tgmt
fi
elif [ "$menu" = "2" ]; then
rm -f /etc/s-box/tg_token.log /etc/s-box/tg_chat_id.log
green "Telegram通知已关闭" && sleep 3 && sb
else
changeserv
fi
}

tgnotice(){
sbactive
if [[ ! -f /etc/s-box/tg_token.log || ! -f /etc/s-box/tg_chat_id.log ]]; then
yellow "未设置Telegram通知，请先选择3-5设置Telegram通知" && sleep 2 && sb
fi
tg_token=$(cat /etc/s-box/tg_token.log)
tg_chat_id=$(cat /etc/s-box/tg_chat_id.log)
sbshare > /dev/null 2>&1
baseurl=$(base64 -w 0 < /etc/s-box/jhdy.txt 2>/dev/null)
gitlab_sub=$(cat /etc/s-box/gitlab_sub.log 2>/dev/null)
curl -s -X POST "https://api.telegram.org/bot$tg_token/sendMessage" -d chat_id="$tg_chat_id" -d text="Sing-box节点配置信息：$baseurl" > /dev/null 2>&1
curl -s -X POST "https://api.telegram.org/bot$tg_token/sendMessage" -d chat_id="$tg_chat_id" -d text="Sing-box Gitlab订阅链接：$gitlab_sub" > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
green "节点信息已成功推送到Telegram" && sleep 3 && sb
else
red "推送失败，请检查Telegram设置是否正确" && sleep 3 && sb
fi
}

warpserv(){
sbactive
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
yellow "当前VPS未安装WARP，将使用默认对端IP：162.159.192.1:2408或者IPV6对端IP：2606:4700:d0::a29f:c001:2408" && sleep 2
fi
wgip=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .server')
wgpo=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .server_port')
wgipv6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .local_address[1]' | sed 's/\/128//')
pvk=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .private_key')
wgres=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .reserved')
echo
yellow "当前对端IP与端口：$wgip:$wgpo"
yellow "当前IPV6本地地址：$wgipv6"
yellow "当前Private_key：$pvk"
yellow "当前Reserved值：$wgres"
echo
yellow "1：自定义设置Warp出站"
yellow "2：一键更换Warp出站优选对端IP"
yellow "0：返回上层"
readp "请选择【0-2】：" menu
if [ "$menu" = "1" ]; then
readp "输入自定义对端IP (回车跳过表示不更改当前对端IP：$wgip)：" menu
if [ -z "$menu" ]; then
menu=$wgip
fi
sed -i "157s/$wgip/$menu/g" /etc/s-box/sb10.json
sed -i "118s/$wgip/$menu/g" /etc/s-box/sb11.json
readp "输入自定义对端端口 (回车跳过表示不更改当前对端端口：$wgpo)：" menu
if [ -z "$menu" ]; then
menu=$wgpo
fi
sed -i "158s/$wgpo/$menu/g" /etc/s-box/sb10.json
sed -i "119s/$wgpo/$menu/g" /etc/s-box/sb11.json
readp "输入自定义IPV6本地地址 (回车跳过表示不更改当前IPV6本地地址：$wgipv6)：" menu
if [ -z "$menu" ]; then
menu=$wgipv6
fi
sed -i "161s/$wgipv6/$menu/g" /etc/s-box/sb10.json
sed -i "113s/$wgipv6/$menu/g" /etc/s-box/sb11.json
readp "输入自定义Reserved值 (格式：数字,数字,数字)，如无值则回车跳过：" menu
if [ -z "$menu" ]; then
menu=0,0,0
fi
sed -i "165s/$wgres/$menu/g" /etc/s-box/sb10.json
sed -i "125s/$wgres/$menu/g" /etc/s-box/sb11.json
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
green "设置结束"
green "可以先在选项5-1或5-2使用完整域名分流：cloudflare.com"
green "然后使用任意节点打开网页https://cloudflare.com/cdn-cgi/trace，查看当前WARP账户类型"
elif  [ "$menu" = "2" ]; then
green "请稍等……更新中……"
if [ -z $(curl -s4m5 icanhazip.com -k) ]; then
curl -sSL https://gitlab.com/rwkgyg/CFwarp/raw/main/point/endip.sh -o endip.sh && chmod +x endip.sh && (echo -e "1\n2\n") | bash endip.sh > /dev/null 2>&1
nwgip=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
nwgpo=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F "]" '{print $2}' | tr -d ':')
else
curl -sSL https://gitlab.com/rwkgyg/CFwarp/raw/main/point/endip.sh -o endip.sh && chmod +x endip.sh && (echo -e "1\n1\n") | bash endip.sh > /dev/null 2>&1
nwgip=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F: '{print $1}')
nwgpo=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F: '{print $2}')
fi
a=$(cat /root/result.csv 2>/dev/null | awk -F, '$3!="timeout ms" {print} ' | sed -n '2p' | awk -F ',' '{print $2}')
if [[ -z $a || $a = "100.00%" ]]; then
if [[ -z $(curl -s4m5 icanhazip.com -k) ]]; then
nwgip=2606:4700:d0::a29f:c001
nwgpo=2408
else
nwgip=162.159.192.1
nwgpo=2408
fi
fi
sed -i "157s#$wgip#$nwgip#g" /etc/s-box/sb10.json
sed -i "158s#$wgpo#$nwgpo#g" /etc/s-box/sb10.json
sed -i "118s#$wgip#$nwgip#g" /etc/s-box/sb11.json
sed -i "119s#$wgpo#$nwgpo#g" /etc/s-box/sb11.json
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
rm -rf /root/result.csv /root/endip.sh 
echo
green "优选完毕，当前使用的对端IP：$nwgip:$nwgpo"
else
changeserv
fi
}

sbymfl(){
sbport=$(cat /etc/s-box/sbwpph.log 2>/dev/null | awk '{print $3}' | awk -F":" '{print $NF}') 
sbport=${sbport:-'40000'}
resv1=$(curl -s --socks5 localhost:$sbport icanhazip.com)
resv2=$(curl -sx socks5h://localhost:$sbport icanhazip.com)
if [[ -z $resv1 && -z $resv2 ]]; then
warp_s4_ip='Socks5-IPV4未启动，黑名单模式'
warp_s6_ip='Socks5-IPV6未启动，黑名单模式'
else
warp_s4_ip='Socks5-IPV4可用'
warp_s6_ip='Socks5-IPV6自测'
fi
v4v6
if [[ -z $v4 ]]; then
vps_ipv4='无本地IPV4，黑名单模式'      
vps_ipv6="当前IP：$v6"
elif [[ -n $v4 &&  -n $v6 ]]; then
vps_ipv4="当前IP：$v4"    
vps_ipv6="当前IP：$v6"
else
vps_ipv4="当前IP：$v4"    
vps_ipv6='无本地IPV6，黑名单模式'
fi
unset swg4 swd4 swd6 swg6 ssd4 ssg4 ssd6 ssg6 sad4 sag4 sad6 sag6
wd4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[1].domain_suffix | join(" ")')
wg4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[1].geosite | join(" ")' 2>/dev/null)
if [[ "$wd4" == "yg_kkk" && ("$wg4" == "yg_kkk" || -z "$wg4") ]]; then
wfl4="${yellow}【warp出站IPV4可用】未分流${plain}"
else
if [[ "$wd4" != "yg_kkk" ]]; then
swd4="$wd4 "
fi
if [[ "$wg4" != "yg_kkk" ]]; then
swg4=$wg4
fi
wfl4="${yellow}【warp出站IPV4可用】已分流：$swd4$swg4${plain} "
fi

wd6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[2].domain_suffix | join(" ")')
wg6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[2].geosite | join(" ")' 2>/dev/null)
if [[ "$wd6" == "yg_kkk" && ("$wg6" == "yg_kkk"|| -z "$wg6") ]]; then
wfl6="${yellow}【warp出站IPV6自测】未分流${plain}"
else
if [[ "$wd6" != "yg_kkk" ]]; then
swd6="$wd6 "
fi
if [[ "$wg6" != "yg_kkk" ]]; then
swg6=$wg6
fi
wfl6="${yellow}【warp出站IPV6自测】已分流：$swd6$swg6${plain} "
fi

sd4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[3].domain_suffix | join(" ")')
sg4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[3].geosite | join(" ")' 2>/dev/null)
if [[ "$sd4" == "yg_kkk" && ("$sg4" == "yg_kkk" || -z "$sg4") ]]; then
sfl4="${yellow}【$warp_s4_ip】未分流${plain}"
else
if [[ "$sd4" != "yg_kkk" ]]; then
ssd4="$sd4 "
fi
if [[ "$sg4" != "yg_kkk" ]]; then
ssg4=$sg4
fi
sfl4="${yellow}【$warp_s4_ip】已分流：$ssd4$ssg4${plain} "
fi

sd6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[4].domain_suffix | join(" ")')
sg6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[4].geosite | join(" ")' 2>/dev/null)
if [[ "$sd6" == "yg_kkk" && ("$sg6" == "yg_kkk" || -z "$sg6") ]]; then
sfl6="${yellow}【$warp_s6_ip】未分流${plain}"
else
if [[ "$sd6" != "yg_kkk" ]]; then
ssd6="$sd6 "
fi
if [[ "$sg6" != "yg_kkk" ]]; then
ssg6=$sg6
fi
sfl6="${yellow}【$warp_s6_ip】已分流：$ssd6$ssg6${plain} "
fi

ad4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[5].domain_suffix | join(" ")')
ag4=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[5].geosite | join(" ")' 2>/dev/null)
if [[ "$ad4" == "yg_kkk" && ("$ag4" == "yg_kkk" || -z "$ag4") ]]; then
adfl4="${yellow}【$vps_ipv4】未分流${plain}" 
else
if [[ "$ad4" != "yg_kkk" ]]; then
sad4="$ad4 "
fi
if [[ "$ag4" != "yg_kkk" ]]; then
sag4=$ag4
fi
adfl4="${yellow}【$vps_ipv4】已分流：$sad4$sag4${plain} "
fi

ad6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[6].domain_suffix | join(" ")')
ag6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.route.rules[6].geosite | join(" ")' 2>/dev/null)
if [[ "$ad6" == "yg_kkk" && ("$ag6" == "yg_kkk" || -z "$ag6") ]]; then
adfl6="${yellow}【$vps_ipv6】未分流${plain}" 
else
if [[ "$ad6" != "yg_kkk" ]]; then
sad6="$ad6 "
fi
if [[ "$ag6" != "yg_kkk" ]]; then
sag6=$ag6
fi
adfl6="${yellow}【$vps_ipv6】已分流：$sad6$sag6${plain} "
fi
}

changefl(){
sbactive
blue "对所有协议进行统一的域名分流"
blue "为确保分流可用，双栈IP（IPV4/IPV6）分流模式为优先模式"
blue "warp-wireguard默认开启 (选项1与2)"
blue "socks5需要在VPS安装warp官方客户端或者WARP-plus-Socks5-赛风VPN (选项3与4)"
blue "VPS本地出站分流(选项5与6)"
echo
[[ "$sbnh" == "1.10" ]] && blue "当前Sing-box内核支持geosite分流方式" || blue "当前Sing-box内核不支持geosite分流方式，仅支持分流2、3、5、6选项"
echo
yellow "注意："
yellow "一、完整域名方式只能填完整域名 (例：谷歌网站填写：www.google.com)"
yellow "二、geosite方式须填写geosite规则名 (例：奈飞填写:netflix ；迪士尼填写:disney ；ChatGPT填写:openai ；全局且绕过中国填写:geolocation-!cn)"
yellow "三、同一个完整域名或者geosite切勿重复分流"
yellow "四、如分流通道中有个别通道无网络，所填分流为黑名单模式，即屏蔽该网站访问"
changef
}

changef(){
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
sbymfl
echo
if [[ "$sbnh" != "1.10" ]]; then
wfl4='暂不支持'
sfl6='暂不支持'
fi
green "1：重置warp-wireguard-ipv4优先分流域名 $wfl4"
green "2：重置warp-wireguard-ipv6优先分流域名 $wfl6"
green "3：重置warp-socks5-ipv4优先分流域名 $sfl4"
green "4：重置warp-socks5-ipv6优先分流域名 $sfl6"
green "5：重置VPS本地ipv4优先分流域名 $adfl4"
green "6：重置VPS本地ipv6优先分流域名 $adfl6"
green "0：返回上层"
echo
readp "请选择【0-6】：" menu

if [ "$menu" = "1" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv4的完整域名方式的分流通道)：" w4flym
if [ -z "$w4flym" ]; then
w4flym='"yg_kkk"'
else
w4flym="$(echo "$w4flym" | sed 's/ /","/g')"
w4flym="\"$w4flym\""
fi
sed -i "184s/.*/$w4flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
elif [ "$menu" = "2" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv4的geosite方式的分流通道)：" w4flym
if [ -z "$w4flym" ]; then
w4flym='"yg_kkk"'
else
w4flym="$(echo "$w4flym" | sed 's/ /","/g')"
w4flym="\"$w4flym\""
fi
sed -i "187s/.*/$w4flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
else
changef
fi
else
yellow "遗憾！当前暂时只支持warp-wireguard-ipv6，如需要warp-wireguard-ipv4，请切换1.10系列内核" && exit
fi

elif [ "$menu" = "2" ]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv6的完整域名方式的分流通道：" w6flym
if [ -z "$w6flym" ]; then
w6flym='"yg_kkk"'
else
w6flym="$(echo "$w6flym" | sed 's/ /","/g')"
w6flym="\"$w6flym\""
fi
sed -i "193s/.*/$w6flym/" /etc/s-box/sb10.json
sed -i "169s/.*/$w6flym/" /etc/s-box/sb11.json
sed -i "181s/.*/$w6flym/" /etc/s-box/sb11.json
rm -rf /etc/s-box/sb.json
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv6的geosite方式的分流通道：" w6flym
if [ -z "$w6flym" ]; then
w6flym='"yg_kkk"'
else
w6flym="$(echo "$w6flym" | sed 's/ /","/g')"
w6flym="\"$w6flym\""
fi
sed -i "196s/.*/$w6flym/" /etc/s-box/sb.json /etc/s-box/sb10.json
restartsb
changef
else
yellow "遗憾！当前Sing-box内核不支持geosite分流方式。如要支持，请切换1.10系列内核" && exit
fi
else
changef
fi

elif [ "$menu" = "3" ]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv4的完整域名方式的分流通道：" s4flym
if [ -z "$s4flym" ]; then
s4flym='"yg_kkk"'
else
s4flym="$(echo "$s4flym" | sed 's/ /","/g')"
s4flym="\"$
