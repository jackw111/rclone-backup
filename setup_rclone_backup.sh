#!/bin/bash

# ==============================================================================
# Rclone 自动化备份设置脚本
# 功能:
# 1. 检查并安装必要的依赖 (curl, unzip, fuse3)
# 2. 检查并安装最新版的 Rclone
# 3. 通过交互式引导，设置备份源、目的地和备份频率
# 4. 自动创建并配置 Cron 定时任务
# ==============================================================================

# --- 美化输出的颜色定义 ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- 函数：检查并安装依赖 ---
install_dependencies() {
    echo -e "${YELLOW}正在检查并安装必要的依赖...${NC}"
    
    # 检查并使用适合的包管理器
    if command -v apt-get &> /dev/null; then
        # 基于 Debian/Ubuntu 的系统
        echo "检测到 Debian/Ubuntu 系统，使用 apt..."
        apt-get update > /dev/null
        apt-get install -y curl unzip fuse3
    elif command -v yum &> /dev/null; then
        # 基于 RHEL/CentOS 的系统
        echo "检测到 RHEL/CentOS 系统，使用 yum..."
        yum install -y curl unzip fuse3
    else
        echo -e "${RED}错误：未找到 apt 或 yum 包管理器。请手动安装 'curl' 和 'unzip'。${NC}"
        exit 1
    fi

    if command -v curl &> /dev/null && command -v unzip &> /dev/null; then
        echo -e "${GREEN}依赖项安装成功！${NC}"
    else
        echo -e "${RED}依赖项安装失败，请检查错误信息。${NC}"
        exit 1
    fi
}

# --- 函数：检查并安装 Rclone ---
install_rclone() {
    if command -v rclone &> /dev/null; then
        echo -e "${GREEN}Rclone 已安装。当前版本: $(rclone --version | head -n 1)${NC}"
    else
        echo -e "${YELLOW}未检测到 Rclone，开始自动安装...${NC}"
        curl https://rclone.org/install.sh | sudo bash
        if command -v rclone &> /dev/null; then
            echo -e "${GREEN}Rclone 安装成功！版本: $(rclone --version | head -n 1)${NC}"
        else
            echo -e "${RED}Rclone 安装失败。请访问 https://rclone.org/install/ 手动安装。${NC}"
            exit 1
        fi
    fi
}

# --- 函数：设置 Cron 定时任务 ---
setup_cron_job() {
    echo -e "\n--- ${YELLOW}开始配置自动备份任务${NC} ---"
    
    # 交互式获取 Rclone 远程名称
    read -p "请输入你的 Rclone 远程名称 (例如: 数据备份): " RCLONE_REMOTE_NAME
    if [ -z "$RCLONE_REMOTE_NAME" ]; then
        echo -e "${RED}远程名称不能为空！${NC}"
        exit 1
    fi
    
    # 交互式获取本地源目录
    read -p "请输入要备份的 VPS 本地目录绝对路径 (例如: /root/mywebsite): " SOURCE_DIR
    if [ ! -d "$SOURCE_DIR" ]; then
        echo -e "${RED}错误：目录 '$SOURCE_DIR' 不存在！请先创建该目录。${NC}"
        exit 1
    fi
    SOURCE_DIR=$(realpath "$SOURCE_DIR") # 获取绝对路径，避免问题

    # 交互式获取远程目标目录
    read -p "请输入备份到 Google Drive 上的文件夹名称 (例如: VPS_Backup): " DEST_DIR
    if [ -z "$DEST_DIR" ]; then
        echo -e "${RED}目标文件夹名称不能为空！${NC}"
        exit 1
    fi
    
    LOG_FILE="/var/log/rclone_backup.log"
    echo -e "备份日志将保存在: ${YELLOW}${LOG_FILE}${NC}"

    # 交互式获取备份频率
    echo -e "\n请选择备份频率:"
    echo "  1) 每天凌晨 3:00"
    echo "  2) 每周日凌晨 4:00"
    echo "  3) 每月1号凌晨 5:00"
    read -p "请输入选项 [1-3]: " cron_choice

    cron_schedule=""
    case $cron_choice in
        1) cron_schedule="0 3 * * *" ;;
        2) cron_schedule="0 4 * * 0" ;;
        3) cron_schedule="0 5 1 * *" ;;
        *) echo -e "${RED}无效选项，退出。${NC}"; exit 1 ;;
    esac

    # 构建完整的 rclone 命令和 cron 任务
    rclone_command="rclone sync \"$SOURCE_DIR\" \"$RCLONE_REMOTE_NAME:$DEST_DIR\" --log-file=$LOG_FILE -v"
    cron_job="$cron_schedule $rclone_command"

    # 安全地将新任务添加到 crontab，不影响其他任务
    (crontab -l 2>/dev/null; echo "# Rclone-Backup-Job (由脚本自动创建)"; echo "$cron_job") | crontab -

    echo -e "\n--------------------------------------------------"
    echo -e "${GREEN}恭喜！自动备份任务已成功设置！${NC}"
    echo -e "--------------------------------------------------"
    echo -e "任务详情:"
    echo -e "  - ${YELLOW}本地源目录:${NC} $SOURCE_DIR"
    echo -e "  - ${YELLOW}远程目标:${NC} ${RCLONE_REMOTE_NAME}:${DEST_DIR}"
    echo -e "  - ${YELLOW}执行计划:${NC} $cron_schedule"
    echo -e "  - ${YELLOW}完整命令:${NC} $rclone_command"
    echo -e "\n你可以使用 'crontab -l' 命令查看所有定时任务。"
    echo -e "备份日志会记录在 ${LOG_FILE} 文件中。"
}

# --- 主程序逻辑 ---
main() {
    # 确保以 root 用户运行
    if [ "$(id -u)" -ne 0 ]; then
       echo -e "${RED}错误：此脚本需要以 root 用户身份运行。请使用 'sudo ./setup_backup.sh'。${NC}"
       exit 1
    fi
    
    install_dependencies
    install_rclone
    setup_cron_job
}

# --- 执行主程序 ---
main
