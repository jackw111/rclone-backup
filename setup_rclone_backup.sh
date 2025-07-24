#!/bin/bash

# ==============================================================================
# Rclone 备份管理面板 (V5.0 - Panel Edition)
#
# 作者: Your Name/GitHub (基于用户反馈重构)
# 版本: 5.0
#
# 重构思路:
# 完全仿照 x-ui 等面板管理脚本，提供一个常驻的、功能分组的交互式菜单。
# 用户可按需执行安装、配置、备份、恢复、卸载等独立操作。
#
# 使用方法:
# 1. 保存为 rclone_panel.sh
# 2. chmod +x rclone_panel.sh
# 3. sudo ./rclone_panel.sh
# ==============================================================================

# --- 全局变量和美化输出 ---
# (这部分和之前版本基本相同)
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
        log_warn "请先从主菜单选择 '4. 配置/重置备份任务'。"
        return 1
    fi
    return 0
}

# --- 核心逻辑函数 (备份、恢复、通知等) ---
# 这些函数大部分与之前的版本相同，这里只展示关键部分或有改动的函数
install_dependencies() {
    local missing_deps=()
    ! command -v curl &> /dev/null && missing_deps+=("curl")
    ! command -v unzip &> /dev/null && missing_deps+=("unzip")
    ! command -v jq &> /dev/null && missing_deps+=("jq") # jq 对通知功能很重要
    ! command -v fuse3 &> /dev/null && ! command -v fuse &> /dev/null && missing_deps+=("fuse3 或 fuse")
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warn "检测到缺少以下依赖: ${missing_deps[*]}，正在尝试自动安装..."
        if command -v apt-get &> /dev/null; then apt-get update -y >/dev/null && apt-get install -y "${missing_deps[@]}" >/dev/null
        elif command -v yum &> /dev/null; then yum install -y "${missing_deps[@]}" >/dev/null
        else log_error "无法自动安装依赖。请手动安装: ${missing_deps[*]}"; exit 1; fi
        log_info "依赖安装完成。"
    fi
}

# 核心备份执行函数(内部调用，不对用户展示)
run_backup_core() {
    # 此函数与v4.0版本完全相同，此处省略以节约篇幅
    # ...
    # 完整的 run_backup_core 函数内容
    if ! load_config; then log_error "无法加载配置文件，备份中止。"; exit 1; fi
    source <(grep = "$CONFIG_FILE") # 确保加载最新配置
    # ... 包含所有逻辑：同步时间、资源限制、 sync/compress、通知、日志清理
    # ...
}

# --- 菜单功能实现 ---

# 1. 安装 Rclone
install_rclone() {
    if command -v rclone &> /dev/null; then
        log_info "Rclone 已安装。如需更新，请选择菜单中的更新选项。"
        return
    fi
    log_info "正在安装 Rclone..."
    install_dependencies
    curl -s https://rclone.org/install.sh | sudo bash
    if ! command -v rclone &>/dev/null; then log_error "Rclone 安装失败。"; exit 1; fi
    log_info "Rclone 安装成功！"
}

# 2. 更新 Rclone
update_rclone() {
    log_info "正在执行 Rclone 官方更新脚本..."
    curl -s https://rclone.org/install.sh | sudo bash
    log_info "Rclone 更新完成！新版本：$(rclone --version | head -n 1)"
}

# 3. 卸载 Rclone 和脚本
uninstall_all() {
    log_warn "这将从系统中彻底移除 Rclone、脚本配置和定时任务！"
    read -p "这是一个不可逆操作，确认请输入 'uninstall' : " confirm
    if [ "$confirm" == "uninstall" ]; then
        log_info "正在停止并禁用定时任务..."
        disable_cron
        log_info "正在删除脚本配置文件和日志..."
        rm -f "$CONFIG_FILE" "$LOG_FILE"
        
        read -p "是否要移除 Rclone 程序本身? [y/N]: " remove_bin
        if [[ "$remove_bin" =~ ^[Yy]$ ]]; then
            # 官方卸载脚本步骤
            log_info "正在卸载 Rclone 程序..."
            rm -f /usr/local/bin/rclone /usr/local/share/man/man1/rclone.1
            log_info "Rclone 程序已卸载。"
        fi

        read -p "是否要删除所有 Rclone 的网盘配置 (~/.config/rclone/rclone.conf)? [y/N]: " remove_rclone_conf
        if [[ "$remove_rclone_conf" =~ ^[Yy]$ ]]; then
            log_info "正在删除 Rclone 网盘配置文件..."
            rm -rf ~/.config/rclone
            log_info "Rclone 网盘配置文件已删除。"
        fi
        log_info "卸载完成！脚本即将退出。"
        exit 0
    else
        log_info "卸载操作已取消。"
    fi
}

# 4. 配置/重置备份任务 (这是之前的完整设置向导)
setup_backup_task() {
    # 此函数与v4.0版本完全相同，此处省略以节约篇幅
    # ...
    # 完整的 setup_backup_task 向导内容
    # ...
    # 在向导结束后, 自动启用定时任务
    enable_cron
}

# 5. 查看当前备份配置
view_current_config() {
    if ! check_config_exists; then return; fi
    # 此函数与v4.0版本完全相同，此处省略以节约篇幅
    # ...
    # 完整的 print_current_config 函数内容
    # ...
}

# 6. 单独重新配置网盘
reconfigure_remote() {
    if ! check_config_exists; then return; fi
    log_info "您将为远程 '${RCLONE_REMOTE_NAME}' 重新执行 Rclone 配置向导。"
    rclone config
    log_info "网盘重配完成。"
}

# 7. 手动执行一次备份
run_backup_manually() {
    if ! check_config_exists; then return; fi
    . "$SCRIPT_PATH" --run-task --progress
    log_info "手动备份任务执行完毕。"
}

# 8. 从网盘恢复备份
restore_backup() {
    if ! check_config_exists; then return; fi
    # 此函数与v4.0版本完全相同，此处省略以节约篇幅
    # ...
    # 完整的 restore_backup 函数内容
    # ...
}

# 9. 演练模式 (Dry Run)
run_backup_dry_run() {
    if ! check_config_exists; then return; fi
    . "$SCRIPT_PATH" --run-task --progress --dry-run
    log_info "演练模式执行完毕。"
}

# 10. 启用定时任务
enable_cron() {
    if ! check_config_exists; then return; fi
    # 先禁用，防止重复添加
    disable_cron >/dev/null 2>&1
    local cron_job="${CRON_SCHEDULE} ${SCRIPT_PATH} --run-task"
    (crontab -l 2>/dev/null; echo "# ${CRON_COMMENT_TAG}"; echo "$cron_job") | crontab -
    log_info "定时任务已启用。"
}

# 11. 禁用定时任务
disable_cron() {
    (crontab -l 2>/dev/null | grep -v "$CRON_COMMENT_TAG") | crontab -
    log_info "定时任务已禁用。"
}

# 12. 查看备份日志
view_log() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "--- ${YELLOW}显示最近 50 条日志${NC} ---"
        tail -n 50 "$LOG_FILE"
    else
        log_warn "日志文件不存在。"
    fi
}


# --- 主菜单显示 ---
show_menu() {
    # 动态获取状态
    local rclone_ver="未安装"
    command -v rclone &> /dev/null && rclone_ver=$(rclone version | head -n 1)
    
    local config_status="${RED}未配置${NC}"
    [ -f "$CONFIG_FILE" ] && config_status="${GREEN}已配置${NC}"

    local cron_status="${RED}未启用${NC}"
    (crontab -l 2>/dev/null | grep -q "$CRON_COMMENT_TAG") && cron_status="${GREEN}已启用${NC}"
    
    clear
    echo -e "
  ${GREEN}Rclone 备份管理面板 (v5.0 Panel Edition)${NC}

  状态: Rclone [${BLUE}${rclone_ver}${NC}] | 备份配置 [${config_status}] | 定时任务 [${cron_status}]
  
  ${YELLOW}0.${NC} 退出脚本
————————————————————————————————
  ${YELLOW}1.${NC} 安装 Rclone
  ${YELLOW}2.${NC} 更新 Rclone
  ${YELLOW}3.${NC} ${RED}卸载 Rclone 和脚本${NC}
————————————————————————————————
  ${YELLOW}4.${NC} 配置/重置备份任务
  ${YELLOW}5.${NC} 查看当前备份配置
  ${YELLOW}6.${NC} 单独重新配置网盘
————————————————————————————————
  ${YELLOW}7.${NC} 手动执行一次备份
  ${YELLOW}8.${NC} 从网盘恢复备份
  ${YELLOW}9.${NC} 演练模式 (Dry Run)
————————————————————————————————
  ${YELLOW}10.${NC} 启用定时任务
  ${YELLOW}11.${NC} 禁用定时任务
  ${YELLOW}12.${NC} 查看备份日志
————————————————————————————————"
    echo
    read -p "请输入选项 [0-12]: " choice
}

# --- 主程序入口 ---
main() {
    # 处理 cron 调用的情况
    if [[ "$1" == "--run-task" ]]; then
        shift # 移除 --run-task
        run_backup_core "$@" # 将剩余参数（如--progress）传递给核心函数
        exit 0
    fi
    
    check_root
    
    while true; do
        show_menu
        case $choice in
            0) exit 0 ;;
            1) install_rclone; press_any_key ;;
            2) update_rclone; press_any_key ;;
            3) uninstall_all ;;
            4) setup_backup_task; press_any_key ;;
            5) view_current_config; press_any_key ;;
            6) reconfigure_remote; press_any_key ;;
            7) run_backup_manually; press_any_key ;;
            8) restore_backup; press_any_key ;;
            9) run_backup_dry_run; press_any_key ;;
            10) enable_cron; press_any_key ;;
            11) disable_cron; press_any_key ;;
            12) view_log; press_any_key ;;
            *) log_error "无效输入，请重试。"; sleep 1 ;;
        esac
    done
}

# 启动主程序
main "$@"
