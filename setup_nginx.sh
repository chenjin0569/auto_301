sudo killall apt apt-get 2>/dev/null; sudo rm -f /var/lib/apt/lists/lock /var/lib/dpkg/lock*
#!/bin/bash
cat > /usr/local/bin/setup_nginx.sh <<'EOF'
#!/bin/bash
# 修正后的 Nginx 跳转配置脚本

REDIRECT_TARGET="https://153.43.84.81:18029/fapage/"
ADMIN_EMAIL="chenjin0569@gmail.com"

# 1. 确保 Nginx 安装并运行
apt update && apt install -y nginx certbot python3-certbot-nginx dnsutils curl

# 2. 强制清理旧配置
rm -f /etc/nginx/sites-enabled/default

# 3. 写入跳转配置
cat > /etc/nginx/sites-available/wildcard-redirect <<INNER_EOF
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
INNER_EOF

# 4. 启用新配置并重启
ln -sf /etc/nginx/sites-available/wildcard-redirect /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# 5. 自动证书申请逻辑
apply_certs() {
    MY_IP=$(curl -s ifconfig.me)
    # 获取最近访问的域名
    DOMAINS=$(tail -n 50 /var/log/nginx/access.log 2>/dev/null | awk '{print $1}' | sort -u)

    for domain in $DOMAINS; do
        # 排除 IP，只针对域名，且没有证书的
        if [[ "$domain" =~ [a-zA-Z] ]] && [ ! -d "/etc/letsencrypt/live/$domain" ]; then
            DOMAIN_IP=$(dig +short "$domain" | tail -n1)
            if [ "$MY_IP" == "$DOMAIN_IP" ]; then
                certbot --nginx --non-interactive --agree-tos --email "$ADMIN_EMAIL" -d "$domain"
                systemctl reload nginx
            fi
        fi
    done
}

apply_certs
EOF

# 给权限并运行
chmod +x /usr/local/bin/setup_nginx.sh
/usr/local/bin/setup_nginx.sh
