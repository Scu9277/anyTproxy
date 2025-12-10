#!/bin/bash
# IPv4-only TProxy for sing-box (Gateway/PREROUTING Only)
# 集成 AnyLink VPN 流量支持

LOG_FILE="/var/log/tproxy.log"
TPROXY_PORT=9420
TPROXY_MARK=0x2333
TABLE_ID=100
DOCKER_PORT=9277
CHAIN_NAME="TPROXY_CHAIN"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始加载 IPv4 TProxy + AnyLink 规则 (链: $CHAIN_NAME)..." | tee -a "$LOG_FILE"

# 自动检测主网卡和IP（注意：这个检测可能在复杂网络环境下不准确，如果AnyLink的MASQUERADE行出错，请手动指定ens5）
MAIN_IF=$(ip -4 route show default | grep -oP '(?<=dev )\S+' | head -n1)
MAIN_IP=$(ip -4 addr show "$MAIN_IF" | grep inet | awk '{print $2}' | cut -d/f1 | head -n1)
echo "检测到主网卡: $MAIN_IF ($MAIN_IP)" | tee -a "$LOG_FILE"

# ---- 安全清理旧规则 ----
# 清理跳转规则
iptables -t mangle -D PREROUTING -j $CHAIN_NAME 2>/dev/null || true
# 清空并删除旧链
iptables -t mangle -F $CHAIN_NAME 2>/dev/null || true
iptables -t mangle -X $CHAIN_NAME 2>/dev/null || true
# 清理策略路由
ip rule del fwmark $TPROXY_MARK table $TABLE_ID 2>/dev/null || true
ip route flush table $TABLE_ID 2>/dev/null || true
# 清理 AnyLink 相关的 NAT 规则
iptables -D FORWARD -s 10.21.13.0/24 -j ACCEPT 2>/dev/null || true
iptables -t nat -D POSTROUTING -s 10.21.13.0/24 -o $MAIN_IF -j MASQUERADE 2>/dev/null || true


# ---- 创建新链 ----
iptables -t mangle -N $CHAIN_NAME

# ---- 规则详情 ----

# 1. 豁免本地、局域网、Docker 订阅端口 9277
# 注意：移除了 10.0.0.0/8，以确保 AnyLink 的 10.21.13.0/24 流量能被捕获进行 TPROXY
for net in 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 255.255.255.255; do
  iptables -t mangle -A $CHAIN_NAME -d $net -j RETURN
done

iptables -t mangle -A $CHAIN_NAME -p tcp --dport $DOCKER_PORT -j RETURN
iptables -t mangle -A $CHAIN_NAME -p udp --dport $DOCKER_PORT -j RETURN

# 2. 添加 TProxy 转发
# 阻止 DTLS UDP 443 流量，因为 sing-box 通常只处理标准 TCP/UDP 代理
iptables -t mangle -A $CHAIN_NAME -p udp --dport 443 -j REJECT

iptables -t mangle -A $CHAIN_NAME -p tcp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark $TPROXY_MARK
iptables -t mangle -A $CHAIN_NAME -p udp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark $TPROXY_MARK

# 3. Hook 链 (!! 重点：跳转到我们的 *自定义链* !!)
iptables -t mangle -I PREROUTING -j $CHAIN_NAME

# 4. 策略路由
ip rule add fwmark $TPROXY_MARK table $TABLE_ID
ip route add local default dev lo table $TABLE_ID

# 5. AnyLink VPN 兼容规则（允许转发和源地址伪装）
# 确保 IP 转发已开启
sysctl -w net.ipv4.ip_forward=1
# 允许 AnyLink VPN 网段的流量转发
iptables -A FORWARD -s 10.21.13.0/24 -j ACCEPT
# 对外网卡进行 NAT 伪装，使流量能够正常出站（请确认 $MAIN_IF 变量或手动修改为 ens5）
iptables -t nat -A POSTROUTING -s 10.21.13.0/24 -o $MAIN_IF -j MASQUERADE

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ IPv4 TProxy + AnyLink 规则加载完成" | tee -a "$LOG_FILE"
