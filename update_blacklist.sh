#!/bin/bash
# Ubuntu 24.04 LTS
# 整合 IP 黑名單 + Domain RPZ 黑名單自動更新
# Log: /var/log/blacklist_all.log

set -euo pipefail

LOG_FILE="/var/log/blacklist_all.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# ====== 配置 ======
TOKENIP="123-456-789"    # 你的 IP 黑名單 Token
TOKENDN="001-002-003"    # 你的 Domain 黑名單 Token

IP_BLACKLIST_URL="https://ironcloak.nics.nat.gov.tw/api/get_blacklist_ip/$TOKENIP"
IPSET_NAME="blacklist_nics"

DOMAIN_BLACKLIST_URL="https://ironcloak.nics.nat.gov.tw/api/get_linux_blacklist_dn/$TOKENDN"
ZONE_FILE="/var/cache/bind/zones/db-rpz-nics"

# ====== 開始 ======
echo "[$TIMESTAMP] ==== 開始更新黑名單 ====" >> "$LOG_FILE"

### ---------------------------
### IP 黑名單更新 (ipset + iptables)
### ---------------------------
IP_TMP="/tmp/blacklist_ip.$$"

# 下載 IP 黑名單
if curl -s -o "$IP_TMP" "$IP_BLACKLIST_URL"; then
    echo "[$TIMESTAMP] IP 黑名單下載完成" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] [ERROR] IP 黑名單下載失敗" >> "$LOG_FILE"
    rm -f "$IP_TMP"
fi

# 建立暫存 ipset
ipset destroy ${IPSET_NAME}_tmp 2>/dev/null || true
ipset create ${IPSET_NAME}_tmp hash:ip -exist

# 匯入 IP
grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' "$IP_TMP" | while read -r ip; do
    ipset add ${IPSET_NAME}_tmp "$ip" -exist
done

# 建立正式 ipset，如果不存在
ipset list $IPSET_NAME >/dev/null 2>&1 || ipset create $IPSET_NAME hash:ip

# swap 暫存集合到正式集合
ipset swap ${IPSET_NAME}_tmp $IPSET_NAME
ipset destroy ${IPSET_NAME}_tmp

# 確認 iptables 規則
iptables -C INPUT -m set --match-set $IPSET_NAME src -j DROP 2>/dev/null || \
    iptables -I INPUT -m set --match-set $IPSET_NAME src -j DROP

IP_COUNT=$(ipset list $IPSET_NAME | grep -c '^[0-9]')
echo "[$TIMESTAMP] IP 黑名單匯入完成，共 $IP_COUNT 筆" >> "$LOG_FILE"
rm -f "$IP_TMP"

### ---------------------------
### Domain 黑名單更新 (BIND RPZ)
### ---------------------------
TMP_ZONE="/tmp/db-rpz-nics.$$"

curl -s "$DOMAIN_BLACKLIST_URL" -o "$TMP_ZONE"

if [ -s "$TMP_ZONE" ]; then
    mv "$TMP_ZONE" "$ZONE_FILE"
    chown bind:bind "$ZONE_FILE"

    # 重新載入 BIND
    rndc reload nics.rpz || systemctl reload bind9

    DOMAIN_COUNT=$(grep -c 'CNAME' "$ZONE_FILE")
    echo "[$TIMESTAMP] Domain 黑名單匯入完成，共 $DOMAIN_COUNT 筆" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] [ERROR] Domain 黑名單下載失敗，保留舊檔" >> "$LOG_FILE"
    rm -f "$TMP_ZONE"
fi

echo "[$TIMESTAMP] ==== 黑名單更新完成 ====" >> "$LOG_FILE"
