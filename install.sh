#!/usr/bin/env bash
# EasyCard (易发卡) Linux 一键安装脚本
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/ecard8/EasyCard/main/install.sh | sudo bash
#   或: sudo bash install.sh [版本号，如 1.0.0]
#        sudo bash install.sh --dir /opt/easycard --port 8080 --version 1.0.0
set -euo pipefail

REPO="ecard8/EasyCard"
PRODUCT="EasyCard"
BIN_NAME="cardgo"
INSTALL_DIR="${INSTALL_DIR:-/opt/easycard}"
SERVICE_NAME="${SERVICE_NAME:-easycard}"
PORT="${PORT:-8080}"
VERSION="${VERSION:-}"
ASSUME_YES=0

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
EasyCard Linux 安装脚本

用法:
  sudo bash install.sh [选项] [版本]

选项:
  -d, --dir DIR       安装目录 (默认: /opt/easycard)
  -p, --port PORT     监听端口 (默认: 8080)
  -v, --version VER   指定版本，如 1.0.0；省略则安装最新 Release
  -y, --yes           非交互确认
  -h, --help          显示帮助

示例:
  sudo bash install.sh
  sudo bash install.sh 1.0.0
  sudo bash install.sh --dir /opt/easycard --port 8080 --version 1.0.0
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

api_latest_tag() {
  # 返回不含 v 前缀的版本号
  local tag
  tag="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [[ -n "$tag" ]] || die "无法获取最新 Release，请检查网络或仓库 ${REPO}"
  echo "${tag#v}"
}

asset_url() {
  local ver="$1" arch="$2" name url
  name="${PRODUCT}-${ver}-linux-${arch}.tar.gz"
  url="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/tags/v${ver}" \
    | sed -n "s/.*\"browser_download_url\":[[:space:]]*\"\\([^\"]*${name}\\)\".*/\\1/p" | head -n1)"
  if [[ -z "$url" ]]; then
    # 兼容直接拼接（公开 Release 常见路径）
    url="https://github.com/${REPO}/releases/download/v${ver}/${name}"
  fi
  echo "$url"
}

confirm() {
  if [[ "$ASSUME_YES" -eq 1 ]]; then return 0; fi
  local ans
  read -r -p "确认继续安装到 ${INSTALL_DIR} 并监听 :${PORT} ? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || die "已取消"
}

install_deps_hint() {
  need_cmd curl
  need_cmd tar
  need_cmd sha256sum || warn "未找到 sha256sum，将跳过校验"
}

create_user() {
  if ! id -u easycard >/dev/null 2>&1; then
    useradd --system --home "$INSTALL_DIR" --shell /usr/sbin/nologin easycard 2>/dev/null \
      || useradd --system --home "$INSTALL_DIR" --shell /sbin/nologin easycard
    info "已创建系统用户 easycard"
  fi
}

write_systemd() {
  cat >"/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=EasyCard (易发卡) Card Issuing Service
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
LimitNOFILE=65535
# 仅绑定配置中的端口；默认见 config.json listen
Environment=HOME=${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

write_default_config() {
  local cfg="${INSTALL_DIR}/config.json"
  if [[ -f "$cfg" ]]; then
    info "保留已有配置: $cfg"
    return 0
  fi
  cat >"$cfg" <<EOF
{
  "listen": ":${PORT}",
  "db_path": "data/data.db",
  "base_url": "http://127.0.0.1:${PORT}"
}
EOF
  chown easycard:easycard "$cfg"
  chmod 640 "$cfg"
  info "已生成默认配置: $cfg （首次访问 /admin 完成安装向导）"
}

download_and_extract() {
  local ver="$1" arch="$2" url tmp archive
  url="$(asset_url "$ver" "$arch")"
  tmp="$(mktemp -d)"
  archive="${tmp}/${PRODUCT}-${ver}-linux-${arch}.tar.gz"
  info "下载: $url"
  curl -fL --retry 3 -o "$archive" "$url" || die "下载失败"

  # 可选校验
  if command -v sha256sum >/dev/null 2>&1; then
    local sums_url sums
    sums_url="https://github.com/${REPO}/releases/download/v${ver}/SHA256SUMS"
    sums="${tmp}/SHA256SUMS"
    if curl -fsSL -o "$sums" "$sums_url"; then
      (cd "$tmp" && sha256sum -c SHA256SUMS --ignore-missing) || die "SHA256 校验失败"
      info "SHA256 校验通过"
    else
      warn "未找到 SHA256SUMS，跳过校验"
    fi
  fi

  mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/data" "$INSTALL_DIR/backups" "$INSTALL_DIR/logs"
  tar -xzf "$archive" -C "$tmp"
  if [[ ! -f "${tmp}/${BIN_NAME}" ]]; then
    # 兼容归档内带子目录
    local found
    found="$(find "$tmp" -type f -name "$BIN_NAME" | head -n1 || true)"
    [[ -n "$found" ]] || die "归档中未找到二进制 ${BIN_NAME}"
    install -m 755 "$found" "${INSTALL_DIR}/${BIN_NAME}"
  else
    install -m 755 "${tmp}/${BIN_NAME}" "${INSTALL_DIR}/${BIN_NAME}"
  fi
  echo "$ver" > "${INSTALL_DIR}/VERSION"
  chown -R easycard:easycard "$INSTALL_DIR"
  rm -rf "$tmp"
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

  create_user
  download_and_extract "$ver" "$arch"
  write_default_config
  write_systemd

  systemctl enable "${SERVICE_NAME}" >/dev/null
  systemctl restart "${SERVICE_NAME}"
  sleep 1
  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    info "服务已启动: systemctl status ${SERVICE_NAME}"
  else
    warn "服务可能未就绪，请查看: journalctl -u ${SERVICE_NAME} -e"
  fi

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
