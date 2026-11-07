#!/usr/bin/env bash
# EasyCard Linux service manager installed as /usr/local/bin/easycard.
set -euo pipefail

CONFIG_FILE="${EASYCARD_MANAGER_CONFIG:-/etc/easycard/manager.conf}"
INSTANCES_DIR="${EASYCARD_INSTANCES_DIR:-$(dirname "$CONFIG_FILE")/instances}"
INSTALL_DIR="/opt/easycard"
SERVICE_NAME="easycard"
DEFAULT_PORT="18765"
REPO="ecard8/EasyCard"
SYSTEMD_UNIT_DIR="${EASYCARD_SYSTEMD_UNIT_DIR:-/etc/systemd/system}"
MANAGER_BIN="${EASYCARD_MANAGER_BIN:-/usr/local/bin/easycard}"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; NC=$'\033[0m'
info() { echo "${GREEN}[INFO]${NC} $*"; }
warn() { echo "${YELLOW}[WARN]${NC} $*"; }
die() { echo "${RED}[ERR ]${NC} $*" >&2; exit 1; }

valid_instance_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.@-]*$ ]]; }

# Registry files are root-owned shell-escaped configuration, like legacy manager.conf.
INSTANCE_NAMES=()
INSTANCE_FILES=()
discover_instances() {
  local file name existing seen
  INSTANCE_NAMES=(); INSTANCE_FILES=()
  for file in "$INSTANCES_DIR"/*.conf "$CONFIG_FILE"; do
    [[ -f "$file" ]] || continue
    [[ -r "$file" ]] || die "无法读取实例配置: $file"
    name="$(SERVICE_NAME=''; source "$file"; printf '%s' "$SERVICE_NAME")"
    valid_instance_name "$name" || die "实例配置包含无效服务名: $file"
    if [[ "$file" != "$CONFIG_FILE" && "$(basename "$file")" != "$name.conf" ]]; then
      die "实例文件名与服务名不一致: $file"
    fi
    seen=0
    for existing in "${INSTANCE_NAMES[@]}"; do [[ "$existing" != "$name" ]] || seen=1; done
    if [[ "$seen" == 0 ]]; then
      INSTANCE_NAMES+=("$name"); INSTANCE_FILES+=("$file")
    fi
  done
}

load_instance() {
  local index="$1"
  INSTALL_DIR=''; SERVICE_NAME=''; DEFAULT_PORT=''
  source "${INSTANCE_FILES[$index]}"
  validate_config
}

list_instances() {
  local i
  printf '%-24s %-8s %s\n' 'INSTANCE' 'PORT' 'DIRECTORY'
  for i in "${!INSTANCE_NAMES[@]}"; do
    (load_instance "$i"; printf '%-24s %-8s %s\n' "$SERVICE_NAME" "$(service_port)" "$INSTALL_DIR")
  done
}

select_instance() {
  local requested="$1" allow_install="${2:-0}" i choice
  if [[ -n "$requested" ]]; then
    valid_instance_name "$requested" || die "实例名无效: $requested"
    for i in "${!INSTANCE_NAMES[@]}"; do
      if [[ "${INSTANCE_NAMES[$i]}" == "$requested" ]]; then load_instance "$i"; return; fi
    done
    die "未找到实例 $requested；请执行 easycard instances"
  fi
  if [[ "${#INSTANCE_NAMES[@]}" == 0 ]]; then
    die "没有已登记实例；请先安装 EasyCard"
  elif [[ "${#INSTANCE_NAMES[@]}" == 1 ]]; then
    load_instance 0
    return
  fi
  list_instances
  [[ -t 0 ]] || die "存在多个实例，请使用 easycard --instance <实例名> <命令>"
  for i in "${!INSTANCE_NAMES[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${INSTANCE_NAMES[$i]}"; done
  [[ "$allow_install" != 1 ]] || printf '  n) 安装新实例\n'
  read -r -p '请选择实例编号（0 退出）: ' choice || exit 0
  if [[ "$allow_install" == 1 && "$choice" == n ]]; then install_instance; exit $?; fi
  [[ "$choice" != 0 ]] || exit 0
  [[ "$choice" =~ ^[1-9][0-9]*$ && ${#choice} -le 6 ]] || die '无效实例编号'
  (( choice <= ${#INSTANCE_NAMES[@]} )) || die '无效实例编号'
  load_instance "$((choice - 1))"
}

validate_config() {
  [[ "$INSTALL_DIR" == /* && "$INSTALL_DIR" != *$'\n'* ]] || die "安装目录配置无效: $INSTALL_DIR"
  valid_instance_name "$SERVICE_NAME" || die "systemd 服务名配置无效: $SERVICE_NAME"
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
  easycard instances               列出所有实例、端口和目录
  easycard install                 交互安装新实例
  easycard install shop2 --port 18766 --dir /opt/shop2 -y
                                   安装新实例（可加 --version 固定版本）
  easycard remove                  选择并删除实例（默认保留目录数据）
  easycard remove shop2            删除指定实例，交互选择是否保留数据
  easycard --instance shop2 remove --keep-data --confirm shop2
                                   非交互删除；--purge 表示同时删除实例目录
  easycard --instance shop2 status  管理指定实例（-i 同义）
  easycard --instance shop2 update  仅更新指定实例

单实例沿用原命令；多实例服务操作须选择实例。install 是全局操作，无需选择旧实例。
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
  command -v flock >/dev/null 2>&1 || die '端口变更需要 flock'
  exec 9>"$(dirname "$CONFIG_FILE")/install.lock"
  flock -n 9 || die '另一个实例正在安装、更新或修改端口，请稍后再试'
  discover_instances
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
  local i reserved
  for i in "${!INSTANCE_NAMES[@]}"; do
    [[ "${INSTANCE_NAMES[$i]}" != "$SERVICE_NAME" ]] || continue
    reserved="$(load_instance "$i"; service_port)"
    [[ "$reserved" != "$new_port" ]] || die "端口 $new_port 已配置给实例 ${INSTANCE_NAMES[$i]}"
  done
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
    command -v logger >/dev/null 2>&1 && logger -t easycard-manager "instance ${SERVICE_NAME}: listen port changed from ${current} to ${next}"
    return 0
  fi
  warn "新端口启动失败，正在恢复原配置"
  cp -f "$backup" "$cfg"
  chown easycard:easycard "$cfg"
  chmod 640 "$cfg"
  systemctl restart "$SERVICE_NAME" || true
  die "端口修改失败，已恢复原配置；请执行 easycard logs 查看原因"
}

install_instance() {
  need_root install
  command -v systemctl >/dev/null 2>&1 || die '当前系统未提供 systemctl'
  local name='' directory='' port='' version='' yes=0 suggested suffix i reserved answer
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir|--port|--version)
        [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || die "$1 缺少参数"
        case "$1" in --dir) directory="$2" ;; --port) port="$2" ;; --version) version="${2#v}" ;; esac
        shift 2 ;;
      -y|--yes) yes=1; shift ;;
      -*) die "未知安装参数: $1" ;;
      *) [[ -z "$name" ]] || die '只能指定一个新实例名'; name="$1"; shift ;;
    esac
  done
  discover_instances
  if [[ ! -t 0 ]]; then
    [[ -n "$name" && -n "$port" && "$yes" == 1 ]] || die '非交互安装用法: sudo easycard install <新实例名> --port <空闲端口> [--dir <目录>] [-y]（必须加 -y）'
  fi
  if [[ -z "$name" ]]; then
    suffix=2
    while :; do
      suggested="easycard$suffix"; reserved=0
      for i in "${INSTANCE_NAMES[@]}"; do [[ "$i" != "$suggested" ]] || reserved=1; done
      if [[ "$reserved" == 0 && ! -e "/opt/$suggested" && ! -e "$SYSTEMD_UNIT_DIR/$suggested.service" ]]; then break; fi
      suffix=$((suffix + 1))
    done
    read -r -p "新实例名 [$suggested]: " name || return 0
    name="${name:-$suggested}"
  fi
  valid_instance_name "$name" || die '实例名只能使用字母、数字、点、下划线、@ 和连字符，且以字母或数字开头'
  for i in "${INSTANCE_NAMES[@]}"; do [[ "$name" != "$i" ]] || die "实例 $name 已存在；更新请使用 easycard --instance $name update"; done
  [[ ! -e "$SYSTEMD_UNIT_DIR/$name.service" && ! -L "$SYSTEMD_UNIT_DIR/$name.service" ]] || die "同名服务已存在: $name"
  if [[ -z "$directory" ]]; then
    directory="/opt/$name"
    if [[ -t 0 && "$yes" == 0 ]]; then
      read -r -p "安装目录 [$directory]: " answer || return 0
      directory="${answer:-$directory}"
    fi
  fi
  if [[ -z "$port" ]]; then
    suggested=18766
    while (( suggested <= 65535 )); do
      reserved=0
      for i in "${!INSTANCE_NAMES[@]}"; do
        [[ "$(load_instance "$i"; service_port)" != "$suggested" ]] || reserved=1
      done
      if [[ "$reserved" == 0 ]] && ! port_is_listening "$suggested"; then break; fi
      suggested=$((suggested + 1))
    done
    (( suggested <= 65535 )) || die '没有可推荐的空闲端口，请显式指定 --port'
    read -r -p "监听端口 [$suggested]: " port || return 0
    port="${port:-$suggested}"
  fi
  [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] && (( port <= 65535 )) || die '端口必须为 1-65535，且不带前导零'
  [[ "$directory" == /* && "$directory" != *[[:space:]]* ]] || die '安装目录必须是无空白绝对路径'
  [[ -z "$version" || "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] || die '版本号格式无效'
  printf '\n新实例: %s\n目录: %s\n端口: %s\n版本: %s\n' "$name" "$directory" "$port" "${version:-最新公开版本}"
  if [[ "$yes" == 0 ]]; then
    read -r -p '确认安装新实例？[y/N]: ' answer || return 0
    case "$answer" in y|Y|yes|YES) ;; *) info '已取消安装'; return 0 ;; esac
  fi
  local -a args=(--new-instance --instance "$name" --dir "$directory" --port "$port" -y)
  [[ -z "$version" ]] || args+=(--version "$version")
  # Do not inherit the selected instance or library-only mode into the installer.
  (
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' EXIT
    info '正在下载官方安装器'
    download "https://raw.githubusercontent.com/${REPO}/main/install.sh" "$tmp/install.sh" || exit 1
    unset INSTALL_DIR SERVICE_NAME PORT VERSION EASYCARD_INSTALLER_LIBRARY
    bash "$tmp/install.sh" "${args[@]}"
  )
}

verify_managed_unit() {
  local file="$1" directory="$2" expected actual
  expected="$(cat <<EOF
[Unit]
Description=EasyCard Digital Commerce Platform
After=network.target
Wants=network-online.target
[Service]
Type=simple
User=easycard
Group=easycard
WorkingDirectory=$directory
ExecStart=$directory/cardgo -config $directory/config.json
Restart=on-failure
RestartSec=3
TimeoutStopSec=30
KillSignal=SIGTERM
LimitNOFILE=65535
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$directory
RestrictSUIDSGID=true
LockPersonality=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
Environment=HOME=$directory
Environment=CARDGO_ROOT=$directory
[Install]
WantedBy=multi-user.target
EOF
)"
  actual="$(sed -e 's/\r$//' -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$file")" || return 1
  [[ "$actual" == "$expected" ]]
}

remove_instance() (
  need_root remove
  local name='' mode='' confirmation='' answer i directory other shared unit fragment dropins state pid control legacy='' survivor='' tmp
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep-data|--purge)
        [[ -z "$mode" ]] || die '只能选择一种数据处理方式'
        mode="$1"; shift ;;
      --confirm)
        [[ $# -ge 2 && -n "$2" ]] || die '--confirm 缺少实例名'
        confirmation="$2"; shift 2 ;;
      -*) die "未知删除参数: $1（删除不接受 -y，请输入实例名确认）" ;;
      *) [[ -z "$name" ]] || die '只能删除一个实例'; name="$1"; shift ;;
    esac
  done
  for shared in systemctl realpath flock; do command -v "$shared" >/dev/null 2>&1 || die "删除需要 $shared"; done
  [[ -t 0 || ( -n "$name" && "$confirmation" == "$name" ) ]] || die '非交互删除必须指定实例名及 --confirm 同一实例名'
  # Serialize validation, confirmation and removal with installation and port changes.
  exec 9>"$(dirname "$CONFIG_FILE")/install.lock"
  flock -n 9 || die '另一个实例正在安装、更新、修改端口或删除，请稍后再试'
  discover_instances
  select_instance "$name"
  name="$SERVICE_NAME"
  directory="$(realpath -m -- "$INSTALL_DIR")" || die '无法解析实例目录'
  [[ "$INSTALL_DIR" == /* && "$INSTALL_DIR" != *[[:space:]]* && "$INSTALL_DIR" != *\\* ]] || die '实例目录格式不安全'
  [[ "$directory" == "$(realpath -ms -- "$INSTALL_DIR")" && ! -L "$INSTALL_DIR" ]] || die '实例目录经过符号链接，拒绝自动删除'
  case "$directory" in /|/opt|/usr|/usr/local|/etc|/var|/var/lib|/home|/root|/tmp|/run|/bin|/sbin|/lib|/lib64|/boot|/dev|/proc|/sys|/mnt|/media|/srv) die '实例目录范围过大，拒绝删除' ;; esac
  for shared in "$(dirname "$CONFIG_FILE")" "$INSTANCES_DIR" "$SYSTEMD_UNIT_DIR" "$(dirname "$MANAGER_BIN")"; do
    shared="$(realpath -m -- "$shared")"
    [[ "$directory" != "$shared" && "$directory" != "$shared/"* && "$shared" != "$directory/"* ]] || die '实例目录与共享管理文件重叠，拒绝删除'
  done
  for i in "${!INSTANCE_NAMES[@]}"; do
    [[ "${INSTANCE_NAMES[$i]}" != "$name" ]] || continue
    other="$(load_instance "$i"; realpath -m -- "$INSTALL_DIR")" || die '无法验证其他实例目录'
    [[ "$other" != "$directory" && "$other" != "$directory/"* && "$directory" != "$other/"* ]] || die "目录与实例 ${INSTANCE_NAMES[$i]} 重叠，拒绝删除"
    [[ -n "$survivor" ]] || survivor="${INSTANCE_FILES[$i]}"
  done
  if [[ -f "$CONFIG_FILE" ]]; then legacy="$(SERVICE_NAME=''; source "$CONFIG_FILE"; printf '%s' "$SERVICE_NAME")"; fi
  unit="$SYSTEMD_UNIT_DIR/$name.service"
  [[ -f "$unit" && ! -L "$unit" ]] || die '目标服务文件缺失或为符号链接，拒绝自动删除'
  verify_managed_unit "$unit" "$directory" || die '服务文件不是标准管理模板或已被自定义，拒绝自动删除'
  [[ ! -e "$unit.d" ]] || die '服务存在自定义覆盖目录，请先人工核对'
  fragment="$(systemctl show "$name.service" --property=FragmentPath --value)" || die '无法确认目标服务来源'
  [[ "$fragment" == "$unit" ]] || die 'systemd 实际服务来源与登记不一致，拒绝删除'
  dropins="$(systemctl show "$name.service" --property=DropInPaths --value)" || die '无法核对服务覆盖配置'
  [[ -z "$dropins" ]] || die '服务存在覆盖配置，请先人工核对'
  # Reverse dependencies can live in another unit even when this file is standard.
  local relationship dependents
  for relationship in ConsistsOf PropagatesStopTo BoundBy RequiredBy RequisiteOf ExecStop ExecStopPost; do
    dependents="$(systemctl show "$name.service" "--property=$relationship" --value)" || die '无法核对服务停止依赖'
    [[ -z "$dependents" ]] || die "服务存在联动依赖 $relationship: $dependents；拒绝自动删除"
  done
  printf '\n将删除实例: %s\n服务: %s.service\n目录: %s\n端口: %s\n' "$name" "$name" "$directory" "$(service_port)"
  if [[ -z "$mode" && -t 0 ]]; then
    printf '  1) 移除服务与登记，保留目录数据（默认）\n  2) 同时永久删除该实例目录及其中全部数据\n  0) 取消\n'
    read -r -p '请选择 [1]: ' answer || exit 0
    case "$answer" in ''|1) mode=--keep-data ;; 2) mode=--purge ;; 0) info '已取消删除'; exit 0 ;; *) die '无效选项' ;; esac
  fi
  mode="${mode:---keep-data}"
  if [[ "$mode" == --purge ]]; then
    command -v findmnt >/dev/null 2>&1 || die '清除数据需要 findmnt 检查挂载目录'
    local mounts mount
    mounts="$(findmnt -rn -o TARGET)" || die '无法确认挂载情况，拒绝清除数据'
    while IFS= read -r mount; do
      [[ "$mount" != "$directory" && "$mount" != "$directory/"* ]] || die '实例目录中存在挂载点，拒绝递归清除'
    done <<< "$mounts"
    warn "将永久删除 $directory 内的配置、数据库、上传、备份和程序；外部数据路径不会清除"
  else
    info "保留目录及全部数据: $directory"
  fi
  if [[ -z "$confirmation" && -t 0 ]]; then
    read -r -p "请输入实例名 $name 确认删除（其他输入取消）: " confirmation || exit 0
    if [[ "$confirmation" != "$name" ]]; then info '已取消删除'; exit 0; fi
  fi
  [[ "$confirmation" == "$name" ]] || die '确认实例名不匹配，未删除'
  systemctl stop "$name.service" || die '服务停止失败，未删除文件或登记'
  state="$(systemctl show "$name.service" --property=ActiveState --value)" || die '无法确认服务已停止，未删除文件或登记'
  pid="$(systemctl show "$name.service" --property=MainPID --value)" || die '无法确认服务进程，未删除文件或登记'
  control="$(systemctl show "$name.service" --property=ControlPID --value)" || die '无法确认服务控制进程，未删除文件或登记'
  [[ ( "$state" == inactive || "$state" == failed ) && "$pid" == 0 && "$control" == 0 ]] || die '服务仍在运行，未删除文件或登记'
  systemctl disable "$name.service" || die '禁用服务失败，实例已停止，文件与登记保留'
  if [[ "$mode" == --purge && -e "$directory" ]]; then
    [[ ! -L "$directory" && "$(realpath -e -- "$directory")" == "$directory" ]] || die '目录在确认后发生变化，拒绝清除'
    mounts="$(findmnt -rn -o TARGET)" || die '无法再次确认挂载情况，拒绝清除数据'
    while IFS= read -r mount; do
      [[ "$mount" != "$directory" && "$mount" != "$directory/"* ]] || die '确认后出现挂载点，拒绝清除数据'
    done <<< "$mounts"
    rm -rf --one-file-system --preserve-root=all -- "$directory" || die '数据清除未完成，实例已停止，服务文件与登记保留'
  fi
  rm -f -- "$unit" || die '移除服务文件失败，实例登记保留'
  systemctl daemon-reload || die '重新加载服务配置失败，实例登记保留，请人工核对'
  if [[ "$legacy" == "$name" ]]; then
    if [[ -n "$survivor" ]]; then
      tmp="$(mktemp "${CONFIG_FILE}.tmp.XXXXXX")"
      trap '[[ -z "${tmp:-}" ]] || rm -f -- "$tmp"' EXIT
      install -o root -g root -m 644 "$survivor" "$tmp"
      mv -f -- "$tmp" "$CONFIG_FILE"; tmp=''
    else
      rm -f -- "$CONFIG_FILE"
    fi
  fi
  rm -f -- "$INSTANCES_DIR/$name.conf"
  info "已删除实例 $name；其他实例、共享管理命令和系统账户保留"
  [[ "$mode" != --keep-data ]] || info "数据仍在 $directory；重新使用前请人工核对，安装器不会覆盖非空目录"
)

update_service() {
  need_root "$@"; need_systemd
  local version="${1:-}" tmp installer port result
  tmp="$(mktemp -d)"
  installer="${tmp}/install.sh"
  port="$(service_port)"
  info "正在下载官方更新器"
  download "https://raw.githubusercontent.com/${REPO}/main/install.sh" "$installer"
  local args=(-y --dir "$INSTALL_DIR" --port "$port" --service "$SERVICE_NAME")
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
  printf '实例: %s  目录: %s  端口: %s\n' "$SERVICE_NAME" "$INSTALL_DIR" "$(service_port)"
  printf '  1) 查看状态\n  2) 启动服务\n  3) 停止服务\n  4) 重启服务\n  5) 在线更新\n  6) 查看日志\n  7) 查看版本\n  8) 更换监听端口\n  9) 安装新实例\n  10) 删除当前实例\n  0) 退出\n'
  read -r -p "请选择 [0-10]: " choice
  case "$choice" in
    1) show_status || true ;;
    2) start_service start ;;
    3) stop_service stop ;;
    4) restart_service restart ;;
    5) update_service ;;
    6) show_logs 100 ;;
    7) show_version ;;
    8) read -r -p "请输入新端口（1-65535）: " new_port; change_port "$new_port" ;;
    9) install_instance ;;
    10) remove_instance "$SERVICE_NAME" ;;
    0) return ;;
    *) warn "无效选项" ;;
  esac
}

main() {
  local instance='' command
  if [[ "${1:-}" == '--instance' || "${1:-}" == '-i' ]]; then
    [[ $# -ge 2 && -n "$2" ]] || die '--instance 需要实例名'
    instance="$2"; shift 2
  fi
  command="${1:-}"
  case "$command" in help|--help|-help|-h) show_help; return ;; esac
  if [[ "$command" == remove || "$command" == uninstall ]]; then
    shift
    if [[ -n "$instance" ]]; then remove_instance "$instance" "$@"; else remove_instance "$@"; fi
    return
  fi
  if [[ "$command" == install ]]; then
    [[ -z "$instance" ]] || die '新增实例请使用 easycard install <新实例名>，不要加前置 --instance'
    shift; install_instance "$@"; return
  fi
  discover_instances
  case "$command" in instances|list) list_instances; return ;; esac
  if [[ $# -eq 0 && ! -t 0 ]]; then show_help; return; fi
  if [[ $# -eq 0 && -z "$instance" && ${#INSTANCE_NAMES[@]} == 0 ]]; then install_instance; return; fi
  local allow_install=0
  [[ $# -ne 0 ]] || allow_install=1
  select_instance "$instance" "$allow_install"
  if [[ $# -eq 0 ]]; then menu; else run_command "$@"; fi
}

main "$@"
