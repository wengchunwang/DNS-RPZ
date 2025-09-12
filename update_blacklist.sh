#!/bin/bash
# Ubuntu 24.04 LTS
set -euo pipefail

# ----------------------------
# 設定區
# ----------------------------
PROXY_SERVER=""
LOG_FILE="/var/log/update_blacklist.log"
REPORT_SUMMARY=""
MAIL_TO="log@domain.org"    # 必填
MAIL_FROM="blacklist@server.local"
MAIL_SUBJECT=""
TOKEN_IP=""        # 你的 IP 黑名單 Token
TOKEN_DN=""        # 你的 Domain 黑名單 Token
URL_BLACKLIST_IP="https://api.url.domain/api/get_blacklist_ip/$TOKEN_IP"
URL_BLACKLIST_DN="https://api.url.domain/api/get_blacklist_dn/$TOKEN_DN"
IPSET_NAME="blacklist" # 若要更改名稱，請同時修改 iptables 規則。
ZONE_RPZ="domain.rpz"
ZONE_FILE="/var/cache/bind/zones/db-rpz-domain" #請確認下載的 RPZ zone file 已包含正確的 SOA serial，否則建議在更新時自動遞增 serial。
RUN_TYPE="${1:-manual}"  # 默認 manual

# ----------------------------
# 函數：日誌紀錄
# ----------------------------
log_message() {
    local MSG="$1"
	if [ "$RUN_TYPE" = "manual" ]; then
        # 手動執行時，同時輸出到螢幕和日誌檔案
        echo "[$(date '+%Y/%m/%d %H:%M:%S')] $MSG ($RUN_TYPE)" | tee -a "$LOG_FILE"
    else
        # 其他情況（例如 cron），只寫入日誌檔案
        echo "[$(date '+%Y/%m/%d %H:%M:%S')] $MSG ($RUN_TYPE)" >> "$LOG_FILE"
    fi
}

# ----------------------------
# 函數：檢查 ipset 是否可用
# ----------------------------
check_ipset() {
    command -v ipset >/dev/null 2>&1
}

# ----------------------------
# 函數：檢查 bind9 是否運行
# ----------------------------
check_bind_service() {
    systemctl is-active --quiet bind9
}

# ----------------------------
# 函數：更新 IP 黑名單
# ----------------------------
update_ip_blacklist() {
    log_message "==== 開始更新 IP 黑名單 ===="
    local IP_TMP="/tmp/BLACKLIST_IP.$$"

    # 設定 curl 選項
    local CURL_OPT=(-s)
    [ -n "$PROXY_SERVER" ] && CURL_OPT+=(--proxy "$PROXY_SERVER")

    curl "${CURL_OPT[@]}" -o "$IP_TMP" "$URL_BLACKLIST_IP" || {
        log_message "[ERROR] IP 黑名單下載失敗。"
        REPORT_SUMMARY+="IP 黑名單更新失敗。\n"
        return 1
    }

    local IP_OLD="/tmp/IP_OLD.$$"
    local IP_NEW="/tmp/IP_NEW.$$"

    ipset list $IPSET_NAME | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' > "$IP_OLD" 2>/dev/null || true

    ipset destroy ${IPSET_NAME}_TMP 2>/dev/null || true
    ipset create ${IPSET_NAME}_TMP hash:ip -exist
    grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' "$IP_TMP" | while read -r IP; do
        ipset add ${IPSET_NAME}_TMP "$IP" -exist
    done

    log_message "[INFO] 初始化 ipset $IPSET_NAME"

    if ! ipset list $IPSET_NAME >/dev/null 2>&1; then
            log_message "[INFO] 初始化 ipset $IPSET_NAME"
                ipset create $IPSET_NAME hash:ip
        fi

    if ipset swap ${IPSET_NAME}_TMP $IPSET_NAME; then
        log_message "IP set 交換完成。"
    else
        log_message "[WARN] IP set 交換失敗，可能存在重複的 ipset 名稱。"
    fi

    ipset destroy ${IPSET_NAME}_TMP

    iptables -C INPUT -m set --match-set $IPSET_NAME src -j DROP 2>/dev/null || \
        iptables -I INPUT -m set --match-set $IPSET_NAME src -j DROP

    ipset list $IPSET_NAME | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' > "$IP_NEW"

    local ADDED=$(comm -13 <(sort "$IP_OLD") <(sort "$IP_NEW") | wc -l)
    local REMOVED=$(comm -23 <(sort "$IP_OLD") <(sort "$IP_NEW") | wc -l)
    local TOTAL=$(wc -l < "$IP_NEW")

    if [ "$ADDED" -gt 0 ] || [ "$REMOVED" -gt 0 ]; then
        log_message "IP 黑名單匯入完成，共 $TOTAL 筆，新增 $ADDED，移除 $REMOVED。"
        REPORT_SUMMARY+="IP 黑名單更新：新增 $ADDED，移除 $REMOVED，總計 $TOTAL 筆。\n"
    else
        log_message "IP 黑名單無異動，共 $TOTAL 筆。"
        REPORT_SUMMARY+="IP 黑名單更新：無異動，總計 $TOTAL 筆。\n"
    fi

    rm -f "$IP_TMP" "$IP_OLD" "$IP_NEW"
    return 0
}

# ----------------------------
# 函數：更新 Domain 黑名單
# ----------------------------
update_domain_blacklist() {
    log_message "==== 開始更新 Domain 黑名單 ===="
    local TMP_ZONE="/tmp/BLACKLIST_DN.$$"

    # 設定 curl 選項
    local CURL_OPT=(-s)
    [ -n "$PROXY_SERVER" ] && CURL_OPT+=(--proxy "$PROXY_SERVER")

    curl "${CURL_OPT[@]}" -o "$TMP_ZONE" "$URL_BLACKLIST_DN" || {
        log_message "[ERROR] Domain 黑名單下載失敗。"
        REPORT_SUMMARY+="Domain 黑名單更新失敗。\n"
        return 1
    }

    if [ -s "$TMP_ZONE" ]; then
        local OLD_DOMAINS="/tmp/BLACKLIST_DN_OLD.$$"
        local NEW_DOMAINS="/tmp/BLACKLIST_DN_NEW.$$"
        grep 'CNAME' "$ZONE_FILE" | awk '{print $1}' > "$OLD_DOMAINS" 2>/dev/null || true
        grep 'CNAME' "$TMP_ZONE" | awk '{print $1}' > "$NEW_DOMAINS"

        if check_bind_service; then
            log_message "偵測到 bind9 服務正在運行。"
            rndc freeze $ZONE_RPZ 2>/dev/null || log_message "[WARN] rndc freeze 失敗，可能不是動態 zone。"
        fi

        cp "$TMP_ZONE" "$ZONE_FILE.new"
                named-checkzone $ZONE_RPZ "$ZONE_FILE.new" && mv "$ZONE_FILE.new" "$ZONE_FILE"

        chown bind:bind "$ZONE_FILE"

        if check_bind_service; then
            if ! rndc thaw $ZONE_RPZ; then
                log_message "[WARN] rndc thaw 失敗，嘗試重新載入 bind9。"
                systemctl reload bind9
            fi
        else
            log_message "[INFO] bind9 服務未運行，跳過 rndc 相關操作。"
        fi

        local ADDED=$(comm -13 <(sort "$OLD_DOMAINS") <(sort "$NEW_DOMAINS") | wc -l)
        local REMOVED=$(comm -23 <(sort "$OLD_DOMAINS") <(sort "$NEW_DOMAINS") | wc -l)
        local TOTAL=$(wc -l < "$NEW_DOMAINS")

        if [ "$ADDED" -gt 0 ] || [ "$REMOVED" -gt 0 ]; then
            log_message "Domain 黑名單匯入完成，共 $TOTAL 筆，新增 $ADDED，移除 $REMOVED。"
            REPORT_SUMMARY+="Domain 黑名單更新：新增 $ADDED，移除 $REMOVED，總計 $TOTAL 筆。\n"
        else
            log_message "Domain 黑名單無異動，共 $TOTAL 筆。"
            REPORT_SUMMARY+="Domain 黑名單更新：無異動，總計 $TOTAL 筆。\n"
        fi

        rm -f "$OLD_DOMAINS" "$NEW_DOMAINS"
    else
        log_message "[ERROR] 下載的 Domain 黑名單為空檔，保留舊檔。"
        REPORT_SUMMARY+="Domain 黑名單下載為空檔，更新失敗。\n"
        rm -f "$TMP_ZONE"
    fi
    return 0
}

# ----------------------------
# 主程式
# ----------------------------
log_message "==== 開始黑名單更新流程 ===="

# ----------------------------
# IP 黑名單更新
# ----------------------------
if check_ipset; then
    log_message "偵測到 ipset 可用，開始更新 IP 黑名單..."
    update_ip_blacklist || log_message "[WARN] IP 黑名單更新失敗，繼續執行 Domain 更新"
else
    log_message "系統未安裝 ipset，跳過 IP 黑名單更新。"
fi
if check_bind_service; then
    log_message "偵測到 bind9 服務正在運行，開始更新 Domain 黑名單..."
    # 執行 Domain 黑名單更新程式區塊
    update_domain_blacklist || log_message "[WARN] Domain 黑名單更新失敗"
else
    log_message "系統未安裝或未啟動 bind9，跳過 Domain 黑名單更新。"
fi
log_message "==== 黑名單更新完成 ===="

# 寄送郵件報告
if command -v mail >/dev/null 2>&1; then
    STATUS="SUCCESS"
    [[ "$REPORT_SUMMARY" =~ "失敗" ]] && STATUS="FAIL"
    MAIL_SUBJECT="[$STATUS] $(hostname) $(date '+%Y-%m-%d %H:%M')"
    MAIL_BODY="主機: $(hostname) \n\n時間: $(date '+%Y-%m-%d %H:%M:%S') \n\n執行完成，以下為更新摘要：\n\n$REPORT_SUMMARY"
    echo -e "$MAIL_BODY" | mail -s "$MAIL_SUBJECT" -r "$MAIL_FROM" "$MAIL_TO"
else
    log_message "[WARN] 'mail' 指令不存在，跳過郵件通知。"
fi
