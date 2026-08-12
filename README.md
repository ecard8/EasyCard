# EasyCard 易卡数字平台安装与部署

发布候选部署后，请按 [目标环境与真实渠道验收手册](../docs/acceptance-runbook.zh-CN.md) 执行只读预检、首装/升级/回退、灾难恢复和计划启用渠道验收。发行包内同时附带 `ACCEPTANCE.zh-CN.md`、`acceptance.sh` 与 `acceptance-preflight.ps1`。

> 本仓库**仅提供发行包与安装说明**，不包含业务源代码。

EasyCard 易卡数字平台是一套数字商品智能交易与自动交付平台，采用单文件部署（二进制名 `cardgo`）。

- 官网: [https://www.ecard8.com](https://www.ecard8.com)
- 发行包: 本仓库 [Releases](https://github.com/ecard8/EasyCard/releases)

## 支持的平台

| 平台 | 归档文件 |
|------|----------|
| Windows x64 | `EasyCard-<版本>-windows-amd64.zip` |
| Windows ARM64 | `EasyCard-<版本>-windows-arm64.zip` |
| Linux x64 | `EasyCard-<版本>-linux-amd64.tar.gz` |
| Linux ARM64 | `EasyCard-<版本>-linux-arm64.tar.gz` |
| macOS Intel | `EasyCard-<版本>-darwin-amd64.tar.gz` |
| macOS Apple Silicon | `EasyCard-<版本>-darwin-arm64.tar.gz` |

归档内可执行文件名均为 **`cardgo`**（Windows 为 `cardgo.exe`）。

`EasyCard-*` 归档名、`ecard8/EasyCard` 仓库路径、`easycard` 服务用户/目录是现有发行与升级链路的兼容标识，品牌升级阶段继续保留；产品展示名称统一为 EasyCard。

> **候选版升级期限：**`v1.1.0-rc.2` 客户端网页可使用至站点时区 `2026-12-30`；从 `2026-12-31 00:00` 起商城与客户中心要求升级。管理后台、`easycard update`、健康检查、API 与支付回调继续可用，因此可以安全完成升级。

---

## Linux 一键安装（推荐）

需要: `curl` 或 `wget`、`tar`、**root**；支持 **amd64 / arm64**。

推荐写法（与宝塔面板类似：先下载到本地再执行，避免 `curl|bash` 管道问题）：

```bash
if [ -f /usr/bin/curl ];then curl -sSO https://raw.githubusercontent.com/ecard8/EasyCard/main/install.sh;else wget -O install.sh https://raw.githubusercontent.com/ecard8/EasyCard/main/install.sh;fi;bash install.sh -y
```

默认自动安装最近公开发布的版本（包含预发布）；也可指定目录 / 端口:

```bash
bash install.sh --dir /opt/easycard --port 18765 -y
```

需要复现、回滚或受控验收时，可额外使用 `--version 1.1.0-rc.2` 固定版本。

安装脚本会:

1. 从 GitHub Release 下载对应架构的 `EasyCard-*-linux-*.tar.gz`
2. 使用 `SHA256SUMS` 校验归档，并执行候选程序的 `-version` 核对版本
3. 安装到 `/opt/easycard`（可用 `--dir` 修改）
4. 创建最小权限系统用户 `easycard` 与加固后的 systemd 服务 `easycard`
5. 生成默认 `config.json`（若不存在）并始终保留已有配置、数据库和上传文件
6. 启动后轮询 `/health/ready`；30 秒内未就绪则自动恢复上一版本二进制
7. 安装 `/usr/local/bin/easycard` 管理命令，用统一入口管理 systemd、日志和安全更新

首次打开管理端完成安装向导:

```text
http://服务器IP:18765/admin
```

安装向导按以下顺序进行：

1. 阅读软件许可、免责声明和店铺经营者责任声明，并通过一个组合勾选确认同意这些文件；
2. 创建首位管理员，填写显示名称、唯一邮箱、强密码和监听端口；
3. 安装完成后登录后台；如使用反向代理，再到“系统设置 → 网络与代理”独立配置。首次安装不要求代理地址或令牌。

> **安全警告：**初始化完成前不要将监听端口开放到公网。先通过本机、SSH 隧道或临时受限访问完成管理员初始化，再配置 HTTPS 入口。

未初始化且仍使用默认 18765 时，若该端口被占用，程序会从 18766 起自动选择可用端口；以控制台打印的实际安装地址为准，`base_url` 不随之改变。已安装实例或自定义端口被占用时，启动会直接失败。

### 常用运维命令

```bash
easycard                 # 打开单次操作菜单；执行所选操作后直接退出
easycard status
easycard start
easycard stop
easycard restart
easycard update          # 更新到最近公开版本
easycard update 1.1.0-rc.2
easycard port             # 查看当前监听端口
easycard port 9090        # 安全更换监听端口
easycard logs 200
easycard logs -f
```

同时兼容 `easycard -restart`、`easycard -stop`、`easycard -start`、`easycard -update`、`easycard -port`。服务变更与更新需要 root 权限，普通账户使用 `sudo easycard <命令>`。`easycard update` 会复用一键安装器的架构识别、SHA-256、候选版本身份、健康检查和自动二进制回滚，不会绕过发布校验。`easycard port` 修改前检查占用，修改后验证健康并在失败时恢复原配置；它只修改 `listen`，不会修改可能由反向代理管理的 `base_url`。

升级（保留数据与配置）:

```bash
sudo bash install.sh --version 1.0.1 -y
# 或自动安装最近公开版本（包含预发布）
sudo bash install.sh -y
```

升级前仍建议在管理后台创建并验证一份完整备份。脚本的自动回滚只恢复上一版本程序，不回滚已经执行的数据库迁移；跨版本降级必须先核对目标版本的数据兼容性，必要时使用升级前完整备份恢复。

卸载（**会保留数据目录**，按需自行删除）:

```bash
sudo systemctl disable --now easycard
sudo rm -f /etc/systemd/system/easycard.service
sudo rm -f /usr/local/bin/easycard /etc/easycard/manager.conf
sudo systemctl daemon-reload
# 可选: sudo rm -rf /opt/easycard
```

---

## Linux 手动安装

```bash
# 以 1.1.0-rc.2 / amd64 为例
VER=1.1.0-rc.2
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
  "listen": "18765",
  "db_path": "data/data.db",
  "base_url": "http://你的域名或IP:18765",
  "proxy_mode": "direct"
}
```

监听端口与 `base_url` 相互独立，修改一项不会自动改另一项。修改 `listen` 时编辑 `config.json`，通过 systemd/容器编排执行受控重启，再验证 `/health` 和 `/health/ready`。`proxy_mode` 与 `trusted_proxies` 可在安装完成后通过“系统设置 → 网络与代理”独立保存；有效值变化会触发服务自动重启，恢复后还应验证真实客户端 IP。

---

## 反向代理（Nginx / Apache）

纯端口 `"18765"` 等价于旧格式 `":18765"`，监听所有接口；只有需要限制网卡时才写 `"127.0.0.1:18765"`。生产环境建议本机监听 `127.0.0.1:18765`，由 Nginx / Apache 对外提供 HTTPS 后转发到 EasyCard。

### `config.json`

```json
{
  "listen": "127.0.0.1:18765",
  "db_path": "data/data.db",
  "base_url": "https://shop.example.com",
  "proxy_mode": "local_proxy"
}
```

- `base_url`：对外访问地址（含 `https://`，无尾斜杠），须与域名一致  
- `proxy_mode: "direct"`：默认，不信任任何转发客户端 IP
- `proxy_mode: "local_proxy"`：仅信任同机的 `127.0.0.1` 和 `::1`，不需要 `trusted_proxies`
- `proxy_mode: "custom"`：只用于代理在其他主机/网段的拓扑，并在 `trusted_proxies` 列出至少一个真实代理 IP/CIDR

推荐安装后在“系统设置 → 网络与代理”维护上述代理信任边界。该页面单独保存代理模式与可信地址，不会连带改写站点、交易等业务设置；有效配置变化后服务自动重启。重新连接后台并确认 `/health`、`/health/ready` 以及访问日志中的真实客户端 IP 正确。不要把全网网段加入 `trusted_proxies`。

“系统设置 → 许可与联系”可只读查看软件法律文档和首次安装接受证据，并设置客户端页脚的 QQ、微信、Telegram、Discord、X、邮箱与 WhatsApp 联系渠道。每个渠道只有在开关启用且内容非空时显示，关闭或留空不会展示。

暂不建议子路径部署（如 `/shop/`），请用独立域名或子域名反代到根路径 `/`。

### Nginx

整站反代（独立站点推荐）：

```nginx
location ^~ / {
    proxy_pass http://127.0.0.1:18765;
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
    proxy_pass http://127.0.0.1:18765;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
location ^~ /api/ {
    proxy_pass http://127.0.0.1:18765;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
location ^~ /static/ {
    proxy_pass http://127.0.0.1:18765;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

改完后：`nginx -t && nginx -s reload`，浏览器强制刷新（Ctrl+F5）。

自检：直接打开 `http://服务器IP:18765/admin` 若正常、走域名却白屏，就是 Nginx 未把 `/admin/assets/` 转到后端。
### Apache

在已有 VirtualHost 中加入：

```apache
    ProxyPass        / http://127.0.0.1:18765/
    ProxyPassReverse / http://127.0.0.1:18765/
```

---

## Windows 安装

1. 打开 [Releases](https://github.com/ecard8/EasyCard/releases)，按“设置 → 系统 → 系统类型”下载：
   - x64：`EasyCard-<版本>-windows-amd64.zip`
   - ARM64：`EasyCard-<版本>-windows-arm64.zip`
2. 解压到任意目录（例如 `D:\EasyCard\`）
3. 双击或在终端运行 `cardgo.exe`
4. 浏览器访问 `http://127.0.0.1:18765/admin`，先完成许可与经营者责任确认，再创建首位管理员

首次初始化通过后，再按真实部署需要开放防火墙入站端口（默认 18765）。
数据文件默认写在程序目录下的 `data.db` / `config.json`（以实际配置为准）。

---

## macOS 安装

按芯片选择归档：

- Intel Mac：`EasyCard-<版本>-darwin-amd64.tar.gz`
- Apple Silicon（M1/M2/M3/M4 等）：`EasyCard-<版本>-darwin-arm64.tar.gz`

```bash
tar -xzf EasyCard-<版本>-darwin-<架构>.tar.gz
chmod 700 cardgo
./cardgo -version
./cardgo
```

浏览器访问 `http://127.0.0.1:18765/admin` 完成首次安装。生产使用时应通过受控的 `launchd` 服务或其他进程管理器运行，保护程序目录、`config.json`、数据库、上传、安全交付文件和备份，并在本机反向代理后提供 HTTPS。

当前 macOS 归档由 Go 在 Windows 构建机交叉编译，能够校验 Mach-O 平台和 Go 构建身份，但**尚未使用 Apple Developer ID 签名或完成 Apple 公证**。正式向普通 macOS 用户分发前，必须在受控 macOS 构建环境完成签名、公证、Staple 和 Intel/Apple Silicon 真机验收；不要要求用户关闭 Gatekeeper。

---

## 校验下载

每个 Release 附带 `SHA256SUMS`。Linux:

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

macOS:

```bash
shasum -a 256 EasyCard-<版本>-darwin-<架构>.tar.gz
```

PowerShell:

```powershell
Get-FileHash .\EasyCard-1.1.0-rc.2-windows-amd64.zip -Algorithm SHA256
```

---

## 安全提示

- 请妥善备份 `config.json` 中的 `aes_key` 与数据库文件；密钥丢失将无法解密已有卡密。
- `config.json`、数据库、`uploads/` 与许可证私钥必须按同一恢复点保存；不要单独恢复其中一项。
- 生产环境建议置于反向代理之后，启用 HTTPS，并限制管理端访问来源。
- 每次升级后确认 `systemctl status easycard`、`/health/ready`、管理端运行监控及一笔受控业务流程正常。
- 本仓库不含源码；如需商业授权或定制请通过官网联系。

## License / 声明

发行包版权归 EasyCard 易卡数字平台所有。未经授权请勿反编译、二次分发商业源码等价物。
