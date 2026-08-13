*This project has been created as part of the 42 curriculum by tcassu.*

# Inception

A small WordPress infrastructure built from scratch with Docker Compose: three services,
three containers, three Dockerfiles.

---

## Description

The goal is to stop treating a server like one big machine where you install everything
side by side, and instead split it into isolated services that only talk to each other
through a private network.

Concretely, the stack serves a WordPress site over HTTPS:

```
                        WWW
                         │ 443 (TLS 1.2 / 1.3)
    ┌────────────────────┴─────────────────────────┐
    │   docker network: srcs_inception (bridge)    │
    │                                              │
    │   mariadb ◄──3306──► wordpress ◄──9000──► nginx
    │   mysqld             php-fpm             nginx │
    └──────────────────────────────────────────────┘
         │                    │
    volume mariadb       volume wordpress
    ~/data/mariadb       ~/data/wordpress
```

---

## Instructions

You need Docker, docker compose, `make`, and one line in
your hosts file.

```bash
# 1. tell your machine what tcassu.42.fr means
echo "127.0.0.1 tcassu.42.fr" | sudo tee -a /etc/hosts

# 2. create the config files
cp srcs/.env.example srcs/.env      # then fill in the values
# and create the secrets/ folder — see DEV_DOC.md §3.3

# 3. build and start
make
```

Then open **https://tcassu.42.fr**. Your browser will complain about the certificate —
that is expected, it is self-signed. The admin panel is at `/wp-admin`.

| Command | What it does |
|---|---|
| `make` | build the images and start everything |
| `make down` | stop and remove the containers (data is kept) |
| `make logs` | follow the logs |
| `make re` | rebuild from scratch |
| `make fclean` | **deletes everything, including the database** |

Full details in [DEV_DOC.md](DEV_DOC.md) and [USER_DOC.md](USER_DOC.md).

---

## Project description

### How Docker is used

Every service follows the same layout under `srcs/requirements/`: a `Dockerfile`, a
`conf/` folder for the files copied into the image, and a `tools/` folder for the
entrypoint script. `docker-compose.yml` ties them together — one bridge network, two
named volumes, four secrets, one published port.

All three images are built locally and named after their service. The only thing pulled
from DockerHub is `debian:bookworm`, the penultimate stable Debian, which the subject
allows.

Both entrypoints share one shape: fix ownership of the mounted volume, check whether the
service is already set up, do the one-time setup if it is not, then `exec` the real
process. That last step is what makes the service **PID 1**.

### Main design choices

| Choice | Why |
|---|---|
| Entrypoints end with **`exec`** | The service becomes PID 1 and receives `SIGTERM` directly on `docker stop`. Without it bash stays PID 1, never forwards the signal, and the process is `SIGKILL`ed after 10 s — enough to corrupt a database mid-write. Measurable: `time docker stop mariadb` returns in under 2 s. |
| MariaDB set up with **`--init-file`** | One server start instead of two, no wait loop, and port 3306 is never open while root still has no password. Trade-off: it fails *silently* on bad SQL, so I verify with a real query instead of trusting `docker ps`. |
| A **bounded** wait loop | WordPress polls `mysqladmin ping -h mariadb` with a 30 s deadline, then exits with an error. `depends_on` only guarantees the container *started*, not that mysqld accepts connections — two different problems. |
| php-fpm on **TCP 9000** | Debian defaults to a unix socket, which is a filesystem object and cannot cross a container boundary. NGINX lives elsewhere, so it needs a real port. |
| **No `php` metapackage** | It depends on `libapache2-mod-php` → `apache2`, a second web server the subject forbids. Naming `php-fpm`, `php-cli` and `php-mysql` avoids it and saves ~260 MB. |
| Passwords as **Docker secrets** | Environment variables are readable through `docker inspect`; secrets are files mounted per service. Detailed below. |
| `rm -rf /var/lib/mysql/*` at build | `apt` pre-initialises the datadir, and Docker copies image content into an empty volume — which silently defeated my "is it installed?" check. |

### Virtual Machines vs Docker

A VM emulates hardware and runs **its own kernel** on top of yours. A container has no
kernel at all: its processes run directly on the host kernel, isolated by **namespaces**
(what a process can see: other processes, the network, the filesystem) and **cgroups**
(what it can consume: CPU, memory, I/O).

That is why a VM takes gigabytes and tens of seconds to boot, while a container takes
hundreds of megabytes and milliseconds.

The clearest proof is on my own machine:

```bash
docker exec mariadb cat /proc/1/comm             # mysqld
docker inspect mariadb --format '{{.State.Pid}}' # 48892
```

One single process, two numbers: PID 1 inside its namespace, PID 48892 on the host.
There is no "MariaDB machine" anywhere — just an ordinary Linux process that has been
lied to about what it can see.

Another giveaway: `ls -l /home/tcassu/data/mariadb` shows the files owned by `dhcpcd`.
Inside the container that user is `mysql`, uid 999; on my host, uid 999 happens to be
`dhcpcd`. The kernel only ever sees the number — the name is a lookup that differs on
each side. A VM would never behave like that.

**Trade-off:** the isolation is weaker. Containers share a kernel, so a kernel-level
vulnerability affects all of them. A VM isolates at the hardware level. For this project
the trade is obviously worth it.

### Secrets vs Environment Variables

I started with all the passwords in `.env`, injected through `env_file:`. That works,
but environment variables are **designed to be readable** — that is their whole job:

```bash
docker inspect mariadb --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -i password
MARIADB_ROOT_PASSWORD=…
WP_ADMIN_PASSWORD=…
```

Anyone with access to the Docker daemon reads them in plaintext. They also land in
`/proc/<pid>/environ` and are inherited by every child process.

A Docker secret is not a variable — it is a **file mounted read-only** inside the
container at `/run/secrets/<name>`. It does not appear in `docker inspect`, is not in
the process environment, and is not inherited. After the switch, the same command prints
nothing.

The part I did not expect is that the real gain is not encryption — it is
**compartmentalisation**. With a single `.env` passed to every service, all three
containers received every password. With secrets, each service declares what it needs:

| Service | Receives |
|---|---|
| mariadb | `db_root_password`, `db_password` |
| wordpress | `db_password`, `wp_admin_password`, `wp_sc_usr_password` |
| nginx | nothing |

WordPress never sees the MariaDB **root** password, because it has no use for it.

So I use both, as the subject requires: `.env` for names, titles, emails and paths;
`secrets/` for every password.

### Docker Network vs Host Network

With a user-defined bridge network, Docker runs an **embedded DNS server**. Each
container is reachable by its **service name**:

```bash
docker exec wordpress getent hosts mariadb     # 172.18.0.2  mariadb
```

That is why my configuration says `fastcgi_pass wordpress:9000` and
`--dbhost=mariadb:3306` and never a hardcoded IP — the IPs change on every recreation,
the names do not.

The second benefit is isolation. Only NGINX publishes a port, so the database is simply
unreachable from the host:

```bash
bash -c '</dev/tcp/127.0.0.1/3306'             # Connection refused
```

`network: host` would remove the network namespace entirely: the container would use the
host's network stack directly. No isolation, no name-based DNS, and MariaDB would be
listening on my machine. It is forbidden by the subject, and it would defeat the whole
point of the exercise. (`links:` is the ancestor of the embedded DNS and has been
obsolete since user-defined networks exist.)

### Docker Volumes vs Bind Mounts

A container's writable layer is **disposable** — anything written outside a volume dies
with the container. A database without persistence is useless, so both services need
storage that outlives them.

| | Named volume | Bind mount |
|---|---|---|
| Location | managed by Docker | a path you choose |
| Lifecycle | managed by Docker | none — it is your folder |
| Shows in `docker volume ls` | yes | no |
| Portable | yes | tied to that host path |

The subject asks for **named volumes** whose data lives in `/home/login/data`, which is
why I declare them with the `local` driver and a `bind` option:

```yaml
volumes:
  mariadb:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/tcassu/data/mariadb
```

They are named volumes — Docker knows them, they appear in `docker volume ls` — but the
underlying storage is a directory I control.

This cost me an hour of debugging, and it is the thing I understand best now: **because
the storage is a bind, `docker volume rm` removes Docker's *reference* to the data, not
the data itself.** Compose proudly printed `Volume srcs_mariadb Removed` while every
file was still on disk. My database "kept surviving" a clean rebuild, and the entrypoint
kept concluding it was already installed. That is why `fclean` runs an explicit `rm -rf`
afterwards.

---

## What went wrong (and what I learned)

I am keeping this section because these are the parts I actually understand, as opposed
to the parts I merely read about.

**The container that would not stop restarting.** My first `mariadb.sh` ran `mysqld &`
and then `exec mysqld` at the end. Two servers, same datadir, same port — the second one
failed to bind, and since it was PID 1, the container died. This is where PID 1 finally
clicked.

**The database that was never created.** `apt-get install mariadb-server` initialises
`/var/lib/mysql` at build time. When Docker mounts an empty named volume over a
directory that has content in the image, it **copies the image content into the volume**.
So my "empty" datadir arrived pre-filled, my `if [ ! -d /var/lib/mysql/mysql ]` guard
honestly answered "already installed", and the init file never ran. Fixed with
`rm -rf /var/lib/mysql/*` in the same `RUN`.

**`Access denied` for a user that existed.** `mysql_install_db` creates two anonymous
`''@'localhost'` accounts, bundled with the `test` database. MariaDB sorts candidate
accounts most-specific-host-first, so the anonymous account shadowed my `'user'@'%'` on
socket connections. `--skip-test-db` prevents all of it — better than deleting the rows
afterwards.

**A diagnostic that lied.** The `plugin` column of `mysql.user` showed
`mysql_native_password`, which made it look like my `ALTER USER` had run. It had not.
`SHOW CREATE USER` revealed the truth: `mysql_native_password USING 'invalid' OR
unix_socket` — two authentication methods where the view only displayed one, and root
was still authenticating by uid. Lesson: when a diagnostic contradicts reality, distrust
the diagnostic.

**A build that depended on volunteers.** I used `wp core download --locale=fr_FR`. It
worked until WordPress 7.0.4 was released and the French translation had not been
published yet — my container then crash-looped on something entirely outside my control.
I dropped the locale. A build should not depend on a third party's publishing schedule.

---

## Resources

**Official documentation**
- [Docker documentation](https://docs.docker.com/) — Dockerfile reference, best practices
- [Docker Compose file reference](https://docs.docker.com/reference/compose-file/)
- [Docker secrets in Compose](https://docs.docker.com/compose/how-tos/use-secrets/)
- [NGINX documentation](https://nginx.org/en/docs/) — `ssl_protocols`, `fastcgi_pass`, `try_files`
- [MariaDB knowledge base](https://mariadb.com/kb/en/) — `mysql_install_db`, `--init-file`, account matching
- [PHP-FPM configuration](https://www.php.net/manual/en/install.fpm.configuration.php)
- [WP-CLI commands](https://developer.wordpress.org/cli/commands/)

### How AI was used

I used Claude (Anthropic) throughout this project, and I want to be precise about what
for, because the point was to end up understanding my own code.

**What I used it for:**
- **Explaining concepts** before writing anything: PID 1 and signal propagation, the
  difference between namespaces and cgroups, how Docker's embedded DNS works, what
  `docker volume rm` actually removes on a bind-backed volume.
- **Code review.** I wrote the entrypoint scripts, the Dockerfiles and the compose file
  myself, then had them reviewed line by line. Most of my mistakes were shell mistakes:
  missing `&&` between commands, a `\` where none belonged, `[` used without spaces,
  `$@` used where a real path was needed.
- **Debugging.** The five bugs listed above were diagnosed by running commands and
  reading the output — `docker inspect`, `SHOW CREATE USER`, `docker history`, the
  wordpress.org API — rather than by guessing. That method is the most useful thing I
  took from this project.
- **Drafting these documentation files**, which I edited and corrected.

