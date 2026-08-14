# Developer Documentation

Technical documentation for the Inception project: how to set up the environment from
scratch, build and run the stack, manage containers and volumes, and where the data lives.

---

## Table of contents

1. [Prerequisites](#1-prerequisites)
2. [Repository layout](#2-repository-layout)
3. [Environment setup from scratch](#3-environment-setup-from-scratch)
4. [Build and launch](#4-build-and-launch)
5. [Managing containers](#5-managing-containers)
6. [Managing volumes and data persistence](#6-managing-volumes-and-data-persistence)
7. [More commands](#7-more-commands)


---

## 1. Prerequisites

| Requirement | Notes |
|---|---|
| `docker` | |
| `docker compose` | |
| `sudo` rights | The `Makefile` calls `sudo docker` |
| An entry in `/etc/hosts` | 127.0.0.1 tcassu.42.fr |

### Docker without `sudo` (optional)

```bash
sudo usermod -aG docker $USER
```

If you do this, remove `sudo` from the `COMPOSE`

### Domain name

The domain `tcassu.42.fr` does not exist in any public DNS. It only resolves because the
host is told to resolve it locally:

```bash
echo "127.0.0.1 tcassu.42.fr" | sudo tee -a /etc/hosts
```

you can verify with this command if the host is correctly set :

```bash
getent hosts tcassu.42.fr
```

Without this line nothing at `https://tcassu.42.fr` works 

---

## 2. Repository layout

```
.
├── Makefile                  entry point — builds everything via docker compose
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── .gitignore                ignores .env and the whole secrets/ folder
├── secrets/                  one file per credential — NEVER committed
│   ├── db_root_password.txt
│   ├── db_password.txt
│   ├── wp_admin_password.txt
│   └── wp_sc_usr_password.txt
└── srcs/
    ├── docker-compose.yml    3 services, 1 network, 2 named volumes, 4 secrets
    ├── .env                  non-sensitive settings — NEVER committed
    ├── .env.example          same keys with placeholder values — committed
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── conf/mysqld.conf
        │   └── tools/mariadb.sh
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── conf/www.conf
        │   └── tools/wordpress.sh
        └── nginx/
            ├── Dockerfile
            └── conf/nginx.conf
```

Every file needed to configure the application lives under `srcs/`, and the `Makefile`
sits at the repository root, as the subject requires.

---

## 3. Environment setup from scratch

Credentials are split in two, on purpose:

| | Holds | Mechanism |
|---|---|---|
| `srcs/.env` | non-sensitive settings (names, titles, emails, paths) | environment variables |
| `secrets/` | **every password** | Docker secrets, mounted as files |

### 3.1 Clone and create the config files

```bash
git clone https://github.com/TommyCassu/Inception.git Inception
cd Inception
cp srcs/.env.example srcs/.env
```

Then edit `srcs/.env` and replace every `XXXXX` with a real value.

### 3.2 Environment variables

`srcs/.env` is read by Docker Compose and injected into the containers through
`env_file:`. It is git-ignored and must never be committed. **It contains no password.**

| Variable | Used by | Description |
|---|---|---|
| `DOMAIN_NAME` | wordpress | Site URL passed to `wp core install` (`tcassu.42.fr`) |
| `MARIADB_DATABASE` | mariadb, wordpress | Database name |
| `MARIADB_USER` | mariadb, wordpress | Non-root database user WordPress connects with |
| `MARIADB_BASEDIR` | mariadb | MariaDB installation prefix (`/usr`) |
| `MARIADB_DATADIR` | mariadb | Data directory (`/var/lib/mysql`) |
| `WP_TITLE` | wordpress | Site title |
| `WP_ADMIN_USER` | wordpress | Administrator login — must not contain `admin` |
| `WP_ADMIN_EMAIL` | wordpress | Administrator email |
| `SECOND_WP_USER` | wordpress | Second user (role: editor) |
| `SECOND_WP_EMAIL` | wordpress | Its email |

### 3.3 Docker secrets

The subject forbids any password in a `Dockerfile` and any credential reaching git, and
recommends Docker secrets for confidential data. Every password in this project is a
secret, never an environment variable.

**Why it matters.** Environment variables are designed to be readable — that is their
job. Anyone with access to the Docker daemon can dump them:

```bash
docker inspect mariadb --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -i password
```

With passwords in `.env`, that command printed all four in plaintext. With secrets it
prints nothing.

**How a secret works.** It is not a variable: it is a **file mounted read-only inside
the container** at `/run/secrets/<secret name>`. It never appears in `docker inspect`,
never lands in `/proc/<pid>/environ`, and is not inherited by child processes.

**Create one file per credential**, containing only the value:

```bash
mkdir -p secrets
echo -n "your_root_password" > secrets/db_root_password.txt
echo -n "your_db_password"   > secrets/db_password.txt
echo -n "your_wp_admin_pw"   > secrets/wp_admin_password.txt
echo -n "your_wp_user_pw"    > secrets/wp_sc_usr_password.txt
```

`-n` avoids a trailing newline. (`$(cat …)` would strip it anyway, but the file stays
clean.)

**Declare them** in `srcs/docker-compose.yml`, at the top level next to `volumes:` and
`networks:`. The path is `../secrets/` because the compose file lives in `srcs/` while
the folder sits at the repository root:

```yaml
secrets:
  db_password:
    file: ../secrets/db_password.txt
  db_root_password:
    file: ../secrets/db_root_password.txt
  wp_admin_password:
    file: ../secrets/wp_admin_password.txt
  wp_sc_usr_password:
    file: ../secrets/wp_sc_usr_password.txt
```

> The **secret name** determines the mount path `/run/secrets/<name>` — not the file
> name. That is why `wp_sc_usr_password` can point at a file whose name is spelled
> differently.

**Distribute them** per service — each one receives only what it needs:

| Service | Secrets received | Why |
|---|---|---|
| `mariadb` | `db_root_password`, `db_password` | sets the root password and creates the application user |
| `wordpress` | `db_password`, `wp_admin_password`, `wp_sc_usr_password` | connects to the DB, creates both WordPress users |
| `nginx` | *none* | serves files and terminates TLS — it has no credential to hold |

This per-service split is the real gain over a single `.env` passed to everything:
WordPress never sees the MariaDB **root** password, because it has no use for it.

**Read them** in the entrypoint scripts:

```bash
--dbpass="$(cat /run/secrets/db_password)"
```

Only the value goes inside the quotes. Writing `"MARIADB_PASSWORD=$(cat …)"` would make
the password literally the string `MARIADB_PASSWORD=…`.

With `set -eu`, a missing secret makes `cat` fail and the container exits loudly instead
of starting with an empty password.

**Verify:**

```bash
docker inspect mariadb --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -i password
# → nothing

docker exec mariadb ls -l /run/secrets/       # db_password  db_root_password
docker exec wordpress ls -l /run/secrets/     # db_password  wp_admin_password  wp_sc_usr_password
docker exec nginx ls /run/secrets/            # No such file or directory
```

### 3.4 Remember **NEVER PUSH YOUR SECRET !**

Both `srcs/.env` and the whole `secrets/` folder must be git-ignored:

```bash
git check-ignore -v srcs/.env
git check-ignore -v secrets/db_password.txt
git ls-files | grep -iE "env|secret"    # only .env.example may appear
```

If you already commit a .env file, add it to .gitignore and remove .env with :

```bash
git rm --cached srcs/.env
```

> `.gitignore` only applies to files git is **not already tracking**. Adding an
> already-committed file to it protects nothing — it has to leave the index first.

### 3.5 Host directories

Docker does not create your Host directories. So remember to create it first :

```bash
mkdir -p /home/change_to_user/data/mariadb /home/change_to_user/data/wordpress
```

---

## 4. Build and launch

```bash
make            # create host dirs, build the 3 images, start detached
```

### Makefile targets

| Target | Command run | Usage |
|---|---|---|
| `all` / `up` | `docker compose up --build -d` | Create host dirs, build images, start detached |
| `build` | `docker compose build` | Build the images only |
| `down` | `docker compose down` | Stop and remove containers + network. Data survives |
| `stop` | `docker compose stop` | Stop containers without removing them |
| `start` | `docker compose start` | Restart stopped containers |
| `logs` | `docker compose logs -f` | Follow the logs of all services |
| `ps` | `docker compose ps` | List the services |
| `clean` | `docker compose down --remove-orphans` | Like `down`, also removes orphan containers |
| `fclean` | `down -v --rmi all` + `rm -rf` | Destructive: removes containers, images, volumes and the data under `/home/tcassu/data` |
| `re` | `fclean` then `up` | Full rebuild from nothing |

Always inspect a target before running it. So remember to use -n on your command to print each commands without executing them :

Exemple :
```bash
make -n fclean
```

### You can use this followed commands to build it without Makefile

```bash
docker compose -f srcs/docker-compose.yml up --build -d
docker compose -f srcs/docker-compose.yml down
docker compose -f srcs/docker-compose.yml ps
docker compose -f srcs/docker-compose.yml logs -f wordpress
docker compose -f srcs/docker-compose.yml config
```

---

## 5. Managing containers

```bash
docker compose -f srcs/docker-compose.yml ps      # status of the three services
docker ps -a                                      # all containers
docker stats                                      # live CPU / memory usage

docker logs mariadb                               # logs of one container
docker logs -f wordpress                          # follow
docker compose -f srcs/docker-compose.yml logs -f # all services

docker exec -it mariadb bash                      # shell inside a container
docker exec -it wordpress bash
docker exec -it nginx bash

docker top nginx                                  # processes, read from the host
docker exec mariadb cat /proc/1/comm              # what PID 1 actually is

docker inspect mariadb --format '{{.State.Status}} {{.RestartCount}}'
docker restart wordpress
```

### Networking

```bash
docker network ls
docker network inspect srcs_inception
docker exec wordpress getent hosts mariadb        # Docker DNS resolution
```

### Images

```bash
docker images
docker history nginx                              # layers — shows every Dockerfile step
docker build -t test srcs/requirements/nginx      # rebuild one image alone
```

### Rebuilding a single service

```bash
docker compose -f srcs/docker-compose.yml up -d --build nginx
```

---

## 6. Managing volumes and data persistence

### Data living location

| Volume | Host path | Content |
|---|---|---|
| `srcs_mariadb` | `/home/tcassu/data/mariadb` | MariaDB data directory (`wpdatabase`, system tables) |
| `srcs_wordpress` | `/home/tcassu/data/wordpress` | WordPress files (`wp-config.php`, themes, uploads) |

```bash
docker volume ls
docker volume inspect srcs_mariadb
ls -l /home/tcassu/data/mariadb
ls -l /home/tcassu/data/wordpress
```

Data still living if contaienr is deleted.

## 7. More commands

### Reset and rebuild

```bash
docker stop $(docker ps -qa); docker rm $(docker ps -qa)
docker rmi -f $(docker images -qa); docker volume rm $(docker volume ls -q)
docker network rm $(docker network ls -q) 2>/dev/null
make
```

### Dockerfiles and images

```bash
docker images                                       # mariadb, wordpress, nginx
docker compose -f srcs/docker-compose.yml ps        # three containers Up

# no web server in the application containers
docker exec wordpress sh -c "command -v nginx"      # empty
docker exec mariadb   sh -c "command -v nginx"      # empty
```


### Check your docker Network

```bash
docker network ls                                   # srcs_inception is listed
docker network inspect srcs_inception --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
docker exec wordpress getent hosts mariadb          # name resolved to an IP
bash -c '</dev/tcp/127.0.0.1/3306'                  # Connection refused — DB not exposed
```

### check NGINX and TLS

```bash
curl -kI https://tcassu.42.fr        # HTTP 200
curl -I  http://tcassu.42.fr         # connection refused — port 80 is not served

curl -k --tlsv1.0 --tls-max 1.0 https://tcassu.42.fr   # must FAIL
curl -k --tlsv1.1 --tls-max 1.1 https://tcassu.42.fr   # must FAIL
curl -k --tlsv1.2 --tls-max 1.2 https://tcassu.42.fr   # must SUCCEED
curl -k --tlsv1.3 https://tcassu.42.fr                 # must SUCCEED

echo | openssl s_client -connect tcassu.42.fr:443 2>/dev/null \
  | openssl x509 -noout -subject -dates

docker exec nginx nginx -T | grep ssl_protocols        # TLSv1.2 TLSv1.3
```

### Volumes

```bash
docker volume ls
docker volume inspect srcs_mariadb      # "device": "/home/tcassu/data/mariadb"
docker volume inspect srcs_wordpress    # "device": "/home/tcassu/data/wordpress"
ls /home/tcassu/data/mariadb /home/tcassu/data/wordpress
```

### WordPress and the database

```bash
# WordPress is installed — not showing the installation page
docker exec wordpress wp core is-installed --path=/var/www/html --allow-root; echo $?

# two users, administrator name free of "admin"
docker exec wordpress wp user list --path=/var/www/html --allow-root

# database is not empty
docker exec -it mariadb mysql -u <user> -p -e "SHOW DATABASES;"
docker exec -it mariadb mysql -u <user> -p wpdatabase -e "SHOW TABLES;"

# after the evaluator posts a comment in the browser, show it landed in the DB
docker exec mariadb mysql -u <user> -p wpdatabase \
  -e "SELECT comment_ID, comment_author, LEFT(comment_content,40) FROM wp_comments;"

# after editing a page in wp-admin, show NGINX serves the new content
curl -sk "https://tcassu.42.fr/?page_id=2" | grep -o "<title>[^<]*"
```

### Persistence

```bash
# make a change first (edit a page, post a comment), then:
sudo reboot

# after the machine is back:
docker ps                          # containers restarted automatically
make up                            # if needed
curl -kI https://tcassu.42.fr      # HTTP 200
```

The changes made before the reboot must still be there.

