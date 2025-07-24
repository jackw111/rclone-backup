#!/bin/bash

# ==============================================================================
# Rclone 备份管理面板 (V6.0 Workflow Edition)
#
# 作者: Your Name/GitHub (基于用户反馈重构)
# 版本: 6.0
# 更新日志:
# v6.0: 根据用户反馈重构菜单布局，使其更符合新用户的使用流程。
# v5.1: 修复了 setup_backup_task 函数缺失导致无法配置任务的严重 bug。
#
# 使用方法:
# 1. 保存为 rclone_panel.sh
# 2. chmod +x rclone_panel.sh
# 3. sudo ./rclone_panel.sh
# ==============================================================================

# --- 全局变量和美化输出 ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

CONFIG_FILE="/etc/rclone_backup.conf"
LOG_FILE="/var/log/rclone_backup.log"
CRON_COMMENT_TAG="Rclone-Backup-Job-by-Panel-Script"
SCRIPT_PATH=$(realpath "$0")

# --- 基础辅助函数 ---
log_info() { echo -e "${GREEN}[信息] $(date +"%Y-%m-%d %H:%M:%S") $1${NC}"; }
log_warn() { echo -e "${YELLOW}[警告] $(date +"%Y-%m-%d %H:%M:%S") $1${NC}"; }
log_error() { echo -e "${RED}[错误] $(date +"%Y-%m-%d %H:%M:%S") $1${NC}"; }
log_to_file() { echo "$(date +"%Y-%m-%d %H:%M:%S") $1" >> "$LOG_FILE"; }

press_any_key() {
    echo -e "\n${BLUE}按任意键返回主菜单...${NC}"
    read -n 1 -s
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
       echo -e "${RED}[错误] 此脚本需要以 root 用户身份运行。请使用 'sudo ./rclone_panel.sh'。${NC}"
       exit 1
    fi
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

check_config_exists() {
    if ! load_config; then
        log_warn "操作失败：尚未配置备份任务。"
        log_warn "请先从主菜单选择 '3. 配置备份任务'。"
        return 1
    fi
    return 0
}

# --- 核心逻辑函数 (备份、恢复、通知等) ---
install_dependencies() {
    local missing_deps=()
    ! command -v curl &> /dev/null && missing_deps+=("curl")
    ! command -v unzip &> /dev/null && missing_deps+=("unzip")
    ! command -v jq &> /dev/null && missing_deps+=("jq")
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warn "检测到缺少以下依赖: ${missing_deps[*]}，正在尝试自动安装..."
        if command -v apt-get &> /dev/null; then sudo apt-get update -y >/dev/null && sudo apt-get install -y "${missing_deps[@]}" >/dev/null
        elif command -v yum &> /dev/null; then sudo yum install -y "${missing_deps[@]}" >/dev/null
        else log_error "无法自动安装依赖。请手动安装: ${missing_deps[*]}"; exit 1; fi
        log_info "依赖安装完成。"
    fi
}

# 核心备份执行函数
run_backup_core() {
    if ! load_config; then log_error "无法加载配置文件，备份中止。"; log_to_file "[ERROR] Backup failed: config file not found."; exit 1; fi
    source <(grep = "$CONFIG_FILE")
    local rclone_args=($RCLONE_GLOBAL_FLAGS)
    local start_time=$(date +%s)
    local task_name="备份任务"
    local use_compress=false
    [[ "$BACKUP_MODE" == "compress" ]] && use_compress=true

    log_to_file "----------------------------------------------"
    log_to_file "[INFO] Backup task started. Mode: $BACKUP_MODE"
    ntpdate pool.ntp.org >/dev/null 2>&1 || log_to_file "[WARN] Time sync failed, continuing anyway."

    # 准备备份源和目标
    local source_path="$LOCAL_PATH"
    if $use_compress; then
        task_name="压缩并备份"
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local archive_basename=$(basename "$LOCAL_PATH")
        local temp_archive="/tmp/${archive_basename}_${timestamp}.tar.gz"
        log_to_file "[INFO] Compressing '$LOCAL_PATH' to '$temp_archive'..."
        if tar -I 'gzip -6' -cf "$temp_archive" -C "$(dirname "$LOCAL_PATH")" "$(basename "$LOCAL_PATH")"; then
            source_path="$temp_archive"
            log_to_file "[INFO] Compression successful."
        else
            log_error "压缩失败！请检查源目录权限和磁盘空间。"
            log_to_file "[ERROR] Compression failed for '$LOCAL_PATH'."
            send_notification "error" "Rclone: '$LOCAL_PATH' 压缩失败" "请检查服务器日志 $LOG_FILE"
            exit 1
        fi
    fi

    local dest_path="${RCLONE_REMOTE_NAME}:${REMOTE_PATH}"
    log_to_file "[INFO] Source: '$source_path'"
    log_to_file "[INFO] Destination: '$dest_path'"
    log_to_file "[INFO] Rclone command flags: ${rclone_args[*]} $@"

    # 执行备份
    if rclone copy "$source_path" "$dest_path" "${rclone_args[@]}" "$@"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_to_file "[SUCCESS] $task_name completed in $duration seconds."
        send_notification "success" "Rclone: $task_name 成功" "源: $LOCAL_PATH, 耗时: ${duration}s"
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_error "$task_name 失败！详情请查看日志: $LOG_FILE"
        log_to_file "[ERROR] $task_name failed after $duration seconds."
        send_notification "error" "Rclone: $task_name 失败" "请检查服务器日志 $LOG_FILE"
    fi

    # 清理
    $use_compress && rm -f "$source_path"
    [[ "$ENABLE_LOG_CLEANUP" == "true" ]] && cleanup_logs
}

send_notification() {
    if [ -z "$SERVERCHAN_KEY" ]; then return; fi
    local status_title=""
    [[ "$1" == "success" ]] && status_title="✅ 备份成功"
    [[ "$1" == "error" ]] && status_title="❌ 备份失败"
    local title="${2:-$status_title}"
    local content="${3:-"No details provided."}"
    log_to_file "[INFO] Sending notification: ${title}"
    curl -s -X POST "https://sctapi.ftqq.com/${SERVERCHAN_KEY}.send" \
        -d "title=${title}" -d "desp=${content}" > /dev/null
}

cleanup_logs() {
    local max_lines=1000
    if [ -f "$LOG_FILE" ] && [ $(wc -l < "$LOG_FILE") -gt $max_lines ]; then
        log_to_file "[INFO] Log file exceeds $max_lines lines, trimming..."
        echo "$(tail -n $max_lines "$LOG_FILE")" > "$LOG_FILE"
    fi
}

# --- 菜单功能实现 ---

# 1. 安装/更新 Rclone
install_or_update_rclone() {
    log_info "正在执行 Rclone 官方安装/更新脚本..."; install_dependencies
    curl -s https://rclone.org/install.sh | sudo bash
    if ! command -v rclone &>/dev/null; then log_error "Rclone 安装/更新失败。"; exit 1; fi
    log_info "Rclone 安装/更新完成！当前版本：$(rclone --version | head -n 1)"
}

# 2. 配置网盘
configure_remote() {
    log_info "您将进入 Rclone 官方配置向导来添加/删除/修改网盘配置。"
    log_info "这是配置备份任务的【第二步】。"
    load_config
    log_info "当前备份任务使用的远程是: ${BLUE}${RCLONE_REMOTE_NAME:-未配置}${NC}"
    echo -e "${YELLOW}请根据接下来的向导完成操作，例如输入 'n' 创建一个新的远程。${NC}"
    rclone config
    log_info "网盘配置完成。现在您可以进行【第三步】：配置备份任务。"
}

# 3. 配置/重置备份任务
setup_backup_task() {
    log_info "--- 开始配置 Rclone 备份任务 ---"
    
    # 步骤1: 本地备份目录
    while true; do
        read -p "请输入您要备份的【本地文件夹绝对路径】: " LOCAL_PATH
        if [ -d "$LOCAL_PATH" ]; then break; else log_error "目录不存在，请重新输入。"; fi
    done

    # 步骤2: Rclone 远程名称
    log_info "正在列出您已配置的 Rclone 远程网盘..."
    rclone listremotes
    read -p "请输入上面列表中的【远程网盘名称】(例如 a-drive): " RCLONE_REMOTE_NAME
    RCLONE_REMOTE_NAME=${RCLONE_REMOTE_NAME%:}

    # 步骤3: 远程备份路径
    read -p "请输入网盘中的【备份目标文件夹路径】(如 'backups/vps1', 留空则为根目录): " REMOTE_PATH

    # 步骤4: 备份模式
    echo "请选择备份模式:"
    echo "  1. sync (同步模式: 保持远程和本地完全一致，远程多余文件会被删除!)"
    echo "  2. compress (压缩模式: 每次将本地目录压缩成一个 tar.gz 文件再上传)"
    read -p "请输入模式编号 [1-2, 默认 1]: " mode_choice
    [[ "$mode_choice" == "2" ]] && BACKUP_MODE="compress" || BACKUP_MODE="sync"

    # 步骤5: 定时任务
    read -p "请输入【定时任务的 Cron 表达式】(例如 '0 3 * * *' 代表每天凌晨3点, 直接回车则不设置): " CRON_SCHEDULE

    # --- 高级选项 ---
    log_info "\n--- 高级选项 ---"
    read -p "是否启用低优先级模式 (ionice/nice)? [Y/n]: " use_low_prio
    [[ "$use_low_prio" =~ ^[Nn]$ ]] && LOW_PRIORITY="false" || LOW_PRIORITY="true"

    read -p "是否限制上传速度? (例如 5M, 100K, 留空不限制): " bw_limit
    BANDWIDTH_LIMIT_FLAG=""
    [[ -n "$bw_limit" ]] && BANDWIDTH_LIMIT_FLAG="--bwlimit $bw_limit"

    # --- 通知选项 ---
    log_info "\n--- 通知选项 ---"
    read -p "是否启用 ServerChan 微信通知? [Y/n]: " enable_notify
    SERVERCHAN_KEY=""
    if [[ ! "$enable_notify" =~ ^[Nn]$ ]]; then
        read -p "请输入您的 ServerChan SendKey: " SERVERCHAN_KEY
    fi

    # --- 日志选项 ---
    read -p "是否自动清理旧日志 (保留最近1000行)? [Y/n]: " enable_log_cleanup
    [[ "$enable_log_cleanup" =~ ^[Nn]$ ]] && ENABLE_LOG_CLEANUP="false" || ENABLE_LOG_CLEANUP="true"
    
    RCLONE_GLOBAL_FLAGS="--log-file=\"$LOG_FILE\" --log-level=INFO --retries=3 --retries-sleep=30s"
    [[ "$BACKUP_MODE" == "sync" ]] && RCLONE_GLOBAL_FLAGS="$RCLONE_GLOBAL_FLAGS --delete-during"
    [[ -n "$BANDWIDTH_LIMIT_FLAG" ]] && RCLONE_GLOBAL_FLAGS="$RCLONE_GLOBAL_FLAGS $BANDWIDTH_LIMIT_FLAG"
    [[ "$LOW_PRIORITY" == "true" ]] && RCLONE_GLOBAL_FLAGS="ionice -c 3 nice -n 19 $RCLONE_GLOBAL_FLAGS"

    # 写入配置文件
    log_info "正在将配置写入 $CONFIG_FILE..."
    cat > "$CONFIG_FILE" << EOF
# Rclone Backup Configuration
# Auto-generated by script on $(date)

LOCAL_PATH="$LOCAL_PATH"
RCLONE_REMOTE_NAME="$RCLONE_REMOTE_NAME"
REMOTE_PATH="$REMOTE_PATH"
BACKUP_MODE="$BACKUP_MODE"
CRON_SCHEDULE="$CRON_SCHEDULE"
RCLONE_GLOBAL_FLAGS="$RCLONE_GLOBAL_FLAGS"
SERVERCHAN_KEY="$SERVERCHAN_KEY"
ENABLE_LOG_CLEANUP="$ENABLE_LOG_CLEANUP"
EOF

    log_info "配置完成！"
    if [ -n "$CRON_SCHEDULE" ]; then
        log_info "您设置了 Cron 表达式，将自动为您启用定时任务..."
        enable_cron
    else
        log_info "您未设置 Cron 表达式，定时任务未启用。可稍后从主菜单手动启用。"
    fi
}

# 4. 手动执行一次备份
run_backup_manually() {
    if ! check_config_exists; then return; fi
    log_info "开始手动执行备份任务，可按 Ctrl+C 中断。详细日志将实时写入 $LOG_FILE"
    . "$SCRIPT_PATH" --run-task --progress 
    log_info "手动备份任务执行完毕。"
}

# 5. 从网盘恢复备份
restore_backup() {
    if ! check_config_exists; then return; fi
    log_info "恢复操作会将网盘内容同步到本地，这可能会覆盖或删除本地文件！"
    read -p "请输入接收恢复文件的本地路径 (必须是空目录或不存在的目录):" restore_path
    if [ -z "$restore_path" ]; then log_error "路径不能为空！"; return; fi
    if [ -d "$restore_path" ] && [ "$(ls -A $restore_path)" ]; then
        log_error "恢复目录不是空的！为了您的数据安全，操作已中止。"
        return
    fi
    mkdir -p "$restore_path"
    
    local source_path="${RCLONE_REMOTE_NAME}:${REMOTE_PATH}"
    log_info "将从 [${source_path}] 恢复到 [${restore_path}]"
    read -p "确认开始恢复吗? [y/N]: " confirm_restore
    if [[ "$confirm_restore" =~ ^[Yy]$ ]]; then
        log_info "正在恢复... 请稍候..."
        rclone copy "$source_path" "$restore_path" --progress
        log_info "恢复完成！文件已存放在: $restore_path"
    else
        log_info "操作已取消。"
    fi
}

# 6. 演练模式 (Dry Run)
run_backup_dry_run() {
    if ! check_config_exists; then return; fi
    log_info "开始执行演练模式 (Dry Run)，不会有任何实际文件变动。"
    . "$SCRIPT_PATH" --run-task --progress --dry-run
    log_info "演练模式执行完毕。"
}

# 7. 查看当前备份配置
view_current_config() {
    if ! check_config_exists; then return; fi
    echo -e "--- ${YELLOW}当前备份配置 ($CONFIG_FILE)${NC} ---"
    if command -v column &>/dev/null; then
        (
        echo -e "配置项\t值"
        echo -e "-------\t---"
        grep -v '^#' "$CONFIG_FILE" | sed 's/=/ \t/' | sed 's/"//g'
        ) | column -t -s $'\t'
    else
        cat "$CONFIG_FILE"
    fi
}

# 8. 查看备份日志
view_log() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "--- ${YELLOW}显示最近 50 条日志 (完整日志位于 $LOG_FILE)${NC} ---"
        tail -n 50 "$LOG_FILE"
    else
        log_warn "日志文件不存在。"
    fi
}

# 9. 启用定时任务
enable_cron() {
    if ! check_config_exists; then return; fi
    if [ -z "$CRON_SCHEDULE" ]; then
        log_warn "配置文件中未设置 CRON_SCHEDULE，无法启用定时任务。"
        read -p "是否现在就去配置任务？[Y/n]" go_config
        [[ ! "$go_config" =~ ^[Nn]$ ]] && setup_backup_task
        return
    fi
    disable_cron >/dev/null 2>&1
    local cron_job="${CRON_SCHEDULE} ${SCRIPT_PATH} --run-task"
    (crontab -l 2>/dev/null; echo "# ${CRON_COMMENT_TAG}"; echo "$cron_job") | crontab -
    log_info "定时任务已启用。"
}

# 10. 禁用定时任务
disable_cron() {
    (crontab -l 2>/dev/null | grep -v "$CRON_COMMENT_TAG") | crontab - >/dev/null 2>&1
    (crontab -l 2>/dev/null | grep -v "${SCRIPT_PATH}") | crontab -
    log_info "定时任务已禁用。"
}

# 11. 卸载 Rclone 和脚本
uninstall_all() {
    log_warn "这将从系统中彻底移除 Rclone、脚本配置和定时任务！"
    read -p "这是一个不可逆操作，确认请输入 'uninstall' : " confirm
    if [ "$confirm" == "uninstall" ]; then
        log_info "正在停止并禁用定时任务..."; disable_cron
        log_info "正在删除脚本配置文件和日志..."; rm -f "$CONFIG_FILE" "$LOG_FILE"
        read -p "是否要移除 Rclone 程序本身? [y/N]: " remove_bin
        if [[ "$remove_bin" =~ ^[Yy]$ ]]; then
            log_info "正在卸载 Rclone 程序..."; rm -f /usr/local/bin/rclone /usr/local/share/man/man1/rclone.1
            log_info "Rclone 程序已卸载。"
        fi
        read -p "是否要删除所有 Rclone 的网盘配置 (~/.config/rclone/rclone.conf)? [y/N]: " remove_rclone_conf
        if [[ "$remove_rclone_conf" =~ ^[Yy]$ ]]; then
            log_info "正在删除 Rclone 网盘配置文件..."; rm -rf ~/.config/rclone
            log_info "Rclone 网盘配置文件已删除。"
        fi
        log_info "卸载完成！脚本即将退出。"; rm -f "$SCRIPT_PATH"; exit 0
    else log_info "卸载操作已取消。"; fi
}


# --- 主菜单显示 ---
show_menu() {
    local rclone_ver="未安装"
    command -v rclone &> /dev/null && rclone_ver=$(rclone version | head -n 1)
    
    local config_status="${RED}未配置${NC}"
    [ -f "$CONFIG_FILE" ] && config_status="${GREEN}已配置${NC}"

    local cron_status="${RED}未启用${NC}"
    (crontab -l 2>/dev/null | grep -q "$CRON_COMMENT_TAG") && cron_status="${GREEN}已启用${NC}"
    
    clear
    echo -e "
  ${GREEN}Rclone 备份管理面板 (V6.0 Workflow Edition)${NC}

  状态: Rclone [${BLUE}${rclone_ver}${NC}] | 备份配置 [${config_status}] | 定时任务 [${cron_status}]

  --- ${YELLOW}首次设置 (推荐流程 1 -> 2 -> 3)${NC} ---
  1. 安装/更新 Rclone
  2. 配置网盘 (添加/修改云盘授权)
  3. 配置备份任务 (指定备份内容和方式)
————————————————————————————————
  --- ${YELLOW}日常核心操作${NC} ---
  4. 手动执行一次备份
  5. 从网盘恢复备份
  6. 演练模式 (Dry Run)
————————————————————————————————
  --- ${YELLOW}状态与管理${NC} ---
  7. 查看当前备份配置
  8. 查看备份日志
  9. 启用定时任务
  10. 禁用定时任务
————————————————————————————————
  11. ${RED}卸载 Rclone 和脚本${NC}
  0. 退出脚本
"
    echo
    read -p "请输入选项 [0-11]: " choice
}

# --- 主程序入口 ---
main() {
    if [[ "$1" == "--run-task" ]]; then
        shift 
        run_backup_core "$@"
        exit 0
    fi
    
    check_root
    
    while true; do
        show_menu
        case $choice in
            0) exit 0 ;;
            1) install_or_update_rclone; press_any_key ;;
            2) configure_remote; press_any_key ;;
            3) setup_backup_task; press_any_key ;;
            4) run_backup_manually; press_any_key ;;
            5) restore_backup; press_any_key ;;
            6) run_backup_dry_run; press_any_key ;;
            7) view_current_config; press_any_key ;;
            8) view_log; press_any_key ;;
            9) enable_cron; press_any_key ;;
            10) disable_cron; press_any_key ;;
            11) uninstall_all ;;
            *) log_error "无效输入，请重试。"; sleep 1 ;;
        esac
    done
}

# 启动主程序
main "$@"
