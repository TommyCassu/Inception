FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
        php-cli \
        php-fpm \
        php-mysql \
        mariadb-client \
        wget \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/www/html

RUN wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY tools/wordpress.sh /usr/local/bin/wordpress.sh
RUN chmod +x /usr/local/bin/wordpress.sh

WORKDIR /var/www/html

EXPOSE 9000

CMD ["/usr/local/bin/wordpress.sh"]
