#!/bin/bash
set -eu

chown -R mysql:mysql "${MARIADB_DATADIR}" /run/mysqld

if [ ! -d "${MARIADB_DATADIR}/mysql" ]; then
    mysql_install_db --user=mysql --basedir="${MARIADB_BASEDIR}" \
                     --datadir="${MARIADB_DATADIR}" --skip-test-db > /dev/null


cat > /tmp/init.sql << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${MARIADB_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MARIADB_USER}'@'%' IDENTIFIED BY '${MARIADB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MARIADB_DATABASE}\`.* TO '${MARIADB_USER}'@'%';
EOF

    echo "[mariadb] first boot: datadir initialised, applying init file"
    exec mysqld --user=mysql --init-file=/tmp/init.sql
fi

echo "[mariadb] datadir already initialised, starting server"
exec mysqld --user=mysql
