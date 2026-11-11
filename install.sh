#!/usr/bin/env bash
# EasyCard Digital Commerce Platform Linux 一键安装脚本
#
# 推荐（宝塔同款：先落到本地再执行，避免 curl|bash 吞掉 stdin）:
#   if [ -f /usr/bin/curl ];then curl -sSO https://raw.githubusercontent.com/ecard8/EasyCard/main/install.sh;else wget -O install.sh https://raw.githubusercontent.com/ecard8/EasyCard/main/install.sh;fi;bash install.sh -y
#
# 其它:
#   sudo bash install.sh
#   sudo bash install.sh --dir /opt/easycard --port 18765
#   sudo bash install.sh --version 1.1.0-rc.2  # 可选：固定版本
set -euo pipefail

REPO="ecard8/EasyCard"
PRODUCT="EasyCard"
BIN_NAME="cardgo"
DIR_EXPLICIT=0
PORT_EXPLICIT=0
[[ -z "${INSTALL_DIR+x}" ]] || DIR_EXPLICIT=1
[[ -z "${PORT+x}" ]] || PORT_EXPLICIT=1
INSTALL_DIR="${INSTALL_DIR:-/opt/easycard}"
SERVICE_NAME="${SERVICE_NAME:-easycard}"
PORT="${PORT:-18765}"
MANAGER_CONFIG="${EASYCARD_MANAGER_CONFIG:-/etc/easycard/manager.conf}"
INSTANCES_DIR="${EASYCARD_INSTANCES_DIR:-$(dirname "$MANAGER_CONFIG")/instances}"
MANAGER_BIN="${EASYCARD_MANAGER_BIN:-/usr/local/bin/easycard}"
SYSTEMD_UNIT_DIR="${EASYCARD_SYSTEMD_UNIT_DIR:-/etc/systemd/system}"
VERSION="${VERSION:-}"
ASSUME_YES=0
NEW_INSTANCE_ONLY=0
EXISTING_INSTANCE_ONLY=0
CANDIDATE_DIR=""
CANDIDATE_BIN=""
CANDIDATE_MANAGER=""
trap 'if [[ -n "${CANDIDATE_DIR:-}" && -d "$CANDIDATE_DIR" ]]; then rm -rf -- "$CANDIDATE_DIR"; fi' EXIT

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; NC=$'\033[0m'
info() { echo "${GREEN}[INFO]${NC} $*"; }
warn() { echo "${YELLOW}[WARN]${NC} $*"; }
die()  { echo "${RED}[ERR ]${NC} $*" >&2; exit 1; }

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "请使用 root 运行: sudo bash $0"
  fi
}

usage() {
  cat <<EOF
EasyCard 易卡数字平台 Linux 安装脚本

用法:
  sudo bash install.sh [选项] [版本]

选项:
  -d, --dir DIR       安装目录 (默认: /opt/easycard)
  -p, --port PORT     监听端口 (默认: 18765)
  -s, --service NAME  systemd 服务名 (默认: easycard)
  -i, --instance NAME 实例名（与服务名相同；新实例默认目录 /opt/NAME）
      --new-instance 仅新装；同名实例或服务已存在时拒绝，不会转为更新
      --existing-instance 仅更新已登记实例；登记被删除时拒绝重新安装
  -v, --version VER   可选：固定版本；省略则安装最新公开 Release（包含预发布）
  -y, --yes           非交互确认
  -h, --help          显示帮助

示例:
  sudo bash install.sh
  sudo bash install.sh --dir /opt/easycard --port 18765
  sudo bash install.sh --version 1.1.0-rc.2
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--dir) INSTALL_DIR="${2:?缺少安装目录}"; DIR_EXPLICIT=1; shift 2 ;;
      -p|--port) PORT="${2:?缺少端口}"; PORT_EXPLICIT=1; shift 2 ;;
      -s|--service) SERVICE_NAME="$2"; shift 2 ;;
      -i|--instance) SERVICE_NAME="${2:?缺少实例名}"; shift 2 ;;
      -v|--version) VERSION="$2"; shift 2 ;;
      -y|--yes) ASSUME_YES=1; shift ;;
      --new-instance) NEW_INSTANCE_ONLY=1; shift ;;
      --existing-instance) EXISTING_INSTANCE_ONLY=1; shift ;;
      -h|--help) usage; exit 0 ;;
      -*) die "未知参数: $1" ;;
      *) VERSION="$1"; shift ;;
    esac
  done
}

detect_arch() {
  local m
  m="$(uname -m)"
  case "$m" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "不支持的架构: $m（仅支持 amd64 / arm64）" ;;
  esac
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

# 下载到文件：优先 curl，否则 wget（与宝塔一键装同思路）
http_get() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$out" "$url"
  else
    die "缺少 curl 或 wget"
  fi
}

# 输出到 stdout（用于 API JSON）
http_get_stdout() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$url"
  else
    die "缺少 curl 或 wget"
  fi
}

# BEGIN EASYCARD RELEASE SELECTION
# Capability marker: preserve this manager when installing older application packages.
# Highest public SemVer, including prereleases; never trust GitHub list order.
release_api_download() (
  local url="$1" out="$2" request_pid='' timer_pid='' result
  cleanup_release_request() {
    if [[ -n "$timer_pid" ]]; then kill -TERM "$timer_pid" 2>/dev/null || true; wait "$timer_pid" 2>/dev/null || true; fi
    if [[ -n "$request_pid" ]]; then kill -TERM "$request_pid" 2>/dev/null || true; wait "$request_pid" 2>/dev/null || true; fi
  }
  trap cleanup_release_request EXIT
  trap 'exit 130' INT
  trap 'exit 143' HUP TERM
  (
    trap - EXIT HUP INT TERM
    # Bash file-size limits also bound wget responses without Content-Length.
    ulimit -f 8192 || exit 1
    if command -v curl >/dev/null 2>&1; then
      exec curl -fsSL --connect-timeout 10 --max-time 45 --max-filesize 8388608 --retry 2 -o "$out" "$url"
    elif command -v wget >/dev/null 2>&1; then
      exec wget -q --timeout=20 --tries=2 -O "$out" "$url"
    else
      echo '版本查询需要 curl 或 wget' >&2; exit 1
    fi
  ) &
  request_pid=$!
  # wget timeout is only an idle limit. Bound the entire request (and retries)
  # without requiring an additional timeout utility; reap the timer on exit.
  (
    trap - EXIT HUP INT TERM
    trap 'for sleeper in $(jobs -pr); do kill -TERM "$sleeper" 2>/dev/null || true; done; wait 2>/dev/null || true; exit 0' HUP INT TERM
    sleep 50 &
    wait "$!" || exit 1
    kill -TERM "$request_pid" 2>/dev/null || true
  ) &
  timer_pid=$!
  if wait "$request_pid"; then result=0; else result=$?; fi
  request_pid=''
  return "$result"
)

release_parse_page() {
  local bytes
  bytes="$(wc -c < "$1")" || return 1
  [[ "$bytes" =~ ^[[:space:]]*[0-9]+[[:space:]]*$ ]] && (( bytes > 0 && bytes <= 8388608 )) || return 1
  LC_ALL=C awk '
    function bad() { print "Invalid GitHub releases JSON" > "/dev/stderr"; exit 1 }
    function ws() { while (substr(data,pos,1) ~ /^[ \t\r\n]$/) pos++ }
    function take(c) { ws(); if(substr(data,pos,1)!=c) bad(); pos++ }
    function str( c,e,h,n,i,out) {
      take("\""); out=""
      while(pos<=length(data)) {
        c=substr(data,pos++,1)
        if(c=="\"") return out
        if(c ~ /[[:cntrl:]]/) bad()
        if(c!="\\") { out=out c; continue }
        e=substr(data,pos++,1)
        if(e=="\"" || e=="\\" || e=="/") out=out e
        else if(e=="b") out=out sprintf("%c",8)
        else if(e=="f") out=out sprintf("%c",12)
        else if(e=="n") out=out "\n"
        else if(e=="r") out=out "\r"
        else if(e=="t") out=out "\t"
        else if(e=="u") {
          h=substr(data,pos,4); if(length(h)!=4 || h ~ /[^0-9a-fA-F]/) bad()
          n=0; for(i=1;i<=4;i++) n=n*16+index("0123456789abcdef",tolower(substr(h,i,1)))-1
          pos+=4; out=out (n>0 && n<128 ? sprintf("%c",n) : "_")
        } else bad()
      }
      bad()
    }
    function semver(v, core,pre,b,n,a,i,p) {
      sub(/^v/,"",v)
      if(v=="" || v ~ /[^0-9A-Za-z.+-]/) return ""
      n=split(v,b,"[+]"); if(n>2) return ""
      if(n==2 && (b[2]=="" || b[2] ~ /(^\.|\.$|\.\.)/ || b[2] ~ /[^0-9A-Za-z.-]/)) return ""
      core=b[1]; p=index(core,"-")
      if(p) {
        pre=substr(core,p+1); core=substr(core,1,p-1)
        if(pre=="" || pre ~ /(^\.|\.$|\.\.)/) return ""
        n=split(pre,a,"."); for(i=1;i<=n;i++) if(a[i] ~ /^[0-9]+$/ && a[i] ~ /^0[0-9]/) return ""
      }
      n=split(core,a,"."); if(n!=3) return ""
      for(i=1;i<=3;i++) if(a[i] !~ /^(0|[1-9][0-9]*)$/) return ""
      return v
    }
    function timestamp(v, y,m,d,days) {
      if(length(v)!=20 || v !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) return 0
      y=substr(v,1,4)+0; m=substr(v,6,2)+0; d=substr(v,9,2)+0
      if(m<1 || m>12 || d<1 || substr(v,12,2)+0>23 || substr(v,15,2)+0>59 || substr(v,18,2)+0>59) return 0
      days=31; if(m==4||m==6||m==9||m==11) days=30
      if(m==2) days=28+(y%4==0 && (y%100!=0 || y%400==0))
      return d<=days
    }
    function object(depth,release, key,tag,draft,published,ts,ds,ps,version) {
      take("{"); ws()
      if(substr(data,pos,1)!="}") while(1) {
        key=str(); take(":"); value(depth+1)
        if(release && key=="tag_name") { if(ts++ || type!="string") bad(); tag=text }
        if(release && key=="draft") { if(ds++ || type!="boolean") bad(); draft=text }
        if(release && key=="published_at") {
          if(ps++ || (type!="string" && type!="null")) bad()
          if(type=="string" && !timestamp(text)) bad()
          published=(type=="string")
        }
        ws(); if(substr(data,pos,1)=="}") break
        take(",")
      }
      take("}")
      if(release) {
        if(ts!=1 || ds!=1 || ps!=1) bad()
        version=semver(tag)
        if(draft=="false" && published && version!="") tags[++eligible]=version
      }
      type="object"; text=""
    }
    function value(depth, c,rest) {
      if(depth>64) bad()
      ws(); c=substr(data,pos,1)
      if(c=="\"") { text=str(); type="string"; return }
      if(c=="{") { object(depth,0); return }
      if(c=="[") {
        take("["); ws()
        if(substr(data,pos,1)!="]") while(1) {
          value(depth+1); ws(); if(substr(data,pos,1)=="]") break; take(",")
        }
        take("]"); type="array"; text=""; return
      }
      rest=substr(data,pos)
      if(substr(rest,1,4)=="true") { pos+=4; type="boolean"; text="true"; return }
      if(substr(rest,1,5)=="false") { pos+=5; type="boolean"; text="false"; return }
      if(substr(rest,1,4)=="null") { pos+=4; type="null"; text=""; return }
      if(match(rest,/^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/)) { pos+=RLENGTH; type="number"; text=""; return }
      bad()
    }
    { data=data $0 "\n" }
    END {
      pos=1; take("["); ws()
      if(substr(data,pos,1)!="]") while(1) {
        if(++count>100) bad()
        object(1,1); ws(); if(substr(data,pos,1)=="]") break; take(",")
      }
      take("]"); ws(); if(pos<=length(data)) bad()
      print count+0; for(i=1;i<=eligible;i++) print tags[i]
    }
  ' "$1"
}

release_semver_max() {
  LC_ALL=C awk '
    function numeric(a,b) {
      if(length(a)!=length(b)) return length(a)>length(b)?1:-1
      if(("x" a)==("x" b)) return 0
      return ("x" a)>("x" b)?1:-1
    }
    function compare(a,b, ac,bc,ap,bp,x,y,i,n,m,c,p) {
      sub(/[+].*$/,"",a); sub(/[+].*$/,"",b)
      p=index(a,"-"); ac=p?substr(a,1,p-1):a; ap=p?substr(a,p+1):""
      p=index(b,"-"); bc=p?substr(b,1,p-1):b; bp=p?substr(b,p+1):""
      split(ac,x,"."); split(bc,y,".")
      for(i=1;i<=3;i++) { c=numeric(x[i],y[i]); if(c) return c }
      if(ap=="" || bp=="") return ap==bp?0:(ap==""?1:-1)
      n=split(ap,x,"."); m=split(bp,y,".")
      for(i=1;i<=n && i<=m;i++) {
        if(("x" x[i])==("x" y[i])) continue
        if(x[i]~/^[0-9]+$/ && y[i]~/^[0-9]+$/) return numeric(x[i],y[i])
        if(x[i]~/^[0-9]+$/) return -1
        if(y[i]~/^[0-9]+$/) return 1
        return ("x" x[i])>("x" y[i])?1:-1
      }
      return n==m?0:(n>m?1:-1)
    }
    NF { if(best=="" || compare($0,best)>0) best=$0 }
    END { if(best=="") exit 1; print best }
  ' "$1"
}

release_select_latest() (
  local root="${1:-${TMPDIR:-/tmp}}" tmp page count
  tmp="$(mktemp -d "$root/easycard-release.XXXXXX")" || return 1
  trap 'rm -rf -- "$tmp"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' HUP TERM
  : > "$tmp/tags"
  for ((page=1; page<=10; page++)); do
    release_api_download "https://api.github.com/repos/${REPO}/releases?per_page=100&page=$page" "$tmp/page.json" || { echo "公开版本第 $page 页下载失败" >&2; return 1; }
    release_parse_page "$tmp/page.json" > "$tmp/parsed" || { echo "公开版本第 $page 页无效" >&2; return 1; }
    IFS= read -r count < "$tmp/parsed" || return 1
    tail -n +2 "$tmp/parsed" >> "$tmp/tags" || return 1
    if (( count < 100 )); then
      release_semver_max "$tmp/tags" || { echo '没有有效的公开版本' >&2; return 1; }
      return 0
    fi
  done
  echo '公开版本分页超过安全上限，拒绝使用不完整列表' >&2
  return 1
)
# END EASYCARD RELEASE SELECTION

api_latest_tag() {
  release_select_latest || die "无法获取最高公开版本，请检查网络或仓库 ${REPO}"
}

asset_url() {
  local ver="$1" arch="$2" name
  name="${PRODUCT}-${ver}-linux-${arch}.tar.gz"
  echo "https://github.com/${REPO}/releases/download/v${ver}/${name}"
}

confirm() {
  if [[ "$ASSUME_YES" -eq 1 ]]; then return 0; fi
  # curl|bash 时 stdin 不是终端：避免 read 吃到 EOF 静默失败
  if [[ ! -t 0 ]]; then
    warn "非交互安装（stdin 非终端），自动继续。显式确认请加 -y 或先下载再执行。"
    return 0
  fi
  local ans
  read -r -p "确认继续安装到 ${INSTALL_DIR} 并监听 :${PORT} ? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || die "已取消"
}

install_deps_hint() {
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    die "缺少 curl 或 wget"
  fi
  need_cmd tar
  command -v sha256sum >/dev/null 2>&1 || warn "未找到 sha256sum，将跳过校验"
}

create_user() {
  if ! id -u easycard >/dev/null 2>&1; then
    useradd --system --home "$INSTALL_DIR" --shell /usr/sbin/nologin easycard 2>/dev/null \
      || useradd --system --home "$INSTALL_DIR" --shell /sbin/nologin easycard
    info "已创建系统用户 easycard"
  fi
}

write_systemd() {
  if [[ -f "${SYSTEMD_UNIT_DIR}/${SERVICE_NAME}.service" ]]; then
    cp -f "${SYSTEMD_UNIT_DIR}/${SERVICE_NAME}.service" "${INSTALL_DIR}/${SERVICE_NAME}.service.previous"
  else
    rm -f "${INSTALL_DIR}/${SERVICE_NAME}.service.previous"
  fi
  cat >"${SYSTEMD_UNIT_DIR}/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=EasyCard Digital Commerce Platform
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=easycard
Group=easycard
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/${BIN_NAME} -config ${INSTALL_DIR}/config.json
Restart=on-failure
RestartSec=3
TimeoutStopSec=30
KillSignal=SIGTERM
LimitNOFILE=65535
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=${INSTALL_DIR}
RestrictSUIDSGID=true
LockPersonality=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
# 仅绑定配置中的端口；默认见 config.json listen
Environment=HOME=${INSTALL_DIR}
Environment=CARDGO_ROOT=${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

rand_hex() {
  local n="${1:-32}"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$n"
  else
    head -c "$n" /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

write_default_config() {
  local cfg="${INSTALL_DIR}/config.json"
  if [[ -f "$cfg" ]]; then
    info "保留已有配置: $cfg"
    return 0
  fi
  local aes sess
  aes="$(rand_hex 32)"
  sess="$(rand_hex 32)"
  [[ ${#aes} -eq 64 ]] || die "生成 aes_key 失败"
  [[ ${#sess} -eq 64 ]] || die "生成 session_secret 失败"
  cat >"$cfg" <<EOF
{
  "listen": "${PORT}",
  "db_path": "data/data.db",
  "base_url": "http://localhost:18765",
  "proxy_mode": "direct",
  "aes_key": "${aes}",
  "session_secret": "${sess}"
}
EOF
  chown easycard:easycard "$cfg"
  chmod 640 "$cfg"
  info "已生成默认配置: $cfg （首次访问 /admin 完成安装向导；初始化完成前请勿向公网开放监听端口）"
}

download_candidate() {
  local ver="$1" arch="$2" url tmp archive
  url="$(asset_url "$ver" "$arch")"
  tmp="$(mktemp -d)"
  CANDIDATE_DIR="$tmp"
  archive="${tmp}/${PRODUCT}-${ver}-linux-${arch}.tar.gz"
  info "下载: $url"
  http_get "$url" "$archive" || die "下载失败"

  # 可选校验
  if command -v sha256sum >/dev/null 2>&1; then
    local sums_url sums
    sums_url="https://github.com/${REPO}/releases/download/v${ver}/SHA256SUMS"
    sums="${tmp}/SHA256SUMS"
    if http_get "$sums_url" "$sums" 2>/dev/null; then
      (cd "$tmp" && sha256sum -c SHA256SUMS --ignore-missing) || die "SHA256 校验失败"
      info "SHA256 校验通过"
    else
      warn "未找到 SHA256SUMS，跳过校验"
    fi
  fi

  tar -xzf "$archive" -C "$tmp"
  CANDIDATE_BIN="$(find "$tmp" -type f -name "$BIN_NAME" | head -n1 || true)"
  CANDIDATE_MANAGER="$(find "$tmp" -type f -name "easycardctl.sh" | head -n1 || true)"
  [[ -n "$CANDIDATE_BIN" ]] || die "归档中未找到二进制 ${BIN_NAME}"
  chmod 755 "$CANDIDATE_BIN"
  local reported
  reported="$($CANDIDATE_BIN -version 2>/dev/null || true)"
  if [[ "$reported" != *"EasyCard ${ver}"* ]]; then
    die "候选程序版本不匹配，期望 ${ver}，实际输出: ${reported:-无}"
  fi
  info "候选程序版本校验通过: $reported"
}

valid_instance_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.@-]*$ ]]; }

# Read only root-managed, shell-escaped metadata, never application config/secrets.
instance_metadata() (
  INSTALL_DIR=''; SERVICE_NAME=''; DEFAULT_PORT=''
  source "$1" || die "无法加载实例配置: $1"
  valid_instance_name "$SERVICE_NAME" || die "无效实例配置: $1"
  [[ "$INSTALL_DIR" == /* && "$INSTALL_DIR" != *$'\n'* && "$INSTALL_DIR" != *$'\t'* ]] || die "无效实例目录: $1"
  [[ "$DEFAULT_PORT" =~ ^[0-9]+$ ]] || die "无效实例端口: $1"
  PORT="$DEFAULT_PORT"
  printf '%s\t%s\t%s\n' "$SERVICE_NAME" "$(realpath -m -- "$INSTALL_DIR")" "$(service_port)"
)

prepare_instance() {
  [[ "$NEW_INSTANCE_ONLY" == 0 || "$EXISTING_INSTANCE_ONLY" == 0 ]] || die '不能同时要求仅新装和仅更新'
  valid_instance_name "$SERVICE_NAME" || die "systemd 服务名无效: $SERVICE_NAME"
  local file name directory configured metadata matched=0
  local -a records=()
  for file in "$INSTANCES_DIR"/*.conf "$MANAGER_CONFIG"; do
    [[ -f "$file" ]] || continue
    metadata="$(instance_metadata "$file")" || die "无法读取实例配置: $file"
    IFS=$'\t' read -r name directory configured <<< "$metadata"
    # The registry entry supersedes the compatibility pointer for the same instance.
    [[ "$file" != "$MANAGER_CONFIG" || ! -f "$INSTANCES_DIR/$name.conf" ]] || continue
    if [[ "$file" != "$MANAGER_CONFIG" && "$(basename "$file")" != "$name.conf" ]]; then
      die "实例文件名与服务名不一致: $file"
    fi
    records+=("$metadata")
    if [[ "$name" == "$SERVICE_NAME" ]]; then
      [[ "$NEW_INSTANCE_ONLY" == 0 ]] || die "实例 $name 已存在，拒绝将新装变为更新"
      matched=1
      if [[ "$DIR_EXPLICIT" == 0 ]]; then INSTALL_DIR="$directory"; fi
      [[ "$(realpath -m -- "$INSTALL_DIR")" == "$directory" ]] || die "实例 $name 已绑定目录 $directory"
      if [[ "$PORT_EXPLICIT" == 0 ]]; then PORT="$configured"; fi
    fi
  done
  [[ "$EXISTING_INSTANCE_ONLY" == 0 || "$matched" == 1 ]] || die "实例 $SERVICE_NAME 的登记不存在，拒绝将更新变为新装"
  if [[ "$NEW_INSTANCE_ONLY" == 1 && ( -e "$SYSTEMD_UNIT_DIR/$SERVICE_NAME.service" || -L "$SYSTEMD_UNIT_DIR/$SERVICE_NAME.service" ) ]]; then
    die "同名服务已存在，拒绝覆盖: $SERVICE_NAME"
  fi
  if [[ "$matched" == 0 && "$DIR_EXPLICIT" == 0 && "$SERVICE_NAME" != easycard ]]; then
    INSTALL_DIR="/opt/$SERVICE_NAME"
  fi
  [[ "$INSTALL_DIR" == /* && "$INSTALL_DIR" != *$'\n'* && "$INSTALL_DIR" != *$'\t'* && "$INSTALL_DIR" != *' '* ]] || die "安装目录必须是无空白绝对路径"
  INSTALL_DIR="$(realpath -m -- "$INSTALL_DIR")"
  case "$INSTALL_DIR" in /|/opt|/usr|/etc|/var|/home|/root|/tmp) die '不能将系统公共目录用作实例根目录' ;; esac
  [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || die '端口必须为 1-65535'
  if [[ "$EXISTING_INSTANCE_ONLY" == 1 ]]; then
    [[ -d "$INSTALL_DIR" && -r "$INSTALL_DIR/config.json" && -f "$SYSTEMD_UNIT_DIR/$SERVICE_NAME.service" ]] || die "实例 $SERVICE_NAME 的目录、配置或服务已移除，拒绝重新安装"
    configured="$(sed -n 's/.*"listen"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$INSTALL_DIR/config.json" | head -n1)" || die '无法读取实例监听端口'
    configured="${configured##*:}"; configured="${configured%]}"
    [[ "$configured" =~ ^[1-9][0-9]{0,4}$ ]] && (( configured <= 65535 )) || die '实例监听端口无效，拒绝继续更新'
    [[ "$PORT" == "$configured" ]] || die "实例 $SERVICE_NAME 的端口已变为 $configured，拒绝覆盖批次目标"
  fi
  # Existing application configuration is preserved; --port must not imply a change.
  configured="$(service_port)"
  if [[ -f "$INSTALL_DIR/config.json" && "$PORT_EXPLICIT" == 1 && "$PORT" != "$configured" ]]; then
    die "已有实例端口为 $configured；请使用 easycard --instance $SERVICE_NAME port 修改"
  fi
  PORT="$configured"
  for metadata in "${records[@]}"; do
    IFS=$'\t' read -r name directory configured <<< "$metadata"
    [[ "$name" != "$SERVICE_NAME" ]] || continue
    if [[ "$INSTALL_DIR/" == "$directory/"* || "$directory/" == "$INSTALL_DIR/"* ]]; then
      die "实例目录与 $name 重叠: $directory"
    fi
    [[ "$PORT" != "$configured" ]] || die "端口 $PORT 已配置给实例 $name，请用 --port 指定不同端口"
  done
  if [[ "$matched" == 0 && -f "$SYSTEMD_UNIT_DIR/$SERVICE_NAME.service" ]]; then
    # Adopt pre-registry installations only when the existing unit identifies this root.
    grep -Fxq "WorkingDirectory=$INSTALL_DIR" "$SYSTEMD_UNIT_DIR/$SERVICE_NAME.service" &&
      grep -Fxq "ExecStart=$INSTALL_DIR/$BIN_NAME -config $INSTALL_DIR/config.json" "$SYSTEMD_UNIT_DIR/$SERVICE_NAME.service" ||
      die "已有同名 systemd 服务，拒绝覆盖: $SERVICE_NAME"
    matched=1
  fi
  if [[ "$matched" == 0 && -e "$INSTALL_DIR" && -n "$(ls -A -- "$INSTALL_DIR")" ]]; then
    die "新实例目录非空，拒绝覆盖: $INSTALL_DIR"
  fi
  if [[ "$matched" == 0 ]]; then
    if command -v ss >/dev/null 2>&1; then
      if ss -ltnH | awk '{print $4}' | grep -Eq "(^|[.:])${PORT}$"; then die "端口 $PORT 已被占用"; fi
    elif (echo >/dev/tcp/127.0.0.1/"$PORT") >/dev/null 2>&1; then
      die "端口 $PORT 已被占用"
    fi
  fi
}

install_manager() {
  mkdir -p "$INSTANCES_DIR"
  local cfg_tmp old_name
  # Keep the old default pointer and import it before registering a second instance.
  if [[ -f "$MANAGER_CONFIG" ]]; then
    old_name="$(instance_metadata "$MANAGER_CONFIG" | cut -f1)"
    if [[ ! -f "$INSTANCES_DIR/$old_name.conf" ]]; then
      install -o root -g root -m 644 "$MANAGER_CONFIG" "$INSTANCES_DIR/$old_name.conf"
    fi
  fi
  cfg_tmp="$(mktemp "$INSTANCES_DIR/.instance.XXXXXX")"
  {
    printf 'INSTALL_DIR=%q\n' "$INSTALL_DIR"
    printf 'SERVICE_NAME=%q\n' "$SERVICE_NAME"
    printf 'DEFAULT_PORT=%q\n' "$(service_port)"
  } > "$cfg_tmp"
  chown root:root "$cfg_tmp"; chmod 644 "$cfg_tmp"
  mv -f "$cfg_tmp" "$INSTANCES_DIR/$SERVICE_NAME.conf"
  if [[ ! -f "$MANAGER_CONFIG" ]]; then
    install -o root -g root -m 644 "$INSTANCES_DIR/$SERVICE_NAME.conf" "$MANAGER_CONFIG"
  fi
  # An older application package must not downgrade the shared multi-instance manager.
  if grep -q 'EASYCARD_INSTANCES_DIR' "$CANDIDATE_MANAGER"; then
    if [[ -f "$MANAGER_BIN" ]] && {
      { grep -q '^install_instance()' "$MANAGER_BIN" && ! grep -q '^install_instance()' "$CANDIDATE_MANAGER"; } ||
      { grep -q '^remove_instance()' "$MANAGER_BIN" && ! grep -q '^remove_instance()' "$CANDIDATE_MANAGER"; } ||
      { grep -q '^update_all_instances()' "$MANAGER_BIN" && ! grep -q '^update_all_instances()' "$CANDIDATE_MANAGER"; } ||
      { grep -q '^release_select_latest()' "$MANAGER_BIN" && ! grep -q '^release_select_latest()' "$CANDIDATE_MANAGER"; }
    }; then
      info '保留已安装的新版管理工具及实例安装/删除/批量更新入口'
    else
      install -o root -g root -m 755 "$CANDIDATE_MANAGER" "$MANAGER_BIN"
    fi
  fi
  info "已登记实例 $SERVICE_NAME；管理命令: easycard --instance $SERVICE_NAME <命令>"
}

health_ready() {
  local check_port configured
  check_port="$(service_port)"
  local url="http://127.0.0.1:${check_port}/health/ready"
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 2 "$url" >/dev/null 2>&1
  else
    wget -q -T 2 -O /dev/null "$url" >/dev/null 2>&1
  fi
}

health_live() {
  local check_port url
  check_port="$(service_port)"
  url="http://127.0.0.1:${check_port}/health"
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 2 "$url" >/dev/null 2>&1
  else
    wget -q -T 2 -O /dev/null "$url" >/dev/null 2>&1
  fi
}

service_port() {
  local check_port="$PORT" configured
  if [[ -f "${INSTALL_DIR}/config.json" ]]; then
    configured="$(sed -n 's/.*"listen"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${INSTALL_DIR}/config.json" | head -n1)"
    configured="${configured##*:}"
    configured="${configured%]}"
    if [[ "$configured" =~ ^[0-9]+$ ]] && (( configured >= 1 && configured <= 65535 )); then
      check_port="$configured"
    fi
  fi
  printf '%s\n' "$check_port"
}

setup_pending() {
  local check_port body url
  check_port="$(service_port)"
  url="http://127.0.0.1:${check_port}/api/admin/setup/status"
  if command -v curl >/dev/null 2>&1; then
    body="$(curl -fsS --max-time 2 "$url" 2>/dev/null || true)"
  else
    body="$(wget -q -T 2 -O - "$url" 2>/dev/null || true)"
  fi
  printf '%s' "$body" | grep -Eq '"needed"[[:space:]]*:[[:space:]]*true'
}

DEPLOYMENT_STATE=""
deployment_healthy() {
	# /health proves that the process can serve requests and ping its database.
	# /health/ready also contains operational policy (for example backup age and
	# external-channel health), so a pre-existing degraded state must not make a
	# sound binary look like a failed start or prevent rollback recovery.
	if ! health_live; then
		return 1
	fi
  if health_ready; then
    DEPLOYMENT_STATE="ready"
    return 0
  fi
  if setup_pending; then
    DEPLOYMENT_STATE="setup"
    return 0
  fi
  DEPLOYMENT_STATE="live"
  return 0
}

wait_deployment() {
  local i
  for i in $(seq 1 30); do
    if deployment_healthy; then return 0; fi
    sleep 1
  done
  return 1
}

install_candidate() {
  local ver="$1" had_previous=0
  mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/data" "$INSTALL_DIR/backups" "$INSTALL_DIR/logs"

  if [[ -f "${INSTALL_DIR}/${BIN_NAME}" ]]; then
    had_previous=1
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    install -m 755 "${INSTALL_DIR}/${BIN_NAME}" "${INSTALL_DIR}/${BIN_NAME}.previous"
    if [[ -f "${INSTALL_DIR}/VERSION" ]]; then
      cp -f "${INSTALL_DIR}/VERSION" "${INSTALL_DIR}/VERSION.previous"
    fi
  fi

  install -m 755 "$CANDIDATE_BIN" "${INSTALL_DIR}/${BIN_NAME}"
  echo "$ver" > "${INSTALL_DIR}/VERSION"
  chown -R easycard:easycard "$INSTALL_DIR"

  systemctl enable "${SERVICE_NAME}" >/dev/null
  if systemctl restart "${SERVICE_NAME}" && wait_deployment; then
    if [[ "$DEPLOYMENT_STATE" == "setup" ]]; then
      info "服务进程与数据库检查通过，正在等待首次安装向导完成；安装完成后请再验证 /health/ready"
    elif [[ "$DEPLOYMENT_STATE" == "live" ]]; then
      warn "服务启动和数据库检查通过，但运营就绪检查尚未通过；更新已完成，请执行 easycard status 并在管理后台查看运行监控"
    else
      info "服务就绪检查通过: http://127.0.0.1:$(service_port)/health/ready"
    fi
    return 0
  fi

  warn "新版本未能在 30 秒内就绪，开始自动回滚"
  systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
  if [[ "$had_previous" -eq 1 && -f "${INSTALL_DIR}/${BIN_NAME}.previous" ]]; then
    install -m 755 "${INSTALL_DIR}/${BIN_NAME}.previous" "${INSTALL_DIR}/${BIN_NAME}"
    if [[ -f "${INSTALL_DIR}/VERSION.previous" ]]; then
      cp -f "${INSTALL_DIR}/VERSION.previous" "${INSTALL_DIR}/VERSION"
    fi
    if [[ -f "${INSTALL_DIR}/${SERVICE_NAME}.service.previous" ]]; then
      cp -f "${INSTALL_DIR}/${SERVICE_NAME}.service.previous" "${SYSTEMD_UNIT_DIR}/${SERVICE_NAME}.service"
      systemctl daemon-reload
    fi
    chown easycard:easycard "${INSTALL_DIR}/${BIN_NAME}" "${INSTALL_DIR}/VERSION"
    systemctl restart "${SERVICE_NAME}"
    if wait_deployment; then
      die "新版本启动失败，已恢复并启动上一版本；请查看 journalctl -u ${SERVICE_NAME} -e"
    fi
    die "新版本启动失败，上一版本回滚后也未就绪；请立即检查 journalctl -u ${SERVICE_NAME} -e"
  fi
  die "首次安装未能启动；未修改任何既有业务数据，请查看 journalctl -u ${SERVICE_NAME} -e"
}

main() {
  parse_args "$@"
  need_root
  [[ "$(uname -s)" == "Linux" ]] || die "本脚本仅支持 Linux"
  [[ "$INSTALL_DIR" == /* && "$INSTALL_DIR" != *$'\n'* ]] || die "安装目录必须是绝对路径"
  [[ "$SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]] || die "systemd 服务名无效: $SERVICE_NAME"
  [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || die "端口必须为 1-65535"
  install_deps_hint
  need_cmd realpath; need_cmd flock
  mkdir -p "$(dirname "$MANAGER_CONFIG")"
  exec 9>"$(dirname "$MANAGER_CONFIG")/install.lock"
  flock -n 9 || die '另一个实例正在安装或更新，请稍后再试'
  prepare_instance

  local arch ver
  arch="$(detect_arch)"
  if [[ -z "$VERSION" ]]; then
    ver="$(api_latest_tag)"
  else
    ver="${VERSION#v}"
  fi

  info "产品: ${PRODUCT}  版本: ${ver}  架构: linux-${arch}"
  info "安装目录: ${INSTALL_DIR}  端口: ${PORT}"
  confirm

  download_candidate "$ver" "$arch"
  [[ -n "$CANDIDATE_MANAGER" && -f "$CANDIDATE_MANAGER" ]] || die '发行包缺少 easycard 管理工具，拒绝安装不完整版本'
  if ! grep -q 'EASYCARD_INSTANCES_DIR' "$CANDIDATE_MANAGER" &&
     ! grep -q 'EASYCARD_INSTANCES_DIR' "$MANAGER_BIN" 2>/dev/null; then
    die '候选包不支持多实例管理，请使用包含新版管理工具的发行版本'
  fi
  create_user
  mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/data" "$INSTALL_DIR/backups" "$INSTALL_DIR/logs"
  chown -R easycard:easycard "$INSTALL_DIR"
  write_default_config
  write_systemd
  install_candidate "$ver"
  install_manager
  rm -rf "$CANDIDATE_DIR"
  CANDIDATE_DIR=""

  cat <<EOF

${GREEN}安装完成${NC}
  程序:   ${INSTALL_DIR}/${BIN_NAME}
  配置:   ${INSTALL_DIR}/config.json
  数据:   ${INSTALL_DIR}/data/
  版本:   ${ver}

访问管理端完成首次安装:
  http://服务器IP:${PORT}/admin

常用命令:
  easycard instances
  easycard --instance ${SERVICE_NAME} status
  easycard --instance ${SERVICE_NAME} restart
  easycard --instance ${SERVICE_NAME} update
  easycard --instance ${SERVICE_NAME} logs -f

只有一个实例时仍可直接使用 easycard、easycard update 等原命令。

EOF
}

if [[ "${EASYCARD_INSTALLER_LIBRARY:-0}" != "1" ]]; then
  main "$@"
fi
