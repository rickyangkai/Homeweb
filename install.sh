#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

# 错误处理函数
handle_error() {
    error "命令执行失败: $1"
    exit 1
}

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then 
    error "请使用sudo运行此脚本"
    exit 1
fi

# 检查当前目录是否有网站文件
if [ ! -f "navigation.html" ]; then
    error "未找到navigation.html文件，请确保在正确的目录下运行此脚本"
    exit 1
fi

# 更新系统包
log "正在更新系统包..."
apt-get update || handle_error "系统包更新失败"
apt-get upgrade -y || handle_error "系统包升级失败"

# 检查并安装nginx
if ! command -v nginx &> /dev/null; then
    log "正在安装nginx..."
    apt-get install nginx -y || handle_error "nginx安装失败"
else
    warn "nginx已安装，跳过安装步骤"
fi

# 创建网站目录
log "正在创建网站目录..."
mkdir -p /var/www/html || handle_error "创建网站目录失败"

# 复制网站文件
log "正在复制网站文件..."
cp -r ./* /var/www/html/ || handle_error "复制网站文件失败"

# 设置正确的文件权限
log "正在设置文件权限..."
chown -R www-data:www-data /var/www/html || handle_error "设置文件所有权失败"
chmod -R 755 /var/www/html || handle_error "设置文件权限失败"

# 检查文件是否成功复制
log "正在检查文件..."
if [ ! -f "/var/www/html/navigation.html" ]; then
    error "网站文件复制失败，请检查文件权限和磁盘空间"
    exit 1
fi

if [ ! -d "/var/www/html/Icon" ]; then
    error "图标目录复制失败，请检查文件权限和磁盘空间"
    exit 1
fi

# 配置nginx
log "正在配置nginx..."
cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/html;
    index navigation.html;

    # 添加安全headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";

    # 添加调试日志
    access_log /var/log/nginx/access.log combined buffer=512k flush=1m;
    error_log /var/log/nginx/error.log debug;

    # 确保正确的MIME类型
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # 添加调试信息
    add_header X-Debug-Message "Server is running" always;
    add_header X-Server-IP \$server_addr always;

    # 添加错误页面
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;

    location / {
        try_files \$uri \$uri/ =404;
        add_header Content-Type text/html;
        add_header X-Debug-Path \$document_root\$uri always;
        add_header X-Request-URI \$request_uri always;
    }

    # 修改图标配置
    location ~* ^/Icon/.*\.(svg|png)$ {
        root /var/www/html;
        expires 30d;
        add_header Cache-Control "public, no-transform";
        
        # 根据文件扩展名设置正确的Content-Type
        location ~* \.svg$ {
            add_header Content-Type image/svg+xml;
        }
        
        location ~* \.png$ {
            add_header Content-Type image/png;
        }
    }

    # 添加gzip压缩
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;
}
EOF

# 测试nginx配置
log "正在测试nginx配置..."
nginx -t || handle_error "nginx配置测试失败"

# 重启nginx
log "正在重启nginx..."
systemctl restart nginx || handle_error "nginx重启失败"

# 检查nginx状态
log "正在检查nginx状态..."
if ! systemctl is-active --quiet nginx; then
    error "nginx服务未正常运行，请检查日志"
    exit 1
fi

# 检查防火墙状态并配置
if command -v ufw &> /dev/null; then
    log "正在配置防火墙..."
    ufw allow 80/tcp || handle_error "防火墙配置失败"
else
    warn "未检测到ufw，跳过防火墙配置"
fi

# 设置开机自启
log "正在设置开机自启..."
systemctl enable nginx || handle_error "设置nginx开机自启失败"

# 获取服务器IP地址
SERVER_IP=$(hostname -I | awk '{print $1}')

log "安装完成！"
log "您可以通过以下地址访问网页："
log "http://$SERVER_IP"
log "http://localhost"

# 显示调试信息
log "调试信息："
log "1. 网站根目录: /var/www/html"
log "2. 网站文件权限: $(ls -l /var/www/html/navigation.html)"
log "3. 图标目录权限: $(ls -ld /var/www/html/Icon)"
log "4. Nginx状态: $(systemctl status nginx | grep Active)"
log "5. Nginx配置测试: $(nginx -t 2>&1)"
log "6. 检查网站文件内容:"
head -n 5 /var/www/html/navigation.html
log "7. 检查网络监听状态:"
netstat -tulpn | grep :80 || echo "无法获取网络监听状态"
log "8. 检查SELinux状态:"
getenforce 2>/dev/null || echo "SELinux未安装"
log "9. 检查nginx错误日志:"
tail -n 5 /var/log/nginx/error.log
log "10. 检查nginx访问日志:"
tail -n 5 /var/log/nginx/access.log 