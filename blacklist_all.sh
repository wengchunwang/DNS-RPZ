#!/bin/bash
# Ubuntu 24.04 LTS
# 整合 IP + Domain 黑名單自動更新，並產生異動統計
# Log: /var/log/blacklist_all.log

set -euo pipefail

LOG_FILE="/var/log/blacklist_all.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

TOKENIP="123-456-789"        # 你的 IP 黑名單 Token
TOKENDN="987-654-321"        # 你的 Domain 黑名單 Token

IP_BLACKLIST_URL="https://ironcloak.nics.nat.gov.tw/api/get_blacklist_ip/$TOKENIP"
IPSET_NAME="blacklist"

DOMAIN_BLACKLIST_URL="https://ironcloak.nics.nat.gov.tw/api/get_linux_blacklist_dn/$TOKENDN"
ZONE_FILE="/var/cache/bind/zones/db-rpz-domain"

log_message() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
}

# 更新 IP 黑名單並比對異動
update_ip_blacklist() {
    log_message "==== 開始更新 IP 黑名單 ===="
    local ip_tmp="/tmp/blacklist_ip.$$"
    curl -s -o "$ip_tmp" "$IP_BLACKLIST_URL" || { log_message "[ERROR] IP 黑名單下載失敗"; return 1; }

    # 舊黑名單快照
    local ip_old="/tmp/ip_old.$$"
    ipset list $IPSET_NAME | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' > "$ip_old" 2>/dev/null || true

    # 新暫存 ipset
    ipset destroy ${IPSET_NAME}_tmp 2>/dev/null || true
    ipset create ${IPSET_NAME}_tmp hash:ip -exist
    grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' "$ip_tmp" | while read -r ip; do
        ipset add ${IPSET_NAME}_tmp "$ip" -exist
    done

    ipset list $IPSET_NAME >/dev/null 2>&1 || ipset create $IPSET_NAME hash:ip
    ipset swap ${IPSET_NAME}_tmp $IPSET_NAME
    ipset destroy ${IPSET_NAME}_tmp
    iptables -C INPUT -m set --match-set $IPSET_NAME src -j DROP 2>/dev/null || \
        iptables -I INPUT -m set --match-set $IPSET_NAME src -j DROP

    # 比對異動
    local ip_new="/tmp/ip_new.$$"
    ipset list $IPSET_NAME | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' > "$ip_new"
    local added=$(comm -13 <(sort "$ip_old") <(sort "$ip_new") | wc -l)
    local removed=$(comm -23 <(sort "$ip_old") <(sort "$ip_new") | wc -l)
    local total=$(wc -l < "$ip_new")
    log_message "IP 黑名單匯入完成，共 $total 筆，新增 $added，移除 $removed。"

    rm -f "$ip_tmp" "$ip_old" "$ip_new"
}

# 更新 Domain 黑名單並比對異動
update_domain_blacklist() {
    log_message "==== 開始更新 Domain 黑名單 ===="
    local tmp_zone="/tmp/blacklist_dn.$$"
    curl -s -o "$tmp_zone" "$DOMAIN_BLACKLIST_URL" || { log_message "[ERROR] Domain 黑名單下載失敗"; return 1; }

    if [ -s "$tmp_zone" ]; then
        # 舊檔比對
        local old_domains="/tmp/blacklist_dn_old.$$"
        local new_domains="/tmp/blacklist_dn_new.$$"
        grep 'CNAME' "$ZONE_FILE" | awk '{print $1}' > "$old_domains" 2>/dev/null || true
        grep 'CNAME' "$tmp_zone" | awk '{print $1}' > "$new_domains"

		# 對動態 zone 使用 freeze/thaw
		rndc freeze nics.rpz 2>/dev/null || true
        mv "$tmp_zone" "$ZONE_FILE"
        chown bind:bind "$ZONE_FILE"
		rndc thaw nics.rpz 2>/dev/null || systemctl reload bind9
        if ! rndc thaw nics.rpz; then
			log_message "[WARN] rndc thaw 失敗，嘗試重新載入 bind9"
			systemctl reload bind9
        fi

        local added=$(comm -13 <(sort "$old_domains") <(sort "$new_domains") | wc -l)
        local removed=$(comm -23 <(sort "$old_domains") <(sort "$new_domains") | wc -l)
        local total=$(wc -l < "$new_domains")
        log_message "Domain 黑名單匯入完成，共 $total 筆，新增 $added，移除 $removed。"

        rm -f "$old_domains" "$new_domains"
    else
        log_message "[ERROR] 下載的 Domain 黑名單為空檔，保留舊檔。"
        rm -f "$tmp_zone"
    fi
}

# ===== 主程式 =====
log_message "==== 腳本開始執行 ===="
update_ip_blacklist
update_domain_blacklist
log_message "==== 腳本執行完成 ===="
