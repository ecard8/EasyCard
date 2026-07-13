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

需要: `curl` 或 `wget`、`tar`、**root**；支持 **amd64 / arm64**。

推荐写法（与宝塔面板类似：先下载到本地再执行，避免 `curl|bash` 管道问题）：

```bash
if [ -f /usr/bin/curl ];then curl -sSO https://raw.githubusercontent.com/ecard8/EasyCard/main/install.sh;else wget -O install.sh https://raw.githubusercontent.com/ecard8/EasyCard/main/install.sh;fi;bash install.sh -y
```

指定版本 / 目录 / 端口:

```bash
bash install.sh --version 1.0.0 --dir /opt/easycard --port 8080 -y
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

建议本机监听 `127.0.0.1:8080`，由 Nginx / Apache 对外提供 HTTPS 后转发到 EasyCard。

### `config.json`

```json
{
  "listen": "127.0.0.1:8080",
  "db_path": "data/data.db",
  "base_url": "https://shop.example.com",
  "trusted_proxies": ["127.0.0.1", "::1"]
}
```

- `base_url`：对外访问地址（含 `https://`，无尾斜杠），须与域名一致  
- `trusted_proxies`：反代可信 IP；同机反代填 `127.0.0.1` 即可  

暂不建议子路径部署（如 `/shop/`），请用独立域名或子域名反代到根路径 `/`。

### Nginx

整站反代（独立站点推荐）：

```nginx
location ^~ / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

**务必使用 `^~`**，否则宝塔默认的 `location ~* \.(js|css)$` 会优先匹配管理端 `/admin/assets/*.js|css`，在网站根目录找文件失败 → **404 白屏**（页面 HTML 能开、favicon 正常，但 JS/CSS 挂）。

若必须保留站点其它静态缓存规则，至少保证下列前缀走反代：

```nginx
location ^~ /admin/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
location ^~ /api/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
location ^~ /static/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

改完后：`nginx -t && nginx -s reload`，浏览器强制刷新（Ctrl+F5）。

自检：直接打开 `http://服务器IP:8080/admin` 若正常、走域名却白屏，就是 Nginx 未把 `/admin/assets/` 转到后端。
### Apache

在已有 VirtualHost 中加入：

```apache
    ProxyPass        / http://127.0.0.1:8080/
    ProxyPassReverse / http://127.0.0.1:8080/
```

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
