FROM debian:bookworm

RUN apt update && \
    apt install mariadb-server -y && \
    rm -rf /var/lib/apt/lists/* /var/lib/mysql/* && \
    mkdir -p /var/run/mysqld && chown -R mysql:mysql /var/run/mysqld

COPY conf/mysqld.conf /etc/mysql/mariadb.conf.d/50-server.cnf
COPY tools/mariadb.sh /usr/local/bin/mariadb.sh

RUN chmod +x /usr/local/bin/mariadb.sh

CMD ["/usr/local/bin/mariadb.sh"]