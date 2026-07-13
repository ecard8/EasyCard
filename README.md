# EasyCard（易发卡）安装与下载

> 本仓库**仅提供发行包与安装说明**，不包含业务源代码。

易发卡 / EasyCard 是一款自助虚拟卡密发卡系统，单文件部署（二进制名 `cardgo`）。

- 官网: [https://ecard8.com](https://ecard8.com)
- 发行包: 本仓库 [Releases](https://github.com/ecard8/EasyCard/releases)

## 支持的平台

| 平台 | 归档文件 |
|------|----------|
| Windows x64 | `EasyCard-<版本>-windows-amd64.zip` |
| Linux x64 | `EasyCard-<版本>-linux-amd64.tar.gz` |
| Linux ARM64 | `EasyCard-<版本>-linux-arm64.tar.gz` |

归档内可执行文件名均为 **`cardgo`**（Windows 为 `cardgo.exe`）。

---

## Linux 一键安装（推荐）

需要: `curl`、`tar`、root 权限；支持 **amd64 / arm64**。

```bash
curl -fsSL https://raw.githubusercontent.com/ecard8/EasyCard/main/install.sh | sudo bash
```

指定版本 / 目录 / 端口:

```bash
curl -fsSL https://raw.githubusercontent.com/ecard8/EasyCard/main/install.sh -o install.sh
sudo bash install.sh --version 1.0.0 --dir /opt/easycard --port 8080
```

安装脚本会:

1. 从 GitHub Release 下载对应架构的 `EasyCard-*-linux-*.tar.gz`
2. 安装到 `/opt/easycard`（可用 `--dir` 修改）
3. 创建系统用户 `easycard` 与 systemd 服务 `easycard`
4. 生成默认 `config.json`（若不存在）
5. 启动服务

首次打开管理端完成安装向导:

```text
http://服务器IP:8080/admin
```

### 常用运维命令

```bash
systemctl status easycard
systemctl restart easycard
journalctl -u easycard -f
```

升级（保留数据与配置）:

```bash
sudo bash install.sh --version 1.0.1 -y
# 或安装最新版
sudo bash install.sh -y
```

卸载（**会保留数据目录**，按需自行删除）:

```bash
sudo systemctl disable --now easycard
sudo rm -f /etc/systemd/system/easycard.service
sudo systemctl daemon-reload
# 可选: sudo rm -rf /opt/easycard
```

---

## Linux 手动安装

```bash
# 以 1.0.0 / amd64 为例
VER=1.0.0
ARCH=amd64   # 或 arm64
curl -fLO "https://github.com/ecard8/EasyCard/releases/download/v${VER}/EasyCard-${VER}-linux-${ARCH}.tar.gz"
curl -fLO "https://github.com/ecard8/EasyCard/releases/download/v${VER}/SHA256SUMS"
sha256sum -c SHA256SUMS --ignore-missing

mkdir -p /opt/easycard/data
tar -xzf "EasyCard-${VER}-linux-${ARCH}.tar.gz" -C /opt/easycard
chmod +x /opt/easycard/cardgo
cd /opt/easycard
./cardgo
```

可选 `config.json`（首次也可由程序自动生成，或走 `/admin` 安装向导）:

```json
{
  "listen": ":8080",
  "db_path": "data/data.db",
  "base_url": "http://你的域名或IP:8080"
}
```

反向代理时请正确设置 `base_url`（含 `https://`），并配置 `trusted_proxies`（见下一节）。

---

## 反向代理（Nginx / Apache）

生产环境建议：本机只监听 `127.0.0.1:8080`，由 Nginx / Apache 对外提供 **HTTPS**，再转发到 EasyCard。

### 1. 调整 `config.json`

```json
{
  "listen": "127.0.0.1:8080",
  "db_path": "data/data.db",
  "base_url": "https://shop.example.com",
  "trusted_proxies": ["127.0.0.1", "::1"]
}
```

| 字段 | 作用 |
|------|------|
| `listen` | 仅本机访问时写 `127.0.0.1:8080`，避免绕过反代直连 |
| `base_url` | **对外完整地址**（支付回调等依赖它），须与浏览器域名一致，含 `https://`，末尾不要斜杠 |
| `trusted_proxies` | 可信反代 IP/CIDR。填写后才信任 `X-Forwarded-*`；同机反代填 `127.0.0.1` 即可 |

修改后重启服务：

```bash
sudo systemctl restart easycard
```

### 2. Nginx 示例（HTTPS）

域名以 `shop.example.com` 为例（证书路径按实际修改，也可用 Certbot）。

```nginx
# /etc/nginx/sites-available/easycard
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name shop.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name shop.example.com;

    ssl_certificate     /etc/nginx/ssl/shop.example.com.fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/shop.example.com.key;

    client_max_body_size 32m;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host  $host;

        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
```

启用并重载：

```bash
sudo ln -sf /etc/nginx/sites-available/easycard /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

Certbot（Let's Encrypt）：

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d shop.example.com
```

### 3. Apache 示例（HTTPS）

需启用模块：`proxy`、`proxy_http`、`ssl`、`headers`、`rewrite`。

```apache
# /etc/apache2/sites-available/easycard.conf
<VirtualHost *:80>
    ServerName shop.example.com
    RewriteEngine On
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>

<VirtualHost *:443>
    ServerName shop.example.com

    SSLEngine on
    SSLCertificateFile      /etc/ssl/certs/shop.example.com.fullchain.pem
    SSLCertificateKeyFile   /etc/ssl/private/shop.example.com.key

    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port "443"

    ProxyPass        / http://127.0.0.1:8080/
    ProxyPassReverse / http://127.0.0.1:8080/

    # 卡密导入等上传
    LimitRequestBody 33554432
</VirtualHost>
```

启用站点：

```bash
sudo a2enmod proxy proxy_http ssl headers rewrite
sudo a2ensite easycard
sudo apache2ctl configtest && sudo systemctl reload apache2
```

Certbot：

```bash
sudo apt install -y certbot python3-certbot-apache
sudo certbot --apache -d shop.example.com
```

### 4. 验证清单

1. 打开 `https://shop.example.com/admin`，管理端可正常访问  
2. `base_url` 必须为 `https://shop.example.com`（与证书域名一致）  
3. 支付回调基于 `base_url` 生成；换域名后请检查支付渠道回调配置  
4. 若客户端 IP 异常，检查 `trusted_proxies` 是否包含反代地址  

**注意：** 暂不建议子路径部署（如 `https://example.com/shop/`），请使用独立域名或子域名，反代到根路径 `/`。


---

## Windows 安装

1. 打开 [Releases](https://github.com/ecard8/EasyCard/releases)，下载  
   `EasyCard-<版本>-windows-amd64.zip`
2. 解压到任意目录（例如 `D:\EasyCard\`）
3. 双击或在终端运行 `cardgo.exe`
4. 浏览器访问 `http://127.0.0.1:8080/admin` 完成首次安装

建议使用管理员权限开放防火墙入站端口（默认 8080）。  
数据文件默认写在程序目录下的 `data.db` / `config.json`（以实际配置为准）。

---

## 校验下载

每个 Release 附带 `SHA256SUMS`。Linux / macOS:

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

PowerShell:

```powershell
Get-FileHash .\EasyCard-1.0.0-windows-amd64.zip -Algorithm SHA256
```

---

## 安全提示

- 请妥善备份 `config.json` 中的 `aes_key` 与数据库文件；密钥丢失将无法解密已有卡密。
- 生产环境建议置于反向代理之后，启用 HTTPS，并限制管理端访问来源。
- 本仓库不含源码；如需商业授权或定制请通过官网联系。

## License / 声明

发行包版权归 EasyCard / 易发卡所有。未经授权请勿反编译、二次分发商业源码等价物。
