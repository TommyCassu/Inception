#!/bin/bash
set -eu

secs=30
endTime=$(( $(date +%s) + secs))

chown -R www-data:www-data /var/www/html

#Wait for mariadb server ping
until mysqladmin ping -h mariadb --silent; do
    if [ "$(date +%s)" -ge "$endTime" ]; then
        echo "[WP] Mariadb is unreachable. TIMEOUT" >&2
        exit 1
    fi
    sleep 1
done

if ! wp core is-installed --path=/var/www/html --allow-root; then
    wp core download --path=/var/www/html --locale=fr_FR --allow-root

    wp config create \
        --path=/var/www/html \
        --dbname="${MARIADB_DATABASE}" \
        --dbuser="${MARIADB_USER}" \
        --dbpass="${MARIADB_PASSWORD}" \
        --dbhost="mariadb:3306" \
        --allow-root

    wp core install \
        --path=/var/www/html \
        --url="https://${DOMAIN_NAME}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --allow-root

    wp user create \
        "${SECOND_WP_USER}" \
        "${SECOND_WP_EMAIL}" \
        --path=/var/www/html \
        --role=editor \
        --user_pass="${SECOND_WP_PASSWORD}" \
        --allow-root
else
    echo "[WP] already installed"
fi

exec php-fpm8.2 -F -O
