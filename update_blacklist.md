# Ubuntu 黑名單自動更新系統 (IP + Domain RPZ)

## 1. 簡介

本系統用於自動更新 IP 與 Domain 黑名單，並阻擋惡意連線。  
特性包括：

- 支援 BIND RPZ（Response Policy Zone）阻擋惡意 Domain
- 使用 ipset + iptables 封鎖 IP 黑名單
- 自動下載官方黑名單
- 自動比對異動，產生新增/移除統計
- 日誌完整紀錄，支援 logrotate

---

## 2. 環境需求

- Ubuntu 24.04 LTS
- 安裝套件：
  ```bash
  sudo apt update
  sudo apt install bind9 iptables ipset curl
  ```
- BIND 設定 RPZ zone：
  ```bind
  response-policy { zone "domain.rpz"; };
  zone "domain.rpz" { type master; file "/var/cache/bind/zones/db-rpz-domain"; };
  ```

---

## 3. 黑名單來源

- IP 黑名單：
  ```
  https://api.url.domain/api/get_blacklist_ip/<TOKEN>
  ```
- Domain 黑名單：
  ```
  https://api.url.domain/api/get_blacklist_dn/<TOKEN>
  ```
- 黑名單格式：
  - IP：純 IP 列表
  - Domain：RPZ zone file（包含 SOA / NS / CNAME）

---

## 4. 自動更新腳本

### 腳本路徑

```text
/etc/blacklist/update_blacklist_all.sh
```

### 核心功能

- 自動下載 IP / Domain 黑名單
- IP 黑名單：
  - 使用 ipset 建立 `blacklist`
  - 使用 iptables 封鎖
- Domain 黑名單：
  - 更新 BIND RPZ zone file
  - 自動 reload / thaw
- 異動統計：
  - 每次更新記錄新增與移除筆數
- 日誌：
  - `/var/log/blacklist_all.log`

### 腳本範例

```bash
#!/bin/bash
LOG_FILE="/var/log/update_blacklist.log"
REPORT_SUMMARY=""
MAIL_TO=""
MAIL_FROM=""

# ----------------------------
# 設定區
# ----------------------------
PROXY_SERVER=""
TOKEN_IP=""        # 你的 IP 黑名單 Token
TOKEN_DN=""        # 你的 Domain 黑名單 Token
URL_BLACKLIST_IP="https://api/$TOKEN_IP"
URL_BLACKLIST_DN="https://api/$TOKEN_DN"
IPSET_NAME=""
ZONE_FILE=""

# ----------------------------
# 函數：日誌紀錄
# ----------------------------
log_message() {
    local MSG="$1"
    echo "$(date '+%Y/%m/%d %H:%M:%S') $MSG" | tee -a "$LOG_FILE"
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

    ipset list $IPSET_NAME >/dev/null 2>&1 || ipset create $IPSET_NAME hash:ip

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
            rndc freeze nics.rpz 2>/dev/null || log_message "[WARN] rndc freeze 失敗，可能不是動態 zone。"
        fi

        mv "$TMP_ZONE" "$ZONE_FILE"
        chown bind:bind "$ZONE_FILE"

        if check_bind_service; then
            if ! rndc thaw nics.rpz; then
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
update_ip_blacklist
update_domain_blacklist
log_message "==== 黑名單更新完成 ===="

# 寄送郵件報告
if command -v mail >/dev/null 2>&1; then
    echo -e "執行完成，以下為更新摘要：\n\n$REPORT_SUMMARY" | mail -s "Update Report $(date '+%Y/%m/%d %H:%M:%S')" -r "$MAIL_FROM" "$MAIL_TO"
else
    log_message "[WARN] 'mail' 指令不存在，跳過郵件通知。"
fi
```

---

## 5. 日誌與 logrotate

### 日誌路徑

```text
/var/log/blacklist_all.log
```

### logrotate 設定

建立 `/etc/logrotate.d/blacklist_all`：

```text
/var/log/blacklist_all.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    create 644 root root
    postrotate
        systemctl restart bind9 >/dev/null 2>&1 || true
    endscript
}
```

---

## 6. 排程 (cron)

每 30 分鐘自動更新：

```bash
sudo crontab -e
```

加入：

```cron
*/30 * * * * /etc/blacklist/update_blacklist_all.sh
```

---

## 7. 日誌範例

```
[2025-09-10 15:30:01] ==== 開始更新黑名單 ====
[2025-09-10 15:30:01] IP 黑名單匯入完成，共 2793 筆，新增 12，移除 0。
[2025-09-10 15:30:01] Domain 黑名單匯入完成，共 202 筆，新增 3，移除 1。
[2025-09-10 15:30:01] ==== 黑名單更新完成 ====
```

---

## 8. 檔案位置建議

```
/usr/local/bin/update_blacklist_all.sh   # 腳本
/var/log/blacklist_all.log               # 日誌
/var/cache/bind/zones/db-rpz            # RPZ zone
```

---

## 9. RPZ 查詢統計

BIND RPZ 查詢可透過 log 分析統計：

```bash
# 確認 BIND log 位置
/var/cache/bind/logs/rpz.log

# 統計今天 zone.rpz 查詢命中次數
grep 'zone.rpz' /var/cache/bind/logs/rpz.log | grep "$(date '+%Y-%m-%d')" | wc -l

# 統計每個 domain 命中次數
grep 'zone.rpz' /var/cache/bind/logs/rpz.log | awk '{print $7}' | sort | uniq -c | sort -nr | head -20
```

> 說明：
> - `$7` 為 log 中查詢 domain 的欄位，請依實際 log 格式調整。
> - 可改為每天排程產生報表，方便監控 RPZ 命中情況。

---

## 10. 注意事項

1. 確保 BIND zone file 權限正確：`chown bind:bind /var/cache/bind/zones/db-rpz-domain`
2. IP 黑名單套用前會自動建立 ipset 並更新 iptables
3. Domain 黑名單更新會自動 reload BIND RPZ
4. 日誌檔案會自動輪替並保留 14 天

---

## 11. 參考

- [BIND RPZ 官方文件](https://www.isc.org/bind/)
- [ipset 官方文件](https://ipset.netfilter.org/)
- [iptables 官方文件](https://netfilter.org/projects/iptables/index.html)

