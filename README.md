# DNS-RPZ  
## DNS Sinkhole / DNS Firewalls / DNS RPZ  

### 📌 DNS RPZ（回應政策區域，Response Policy Zone）

---

## Windows Server (2016 以上)  

Windows Server 2016 以上提供 **DNS Policy** 設定功能，可達成阻擋特定域名的效果。  

常用指令：  

| 指令 | 說明 |
|------|------|
| `Get-DnsServerQueryResolutionPolicy` | 取得 DNS 伺服器現有網域查詢解析規則 |
| `Add-DnsServerQueryResolutionPolicy` | 新增網域查詢解析規則至 DNS 伺服器 |
| `Remove-DnsServerQueryResolutionPolicy` | 從 DNS 伺服器中刪除網域查詢解析規則 |

---

## Bind DNS Server (9.10 以上)  

Bind 9.10 以上提供 **RPZ (Response Policy Zone)** 功能。  

### `named.conf.options`  
```conf
options {
  response-policy {
    zone "local.rpz";
  };
};
```

### `named.conf.default-zones`  
```conf
zone "local.rpz" {
  type master;
  file "zones/db-rpz-local";
  allow-query { localhost; };
  allow-transfer { localhost; };
};
```
