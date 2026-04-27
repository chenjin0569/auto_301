
Bash
#!/bin/bash

# =================================================================
# 脚本名称: setup_redirect.sh
# 优化点：修复变量冲突，解决首次启动证书缺失问题
# =================================================================

# 只需要填跳转的目标全路径
REDIRECT_TARGET="https://153.43.84.81:18029/fapage/"
# 随便填个用来做初始化和邮箱的域名（必须是纯域名格式）
ADMIN_EMAIL="admin@0569.com"

echo "正在安装必要组件..."
sudo apt update && sudo apt install -y nginx certbot python3-certbot-nginx ufw curl dnsutils

# 开启防火墙
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# 创建临时占位证书文件夹（防止 Nginx 启动报错）
sudo mkdir -p /etc/nginx/ssl/
if [ ! -f /etc/nginx/ssl/dummy.crt ]; then
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/dummy.key -out /etc/nginx/ssl/dummy.crt \
    -subj "/C=CN/ST=GD/L=GZ/O=IT/CN=redirect.local"
fi

# 写入 Nginx 配置
NGINX_CONF="/etc/nginx/sites-available/wildcard-redirect"
echo "写入 Nginx 跳转配置..."
sudo bash -c "cat > $NGINX_CONF <<EOF
server {
    listen 80 default_server;
    server_name _;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 $REDIRECT_TARGET;
    }
}

server {
    listen 443 ssl default_server;
    server_name _;

    # 默认使用自签名证书兜底，防止报错
    ssl_certificate /etc/nginx/ssl/dummy.crt;
    ssl_certificate_key /etc/nginx/ssl/dummy.key;

    location / {
        return 301 $REDIRECT_TARGET;
    }
}
EOF"

# 启用配置
[ -f /etc/nginx/sites-enabled/default ] && sudo rm /etc/nginx/sites-enabled/default
[ ! -L "/etc/nginx/sites-enabled/wildcard-redirect" ] && sudo ln -s "$NGINX_CONF" "/etc/nginx/sites-enabled/wildcard-redirect"

sudo systemctl restart nginx

# 自动化申请函数
apply_certs() {
    MY_IP=\$(curl -s ifconfig.me)
    # 提取过去 10 分钟内访问过但没配证书的 Host
    DOMAINS=\$(tail -n 100 /var/log/nginx/access.log 2>/dev/null | awk '{print \$1}' | sort -u)

    for domain in \$DOMAINS; do
        # 排除纯 IP 和已有的证书
        if [[ "\$domain" =~ [a-zA-Z] ]] && [ ! -d "/etc/letsencrypt/live/\$domain" ]; then
            DOMAIN_IP=\$(dig +short "\$domain" | tail -n1)
            if [ "\$MY_IP" == "\$DOMAIN_IP" ]; then
                echo "为 \$domain 申请证书..."
                sudo certbot --nginx --non-interactive --agree-tos --email "$ADMIN_EMAIL" -d "\$domain"
                sudo systemctl reload nginx
            fi
        fi
    done
}

# 第一次手动执行一次
apply_certs

echo "配置完成！"
