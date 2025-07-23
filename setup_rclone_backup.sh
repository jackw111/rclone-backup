#!/bin/bash

# ==============================================================================
# Rclone保姆级一站式备份脚本 (God Mode Plus Edition)
#
# 作者: Your Name/GitHub (基于原版修改)
# 版本: 3.0
#
# 新增功能 (v3.0):
# 1. 新增 "压缩后上传" 模式, 将目录打包为 .tar.gz 文件上传。
# 2. 新增备份保留策略, 自动删除网盘中旧的备份文件 (仅压缩模式)。
# 3. 新增自定义 Cron 表达式, 实现任意时间频率的备份。
# 4. 新增日志文件自动清理, 防止日志文件过大。
#
# 使用方法:
# 1. 保存为 rclone_god_mode.sh
# 2. chmod +x rclone_god_mode.sh
# 3. sudo ./rclone_god_mode.sh
# ==============================================================================

# --- 全局变量和美化输出 ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

CONFIG_FILE="/etc/rclone_backup.conf"
LOG_FILE="/var/log/rclone_backup.log"
CRON_COMMENT_TAG="Rclone-Backup-Job-by-GodMode-Script"
TMP_DIR="/tmp"
LOG_RETENTION_LINES=5000 # 日志文件保留的最大行数

# --- 基础函数 ---
log_info() { echo -e "${GREEN}[信息] $(date +"%Y-%m-%d %H:%M:%S") $1${NC}" >> "$LOG_FILE"; echo -e "${GREEN}[信息] $1${NC}"; }
log_warn() { echo -e "${YELLOW}[警告] $(date +"%Y-%m-%d %H:%M:%S") $1${NC}" >> "$LOG_FILE"; echo -e "${YELLOW}[警告] $1${NC}"; }
log_error() { echo -e "${RED}[错误] $(date +"%Y-%m-%d %H:%M:%S") $1${NC}" >> "$LOG_FILE"; echo -e "${RED}[错误] $1${NC}"; }
log_to_file() { echo "$(date +"%Y-%m-%d %H:%M:%S") $1" >> "$LOG_FILE"; }

press_any_key() {
    echo -e "\n${BLUE}按任意键继续...${NC}"
    read -n 1 -s
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
       echo -e "${RED}[错误] 此脚本需要以 root 用户身份运行。请使用 'sudo ./rclone_god_mode.sh'。${NC}"
       exit 1
    fi
}

# --- 安装与配置核心函数 ---

install_dependencies_and_rclone() {
    echo -e "${GREEN}[信息] 正在检查并安装 Rclone 及依赖 (curl, unzip, fuse3)...${NC}"
    if ! command -v rclone &> /dev/null; then
        if command -v apt-get &> /dev/null; then
            apt-get update -y >/dev/null && apt-get install -y curl unzip fuse3 >/dev/null
        elif command -v yum &> /dev/null; then
            yum install -y curl unzip fuse3 >/dev/null
        else
            echo -e "${RED}[错误] 未找到 apt 或 yum。请手动安装 'curl', 'unzip', 'fuse3'。${NC}"
            exit 1
        fi
        
        # 安装 Rclone
        curl -s https://rclone.org/install.sh | sudo bash
        if ! command -v rclone &>/dev/null; then
            echo -e "${RED}[错误] Rclone 安装失败。请访问官网手动安装。${NC}"
            exit 1
        fi
        echo -e "${GREEN}[信息] Rclone 安装成功！版本: $(rclone --version | head -n 1)${NC}"
    else
        echo -e "${GREEN}[信息] Rclone 已安装。版本: $(rclone --version | head -n 1)${NC}"
    fi
    # 确保日志文件存在且可写
    touch "$LOG_FILE" && chmod 644 "$LOG_FILE"
}

configure_rclone_remote() {
    # ... 此函数与原版相同，为简洁省略 ...
    # (如果需要，将原版脚本中的 configure_rclone_remote 函数完整复制到这里)
    local remote_name=$1
    
    if rclone listremotes | grep -q "${remote_name}:"; then
        log_info "名为 '${remote_name}' 的远程配置已存在，跳过配置步骤。"
        return 0
    fi
    
    echo -e "\n--- ${YELLOW}选择您要配置的网盘类型${NC} ---"
    echo "  1) Google Drive (谷歌云盘)"
    echo "  2) Microsoft OneDrive (微软网盘)"
    echo "  3) Dropbox"
    read -p "请输入选项 [1-3]: " provider_choice
    
    echo -e "\n--- ${RED}重要：Rclone 配置向导【请仔细阅读】${NC} ---"
    log_warn "接下来将启动 Rclone 官方的配置程序。"
    log_warn "我将为您提供每一步的详细指导。请严格按照指导操作。"
    log_warn "最关键的一步是: 程序会生成一个链接, 您需要复制它, 在您【自己电脑的浏览器】中打开, 登录并授权。"
    press_any_key

    case $provider_choice in
        1) # Google Drive 指导
            echo -e "--- ${BLUE}Google Drive 配置步骤指导${NC} ---"
            echo "1. 在 'name>' 提示后，直接按回车 (使用我们已设定的名字 '${remote_name}')。"
            echo "2. 在长长的列表中，找到 'drive' (Google Drive), 输入它前面的【数字】并回车。"
            echo "3. 'client_id>' 和 'client_secret>'，【直接按回车】跳过。"
            echo "4. 'scope>'，输入 '1' (完全访问权限) 并回车。"
            echo "5. 'root_folder_id>' 和 'service_account_file>'，【直接按回车】跳过。"
            echo "6. 'Edit advanced config?'，输入 'n' (否) 并回车。"
            echo "7. 'Use auto config?'，输入 'y' (是) 并回车。 ${RED}<-- 关键步骤${NC}"
            echo "8. ${RED}程序会显示一个'go to the following link'链接, 把它复制到你的电脑浏览器里打开授权。${NC}"
            echo "9. 'Configure this as a team drive?'，个人用户输入 'n' (否) 并回车。"
            echo "10.看到 'y/e/d/r/c/s/q>'，输入 'y' (是) 保存配置。"
            echo "11.最后看到主菜单，输入 'q' 退出配置程序。"
            press_any_key
            rclone config --config "$HOME/.config/rclone/rclone.conf"
            ;;
        2) # OneDrive 指导
            echo -e "--- ${BLUE}Microsoft OneDrive 配置步骤指导${NC} ---"
            echo "1. 在 'name>' 提示后，直接按回车 (使用 '${remote_name}')。"
            echo "2. 在列表中找到 'onedrive' (Microsoft OneDrive), 输入它前面的【数字】并回车。"
            echo "3. 'client_id>' 和 'client_secret>'，【直接按回车】跳过。"
            echo "4. 'Edit advanced config?'，输入 'n' (否) 并回车。"
            echo "5. 'Use auto config?'，输入 'y' (是) 并回车。 ${RED}<-- 关键步骤${NC}"
            echo "6. ${RED}程序会显示一个链接, 复制到你的电脑浏览器里打开授权。${NC}"
            echo "7. 授权后，选择您的网盘类型（例如个人版输入 '1'）。"
            echo "8. 看到 'y/e/d/r/c/s/q>'，输入 'y' (是) 保存配置。"
            echo "9. 最后，输入 'q' 退出配置程序。"
            press_any_key
            rclone config --config "$HOME/.config/rclone/rclone.conf"
            ;;
        3) # Dropbox 指导
            echo -e "--- ${BLUE}Dropbox 配置步骤指导${NC} ---"
            echo "1. 在 'name>' 提示后，直接按回车 (使用 '${remote_name}')。"
            echo "2. 在列表中找到 'dropbox', 输入它前面的【数字】并回车。"
            echo "3. 'client_id>' 和 'client_secret>'，【直接按回车】跳过。"
            echo "4. 'Edit advanced config?'，输入 'n' (否) 并回车。"
            echo "5. 'Use auto config?'，输入 'y' (是) 并回车。 ${RED}<-- 关键步骤${NC}"
            echo "6. ${RED}程序会显示一个链接, 复制到你的电脑浏览器里打开授权。${NC}"
            echo "7. 看到 'y/e/d/r/c/s/q>'，输入 'y' (是) 保存配置。"
            echo "8. 最后，输入 'q' 退出配置程序。"
            press_any_key
            rclone config --config "$HOME/.config/rclone/rclone.conf"
            ;;
        *)
            log_error "无效选项，退出。"; exit 1 ;;
    esac

    # 验证配置是否成功
    if rclone listremotes | grep -q "${remote_name}:"; then
        log_info "远程 '${remote_name}' 配置成功！"
    else
        log_error "远程配置似乎失败了！请检查，或重新运行脚本尝试。"
        exit 1
    fi
}

setup_backup_task() {
    echo -e "\n--- ${YELLOW}第一步：设置备份基础信息${NC} ---"
    read -p "请为您要连接的网盘起个别名 (纯英文, 例如 'gdrive'): " RCLONE_REMOTE_NAME
    [ -z "$RCLONE_REMOTE_NAME" ] && { echo -e "${RED}错误：远程别名不能为空！${NC}"; exit 1; }

    read -p "请输入要备份的【本地目录】绝对路径 (例如 /var/www): " SOURCE_DIR
    if [ ! -d "$SOURCE_DIR" ]; then
        log_warn "目录 '$SOURCE_DIR' 不存在。是否现在创建? [y/N]"
        read -r answer && [[ "$answer" =~ ^[Yy]$ ]] && mkdir -p "$SOURCE_DIR" && log_info "目录已创建。" || { log_error "操作取消。"; exit 1; }
    fi
    SOURCE_DIR=$(realpath "$SOURCE_DIR")

    read -p "请输入备份文件存放在网盘上的【文件夹路径】(例如 vps_backup/site1): " DEST_DIR
    [ -z "$DEST_DIR" ] && { echo -e "${RED}错误：目标文件夹不能为空！${NC}"; exit 1; }

    # 调用配置向导
    configure_rclone_remote "$RCLONE_REMOTE_NAME"

    echo -e "\n--- ${YELLOW}第二步：选择备份模式${NC} ---"
    echo "  1) 同步模式 (Sync): 保持本地和远程目录结构完全一致。"
    echo "  2) 压缩模式 (Compress): 将本地目录打包成单个.tar.gz压缩文件后上传。"
    read -p "请选择备份模式 [1-2, 默认 1]: " backup_choice
    BACKUP_TYPE="sync"
    RETENTION_COUNT=0
    if [ "$backup_choice" == "2" ]; then
        BACKUP_TYPE="compress"
        read -p "请设置在网盘中保留的最新备份数量 (默认 25): " count
        RETENTION_COUNT=${count:-25}
    fi

    echo -e "\n--- ${YELLOW}第三步：设置自动备份频率${NC} ---"
    echo "  1) 每天凌晨 3:00"
    echo "  2) 每周日凌晨 4:00"
    echo "  3) 每月1号凌晨 5:00"
    echo "  4) 每小时的第15分钟"
    echo "  5) ${BLUE}自定义 (输入您自己的 Cron 表达式)${NC}"
    read -p "请选择备份频率 [1-5]: " cron_choice

    case $cron_choice in
        1) cron_schedule="0 3 * * *";;
        2) cron_schedule="0 4 * * 0";;
        3) cron_schedule="0 5 1 * *";;
        4) cron_schedule="15 * * * *";;
        5)
            echo -e "${YELLOW}Cron 表达式格式: 分 时 日 月 周 (例如 '0 2 * * 1' 表示每周一凌晨2点)${NC}"
            echo -e "${YELLOW}您可以使用 ${BLUE}https://crontab.guru/${NC} 来生成表达式。${NC}"
            read -p "请输入您的 Cron 表达式: " cron_schedule
            [ -z "$cron_schedule" ] && { echo -e "${RED}错误：Cron 表达式不能为空！${NC}"; exit 1; }
            ;;
        *) echo -e "${RED}错误：无效选项，退出。${NC}"; exit 1;;
    esac

    # 保存配置到文件
    echo "RCLONE_REMOTE_NAME='${RCLONE_REMOTE_NAME}'" > "$CONFIG_FILE"
    echo "SOURCE_DIR='${SOURCE_DIR}'" >> "$CONFIG_FILE"
    echo "DEST_DIR='${DEST_DIR}'" >> "$CONFIG_FILE"
    echo "BACKUP_TYPE='${BACKUP_TYPE}'" >> "$CONFIG_FILE"
    echo "RETENTION_COUNT='${RETENTION_COUNT}'" >> "$CONFIG_FILE"
    echo "CRON_SCHEDULE='${cron_schedule}'" >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    update_cron_job
    
    echo -e "\n${GREEN}=============================================${NC}"
    log_info "恭喜！所有配置已完成！"
    echo -e "${GREEN}=============================================${NC}"
    print_current_config
    log_info "您可以随时再次运行此脚本进入管理菜单。"
}

# --- 核心备份与管理功能 ---

load_config() {
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" && return 0 || return 1
}

update_cron_job() {
    load_config
    # 让cron直接调用本脚本的--run-task参数，更整洁、更强大
    local script_path=$(realpath "$0")
    local cron_job="${CRON_SCHEDULE} ${script_path} --run-task"
    
    (crontab -l 2>/dev/null | grep -v "$CRON_COMMENT_TAG"; echo "# ${CRON_COMMENT_TAG}"; echo "$cron_job") | crontab -
    log_info "定时任务已成功创建/更新。"
}

print_current_config() {
    if ! load_config; then echo -e "${YELLOW}[警告] 尚未配置备份任务。${NC}"; return; fi
    echo -e "--- ${YELLOW}当前备份配置详情${NC} ---"
    echo -e "  - 本地源目录:   ${BLUE}$SOURCE_DIR${NC}"
    echo -e "  - 远程目标:     ${BLUE}${RCLONE_REMOTE_NAME}:${DEST_DIR}${NC}"
    echo -e "  - 执行计划:     ${BLUE}$CRON_SCHEDULE${NC}"
    echo -e "  - 备份模式:     ${BLUE}${BACKUP_TYPE}${NC}"
    if [ "$BACKUP_TYPE" == "compress" ]; then
    echo -e "  - 保留版本数:   ${BLUE}${RETENTION_COUNT}${NC}"
    fi
    echo -e "  - 日志文件:     ${BLUE}$LOG_FILE${NC}"
    echo "-------------------------"
}

# 【新】日志清理函数
trim_log_file() {
    log_to_file "开始清理日志文件，仅保留最近 ${LOG_RETENTION_LINES} 行..."
    tail -n "${LOG_RETENTION_LINES}" "${LOG_FILE}" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "${LOG_FILE}"
    log_to_file "日志文件清理完毕。"
}

# 【重构】核心备份执行函数
run_backup_core() {
    if ! load_config; then log_error "无法加载配置文件，备份中止。"; exit 1; fi
    
    local show_progress=$1 # 接收 --progress 参数

    log_info "开始执行备份任务，模式: ${BACKUP_TYPE}"

    if [ "$BACKUP_TYPE" == "sync" ]; then
        # 同步模式
        log_to_file "执行 rclone sync 从 ${SOURCE_DIR} 到 ${RCLONE_REMOTE_NAME}:${DEST_DIR}"
        rclone sync "${SOURCE_DIR}" "${RCLONE_REMOTE_NAME}:${DEST_DIR}" -v ${show_progress} >> "$LOG_FILE" 2>&1
        local rclone_exit_code=$?
        if [ $rclone_exit_code -eq 0 ]; then
            log_info "同步模式备份成功。"
        else
            log_error "同步模式备份失败！Rclone退出码: ${rclone_exit_code}"
        fi
    else
        # 压缩模式
        local archive_basename="${SOURCE_DIR##*/}_$(date +%Y%m%d_%H%M%S).tar.gz"
        local temp_archive_path="${TMP_DIR}/${archive_basename}"
        
        log_to_file "创建临时压缩文件: ${temp_archive_path}"
        tar -czf "${temp_archive_path}" -C "$(dirname "${SOURCE_DIR}")" "$(basename "${SOURCE_DIR}")"
        
        if [ -f "${temp_archive_path}" ]; then
            log_to_file "压缩成功，开始上传到 ${RCLONE_REMOTE_NAME}:${DEST_DIR}/${archive_basename}"
            rclone copyto "${temp_archive_path}" "${RCLONE_REMOTE_NAME}:${DEST_DIR}/${archive_basename}" -v ${show_progress} >> "$LOG_FILE" 2>&1
            local rclone_exit_code=$?

            log_to_file "删除本地临时压缩文件: ${temp_archive_path}"
            rm -f "${temp_archive_path}"

            if [ $rclone_exit_code -eq 0 ]; then
                log_info "压缩备份文件上传成功。"
                # --- 删除旧备份 ---
                if [ "$RETENTION_COUNT" -gt 0 ]; then
                    log_to_file "开始清理旧备份，保留最近 ${RETENTION_COUNT} 个文件。"
                    # 列出所有备份文件，按时间倒序，跳过最新的 n 个，然后删除其余的
                    rclone lsf "${RCLONE_REMOTE_NAME}:${DEST_DIR}" | sort -r | tail -n +$((RETENTION_COUNT + 1)) | while read -r file_to_delete; do
                        if [ -n "$file_to_delete" ]; then
                            log_to_file "删除旧备份: ${file_to_delete}"
                            rclone delete "${RCLONE_REMOTE_NAME}:${DEST_DIR}/${file_to_delete}" -v >> "$LOG_FILE" 2>&1
                        fi
                    done
                    log_to_file "旧备份清理完毕。"
                fi
            else
                log_error "压缩备份文件上传失败！Rclone退出码: ${rclone_exit_code}"
            fi
        else
            log_error "创建压缩文件失败！路径: ${temp_archive_path}"
        fi
    fi
    
    # 每次备份后都清理日志
    trim_log_file
}

run_backup_manually() {
    if ! load_config; then log_error "无配置，请先初始化。"; return; fi
    log_info "开始手动执行一次备份 (带进度条)..."
    run_backup_core "--progress"
    log_info "手动备份完成。详情请见日志: ${LOG_FILE}"
}

view_log() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${GREEN}显示最近50条日志 (按 'q' 退出):${NC}"
        tail -n 50 "$LOG_FILE" | less
    else
        log_warn "日志文件不存在，可能还未执行过备份。"
    fi
}

uninstall_backup() {
    log_warn "这将从系统中移除本脚本创建的【自动备份配置】（非Rclone本身）。"
    echo "操作包括: 1.移除定时任务 2.删除脚本配置文件 3.删除日志文件。"
    read -p "确认请输入 'uninstall' : " confirm
    
    if [ "$confirm" == "uninstall" ]; then
        crontab -l | grep -v "$CRON_COMMENT_TAG" | crontab -
        rm -f "$CONFIG_FILE" "$LOG_FILE"
        log_info "自动备份配置已成功卸载。"
        log_warn "注意: Rclone程序和您在~/.config/rclone/rclone.conf中创建的网盘连接【仍保留】。"
        log_warn "如需彻底删除Rclone, 请手动执行 'sudo rm /usr/bin/rclone' 和 'rm -rf ~/.config/rclone'。"
    else
        log_info "卸载已取消。";
    fi
}

# --- 主程序入口与菜单 ---
main() {
    # 检查是否由cron任务调用
    if [[ "$1" == "--run-task" ]]; then
        run_backup_core
        exit 0
    fi

    check_root
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_warn "未找到任何配置，即将进入初始化安装向导..."
        press_any_key
        install_dependencies_and_rclone
        setup_backup_task
    else
        while true; do
            clear
            print_current_config
            echo -e "--- ${GREEN}Rclone 备份管理菜单 (Plus)${NC} ---"
            echo "  1) 手动执行一次备份"
            echo "  2) 查看备份日志 (最近50条)"
            echo "  3) 【重置】所有备份配置"
            echo "  4) 【卸载】自动备份任务"
            echo "  q) 退出"
            read -p "请输入您的选择: " choice
            
            case $choice in
                1) run_backup_manually; press_any_key ;;
                2) view_log; press_any_key ;;
                3) log_warn "将引导您重新设置所有参数..."; setup_backup_task ;;
                4) uninstall_backup; exit 0 ;;
                q|Q) break ;;
                *) echo -e "${RED}无效输入，请重试。${NC}"; press_any_key ;;
            esac
        done
    fi
    echo -e "${GREEN}脚本执行完毕，感谢使用！${NC}"
}

# --- 运行主程序 ---
main
