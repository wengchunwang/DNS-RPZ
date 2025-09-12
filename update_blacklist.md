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
  sudo apt install bind9 iptables ipset curl mailutils
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
/usr/local/bin/update_blacklist.sh
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
  - `/var/log/update_blacklist.log`

### 腳本範例

```bash
#!/bin/bash

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
update_ip_blacklist || log_message "[WARN] IP 黑名單更新失敗，繼續執行 Domain 更新"
update_domain_blacklist || log_message "[WARN] Domain 黑名單更新失敗"
log_message "==== 黑名單更新完成 ===="

# 寄送郵件報告
if command -v mail >/dev/null 2>&1; then
    STATUS="SUCCESS"
    [[ "$REPORT_SUMMARY" =~ "失敗" ]] && STATUS="FAIL"
    MAIL_SUBJECT="[Blacklist Update][$STATUS] $(hostname) $(date '+%Y-%m-%d %H:%M')"
    MAIL_BODY="主機: $(hostname) \n\n 時間: $(date '+%Y-%m-%d %H:%M:%S') \n\n執行完成，以下為更新摘要：\n\n$REPORT_SUMMARY"
    echo -e "$MAIL_BODY" | mail -s "$MAIL_SUBJECT" -r "$MAIL_FROM" "$MAIL_TO"
else
    log_message "[WARN] 'mail' 指令不存在，跳過郵件通知。"
fi
```

---

## 5. 日誌與 logrotate

### 日誌路徑 

```text
/var/log/update_blacklist.log
```
確保 /var/log/update_blacklist.log 所有者為 root，並允許 blacklist 腳本追加寫入。

### logrotate 設定

建立 `/etc/logrotate.d/update_blacklist`：

```text
/var/log/update_blacklist.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    create 640 root adm
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
# 建議將 stderr 一併導入 log
@reboot /usr/local/bin/update_blacklist.sh boot >> /var/log/update_blacklist.log 2>&1
30 6 * * * /usr/local/bin/update_blacklist.sh cron >> /var/log/update_blacklist.log 2>&1
```

# 建議：也可改放 /etc/cron.d/update_blacklist

---

## 7. 日誌範例

```
[2025/09/01 06:30:00] ==== 開始黑名單更新流程 ==== (cron)
[2025/09/01 06:30:00] ==== 開始更新 IP 黑名單 ==== (cron)
[2025/09/01 06:30:00] [INFO] 初始化 ipset blacklist_nics (cron)
[2025/09/01 06:30:00] IP set 交換完成。 (cron)
[2025/09/01 06:30:00] IP 黑名單無異動，共 2791 筆。 (cron)
[2025/09/01 06:30:00] ==== 開始更新 Domain 黑名單 ==== (cron)
[2025/09/01 06:30:00] 偵測到 bind9 服務正在運行。 (cron)
[2025/09/01 06:30:00] Domain 黑名單無異動，共 205 筆。 (cron)
[2025/09/01 06:30:00] ==== 黑名單更新完成 ==== (cron)
```

---

## 8. 檔案位置建議

```
/usr/local/bin/update_blacklist.sh   # 腳本
/var/log/update_blacklist.log               # 日誌
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
> - `$7` 可能依 BIND log 格式不同而需調整，請先 tail -f /var/cache/bind/logs/rpz.log 確認欄位。
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
