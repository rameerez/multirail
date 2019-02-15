#!/bin/sh

# Should be run as sudo

# Usage: add-new-website.sh domain -- script to set up a new site with SSL cert
# where:
#     domain website domain without subdomains (ex: example.com)

if [ ! -z "$1" ]
then
    DOMAIN=$1

    myip=$(hostname -I | awk '{print$1}')

    read -p "Have you already pointed your site DNS to this server's IP? IP: $myip [Y/n] " domain_dns_configured

    if [ "$domain_dns_configured" != "Y" ]
    then
        echo "ERROR: You need to first configure your domain's DNS to point to this server IP address or else this script will fail trying to set up a SSL certificate"
        exit 1
    fi

    echo "Starting website creation and configuration for domain name: $DOMAIN"
    
    echo "Creating $DOMAIN folder structure under /var/www ..."
    mkdir -p /var/www/$DOMAIN/public_html

    echo "Setting correct permissions for the new folder..."
    chown -R $USER:$USER /var/www/$DOMAIN/public_html
    
    echo "Setting correct permissions for /var/www..."
    chmod -R 755 /var/www

    echo "Creating new apache2 VirtualHost configuration file..."
    touch  /etc/apache2/sites-available/$DOMAIN.conf

    echo "Configuring new VirtualHost for $DOMAIN..."
    cat > /etc/apache2/sites-available/$DOMAIN.conf << EOM
<VirtualHost *:80>
  ServerAdmin admin@$DOMAIN
  ServerName $DOMAIN
  ServerAlias www.$DOMAIN
  DocumentRoot /var/www/$DOMAIN/public_html

  <Directory /var/www/$DOMAIN/public_html>
      Options Indexes FollowSymLinks
      AllowOverride All
      Require all granted
  </Directory>

  ErrorLog ${APACHE_LOG_DIR}/error.log
  CustomLog ${APACHE_LOG_DIR}/access.log combined

  <IfModule mod_dir.c>
      DirectoryIndex index.php index.pl index.cgi index.html index.xhtml index.htm
  </IfModule>
</VirtualHost>
EOM

  echo "Will now enable VirtualHost in Apache..."
  a2ensite $DOMAIN.conf

  echo "Restarting apache2 service for VirtualHost changes to take place..."
  service apache2 restart

  echo "VirtualHost for $DOMAIN correctly configured and is now active."

  echo "Generating SSL certificate for $DOMAIN using LetsEncrypt's certbot..."
  certbot --apache --agree-tos --redirect --hsts --uir -n -m admin@$DOMAIN -d $DOMAIN

  echo "Success: Correctly created and configured web space and SSL certificate for $DOMAIN 🎉"

else
    echo "ERROR: CRITICAL: No valid website name passed as argument to configure new website."
    exit 1
fi