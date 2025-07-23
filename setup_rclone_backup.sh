#!/bin/bash

# ==============================================================================
# Rclone 自动备份 Vaultwarden 数据脚本
#
# 功能:
# 1. 检查 root 权限。
# 2. 检查并安装 curl 和 rclone。
# 3. 引导用户通过 rclone config 配置云盘。
# 4. 创建一个每日执行的备份脚本。
# 5. 设置 cron 定时任务。
#
# 作者: Your Name (可以换成你的名字)
# GitHub: https://github.com/YourUsername/YourRepo
# ==============================================================================

# --- 全局变量和颜色定义 ---
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# --- 函数定义 ---

# 检查是否以 root 用户运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本必须以 root 用户权限运行。${NC}"
        echo "请尝试使用 'sudo -i' 命令切换到 root 用户后再执行。"
        exit 1
    fi
}

# 检查并安装必要的软件包
install_dependencies() {
    echo -e "${GREEN}正在检查并安装必要的软件包...${NC}"
    if ! command -v curl &> /dev/null; then
        apt-get update && apt-get install -y curl
    fi
    
    if ! command -v rclone &> /dev/null; then
        echo "未检测到 Rclone，正在自动安装..."
        curl https://rclone.org/install.sh | bash
        if ! command -v rclone &> /dev/null; then
            echo -e "${RED}Rclone 安装失败，请检查网络或手动安装。${NC}"
            exit 1
        fi
    else
        echo "Rclone 已安装。"
    fi
}

# 引导用户配置 Rclone
configure_rclone() {
    echo -e "\n${YELLOW}=== Rclone 配置向导 ===${NC}"
    echo "接下来将启动 Rclone 的交互式配置工具。"
    echo "请按照以下步骤操作："
    echo "1. 输入 'n' 创建一个新的 remote。"
    echo "2. 为你的远程连接起一个名字 (例如：gdrive_backup)。"
    echo "3. 选择你的云存储服务 (例如：Google Drive, OneDrive)。"
    echo "4. 大部分选项直接按回车使用默认值即可。"
    echo "5. 当提示 'Use auto config?' 时，由于在VPS中，请输入 'n'。"
    echo "6. 复制生成的链接，在你的本地电脑浏览器中打开并授权。"
    echo "7. 将授权后得到的验证码粘贴回这里。"
    echo -e "${YELLOW}准备好后，按任意键继续...${NC}"
    read -n 1 -s -r

    rclone config
    
    echo -e "\n${GREEN}Rclone 配置向导已退出。${NC}"
    echo "现在，我们来验证一下配置是否成功。"
    
    rclone listremotes
    echo "上面列出了你已配置的所有远程连接。"
    
    while true; do
        read -p "请输入你刚才配置的远程连接名称 (例如: gdrive_backup): " rclone_remote_name
        if [ -z "$rclone_remote_name" ]; then
            echo -e "${RED}名称不能为空，请重新输入。${NC}"
            continue
        fi

        echo "正在测试连接 '$rclone_remote_name'..."
        if rclone lsd "${rclone_remote_name}:" &> /dev/null; then
            echo -e "${GREEN}连接测试成功！'${rclone_remote_name}' 可以访问。${NC}"
            break
        else
            echo -e "${RED}错误：无法访问远程连接 '${rclone_remote_name}'。${NC}"
            echo "可能的原因："
            echo "1. 名称输入错误。"
            echo "2. 配置过程未成功完成。"
            read -p "要重试吗? (y/n) " retry_choice
            if [[ "$retry_choice" != "y" && "$retry_choice" != "Y" ]]; then
                echo -e "${RED}用户取消，脚本退出。${NC}"
                exit 1
            fi
        fi
    done
}

# 创建备份脚本
create_backup_script() {
    echo -e "\n${GREEN}正在创建 Vaultwarden 备份脚本...${NC}"

    local vaultwarden_data_dir="/opt/vaultwarden/vw-data"
    local backup_script_path="/opt/scripts/backup_vaultwarden.sh"
    local remote_backup_dir="vaultwarden_backup" # 云端存储目录名
    local log_file="/var/log/rclone_vaultwarden_backup.log"

    # 检查 Vaultwarden 数据目录是否存在
    if [ ! -d "$vaultwarden_data_dir" ]; then
        echo -e "${YELLOW}警告: Vaultwarden 数据目录 '${vaultwarden_data_dir}' 不存在。${NC}"
        echo "这可能是因为你还没有安装 Vaultwarden，或者安装在了不同位置。"
        read -p "请输入正确的 Vaultwarden 数据目录路径: " vaultwarden_data_dir
        if [ ! -d "$vaultwarden_data_dir" ]; then
            echo -e "${RED}提供的目录仍然不存在，脚本退出。${NC}"
            exit 1
        fi
    fi

    mkdir -p /opt/scripts

    cat <<EOF > "$backup_script_path"
#!/bin/bash

# --- 变量定义 ---
SOURCE_DIR="${vaultwarden_data_dir}/"
REMOTE_NAME="${rclone_remote_name}"
REMOTE_DIR="${remote_backup_dir}"
LOG_FILE="${log_file}"

# --- 脚本主逻辑 ---
echo "-------------------------------------------" >> "\$LOG_FILE"
echo "\$(date) - 开始备份 Vaultwarden 数据..." >> "\$LOG_FILE"

# 使用 rclone sync 命令同步数据
/usr/bin/rclone sync "\$SOURCE_DIR" "\$REMOTE_NAME:\$REMOTE_DIR" --create-empty-src-dirs --verbose >> "\$LOG_FILE" 2>&1

if [ \$? -eq 0 ]; then
  echo "\$(date) - 备份成功。" >> "\$LOG_FILE"
else
  echo "\$(date) - 错误: 备份过程中发生错误，请检查日志。" >> "\$LOG_FILE"
fi

echo "\$(date) - 备份完成。" >> "\$LOG_FILE"
echo "-------------------------------------------" >> "\$LOG_FILE"

# 清理旧的日志文件，只保留最近的1000行
tail -n 1000 "\$LOG_FILE" > "\$LOG_FILE.tmp" && mv "\$LOG_FILE.tmp" "\$LOG_FILE"

exit 0
EOF

    chmod +x "$backup_script_path"
    echo -e "${GREEN}备份脚本已创建于: ${backup_script_path}${NC}"
}

# 设置 Cron 定时任务
setup_cron() {
    echo -e "\n${GREEN}正在设置 Cron 定时任务...${NC}"
    
    local cron_job="0 3 * * * /opt/scripts/backup_vaultwarden.sh"
    
    # 检查任务是否已存在，避免重复添加
    if crontab -l | grep -q "backup_vaultwarden.sh"; then
        echo -e "${YELLOW}检测到已存在相关的备份任务，跳过添加。${NC}"
    else
        (crontab -l 2>/dev/null; echo "# Daily backup for Vaultwarden at 3:00 AM"; echo "$cron_job") | crontab -
        echo "定时任务已添加，将在每天凌晨3点执行备份。"
    fi
    systemctl restart cron
}

# --- 主程序 ---
main() {
    check_root
    install_dependencies
    configure_rclone
    create_backup_script
    setup_cron

    echo -e "\n🎉 ${GREEN}恭喜！Vaultwarden 自动备份设置全部完成！${NC}"
    echo "---------------------------------------------------------"
    echo -e "重要信息汇总:"
    echo -e "  - Rclone 远程连接名: ${YELLOW}${rclone_remote_name}${NC}"
    echo -e "  - 本地备份脚本: ${YELLOW}/opt/scripts/backup_vaultwarden.sh${NC}"
    echo -e "  - 云端备份目录: 在你的云盘根目录下的 ${YELLOW}vaultwarden_backup${NC} 文件夹"
    echo -e "  - 日志文件: ${YELLOW}/var/log/rclone_vaultwarden_backup.log${NC}"
    echo -e "  - 定时任务: 每天凌晨 3:00 AM 自动执行"
    echo "---------------------------------------------------------"
    echo -e "建议手动执行一次备份脚本以立即验证效果:"
    echo -e "${YELLOW}sudo /opt/scripts/backup_vaultwarden.sh${NC}"
    echo ""
}

# 调用主函数
main
