#!/bin/bash

# ==============================================================================
# Rclone 备份管理面板 (V11.1 "Hotfix" Edition)
#
# 作者: Your Name/GitHub (基于用户反馈迭代)
# 版本: 11.1
# 更新日志:
# v11.1: 紧急修复！修正了手动执行备份时，因使用 `source` 导致在部分系统上
#        出现 "pipe: No such file or directory" 的底层错误。
#        已将调用方式改为更稳定的 `bash` 子进程。
# v11.0: 新增微信推送通知功能！
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

press_any_key() { echo -e "\n${BLUE}按任意键返回主菜单...${NC}"; read -n 1 -s; }
check_root() { if [ "$(id -u)" -ne 0 ]; then echo -e "${RED}[错误] 此脚本需要以 root 用户身份运行。${NC}"; exit 1; fi; }
load_config() { if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; return 0; else return 1; fi; }
check_config_exists() { if ! load_config; then log_warn "操作失败：请先配置备份任务 (选项 3)。"; return 1; fi; return 0; }

# --- 核心逻辑函数 (省略未修改部分) ---

send_notification() {
    if [ -z "$WECHAT_PUSH_KEY" ]; then return; fi
    local title="$1"; local body="$2"
    curl -s --data-urlencode "title=$title" --data-urlencode "desp=$body" "https://sctapi.ftqq.com/${WECHAT_PUSH_KEY}.send" > /dev/null
    log_to_file "[INFO] Notification sent: $title"
}

run_backup_core() {
    #...(此函数内容无变化)
    if ! load_config; then
        log_error "无法加载配置文件，请先完成配置！"
        log_to_file "[ERROR] Backup failed: Cannot load configuration from $CONFIG_FILE"
        exit 1
    fi
    source <(grep -v '^[[:space:]]*#' "$CONFIG_FILE")
    local rclone_args=($RCLONE_GLOBAL_FLAGS)
    local start_time=$(date +%s)
    local task_name="备份任务"
    local use_compression=false
    [[ "$BACKUP_MODE" == "compress" ]] && use_compression=true

    log_to_file "---"; log_to_file "[INFO] Starting $BACKUP_MODE backup task..."
    local source_path="$LOCAL_PATH"

    if $use_compression; then
        task_name="压缩备份"
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local archive_basename=$(basename "$LOCAL_PATH")
        local temp_archive="/tmp/${archive_basename}_${timestamp}.tar.gz"
        log_to_file "[INFO] Compressing '$LOCAL_PATH' to '$temp_archive'..."
        if tar -I 'gzip -6' -cf "$temp_archive" -C "$(dirname "$source_path")" "$(basename "$source_path")"; then
            source_path="$temp_archive"
            log_to_file "[INFO] Compression successful."
        else
            log_error "压缩失败！请检查源目录权限或磁盘空间。"
            log_to_file "[ERROR] Compression of '$LOCAL_PATH' failed."
            local fail_msg="任务 '$task_name' 在压缩阶段就已失败！请登录服务器检查源目录权限或磁盘空间。日志文件: $LOG_FILE"
            send_notification "❌ Rclone 备份失败" "$fail_msg"
            exit 1
        fi
    fi

    local dest_path="${RCLONE_REMOTE_NAME}:${REMOTE_PATH}"
    log_to_file "[INFO] Running Rclone command: rclone copy \"$source_path\" \"$dest_path\" ${rclone_args[*]} $@"

    if rclone copy "$source_path" "$dest_path" "${rclone_args[@]}" "$@"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_info "$task_name 成功完成，耗时 ${duration} 秒。"
        log_to_file "[SUCCESS] $task_name completed successfully in ${duration} seconds."
        local success_msg=$(cat <<EOF
- **任务模式**: $BACKUP_MODE
- **本地路径**: $LOCAL_PATH
- **远程路径**: $dest_path
- **执行耗时**: ${duration} 秒
- **服务器时间**: $(date +"%Y-%m-%d %H:%M:%S")
EOF
        )
        send_notification "✅ Rclone 备份成功" "$success_msg"
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_error "$task_name 失败，耗时 ${duration} 秒。详情请查看日志。"
        log_to_file "[ERROR] $task_name FAILED after ${duration} seconds."
        local fail_msg=$(cat <<EOF
- **任务模式**: $BACKUP_MODE
- **本地路径**: $LOCAL_PATH
- **远程路径**: $dest_path
- **执行状态**: <font color='red'>**失败**</font>
- **错误详情**: 请登录服务器，执行 \`tail -n 50 $LOG_FILE\` 查看详细日志。
- **服务器时间**: $(date +"%Y-%m-%d %H:%M:%S")
EOF
        )
        send_notification "❌ Rclone 备份失败" "$fail_msg"
    fi

    if $use_compression && [ -f "$source_path" ]; then
        rm -f "$source_path"
        log_to_file "[INFO] Cleaned up temporary archive: $source_path"
    fi

    [[ "$ENABLE_LOG_CLEANUP" == "true" ]] && cleanup_logs
}


# --- 菜单功能实现 ---

#...(此处省略多个未修改的函数)...
install_or_update_rclone() { log_info "正在执行 Rclone 官方安装/更新脚本..."; install_dependencies; curl -s https://rclone.org/install.sh | sudo bash; if ! command -v rclone &>/dev/null; then log_error "Rclone 安装/更新失败，请检查网络或手动安装。"; exit 1; fi; log_info "Rclone 安装/更新完成！当前版本：$(rclone --version | head -n 1)"; }
wizard_configure_remote() { clear; echo -e "${GREEN}--- Rclone 网盘配置向导【V11.0 终极修正版】 ---${NC}"; echo "..."; rclone config; log_info "Rclone 配置工具已退出。如果配置成功，您现在可以进行【第3步：配置备份任务】了。"; }
setup_backup_task() { log_info "--- 开始配置备份任务 ---"; while true; do read -p "请输入要备份的【本地目录】的绝对路径: " LOCAL_PATH; if [ -d "$LOCAL_PATH" ]; then break; else log_error "错误：目录 '$LOCAL_PATH' 不存在，请重新输入。"; fi; done; log_info "正在列出您已配置的网盘..."; rclone listremotes; if [ -z "$(rclone listremotes)" ]; then log_error "没有找到已配置的网盘。请先完成第2步。"; return; fi; read -p "请输入上面列表中的【远程网盘名】 (例如 gdrive:): " RCLONE_REMOTE_NAME; RCLONE_REMOTE_NAME=${RCLONE_REMOTE_NAME%:}; read -p "请输入网盘上的【备份目标文件夹路径】 (例如 backup/vps1): " REMOTE_PATH; echo "请选择备份模式:"; echo "  1. 同步模式 (sync)"; echo "  2. 压缩模式 (compress)"; read -p "请输入模式 [1-2, 默认1]: " mode_choice; [[ "$mode_choice" == "2" ]] && BACKUP_MODE="compress" || BACKUP_MODE="sync"; read -p "请输入定时任务的Cron表达式 (例如 '0 3 * * *' 代表每天凌晨3点执行，留空则不设置): " CRON_SCHEDULE; echo -e "\n${YELLOW}【可选】设置微信推送通知 (使用 Server酱):${NC}"; echo "  1. 请先访问 sct.ftqq.com 获取您的 SendKey。"; read -p "  2. 请输入您的 SendKey (留空则不启用此功能): " WECHAT_PUSH_KEY; RCLONE_GLOBAL_FLAGS="--log-file=\"$LOG_FILE\" --log-level=INFO --retries=3"; log_info "正在将配置写入 $CONFIG_FILE ..."; cat > "$CONFIG_FILE" << EOF
# Rclone Backup Configuration File...
LOCAL_PATH="$LOCAL_PATH"
RCLONE_REMOTE_NAME="$RCLONE_REMOTE_NAME"
REMOTE_PATH="$REMOTE_PATH"
BACKUP_MODE="$BACKUP_MODE"
CRON_SCHEDULE="$CRON_SCHEDULE"
WECHAT_PUSH_KEY="$WECHAT_PUSH_KEY"
RCLONE_GLOBAL_FLAGS="$RCLONE_GLOBAL_FLAGS"
ENABLE_LOG_CLEANUP="true"
EOF
log_info "配置已成功保存！"; if [ -n "$CRON_SCHEDULE" ]; then log_info "检测到您输入了Cron表达式，正在为您设置定时任务..."; enable_cron; fi; }

# 【V11.1 修复点】
run_backup_manually() {
    if ! check_config_exists; then return; fi
    log_info "开始手动执行备份任务 (带进度显示)..."
    bash "$SCRIPT_PATH" --run-task --progress  # <-- 已从 '.' 修改为 'bash'
    log_info "手动备份任务执行完毕。"
}

restore_backup() { if ! check_config_exists; then return; fi; echo "恢复功能...";}

# 【V11.1 修复点】
run_backup_dry_run() { 
    if ! check_config_exists; then return; fi;
    log_info "开始演练模式 (不会实际传输文件)..."
    bash "$SCRIPT_PATH" --run-task --progress --dry-run # <-- 已从 '.' 修改为 'bash'
    log_info "演练模式执行完毕。"
}


view_current_config() { if ! check_config_exists; then return; fi; echo -e "--- ${YELLOW}当前备份配置 ($CONFIG_FILE)${NC} ---"; (echo -e "配置项\t值"; echo -e "-------\t---"; grep -v '^#' "$CONFIG_FILE" | sed 's/=/ \t/' | sed 's/"//g') | column -t -s $'\t'; }
view_log() { if [ -f "$LOG_FILE" ]; then echo -e "--- ${YELLOW}最近50条备份日志 ($LOG_FILE)${NC} ---"; tail -n 50 "$LOG_FILE"; else log_warn "日志文件 '$LOG_FILE' 不存在。"; fi; }
enable_cron() { if ! check_config_exists; then return; fi; if [ -z "$CRON_SCHEDULE" ]; then log_error "配置文件中未设置 CRON_SCHEDULE，无法启用定时任务。"; return; fi; (crontab -l 2>/dev/null | grep -v -e "$CRON_COMMENT_TAG" -e "${SCRIPT_PATH}") | crontab -; local job="${CRON_SCHEDULE} ${SCRIPT_PATH} --run-task > /dev/null 2>&1"; (crontab -l 2>/dev/null; echo "# ${CRON_COMMENT_TAG}"; echo "$job") | crontab -; log_info "定时任务已启用。表达式: '$CRON_SCHEDULE'"; }
disable_cron() { (crontab -l 2>/dev/null | grep -v -e "$CRON_COMMENT_TAG" -e "${SCRIPT_PATH}") | crontab -; log_info "所有由本脚本创建的定时任务已被禁用。"; }
uninstall_all(){ log_warn "!!! 警告：此操作将彻底卸载一切 !!!"; read -p "如果您确定要继续，请输入 'uninstall' 并回车: " confirm_uninstall; if [ "$confirm_uninstall" == "uninstall" ]; then log_info "开始执行卸载..."; disable_cron; rm -f "$CONFIG_FILE" "$LOG_FILE"; rm -rf "$HOME/.config/rclone"; sudo rm -f /usr/local/bin/rclone; sudo rm -rf /usr/local/share/man/man1/rclone.1*; log_info "所有相关文件和配置已删除。"; log_warn "脚本将在3秒后自我删除..."; sleep 3; rm -f "$SCRIPT_PATH"; echo "卸载完成。"; exit 0; else log_info "卸载操作已取消。"; fi; }


# --- 主菜单 ---
show_menu() {
    #...(此函数内容无变化)
    local rclone_ver="未安装"; command -v rclone &>/dev/null && rclone_ver=$(rclone version | head -n 1)
    local config_status="${RED}未配置${NC}"; [ -f "$CONFIG_FILE" ] && config_status="${GREEN}已配置${NC}"
    local cron_status="${RED}未启用${NC}"; (crontab -l 2>/dev/null | grep -q "$CRON_COMMENT_TAG") && cron_status="${GREEN}已启用${NC}"
    
    clear
    echo -e "
  ${GREEN}Rclone 备份管理面板 (V11.1 紧急修复版)${NC}
  状态: Rclone [${BLUE}${rclone_ver}${NC}] | 备份配置 [${config_status}] | 定时任务 [${cron_status}]

  --- ${YELLOW}首次使用请按顺序 1 -> 2 -> 3 操作${NC} ---
  1. 安装/更新 Rclone
  2. 配置网盘 (终极修正版中文向导)
  3. 配置备份任务 (已集成微信通知)

  --- ${YELLOW}日常核心操作${NC} ---
  4. 手动执行备份 (带进度)
  5. 从网盘恢复文件
  6. 演练模式 (检查会发生什么)

  --- ${YELLOW}管理与维护${NC} ---
  7. 查看当前配置
  8. 查看备份日志 (最近50条)
  9. [重]启用定时任务
  10. 禁用所有定时任务
  11. ${RED}!! 彻底卸载脚本与Rclone !!${NC}

  0. 退出脚本
"
    read -p "请输入选项 [0-11]: " choice
}

# --- 主程序入口 ---
main() {
    if [[ "$1" == "--run-task" ]]; then shift; run_backup_core "$@"; exit 0; fi
    check_root
    while true; do
        show_menu
        case $choice in
            0) echo "感谢使用，再见！"; exit 0 ;;
            1) install_or_update_rclone; press_any_key ;;
            2) wizard_configure_remote; press_any_key ;;
            3) setup_backup_task; press_any_key ;;
            4) run_backup_manually; press_any_key ;;
            5) restore_backup; press_any_key ;;
            6) run_backup_dry_run; press_any_key ;;
            7) view_current_config; press_any_key ;;
            8) view_log; press_any_key ;;
            9) enable_cron; press_any_key ;;
            10) disable_cron; press_any_key ;;
            11) uninstall_all ;;
            *) log_error "无效输入，请输入 0-11 之间的数字。"; sleep 1 ;;
        esac
    done
}

main "$@"
