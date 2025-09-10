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


