# 自動封鎖腳本
 - 建立 /usr/local/bin/update_blacklist.sh

# 設定排程
 - 每天更新一次（例如凌晨 3 點）：
sudo crontab -e

0 3 * * * /usr/local/bin/update_blacklist.sh >> /var/log/update_blacklist.log 2>&1


# 驗證方式

# 查看 ipset 是否有 IP：
sudo ipset list blacklist

# 確認是否真的執行過
journalctl -u ipset-blacklist.service -b

# 確認 iptables 有規則：
sudo iptables -L INPUT -n --line-numbers


統計 nics.rpz 命中的查詢數

假設 zone 名稱出現在 log 行中，可以用：

grep 'nics.rpz' /var/cache/bind/logs/rpz.log | wc -l

3️⃣ 按網域統計命中次數
grep 'nics.rpz' /var/cache/bind/logs/rpz.log | awk '{print $7}' | sort | uniq -c | sort -nr


$7 是 query: 後面的網域名稱欄位（依你的 log 格式調整）。

這會輸出被 RPZ 攔截的網域及被查詢次數，從高到低排序。

4️⃣ 監控即時查詢
tail -f /var/cache/bind/logs/rpz.log | grep 'nics.rpz'
