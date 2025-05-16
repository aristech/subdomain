#!/bin/bash
set -euo pipefail

# ------------- Configuration -------------

PHP_VERSION="8.2"  # Change if using a different PHP version

# ------------- Helper Functions -------------

log() {
  echo -e "\e[32m[INFO]\e[0m $1"
}

error() {
  echo -e "\e[31m[ERROR]\e[0m $1" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || { error "Command '$1' not found. Please install it."; exit 1; }
}

# ------------- Pre-flight Checks -------------

if [ "$EUID" -ne 0 ]; then
  error "This script must be run as root."
  exit 1
fi

require_command nginx
require_command certbot

# ------------- User Input -------------

read -rp "Enter your main domain (e.g., example.com): " domain_name
while [[ -z "$domain_name" ]]; do
  read -rp "Domain cannot be empty. Try again: " domain_name
done

read -rp "Enter the subdomain name: " subdomain
while [[ -z "$subdomain" ]]; do
  read -rp "Subdomain cannot be empty. Try again: " subdomain
done

read -rp "Is this a Node.js app? (y/n): " nodeapp
if [[ "$nodeapp" != "y" ]]; then
  read -rp "Is this a Pocketbase app? (y/n): " pocketbaseapp
else
  pocketbaseapp="n"
fi

read -rp "Enter the port number the app runs on (e.g., 3000): " port
read -rp "Enter the GitHub repo name (folder under /app): " repo

user_name=$(logname)
app_path="/var/www/$subdomain.$domain_name/app/$repo/$repo"
web_root="/var/www/$subdomain.$domain_name"

# ------------- Setup Functions -------------

create_directory() {
  if [ ! -d "$1" ]; then
    mkdir -p "$1"
    chown -R "$user_name:$user_name" "$1"
    log "Created directory: $1"
  fi
}

create_index_html() {
  local html_path="$web_root/index.html"
  cat > "$html_path" <<EOF
<html>
  <head><title>$subdomain.$domain_name</title></head>
  <body>
    <h1>$subdomain.$domain_name</h1>
    <p>This is the landing page for $subdomain.$domain_name</p>
  </body>
</html>
EOF
  log "Created default index.html"
}

generate_nginx_config() {
  local conf_path="/etc/nginx/conf.d/$subdomain.$domain_name.conf"
  if [[ "$nodeapp" == "y" ]]; then
    cat > "$conf_path" <<EOF
server {
  server_name $subdomain.$domain_name;
  root $app_path;
  error_log $web_root/error.log;
  access_log $web_root/access.log;

  location / {
    proxy_pass http://localhost:$port;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_cache_bypass \$http_upgrade;
  }

  error_page 500 502 503 504 /50x.html;
  location = /50x.html {
    root /usr/share/nginx/html;
  }
}
EOF

  elif [[ "$pocketbaseapp" == "y" ]]; then
    cat > "$conf_path" <<EOF
server {
  server_name $subdomain.$domain_name;
  root $app_path;
  error_log $web_root/error.log;
  access_log $web_root/access.log;

  location / {
    proxy_set_header Connection '';
    proxy_http_version 1.1;
    proxy_read_timeout 360s;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_pass http://localhost:$port;
  }

  error_page 500 502 503 504 /50x.html;
  location = /50x.html {
    root /usr/share/nginx/html;
  }
}
EOF

  else
    cat > "$conf_path" <<EOF
server {
  listen 80;
  server_name $subdomain.$domain_name;
  root $web_root/public;
  index index.php index.html;
  error_log $web_root/error.log;
  access_log $web_root/access.log;

  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  location ~ \.php\$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include fastcgi_params;
  }
}
EOF
  fi

  log "Generated NGINX config at $conf_path"
}

setup_pocketbase_service() {
  local service_file="/lib/systemd/system/$subdomain.service"

  cat > "$service_file" <<EOF
[Unit]
Description=$subdomain Pocketbase App

[Service]
Type=simple
User=$user_name
Group=$user_name
LimitNOFILE=4096
Restart=always
RestartSec=5s
StandardOutput=append:$web_root/pberrors.log
StandardError=append:$web_root/pberrors.log
ExecStart=$app_path/pocketbase serve --http=127.0.0.1:$port

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$subdomain.service"
  systemctl start "$subdomain.service"
  log "Pocketbase systemd service set up and started"
}

# ------------- Execution -------------

create_directory "$web_root"

if [[ "$nodeapp" == "n" && "$pocketbaseapp" == "n" ]]; then
  create_index_html
fi

generate_nginx_config

if [[ "$pocketbaseapp" == "y" ]]; then
  setup_pocketbase_service
fi

certbot --nginx -d "$subdomain.$domain_name"
log "SSL certificate created with Certbot"

systemctl restart nginx
log "Nginx restarted"

if [[ "$pocketbaseapp" == "y" ]]; then
  echo -e "\e[33mReminder:\e[0m Download and extract the Pocketbase binary to $app_path"
fi

log "Setup completed for $subdomain.$domain_name"

exit 0
