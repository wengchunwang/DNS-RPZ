# 黑名單自動更新腳本 (Ubuntu 24.04 LTS)

本腳本用於自動更新 **IP 黑名單**（使用 ipset + iptables）以及 **Domain RPZ 黑名單**（BIND RPZ Zone），並將更新紀錄寫入日誌檔。  

---

## 功能

1. **IP 黑名單更新**
   - 從 API 下載最新 IP 黑名單。
   - 建立暫存 ipset 集合，避免直接修改正在使用的集合。
   - 更新 ipset 集合並套用到 `iptables INPUT` 鏈，阻擋惡意 IP。
   - 支援自動建立 ipset 集合與 iptables 規則。

2. **Domain 黑名單更新 (BIND RPZ)**
   - 從 API 下載最新 RPZ domain 黑名單。
   - 取代現有 zone 檔案。
   - 重新載入 BIND RPZ zone，確保新的黑名單立即生效。

3. **日誌紀錄**
   - 所有操作會寫入 `/var/log/blacklist_all.log`。
   - 記錄下載結果、匯入筆數與錯誤訊息。

---

## 腳本配置

在腳本開頭修改以下參數：

```bash
TOKENIP="123-456-789"    # IP 黑名單 API Token
TOKENDN="001-002-003"    # Domain 黑名單 API Token

IP_BLACKLIST_URL="https://url/api/get_blacklist_ip/$TOKENIP"
IPSET_NAME="blacklist"  # IPSET_NAME：ipset 集合名稱，可自訂。

DOMAIN_BLACKLIST_URL="https://url/api/get_linux_blacklist_dn/$TOKENDN"
# ZONE_FILE：BIND RPZ zone 檔案路徑，請確認 BIND 使用者有權限存取。
ZONE_FILE="/var/cache/bind/zones/db-rpz" 



# 自動封鎖腳本
 - 建立 /usr/local/bin/update_blacklist.sh

# 設定排程
 - 每天更新一次（例如凌晨 3 點）：
sudo crontab -e

0 3 * * * /usr/local/bin/update_blacklist.sh >> /var/log/update_blacklist.log 2>&1

使用方式

手動執行
sudo bash /usr/local/bin/update_blacklist_all.sh

排程自動執行
sudo crontab -e
0 * * * * /usr/local/bin/update_blacklist_all.sh

日誌檔

主日誌檔：/var/log/blacklist_all.log

記錄範例：
[2025-09-10 14:00:00] ==== 開始更新黑名單 ====
[2025-09-10 14:00:01] IP 黑名單下載完成
[2025-09-10 14:00:02] IP 黑名單匯入完成，共 2793 筆
[2025-09-10 14:00:05] Domain 黑名單匯入完成，共 1200 筆
[2025-09-10 14:00:05] ==== 黑名單更新完成 ====

檔案位置建議
/usr/local/bin/update_blacklist_all.sh   # 腳本
/var/log/blacklist_all.log               # 日誌
/var/cache/bind/zones/db-rpz       # RPZ zone



RPZ 查詢統計

BIND RPZ 查詢可透過 log 分析統計：

確認 BIND log 位置，建議配置：

/var/cache/bind/logs/rpz.log


統計 nics.rpz 命中次數：

# 統計今天 nics.rpz 查詢命中次數
grep 'nics.rpz' /var/cache/bind/logs/rpz.log | grep "$(date '+%Y-%m-%d')" | wc -l


統計每個 domain 命中次數：

grep 'nics.rpz' /var/cache/bind/logs/rpz.log | awk '{print $7}' | sort | uniq -c | sort -nr | head -20


說明：

$7 為 log 中查詢 domain 的欄位，請依實際 log 格式調整。

可改為每天排程產生報表，方便監控 RPZ 命中情況。

注意事項

BIND RPZ zone

確認 zone 名稱 (nics.rpz) 與 BIND 設定一致。

如果 zone 是動態更新 (dynamic)，更新時需使用 rndc freeze/thaw 或 rndc reload。

IP 黑名單

避免直接修改正在使用的 ipset 集合，腳本會使用暫存集合再 swap。

確保 iptables INPUT 鏈有套用正確規則。

權限

腳本需以 root 執行，以便操作 ipset、iptables 與 BIND zone 檔案。

檔案位置建議
/usr/local/bin/update_blacklist_all.sh   # 腳本
/var/log/blacklist_all.log               # 日誌
/var/cache/bind/zones/db-rpz-nics       # RPZ zone


授權

MIT License（可依需求修改）





# 驗證方式

# 查看 ipset 是否有 IP：
sudo ipset list blacklist

# 確認是否真的執行過
journalctl -u ipset-blacklist.service -b

# 確認 iptables 有規則：
sudo iptables -L INPUT -n --line-numbers


統計 zone.rpz 命中的查詢數

假設 zone 名稱出現在 log 行中，可以用：

grep 'zone.rpz' /var/cache/bind/logs/rpz.log | wc -l

3️⃣ 按網域統計命中次數
grep 'zone.rpz' /var/cache/bind/logs/rpz.log | awk '{print $7}' | sort | uniq -c | sort -nr


$7 是 query: 後面的網域名稱欄位（依你的 log 格式調整）。

這會輸出被 RPZ 攔截的網域及被查詢次數，從高到低排序。

4️⃣ 監控即時查詢
tail -f /var/cache/bind/logs/rpz.log | grep 'zone.rpz'
