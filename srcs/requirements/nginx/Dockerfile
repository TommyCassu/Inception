FROM debian:bookworm

RUN apt update && apt install nginx -y --no-install-recommends \
    openssl \
    nginx  && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /etc/nginx/ssl && \
    openssl req -x509  -days 365 -nodes -out /etc/nginx/ssl/inception.crt -keyout /etc/nginx/ssl/inception.key -subj "/C=FR/ST=Occitanie/L=Perpignan/O=42/OU=42/CN=tcassu.42.fr/UID=tcassu" && \
    rm -rf /var/www/html/* 

COPY ./conf/nginx.conf /etc/nginx/nginx.conf

EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]