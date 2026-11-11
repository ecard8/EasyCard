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

> **候选版升级期限：**每个新版本从发布日期起提供六个自然月的客户端网页使用期，目标月份无对应日期时取月末。`v1.1.0-rc.15` 发布于 `2026-11-11`，可使用至站点时区 `2027-05-11`；从 `2027-05-12 00:00` 起商城与客户中心要求升级。重新安装或重启不延长期限；管理后台、`easycard update`、健康检查、API 与支付回调继续可用。

---

## 邮件配置（七个独立通道）

rc.12 新增五家邮件服务商，保留已有 Resend 和自定义 SMTP。在每个实例的 **系统设置 → 邮件配置** 中分别保存、启用和测试；无需环境变量或重启。

| 通道 | 发送方式与凭据 |
| --- | --- |
| 自定义 SMTP | 自行填写服务器、端口、加密方式、用户名和密码 |
| Resend | HTTP API Key；[注册](https://resend.com/signup)、[API Key](https://resend.com/api-keys)、[域名验证](https://resend.com/domains) |
| Mailjet | SMTP；加密的 API Key 字段作为用户名，密码字段填 Secret Key |
| SMTP2GO | SMTP Users 中创建的用户名和密码 |
| Cloudflare Email Sending | 发信 API Token 和账户 ID；仅开通 Email Routing 不足以发信 |
| 阿里云邮件推送 | 对应区域的发信地址与 SMTP 密码 |
| 腾讯云 SES | 对应区域的发信地址与 SMTP 密码 |

每个通道均可设置发件邮箱、发件人名称和可选回复邮箱；预设 SMTP 地址和加密方式由程序管理，需要区域的通道提供区域选项。面板附各家官方文档。测试前按服务商控制台验证发信域名或邮箱；使用实际要求的 DNS 记录，保留原有收件服务的 MX 配置。

1. **保存配置**只更新该通道草稿，切换服务商可恢复各自配置，不改变当前活动通道。
2. **启用已保存配置**将草稿作为活动快照并开启邮件总开关。有效配置变化会撤销旧验收；普通草稿修改不会影响正在使用的快照。
3. 填写自己可检查的测试收件邮箱，发送固定测试内容。服务商接受请求不等于送达；检查收件箱和垃圾箱，确认实际收到后，在原有验收卡中**记录验收**，再启用所需验证码或业务邮件功能。
4. 未启用的草稿和总开关关闭时也可预检测试，但不会建立活动通道验收；启用后需重新测试。多实例须分别配置和验收。

首次成功写入邮件设置（保存、启用或更改总开关）时，旧 SMTP/Resend 配置迁移至新加密存储，随后清除旧密钥副本。读取只返回“已配置/未配置”，不会回传密钥或掩码值；留空保留、输入新值替换，勾选明确的清除选项后保存才删除。清除当前通道密钥会立即停用邮件并撤销验收。总开关关闭保留配置，但停用邮件及依赖功能；重新开启后须完成测试、验收并按需开启业务功能。

验证码仍由原业务流程生成、限流和消费，邮件发送不会将邮箱直接标记为已验证。HTTP/SMTP 发送设置有限超时，不自动重试或回退；超时等不确定结果须先核对服务商记录，避免重复发送。

**本轮验收边界：**自动化、协议替身与构建检查通过，尚未验证七通道真实投递。内置浏览器 URL 策略阻止本地页面验收；实际部署后的页面操作、正式发信域名与真实收件仍须验证。历史测试记录不能替代当前通道的验收。

## 注册方式与仅邮箱注册

在 **系统设置 → 注册/登录** 中分别控制“允许邮箱注册”和“允许手机号注册”；两项默认开启，升级时缺失的设置也按开启处理。“允许注册”是总开关，关闭后禁止所有新注册。关闭某一种方式也会禁止该方式的注册验证码发送，但不影响已有用户登录、绑定联系方式或找回密码。

从 rc.15 起，购买和购物车页面余额不足时禁用余额支付并提示；数量、规格、优惠券变动后自动重新判断，余额刚好足够可用。无可用支付方式时禁止提交。

从 rc.14 起，注册与找回密码页面的验证码输入框可自适应缩短，发送按钮文字保持一行。

从 rc.13 起，仅开启邮箱或手机号其中一种注册方式时，注册页自动选中它并隐藏方式选择器；两者均开启才显示选择器。验证码输入及发送控件在页面初始化时即按选中方式显示，已有账号登录方式不变。

仅允许邮箱注册并要求验证码时，先保存并启用邮件通道、确认实际收到测试邮件并记录验收，再保存以下注册设置：

| 设置 | 值 |
| --- | --- |
| 允许注册 `allow_register` | `1` |
| 允许邮箱注册 `allow_email_register` | `1` |
| 允许手机号注册 `allow_phone_register` | `0` |
| 注册邮箱验证 `reg_email_enable` | `1` |

这组设置只限制新注册；已有手机号账号仍可正常登录。注册方式开关与验证码要求独立：允许邮箱注册不自动要求邮箱验证，也不代替邮件通道验收。

## Linux 一键安装（推荐）

需要: `curl` 或 `wget`、`tar`、**root**；支持 **amd64 / arm64**。

推荐写法（与宝塔面板类似：先下载到本地再执行，避免 `curl|bash` 管道问题）：

```bash
if [ -f /usr/bin/curl ];then curl -sSO https://raw.githubusercontent.com/ecard8/EasyCard/main/install.sh;else wget -O install.sh https://raw.githubusercontent.com/ecard8/EasyCard/main/install.sh;fi;bash install.sh -y
```

默认自动安装公开 Release 中语义版本最高的版本（包含预发布，跨页比较，不依赖列表顺序或发布时间）；也可指定目录 / 端口:

```bash
bash install.sh --dir /opt/easycard --port 18765 -y
```

需要复现、回滚或受控验收时，可额外使用 `--version 1.1.0-rc.15` 固定版本。

安装脚本会:

1. 从 GitHub Release 下载对应架构的 `EasyCard-*-linux-*.tar.gz`
2. 使用 `SHA256SUMS` 校验归档，并执行候选程序的 `-version` 核对版本
3. 安装到 `/opt/easycard`（可用 `--dir` 修改）
4. 创建最小权限系统用户 `easycard` 与加固后的 systemd 服务 `easycard`
5. 生成默认 `config.json`（若不存在）并始终保留已有配置、数据库和上传文件
6. 启动后轮询 `/health` 验证进程与数据库；30 秒内仍不可用则自动恢复上一版本二进制，`/health/ready` 的运营告警单独提示
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
easycard update          # 更新到公开 Release 中语义版本最高的版本
easycard update 1.1.0-rc.15
easycard port             # 查看当前监听端口
easycard port 9090        # 安全更换监听端口
easycard logs 200
easycard logs -f
```

同时兼容 `easycard -restart`、`easycard -stop`、`easycard -start`、`easycard -update`、`easycard -port`。服务变更与更新需要 root 权限，普通账户使用 `sudo easycard <命令>`。`easycard update` 会复用一键安装器的架构识别、SHA-256、候选版本身份、健康检查和自动二进制回滚，不会绕过发布校验。`easycard port` 修改前检查占用，修改后验证健康并在失败时恢复原配置；它只修改 `listen`，不会修改可能由反向代理管理的 `base_url`。

### 同机多实例

从 rc.8 起，可一次按实例名顺序更新全部已登记实例；任一实例失败立即停止，后续实例不更新：

```bash
sudo easycard update-all
# 或为整个批次指定同一版本
sudo easycard update-all 1.1.0-rc.15
```

菜单入口：`sudo easycard` → **11) 更新所有实例**；多实例选择页也可输入 **a** 直接进入。未指定版本时仅解析一次公开 Release 中语义版本最高的版本，整个批次使用同一目标版本和安装器。显示已完成、失败和未处理实例；成功实例不会自动回退，失败实例沿用单实例更新器的回滚流程。批次互斥锁阻止重复批量执行，每次实例更新仍使用原安装锁。

旧管理器先明确指定 rc.15 更新一套，以安装修正版本选择的共享管理器，再自动更新全部实例：

```bash
sudo easycard update 1.1.0-rc.15
# 多实例时按提示选择一套；也可用 --instance 实际名称 明确指定
sudo easycard update-all
```

新版管理器按语义版本比较候选版与正式版，例如 `1.1.0-rc.15` 高于 `1.1.0-rc.10`，`1.1.0` 高于两者。已支持 `update-all` 的旧管理器（rc.8 起）也可直接运行 `sudo easycard update-all 1.1.0-rc.15`，绕过旧的自动版本选择；rc.7 或更早版本须先更新一套获得批量命令。批次会再次检查/更新已升级实例。`update-all` 不能和 `--instance` 同时使用。

只有一个实例时，`easycard`、`easycard restart`、`easycard update` 等原命令保持不变。新增实例后，交互命令先选择实例；脚本、计划任务等非交互调用必须使用 `--instance`（或 `-i`）。`easycard instances` 列出实例名、当前端口和目录。

从旧版本升级到 rc.6 后，运行 `sudo easycard` 并选择 **9) 安装新实例**；已有多个实例时，在实例选择页输入 **n** 可直接新增。也可以直接启动安装向导：

```bash
sudo easycard install
```

向导提示实例名、目录和推荐空闲端口，并在确认后安装。非交互调用必须提供实例名、端口和 `-y`；可用 `--version` 固定版本：

```bash
sudo easycard install easycard2 --dir /opt/easycard2 --port 18766 -y
easycard instances
sudo easycard --instance easycard2 restart
sudo easycard --instance easycard2 update
easycard --instance easycard2 logs 200
sudo easycard --instance easycard port 18765
```

新增命令无需先选择旧实例。`install` 拒绝已有名称，且安装器在持有互斥锁后再次检查，不会将新增操作变为更新。也可继续使用独立安装器：`sudo bash install.sh --new-instance --instance easycard2 --dir /opt/easycard2 --port 18766 -y`。

实例名就是 systemd 服务名；安装器的 `--service` 与 `--instance` 使用同一标识。新实例省略 `--dir` 时使用 `/opt/实例名`，更新已有实例时使用登记目录和实际端口。向导推荐的端口仍会在安装时检查；非交互调用应指定空闲端口。安装器拒绝目录重叠、端口冲突，以及覆盖无关服务或非空新目录。

实例登记保存在 `/etc/easycard/instances/实例名.conf`，旧 `/etc/easycard/manager.conf` 会自动迁移并保留；新增实例不会覆盖旧默认指向。各实例分别保存数据库、配置、密钥、上传和备份，分别配置域名、`base_url` 和支付回调。更新、端口变更、日志和失败回滚只操作选中的实例；安装/更新和端口变更共用互斥锁。旧程序包更新不会降级已安装的多实例管理工具。程序回滚仍不等于数据库回滚。

首次使用新安装器时，需要选择包含多实例管理工具的发行包；若候选包和本机都没有新版工具，安装器会在修改服务前停止。已经安装新版工具后，可保留它来管理兼容的旧程序包。

从 rc.7 起，运行 `sudo easycard remove` 选择要删除的实例，或先在 `sudo easycard` 中选择实例，再选 **10) 删除当前实例**。默认只移除该实例服务和登记、保留目录数据，也可选择永久删除该实例目录；最后必须输入实例名确认。非交互用法：

```bash
# 保留该实例目录数据
sudo easycard remove easycard2 --keep-data --confirm easycard2
# 永久删除该实例目录中的配置、数据库、上传、备份和程序
sudo easycard remove easycard2 --purge --confirm easycard2
```

删除只停止和禁用选中的服务；目录与其他实例/共享管理文件重叠、符号链接目录、挂载点、自定义服务覆盖或无法确认服务已停止时拒绝清除。默认指向被删实例时自动改指向剩余实例。共享管理命令、系统账户及其他实例保持不动；删除最后一套后仍可用 `sudo easycard install` 重装。保留的非空目录不会被新安装覆盖；目录外的数据路径不会自动删除。

升级（保留数据与配置）:

```bash
sudo bash install.sh --version 1.0.1 -y
# 或自动安装语义版本最高的公开版本（包含预发布）
sudo bash install.sh -y
```

升级前仍建议在管理后台创建并验证一份完整备份。脚本的自动回滚只恢复上一版本程序，不回滚已经执行的数据库迁移；跨版本降级必须先核对目标版本的数据兼容性，必要时使用升级前完整备份恢复。

更新器以 `/health` 验证新进程和数据库是否能够工作；`/health/ready` 还包含备份时效、外部渠道和运行监控等运营条件。后者未通过时更新器会明确警告但不会把正常启动误判为失败，管理员应在更新完成后进入“运行监控”处理对应告警。

卸载（**会保留数据目录**，按需自行删除）:

```bash
sudo systemctl disable --now easycard
sudo rm -f /etc/systemd/system/easycard.service
sudo rm -f /usr/local/bin/easycard /etc/easycard/manager.conf
sudo rm -f /etc/easycard/instances/easycard.conf
sudo systemctl daemon-reload
# 可选: sudo rm -rf /opt/easycard
```

---

## Linux 手动安装

```bash
# 以 1.1.0-rc.15 / amd64 为例
VER=1.1.0-rc.15
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
Get-FileHash .\EasyCard-1.1.0-rc.15-windows-amd64.zip -Algorithm SHA256
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
