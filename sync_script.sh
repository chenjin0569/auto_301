#!/bin/bash

# =================================================================
# 脚本名称: sync_script.sh
# 描述: 自动从 GitHub 同步 setup_nginx.sh，并触发 SSL 证书自动申请逻辑。
# =================================================================

# --- 配置区域 ---
GITHUB_USER="chenjin0569"
GITHUB_REPO="auto_301"
GITHUB_BRANCH="main"
# ----------------

GITHUB_RAW_BASE="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH"
SETUP_SCRIPT_URL="$GITHUB_RAW_BASE/setup_nginx.sh"

LOCAL_SETUP_SCRIPT="/usr/local/bin/setup_nginx.sh"
TEMP_SCRIPT="/tmp/setup_nginx_new.sh"

echo "执行同步检查: $(date)"

# 1. 下载最新的配置脚本
if curl -s -o "$TEMP_SCRIPT" "$SETUP_SCRIPT_URL"; then
    # 2. 无论脚本是否更新，我们都运行它，因为 setup_nginx.sh 现在包含了“扫描新域名并申请证书”的逻辑
    # 这样可以确保每 10 分钟检查一次是否有新解析的域名需要证书
    mv "$TEMP_SCRIPT" "$LOCAL_SETUP_SCRIPT"
    chmod +x "$LOCAL_SETUP_SCRIPT"
    
    echo "运行 setup_nginx.sh 处理证书和配置..."
    bash "$LOCAL_SETUP_SCRIPT"
else
    echo "同步失败，请检查网络或 GitHub 链接。"
    # 如果下载失败，仍然尝试运行本地旧脚本以确保新域名证书能被申请
    if [ -f "$LOCAL_SETUP_SCRIPT" ]; then
        bash "$LOCAL_SETUP_SCRIPT"
    fi
fi

# 3. 确保定时任务存在
CRON_JOB="*/10 * * * * /usr/local/bin/sync_script.sh >> /var/log/sync_script.log 2>&1"
(crontab -l 2>/dev/null | grep -Fq "/usr/local/bin/sync_script.sh") || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
