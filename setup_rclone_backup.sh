#!/bin/bash

# ==============================================================================
# Rclone 备份管理面板 (V9.0 "Final Boss" Edition)
#
# 作者: Your Name/GitHub (基于用户反馈迭代)
# 版本: 9.0
# 更新日志:
# v9.0: 彻底重写 "保姆级" 向导，适配新版 Rclone 的 `rclone authorize` 远程授权流程。
#       向导现在分为 "服务器" 和 "个人电脑" 两个阶段，并提供了个人电脑上
#       下载和使用 Rclone 的详细步骤，解决了最复杂、最劝退的授权环节。
# v8.0: 详细解释了 scope, service_account 等中间步骤。
# v7.1: 修正了服务器用户在 'Use auto config?' 步骤中应选择 'n' 的关键问题。
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

# --- 核心逻辑函数 ---
install_dependencies(){
    local missing_deps=()
    ! command -v curl &> /dev/null && missing_deps+=("curl")
    ! command -v unzip &> /dev/null && missing_deps+=("unzip")
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warn "检测到缺少依赖: ${missing_deps[*]}，正在尝试安装..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -y >/dev/null && sudo apt-get install -y "${missing_deps[@]}" >/dev/null
        elif command -v yum &> /dev/null; then
            sudo yum install -y "${missing_deps[@]}" >/dev/null
        else
            log_error "无法自动安装依赖，请手动安装: ${missing_deps[*]}"
            return 1
        fi
    fi
}

run_backup_core() {
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
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_error "$task_name 失败，耗时 ${duration} 秒。详情请查看日志。"
        log_to_file "[ERROR] $task_name FAILED after ${duration} seconds."
    fi

    if $use_compression && [ -f "$source_path" ]; then
        rm -f "$source_path"
        log_to_file "[INFO] Cleaned up temporary archive: $source_path"
    fi

    [[ "$ENABLE_LOG_CLEANUP" == "true" ]] && cleanup_logs
}

cleanup_logs() {
    local max_lines=1000
    if [ -f "$LOG_FILE" ] && [ $(wc -l < "$LOG_FILE") -gt $max_lines ]; then
        echo "$(tail -n $max_lines "$LOG_FILE")" > "$LOG_FILE"
        log_to_file "[INFO] Log file cleaned up, retaining last $max_lines lines."
    fi
}

# --- 菜单功能实现 ---

install_or_update_rclone() {
    log_info "正在执行 Rclone 官方安装/更新脚本...";
    install_dependencies
    curl -s https://rclone.org/install.sh | sudo bash
    if ! command -v rclone &>/dev/null; then
        log_error "Rclone 安装/更新失败，请检查网络或手动安装。";
        exit 1;
    fi
    log_info "Rclone 安装/更新完成！当前版本：$(rclone --version | head -n 1)"
}

wizard_configure_remote() {
    clear
    echo -e "${GREEN}--- Rclone 网盘配置【V9.0 终极版】中文向导 ---${NC}"
    echo
    echo -e "本向导将带您走完新版 Rclone 最复杂的远程授权流程。请务必仔细阅读！"
    echo -e "------------------------------------------------------------"
    echo -e "${YELLOW}前序步骤 (1-7)，与之前类似，快速过一遍：${NC}"
    echo -e "   1. 'n/s/q>'             -> 输入 ${BLUE}n${NC} (新建)"
    echo -e "   2. 'name>'               -> 输入一个英文名, 如 ${BLUE}gdrive${NC}"
    echo -e "   3. 'Storage>'           -> 找到云盘 (如Google Drive) 输入其【数字】"
    echo -e "   4. 'client_id>'         -> 直接【回车】"
    echo -e "   5. 'client_secret>'     -> 直接【回车】"
    echo -e "   6. 'scope>'              -> 直接【回车】 (选择默认的完全权限)"
    echo -e "   7. 'Edit advanced config?' -> 直接【回车】 (选择 n, 不编辑高级选项)"
    echo
    echo -e "${YELLOW}【关键步骤】远程授权 (需要服务器和您自己的电脑配合)${NC}"
    echo -e "------------------------------------------------------------"
    echo -e "${BLUE}阶段一：在【服务器】上（当前 SSH 窗口）${NC}"
    echo -e "   - 提示: 'Use auto config?' (y/n)"
    echo -e "   - 操作: 输入 ${BLUE}n${NC} 并回车。"
    echo
    echo -e "   - ${RED}重要！${NC} 接下来服务器会卡住，并显示如下提示:"
    echo -e "     'Execute the following on the machine with the web browser:'"
    echo -e "     '        rclone authorize \"drive\"'"
    echo -e "     'Then paste the result.'"
    echo -e "     'config_token>'"
    echo -e "   - 操作: ${RED}看到这个提示后，不要动这个SSH窗口！把它放在一边，进行第二阶段操作。${NC}"
    echo -e "------------------------------------------------------------"
    echo -e "${BLUE}阶段二：在【您自己的电脑】上（例如 Windows/Mac）${NC}"
    echo -e "   1. 【下载】: 在您的电脑浏览器访问 ${YELLOW}https://rclone.org/downloads/${NC} 下载 Rclone。"
    echo -e "      (例如下载 'Windows (64 bit)' 版，并解压到 C:\\rclone)"
    echo
    echo -e "   2. 【打开命令行】: 在您自己的电脑上打开一个命令行工具（Windows是CMD或PowerShell）。"
    echo -e "      (例如，进入您解压的目录: cd C:\\rclone)"
    echo
    echo -e "   3. 【运行命令】: 在您电脑的命令行里，输入并执行服务器上提示的那句命令："
    echo -e "      比如: ${BLUE}rclone authorize \"gdrive\"${NC} (注意名字要和您第2步起的一致)"
    echo
    echo -e "   4. 【浏览器授权】: 上一步会自动打开浏览器，要求您登录网盘并授权，请照做。"
    echo
    echo -e "   5. 【复制Token】: 授权后，切回您电脑的命令行窗口，会看到一长串被 {} 包起来的文本。"
    echo -e "      ${YELLOW}将这一整段文本（从 { 开始到 } 结束）完整复制下来。${NC}"
    echo -e "------------------------------------------------------------"
    echo -e "${BLUE}阶段三：回到【服务器】上（回到 SSH 窗口）${NC}"
    echo -e "   - 操作: 在光标闪烁的 'config_token>' 后面，【粘贴】您刚刚从自己电脑上复制的全部内容。"
    echo -e "   - 操作: 按下【回车】。"
    echo -e "------------------------------------------------------------"
    echo -e "${YELLOW}收尾步骤 (10-12)${NC}"
    echo -e "   10. 'Configure this as a team drive?' -> 如果是个人盘，直接【回车】 (选n)"
    echo -e "   11. 'Yes this is OK?'                   -> 输入 ${BLUE}y${NC} (确认配置)"
    echo -e "   12. 'n/s/q>'                          -> 输入 ${BLUE}q${NC} (退出)"
    echo -e "------------------------------------------------------------"
    echo
    read -n 1 -s -r -p "说明阅读完毕，按任意键开始进入 Rclone 英文配置界面..."
    
    rclone config
    
    log_info "Rclone 配置工具已退出。如果配置成功，您现在可以进行【第3步：配置备份任务】了。"
}

setup_backup_task() {
    log_info "--- 开始配置备份任务 ---"
    while true; do
        read -p "请输入要备份的【本地目录】的绝对路径: " LOCAL_PATH
        if [ -d "$LOCAL_PATH" ]; then
            break
        else
            log_error "错误：目录 '$LOCAL_PATH' 不存在，请重新输入。"
        fi
    done
    
    log_info "正在列出您已配置的网盘..."
    rclone listremotes
    if [ -z "$(rclone listremotes)" ]; then
        log_error "没有找到已配置的网盘。请先完成第2步。"
        return
    fi
    
    read -p "请输入上面列表中的【远程网盘名】 (例如 gdrive:): " RCLONE_REMOTE_NAME
    RCLONE_REMOTE_NAME=${RCLONE_REMOTE_NAME%:} # 移除末尾的冒号
    
    read -p "请输入网盘上的【备份目标文件夹路径】 (例如 backup/vps1): " REMOTE_PATH
    
    echo "请选择备份模式:"
    echo "  1. 同步模式 (sync): 保持网盘与本地目录完全一致，会删除网盘上多余文件。"
    echo "  2. 压缩模式 (compress): 每次都将本地目录打包成一个 .tar.gz 文件再上传。"
    read -p "请输入模式 [1-2, 默认1]: " mode_choice
    [[ "$mode_choice" == "2" ]] && BACKUP_MODE="compress" || BACKUP_MODE="sync"

    read -p "请输入定时任务的Cron表达式 (例如 '0 3 * * *' 代表每天凌晨3点执行，留空则不设置): " CRON_SCHEDULE
    
    RCLONE_GLOBAL_FLAGS="--log-file=\"$LOG_FILE\" --log-level=INFO --retries=3"
    
    log_info "正在将配置写入 $CONFIG_FILE ..."
    cat > "$CONFIG_FILE" << EOF
# Rclone Backup Configuration File
# Generated by Panel Script V9.0

# 本地备份源目录
LOCAL_PATH="$LOCAL_PATH"

# 远程网盘配置名 (来自 rclone config)
RCLONE_REMOTE_NAME="$RCLONE_REMOTE_NAME"

# 远程网盘目标路径
REMOTE_PATH="$REMOTE_PATH"

# 备份模式: 'sync' 或 'compress'
BACKUP_MODE="$BACKUP_MODE"

# 定时任务Cron表达式 (留空不启用)
CRON_SCHEDULE="$CRON_SCHEDULE"

# Rclone 全局参数
RCLONE_GLOBAL_FLAGS="$RCLONE_GLOBAL_FLAGS"

# 是否启用日志自动清理 (保留最近1000行)
ENABLE_LOG_CLEANUP="true"
EOF
    log_info "配置已成功保存！"
    
    if [ -n "$CRON_SCHEDULE" ]; then
        log_info "检测到您输入了Cron表达式，正在为您设置定时任务..."
        enable_cron
    fi
}

run_backup_manually() {
    if ! check_config_exists; then return; fi
    log_info "开始手动执行备份任务 (带进度显示)..."
    . "$SCRIPT_PATH" --run-task --progress
    log_info "手动备份任务执行完毕。"
}

restore_backup() {
    if ! check_config_exists; then return; fi
    log_warn "【警告】恢复操作将会用网盘文件【覆盖】本地目录内容！"

    while true; do
        read -p "请输入一个【本地空目录】用于存放恢复的文件: " restore_path
        if [ -z "$restore_path" ]; then
            log_error "路径不能为空！"
        elif [ -e "$restore_path" ] && [ "$(ls -A "$restore_path")" ]; then
            log_error "目录 '$restore_path' 不是空的！为安全起见，请提供一个空目录或不存在的路径。"
        else
            mkdir -p "$restore_path"
            break
        fi
    done
    
    local source_path="${RCLONE_REMOTE_NAME}:${REMOTE_PATH}"
    log_info "准备从网盘 [${source_path}] 恢复到本地 [${restore_path}]"
    read -p "请再次确认是否执行恢复操作? [y/N]: " confirm_restore
    if [[ "$confirm_restore" =~ ^[Yy]$ ]]; then
        log_info "开始恢复..."
        rclone copy "$source_path" "$restore_path" --progress
        log_info "恢复完成！文件已存放在 '$restore_path'。"
    else
        log_info "操作已取消。"
    fi
}

run_backup_dry_run() {
    if ! check_config_exists; then return; fi
    log_info "开始执行【演练模式】，只会显示将要执行的操作，不会真正传输文件..."
    . "$SCRIPT_PATH" --run-task --progress --dry-run
    log_info "演练模式执行完毕。"
}

view_current_config() {
    if ! check_config_exists; then return; fi
    echo -e "--- ${YELLOW}当前备份配置 ($CONFIG_FILE)${NC} ---"
    (
        echo -e "配置项\t值"
        echo -e "-------\t---"
        grep -v '^#' "$CONFIG_RILE" | sed 's/=/ \t/' | sed 's/"//g'
    ) | column -t -s $'\t'
}

view_log() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "--- ${YELLOW}最近50条备份日志 ($LOG_FILE)${NC} ---"
        tail -n 50 "$LOG_FILE"
    else
        log_warn "日志文件 '$LOG_FILE' 不存在。"
    fi
}

enable_cron() {
    if ! check_config_exists; then return; fi
    if [ -z "$CRON_SCHEDULE" ]; then
        log_error "配置文件中未设置 CRON_SCHEDULE，无法启用定时任务。"
        return
    fi
    # 先清理旧任务
    (crontab -l 2>/dev/null | grep -v -e "$CRON_COMMENT_TAG" -e "${SCRIPT_PATH}") | crontab -
    # 添加新任务
    local job="${CRON_SCHEDULE} ${SCRIPT_PATH} --run-task > /dev/null 2>&1"
    (crontab -l 2>/dev/null; echo "# ${CRON_COMMENT_TAG}"; echo "$job") | crontab -
    log_info "定时任务已启用。表达式: '$CRON_SCHEDULE'"
}

disable_cron() {
    (crontab -l 2>/dev/null | grep -v -e "$CRON_COMMENT_TAG" -e "${SCRIPT_PATH}") | crontab -
    log_info "所有由本脚本创建的定时任务已被禁用。"
}

uninstall_all() {
    log_warn "!!! 警告：此操作将彻底卸载一切 !!!"
    echo -e "将会执行以下操作:"
    echo -e "  - 禁用并移除所有相关定时任务"
    echo -e "  - 删除备份配置文件 ($CONFIG_FILE)"
    echo -e "  - 删除备份日志文件 ($LOG_FILE)"
    echo -e "  - 删除 Rclone 的全局配置文件 (~/.config/rclone)"
    echo -e "  - 删除 Rclone 主程序"
    echo -e "  - ${RED}删除本管理脚本自身${NC}"
    read -p "如果您确定要继续，请输入 'uninstall' 并回车: " confirm_uninstall
    if [ "$confirm_uninstall" == "uninstall" ]; then
        log_info "开始执行卸载..."
        disable_cron
        rm -f "$CONFIG_FILE" "$LOG_FILE"
        rm -rf "$HOME/.config/rclone" # 用户配置目录
        sudo rm -f /usr/local/bin/rclone # 主程序
        sudo rm -rf /usr/local/share/man/man1/rclone.1* # 手册页
        log_info "所有相关文件和配置已删除。"
        log_warn "脚本将在3秒后自我删除..."
        sleep 3
        rm -f "$SCRIPT_PATH"
        echo "卸载完成。"
        exit 0
    else
        log_info "卸载操作已取消。"
    fi
}

# --- 主菜单 ---
show_menu() {
    local rclone_ver="未安装"
    command -v rclone &>/dev/null && rclone_ver=$(rclone version | head -n 1)
    local config_status="${RED}未配置${NC}"
    [ -f "$CONFIG_FILE" ] && config_status="${GREEN}已配置${NC}"
    local cron_status="${RED}未启用${NC}"
    (crontab -l 2>/dev/null | grep -q "$CRON_COMMENT_TAG") && cron_status="${GREEN}已启用${NC}"
    
    clear
    echo -e "
  ${GREEN}Rclone 备份管理面板 (V9.0)${NC}
  状态: Rclone [${BLUE}${rclone_ver}${NC}] | 备份配置 [${config_status}] | 定时任务 [${cron_status}]

  --- ${YELLOW}首次使用请按顺序 1 -> 2 -> 3 操作${NC} ---
  1. 安装/更新 Rclone
  2. 配置网盘 (终极版中文向导)
  3. 配置备份任务

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
    # 如果脚本被以 --run-task 参数调用，则直接执行备份核心，不显示菜单
    if [[ "$1" == "--run-task" ]]; then
        shift
        run_backup_core "$@"
        exit 0
    fi

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
