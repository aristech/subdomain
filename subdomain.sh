#!/bin/bash
# This script will create a subdomain for a given domain
# and add it to the Nginx configuration
# It will also create a directory for the subdomain
# and add a index.html file to it

# Check if the script is being run as root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi


# replace "domain.com" with your own domain name
# domain name
domainname="domain.com"

# Ask for the subdomain name
echo "Enter the subdomain name:"
read subdomain

# Ask if the subdomain should be a node application or a static website

# Ask if the subdomain should be a node application or a static website
echo "Is this a node application? (y/n)"
read nodeapp

#if [ "$nodeapp" = "y" ]; then read all files in the /etc/nginx/conf.d/ directory for the proxy_pass directive and server-name directive and show them to the user
#    echo "These are the current node applications:"
echo "These are the current node applications:"
for file in /etc/nginx/conf.d/*; do
    # show user proxy_pass directive and server_name directive
    echo "Proxy pass directive: "
    grep -oP '(?<=proxy_pass ).*(?=;)' $file
    echo "Server name directive: "
    grep -oP '(?<=server_name ).*(?=;)' $file
    echo " "


done


# Ask for the port number
echo "Enter the port number:"
read port

# Ask for the github repository
echo "Enter the github repository name .../repo:"

read repo


# Create the subdomain directory
mkdir -p /var/www/$subdomain.$domainname

# chown the directory to the progressnet user
chown -R progressnet:progressnet /var/www/$subdomain.$domainname

# Create the index.html file if it's a static website


if [ "$nodeapp" = "n" ]; then
    echo "<html>
            <head>
            <title>$subdomain.$domainname</title>
            </head>
            <body>
            <h1>$subdomain.$domainname</h1>
            <p>This is the landing page for $subdomain.$domainname</p>
            </body>
            </html>" > /var/www/$subdomain.$domainname/index.html
fi




# Add the subdomain to the Nginx configuration if it doesn't already exist

if [ ! -f /etc/nginx/conf.d/$subdomain.$domainname ]; then
    if [ "$nodeapp" = "n" ]; then
        echo "server {
            listen 80;
            listen [::]:80;

            root /var/www/$subdomain.$domainname;
            index index.html index.htm index.nginx-debian.html;

            server_name $subdomain.$domainname;

            location / {
                try_files \$uri \$uri/ =404;
            }
        }" > /etc/nginx/conf.d/$subdomain.$domainname.conf
    fi
    if [ "$nodeapp" = "y" ]; then
        echo "server {
                  server_name $subdomain.$domainname;
                  root   /var/www/$subdomain.$domainname/app/$repo/$repo;
                  error_log /var/www/$subdomain.$domainname/error.log;
                  access_log  /var/www/$subdomain.$domainname/access.log;
                  location / {
                  proxy_pass http://localhost:$port;
                      proxy_http_version 1.1;
                      proxy_set_header Upgrade \$http_upgrade;
                      proxy_set_header Connection 'upgrade';
                      proxy_set_header Host \$host;
                      proxy_set_header X-Forwarded-Proto https;
                      proxy_cache_bypass \$http_upgrade;
                  }
                  error_page   500 502 503 504  /50x.html;
                  location = /50x.html {
                      root   /usr/share/nginx/html;
                  }



              }

              server {
                  listen       80;
                  server_name  domain.com www.domain.com;
                  return 404; # managed by Certbot




              }" > /etc/nginx/conf.d/$subdomain.$domainname.conf
    fi

fi
# Restart Nginx
sudo service nginx restart

# add ssl certificate
sudo certbot --nginx -d $subdomain.$domainname

#exit
exit



