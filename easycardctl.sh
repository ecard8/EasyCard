#!/usr/bin/env bash
# EasyCard Linux service manager installed as /usr/local/bin/easycard.
set -euo pipefail

CONFIG_FILE="${EASYCARD_MANAGER_CONFIG:-/etc/easycard/manager.conf}"
INSTALL_DIR="/opt/easycard"
SERVICE_NAME="easycard"
DEFAULT_PORT="18765"
REPO="ecard8/EasyCard"
SYSTEMD_UNIT_DIR="${EASYCARD_SYSTEMD_UNIT_DIR:-/etc/systemd/system}"

if [[ -r "$CONFIG_FILE" ]]; then
  # The installer creates this root-owned file with shell-escaped values.
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; NC=$'\033[0m'
info() { echo "${GREEN}[INFO]${NC} $*"; }
warn() { echo "${YELLOW}[WARN]${NC} $*"; }
die() { echo "${RED}[ERR ]${NC} $*" >&2; exit 1; }

validate_config() {
  [[ "$INSTALL_DIR" == /* && "$INSTALL_DIR" != *$'\n'* ]] || die "安装目录配置无效: $INSTALL_DIR"
  [[ "$SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]] || die "systemd 服务名配置无效: $SERVICE_NAME"
  [[ "$DEFAULT_PORT" =~ ^[0-9]+$ ]] && (( DEFAULT_PORT >= 1 && DEFAULT_PORT <= 65535 )) || die "默认端口配置无效"
}

need_root() {
  [[ "$(id -u)" -eq 0 ]] || die "此操作需要 root 权限，请使用: sudo easycard $*"
}

need_systemd() {
  command -v systemctl >/dev/null 2>&1 || die "当前系统未提供 systemctl"
  [[ -f "${SYSTEMD_UNIT_DIR}/${SERVICE_NAME}.service" ]] || die "未找到 EasyCard 服务: ${SERVICE_NAME}.service"
}

service_port() {
  local configured=""
  if [[ -f "${INSTALL_DIR}/config.json" ]]; then
    configured="$(sed -n 's/.*"listen"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${INSTALL_DIR}/config.json" | head -n1)"
    configured="${configured##*:}"
    configured="${configured%]}"
  fi
  if [[ "$configured" =~ ^[0-9]+$ ]] && (( configured >= 1 && configured <= 65535 )); then
    printf '%s\n' "$configured"
  else
    printf '%s\n' "$DEFAULT_PORT"
  fi
}

download() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$out" "$url"
  else
    die "更新需要 curl 或 wget"
  fi
}

show_help() {
  cat <<'EOF'
EasyCard 易卡数字平台 Linux 管理工具

用法:
  easycard                         打开交互菜单
  easycard status                  查看服务状态
  easycard start                   启动服务
  easycard stop                    停止服务
  easycard restart                 重启服务
  easycard update [版本]           更新到最近公开版本，或指定版本
  easycard port [新端口]           查看或更换监听端口
  easycard logs [行数]             查看最近日志（默认 100 行）
  easycard logs -f                 持续查看日志
  easycard version                 查看已安装版本
  easycard help                    显示帮助

兼容写法: easycard -start / easycard -stop / easycard -restart / easycard -update / easycard -status / easycard -port
服务变更和更新操作需要 root 权限，建议使用 sudo easycard <命令>。
EOF
}

show_status() {
  need_systemd
  systemctl status "$SERVICE_NAME" --no-pager
}

start_service() {
  need_root "$@"; need_systemd
  systemctl start "$SERVICE_NAME"
  info "EasyCard 已启动"
}

stop_service() {
  need_root "$@"; need_systemd
  systemctl stop "$SERVICE_NAME"
  info "EasyCard 已停止"
}

restart_service() {
  need_root "$@"; need_systemd
  systemctl restart "$SERVICE_NAME"
  info "EasyCard 已重启"
  systemctl is-active --quiet "$SERVICE_NAME" || die "服务未能保持运行，请执行 easycard logs"
}

show_logs() {
  need_systemd
  if [[ "${1:-}" == "-f" || "${1:-}" == "--follow" ]]; then
    journalctl -u "$SERVICE_NAME" -f
    return
  fi
  local lines="${1:-100}"
  [[ "$lines" =~ ^[0-9]+$ ]] && (( lines >= 1 && lines <= 5000 )) || die "日志行数必须为 1-5000"
  journalctl -u "$SERVICE_NAME" -n "$lines" --no-pager
}

show_version() {
  local version="未知"
  [[ -r "${INSTALL_DIR}/VERSION" ]] && version="$(tr -d '\r\n' < "${INSTALL_DIR}/VERSION")"
  echo "EasyCard ${version}"
  if [[ -x "${INSTALL_DIR}/cardgo" ]]; then
    "${INSTALL_DIR}/cardgo" -version || true
  fi
}

port_is_listening() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltnH | awk '{print $4}' | grep -Eq "(^|[.:])${port}$"
    return
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | awk 'NR > 2 {print $4}' | grep -Eq "(^|[.:])${port}$"
    return
  fi
  (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1
}

wait_health_port() {
  local port="$1" i url
  url="http://127.0.0.1:${port}/health"
  for i in $(seq 1 30); do
    if command -v curl >/dev/null 2>&1; then
      curl -fsS --max-time 2 "$url" >/dev/null 2>&1 && return 0
    elif command -v wget >/dev/null 2>&1; then
      wget -q -T 2 -O /dev/null "$url" >/dev/null 2>&1 && return 0
    fi
    sleep 1
  done
  return 1
}

change_port() {
  local new_port="${1:-}" cfg current next tmp backup
  cfg="${INSTALL_DIR}/config.json"
  if [[ -z "$new_port" ]]; then
    echo "当前监听端口: $(service_port)"
    return 0
  fi
  need_root port; need_systemd
  [[ "$new_port" =~ ^[0-9]+$ ]] && (( new_port >= 1 && new_port <= 65535 )) || die "端口必须为 1-65535"
  [[ -f "$cfg" ]] || die "未找到配置文件: $cfg"
  current="$(sed -n 's/.*"listen"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cfg" | head -n1)"
  [[ -n "$current" ]] || die "config.json 中缺少有效的 listen 字段"
  if [[ "$(service_port)" == "$new_port" ]]; then
    info "监听端口已经是 $new_port"
    return 0
  fi
  if port_is_listening "$new_port"; then
    die "端口 $new_port 已被占用，请选择其他端口"
  fi
  if [[ "$current" =~ ^[0-9]+$ ]]; then
    next="$new_port"
  elif [[ "$current" == *:* && "${current##*:}" =~ ^[0-9]+$ ]]; then
    next="${current%:*}:$new_port"
  else
    die "当前 listen 格式无法安全修改: $current"
  fi
  backup="${cfg}.port.previous"
  cp -f "$cfg" "$backup"
  tmp="$(mktemp "${cfg}.tmp.XXXXXX")"
  if ! awk -v replacement="$next" 'BEGIN { done=0 } !done && $0 ~ /"listen"[[:space:]]*:/ { sub(/"listen"[[:space:]]*:[[:space:]]*"[^"]*"/, "\"listen\": \"" replacement "\""); done=1 } { print } END { if (!done) exit 42 }' "$cfg" > "$tmp"; then
    rm -f "$tmp"
    die "更新 listen 字段失败，原配置未改变"
  fi
  chown easycard:easycard "$tmp"
  chmod 640 "$tmp"
  mv -f "$tmp" "$cfg"
  if systemctl restart "$SERVICE_NAME" && wait_health_port "$new_port"; then
    info "监听端口已从 ${current} 更换为 ${next}；base_url 保持不变"
    command -v logger >/dev/null 2>&1 && logger -t easycard-manager "listen port changed from ${current} to ${next}"
    return 0
  fi
  warn "新端口启动失败，正在恢复原配置"
  cp -f "$backup" "$cfg"
  chown easycard:easycard "$cfg"
  chmod 640 "$cfg"
  systemctl restart "$SERVICE_NAME" || true
  die "端口修改失败，已恢复原配置；请执行 easycard logs 查看原因"
}

update_service() {
  need_root "$@"; need_systemd
  local version="${1:-}" tmp installer port result
  tmp="$(mktemp -d)"
  installer="${tmp}/install.sh"
  port="$(service_port)"
  info "正在下载官方更新器"
  download "https://raw.githubusercontent.com/${REPO}/main/install.sh" "$installer"
  local args=(-y --dir "$INSTALL_DIR" --port "$port")
  [[ -n "$version" ]] && args+=(--version "${version#v}")
  if INSTALL_DIR="$INSTALL_DIR" SERVICE_NAME="$SERVICE_NAME" PORT="$port" bash "$installer" "${args[@]}"; then
    result=0
  else
    result=$?
  fi
  rm -rf -- "$tmp"
  return "$result"
}

run_command() {
  local command="${1:-}"
  shift || true
  command="${command#--}"
  command="${command#-}"
  case "$command" in
    status) show_status "$@" ;;
    start) start_service start ;;
    stop) stop_service stop ;;
    restart) restart_service restart ;;
    update|upgrade) update_service "$@" ;;
    port|set-port|change-port) change_port "$@" ;;
    logs|log) show_logs "$@" ;;
    version) show_version ;;
    help|h) show_help ;;
    *) die "未知命令: ${command:-空}；请执行 easycard help" ;;
  esac
}

menu() {
  [[ -t 0 ]] || { show_help; return; }
  printf '\n%sEasyCard 易卡数字平台%s\n' "$CYAN" "$NC"
  printf '  1) 查看状态\n  2) 启动服务\n  3) 停止服务\n  4) 重启服务\n  5) 在线更新\n  6) 查看日志\n  7) 查看版本\n  8) 更换监听端口\n  0) 退出\n'
  read -r -p "请选择 [0-8]: " choice
  case "$choice" in
    1) show_status || true ;;
    2) start_service start ;;
    3) stop_service stop ;;
    4) restart_service restart ;;
    5) update_service ;;
    6) show_logs 100 ;;
    7) show_version ;;
    8) read -r -p "请输入新端口（1-65535）: " new_port; change_port "$new_port" ;;
    0) return ;;
    *) warn "无效选项" ;;
  esac
}

validate_config
if [[ $# -eq 0 ]]; then
  menu
else
  run_command "$@"
fi
