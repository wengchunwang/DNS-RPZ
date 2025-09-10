#!/bin/bash
# 更新並套用 IP 黑名單
# Ubuntu 24.04 + ipset + iptables

BLACKLIST_URL="https://ironcloak.nics.nat.gov.tw/api/get_blacklist_ip/TokenKey"
BLACKLIST_FILE="/etc/firewall/blacklist_ip"
IPSET_NAME="blacklist"

# 建立目錄
mkdir -p /etc/firewall

# 下載最新黑名單
curl -s -o "$BLACKLIST_FILE" "$BLACKLIST_URL"

# 如果下載失敗或檔案空白就退出
if [ ! -s "$BLACKLIST_FILE" ]; then
    echo "[ERROR] 黑名單下載失敗或為空"
    exit 1
fi

# 建立暫時 ipset
ipset create ${IPSET_NAME}_tmp hash:ip -exist

# 載入黑名單到暫時 ipset
while IFS= read -r ip; do
    [[ -n "$ip" ]] && ipset add ${IPSET_NAME}_tmp "$ip" -exist
done < "$BLACKLIST_FILE"

# 用新的取代舊的
ipset swap ${IPSET_NAME}_tmp $IPSET_NAME 2>/dev/null || {
    ipset create $IPSET_NAME hash:ip
    ipset swap ${IPSET_NAME}_tmp $IPSET_NAME
}
ipset destroy ${IPSET_NAME}_tmp

# 確認 iptables 已有規則
iptables -C INPUT -m set --match-set $IPSET_NAME src -j DROP 2>/dev/null
if [ $? -ne 0 ]; then
    iptables -I INPUT -m set --match-set $IPSET_NAME src -j DROP
fi

echo "[OK] 黑名單已更新並套用，共 $(wc -l < $BLACKLIST_FILE) 筆"
