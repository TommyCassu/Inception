FROM debian:bookworm

RUN apt update && apt upgrade -y && apt install nginx -y
RUN apt install nano -y
RUN apt install curl -y

RUN mkdir -p /etc/nginx/ssl

RUN apt install openssl -y
RUN openssl req -x509 -nodes -out /etc/nginx/ssl/inception.crt -keyout /etc/nginx/ssl/inception.key -subj "/C=FR/ST=Occitanie/L=Perpignan/O=42/OU=42/CN=tcassu.42.fr/UID=tcassu"

COPY ./conf/nginx.conf /etc/nginx/nginx.conf
COPY ./conf/index.html /var/www/html/index.html


RUN mkdir -p /var/run/nginx

EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]