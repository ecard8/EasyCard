#!/usr/bin/env bash
# EasyHub Digital Commerce Platform Linux 一键安装脚本
#
# 推荐（宝塔同款：先落到本地再执行，避免 curl|bash 吞掉 stdin）:
#   if [ -f /usr/bin/curl ];then curl -sSO https://raw.githubusercontent.com/ecard8/EasyCard/main/install.sh;else wget -O install.sh https://raw.githubusercontent.com/ecard8/EasyCard/main/install.sh;fi;bash install.sh -y
#
# 其它:
#   sudo bash install.sh
#   sudo bash install.sh --dir /opt/easycard --port 18765
#   sudo bash install.sh --version 1.1.0-rc.1  # 可选：固定版本
set -euo pipefail

REPO="ecard8/EasyCard"
PRODUCT="EasyCard"
BIN_NAME="cardgo"
INSTALL_DIR="${INSTALL_DIR:-/opt/easycard}"
SERVICE_NAME="${SERVICE_NAME:-easycard}"
PORT="${PORT:-18765}"
VERSION="${VERSION:-}"
ASSUME_YES=0
CANDIDATE_DIR=""
CANDIDATE_BIN=""
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
EasyHub 易汇数字平台 Linux 安装脚本

用法:
  sudo bash install.sh [选项] [版本]

选项:
  -d, --dir DIR       安装目录 (默认: /opt/easycard)
  -p, --port PORT     监听端口 (默认: 18765)
  -v, --version VER   可选：固定版本；省略则安装最新公开 Release（包含预发布）
  -y, --yes           非交互确认
  -h, --help          显示帮助

示例:
  sudo bash install.sh
  sudo bash install.sh --dir /opt/easycard --port 18765
  sudo bash install.sh --version 1.1.0-rc.1
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--dir) INSTALL_DIR="$2"; shift 2 ;;
      -p|--port) PORT="$2"; shift 2 ;;
      -v|--version) VERSION="$2"; shift 2 ;;
      -y|--yes) ASSUME_YES=1; shift ;;
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

api_latest_tag() {
  # GitHub /releases/latest 会排除 prerelease；发布列表第一条才是最近公开发布。
  # per_page=1 同时避免下载不必要的完整发布历史。
  local tag
  tag="$(http_get_stdout "https://api.github.com/repos/${REPO}/releases?per_page=1" \
    | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [[ -n "$tag" ]] || die "无法获取最新公开 Release，请检查网络或仓库 ${REPO}"
  echo "${tag#v}"
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
  if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
    cp -f "/etc/systemd/system/${SERVICE_NAME}.service" "${INSTALL_DIR}/${SERVICE_NAME}.service.previous"
  else
    rm -f "${INSTALL_DIR}/${SERVICE_NAME}.service.previous"
  fi
  cat >"/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=EasyHub Digital Commerce Platform
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
  [[ -n "$CANDIDATE_BIN" ]] || die "归档中未找到二进制 ${BIN_NAME}"
  chmod 755 "$CANDIDATE_BIN"
  local reported
  reported="$($CANDIDATE_BIN -version 2>/dev/null || true)"
  if [[ "$reported" != *"EasyCard ${ver}"* ]]; then
    die "候选程序版本不匹配，期望 ${ver}，实际输出: ${reported:-无}"
  fi
  info "候选程序版本校验通过: $reported"
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
  if health_ready; then
    DEPLOYMENT_STATE="ready"
    return 0
  fi
  if setup_pending; then
    DEPLOYMENT_STATE="setup"
    return 0
  fi
  return 1
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
  systemctl restart "${SERVICE_NAME}"
  if wait_deployment; then
    if [[ "$DEPLOYMENT_STATE" == "setup" ]]; then
      info "服务进程与数据库检查通过，正在等待首次安装向导完成；安装完成后请再验证 /health/ready"
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
      cp -f "${INSTALL_DIR}/${SERVICE_NAME}.service.previous" "/etc/systemd/system/${SERVICE_NAME}.service"
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
  install_deps_hint

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
  create_user
  mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/data" "$INSTALL_DIR/backups" "$INSTALL_DIR/logs"
  chown -R easycard:easycard "$INSTALL_DIR"
  write_default_config
  write_systemd
  install_candidate "$ver"
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
  systemctl status ${SERVICE_NAME}
  systemctl restart ${SERVICE_NAME}
  journalctl -u ${SERVICE_NAME} -f

EOF
}

main "$@"
