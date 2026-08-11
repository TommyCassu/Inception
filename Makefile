COMPOSE      := sudo docker compose -f srcs/docker-compose.yml

all: up
	
up: 
	mkdir -p /home/tcassu/data/mariadb /home/tcassu/data/wordpress
	$(COMPOSE) up --build -d

build: 
	$(COMPOSE) build

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

clean: 
	$(COMPOSE) down --remove-orphans

fclean:
	$(COMPOSE) down -v --rmi all --remove-orphans
	sudo rm -rf /home/tcassu/data/mariadb /home/tcassu/data/wordpress

re: fclean up

.PHONY: all up build logs ps stop start down re clean fclean
