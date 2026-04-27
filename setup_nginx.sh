#!/bin/bash

# =================================================================
# 脚本名称: setup_nginx.sh
# 描述: 自动安装 Nginx/Certbot，配置多域名 HTTPS 跳转，并自动管理证书。
# =================================================================

TARGET_DOMAIN="https://153.43.84.81:18029/fapage/"
EMAIL="admin@$TARGET_DOMAIN"

# 1. 环境安装
echo "正在安装必要组件..."
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx ufw curl

# 2. 防火墙设置
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# 3. Nginx 基础配置：处理所有 HTTP 请求并跳转到目标 HTTPS
NGINX_CONF="/etc/nginx/sites-available/wildcard-redirect"
NGINX_LINK="/etc/nginx/sites-enabled/wildcard-redirect"

echo "配置 Nginx 基础跳转逻辑..."
sudo bash -c "cat > $NGINX_CONF <<EOF
# HTTP 80 端口处理：所有域名（包括新解析的）统一跳转到目标 HTTPS
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$TARGET_DOMAIN\$request_uri;
    }
}

# HTTPS 443 端口处理：捕获所有未匹配证书的 HTTPS 请求
# 注意：首次访问新域名 HTTPS 会报错，直到 sync_script 运行并申请到证书
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;

    # 使用目标域名的证书作为兜底，防止 Nginx 启动失败
    ssl_certificate /etc/letsencrypt/live/$TARGET_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$TARGET_DOMAIN/privkey.pem;

    location / {
        return 301 https://$TARGET_DOMAIN\$request_uri;
    }
}
EOF"

# 4. 首次运行：为目标域名申请证书
if [ ! -d "/etc/letsencrypt/live/$TARGET_DOMAIN" ]; then
    echo "为目标域名 $TARGET_DOMAIN 申请初始证书..."
    sudo certbot --nginx --non-interactive --agree-tos --email "$EMAIL" -d "$TARGET_DOMAIN"
fi

# 5. 核心逻辑：自动发现新域名并申请证书
# 该函数会被调用来扫描 Nginx 日志或根据当前 Host 申请证书
# 为了简化，我们让脚本在每次运行时尝试为当前“已解析”但“未配置证书”的域名申请证书
apply_new_certs() {
    echo "开始扫描并申请新域名的 SSL 证书..."
    
    # 从 Nginx 访问日志中提取过去 10 分钟内访问过的 Host (排除了目标域名)
    # 这一步是为了发现哪些新域名正在尝试访问
    NEW_DOMAINS=$(tail -n 1000 /var/log/nginx/access.log 2>/dev/null | awk '{print $1}' | grep -v "$TARGET_DOMAIN" | sort -u)
    
    for domain in $NEW_DOMAINS; do
        # 验证该域名是否已经有证书
        if [ ! -d "/etc/letsencrypt/live/$domain" ]; then
            # 简单验证该域名是否确实解析到了本机 IP (防止 Certbot 报错过多)
            MY_IP=$(curl -s ifconfig.me)
            DOMAIN_IP=$(dig +short "$domain" | tail -n1)
            
            if [ "$MY_IP" == "$DOMAIN_IP" ]; then
                echo "检测到新解析域名 $domain，正在申请证书..."
                sudo certbot --nginx --non-interactive --agree-tos --email "$EMAIL" -d "$domain"
            fi
        fi
    done
}

# 执行证书申请
apply_new_certs

# 6. 启用配置
[ -f /etc/nginx/sites-enabled/default ] && sudo rm /etc/nginx/sites-enabled/default
[ ! -L "$NGINX_LINK" ] && sudo ln -s "$NGINX_CONF" "$NGINX_LINK"

sudo nginx -t && sudo systemctl reload nginx
echo "Nginx 与 SSL 自动管理配置完成！"
