# Official docker image for Maho open source ecommerce platform

This image is based on FrankenPHP and is specifically designed for deployment in cloud-based production environments such as Sevalla, DigitalOcean, and similar PaaS providers. This image does not include a database server. You will need to provision a managed database (MySQL or PostgreSQL) through your cloud provider, or use SQLite which requires no external service. Database support varies by version - see the tags below.

## Repository tags

- `nightly`: `dev-main` version of Maho, running on latest `FrankenPHP` + `PHP 8.5` (Trixie)
- `latest`: latest stable release version of Maho (26.7.3), running on latest `FrankenPHP` + `PHP 8.5` (Trixie)
- `26.7.3-php8.5`, `26.7.3-php8.4`, `26.7.3-php8.3` -Trixie, MySQL + PostgreSQL + SQLite
- `26.7.2-php8.5`, `26.7.2-php8.4`, `26.7.2-php8.3` -Trixie, MySQL + PostgreSQL + SQLite
- `26.7.1-php8.5`, `26.7.1-php8.4`, `26.7.1-php8.3` -Trixie, MySQL + PostgreSQL + SQLite
- `26.7.0-php8.5`, `26.7.0-php8.4`, `26.7.0-php8.3` -Trixie, MySQL + PostgreSQL + SQLite
- `26.5.0-php8.5`, `26.5.0-php8.4`, `26.5.0-php8.3` -Trixie, MySQL + PostgreSQL + SQLite
- `26.3.0-php8.5`, `26.3.0-php8.4`, `26.3.0-php8.3` -Trixie, MySQL + PostgreSQL + SQLite
- `26.1.0-php8.5`, `26.1.0-php8.4`, `26.1.0-php8.3` -Bookworm, MySQL + PostgreSQL + SQLite
- `25.11.0-php8.4`, `25.11.0-php8.3` -Bookworm, MySQL only
- `25.9.0-php8.4`, `25.9.0-php8.3` -Bookworm, MySQL only
- `25.7.0-php8.4`, `25.7.0-php8.3` -Bookworm, MySQL only
- `25.5.0-php8.4`, `25.5.0-php8.3`, `25.5.0-php8.2` -Bookworm, MySQL only

## Support lifecycle

Every tag is periodically rebuilt so it picks up PHP and Debian security updates. A tag stops being rebuilt once its **runtime** reaches end of life, whichever comes first: its PHP version or its Debian release.

| PHP | rebuilt until |     | Debian   | rebuilt until |
|-----|---------------|-----|----------|---------------|
| 8.2 | 2026-12-31    |     | Bookworm | 2028-06-30    |
| 8.3 | 2027-12-31    |     | Trixie   | 2030-06-30    |
| 8.4 | 2028-12-31    |     |          |               |
| 8.5 | 2029-12-31    |     |          |               |

`nightly` is the exception and never reaches end of life: it always tracks `dev-main` on the current PHP and Debian, and is moved forward in place rather than retired.

Tags that reach end of life are **never deleted**. They remain on Docker Hub and stay pullable indefinitely; they simply stop receiving updates. If you are running one, you are responsible for the unpatched PHP and OS packages inside it, so plan to move to a tag on a supported runtime.

## Deployment

### Option 1: start from local development

- Setup your docker based web server using this image
- Create an empty database (MySQL, PostgreSQL, or SQLite), depending on how your cloud provider allows you
- Install the platform locally during development, generating a `local.xml` file with all configurations
- Copy the `local.xml` and change the configuration options as needed (eg: replacing database hostname, user, pass etc)
- Create an environment variable on your cloud provider configuration, called `MAHO_LOCAL_XML` and copy the contents of the previously edited `local.xml` into it
- Import a dump of the locally created database in your cloud database, edit the values in the `core_config_data` table, fixing the domain name for the website
- Start the infrastructure

### Option 2: online installation

- Setup your docker based web server using this image
- Create an empty database (MySQL, PostgreSQL, or SQLite), depending on how your cloud provider allows you
- Start the whole infrastructure
- Navigate to the domain you pointed the infrastructure to, the web installation should start
- After installing Maho, navigate via ssh to the docker container, copy the contents of `app/etc/local.xml`
- In your cloud provider configurations, create an environment variable called `MAHO_LOCAL_XML` and paste the contents of the `local.xml` into it (the previously created file would be lost by a new deployment or by an update of the docker image)
- Restart the whole infrastructure and test that everything works as expected

### Media filesystem

Remember that Maho stores file uploads (eg: product images) in the `public/media` folder. Since you do not want to lose those important files, you should configure a `persistent disk` through your cloud infrastructure and mount it on `/app/public/media`, then restart the whole infrastructure and test that files actually get saved to that disk.

**Note**: most of the cloud providers will allow you to mount a persistent disk to one container/machine only, that means that at the moment you won't be able to have more than one frontend nodes. In case you need more power, you have two options:
- scale the CPU/RAM of that single container (it should be more than enough)
- create a linux based node to act as `NFS` share for the `public/media` folder, then mount it into the frontend nodes

We're working on supporting S3 compatible storage for better horizontal scaling but that's not available at the moment.

## Simple `docker-compose` configuration

```yml
services:
    php:
        container_name: maho
        image: mahocommerce/maho:latest
        environment:
            - SERVER_NAME=maho.local
        ports:
            - ${HTTP_PORT:-80}:80
            - ${HTTPS_PORT:-443}:443
            - ${HTTPS_PORT:-443}:443/udp
        restart: unless-stopped
        volumes:
            - .docker/data:/data
            - .docker/config:/config
            - ./app:/app/app
            - ./media:/app/public/media
        tty: true
    mysql:
        container_name: mysql
        image: mysql:latest
        environment:
            - MYSQL_DATABASE=maho
            - MYSQL_USER=maho
            - MYSQL_PASSWORD=askmd72BBSspak
            - MYSQL_ROOT_PASSWORD=MaajwekSNUsk242sred
        ports:
            - "3306:3306"
        restart: unless-stopped
        volumes:
            - ./mysql-data:/var/lib/mysql
```

This configuration will have the app (which mainly will contain `local.xml`), media and mysql-data folders directly mapped on the host, but you can manage those the way you prefer the most.

After starting the containers, you can install Maho with:

```bash
docker exec -it maho ./maho install --license_agreement_accepted yes --locale en_US --timezone Europe/London --default_currency EUR --db_host mysql --db_name maho --db_user maho --db_pass askmd72BBSspak --url https://maho.local/ --secure_base_url https://maho.local/ --use_secure 1 --use_secure_admin 1 --admin_lastname admin --admin_firstname admin --admin_email admin@admin.com --admin_username admin --admin_password qwe123098poiqwe123098poi --sample_data=1
docker exec -it maho ./maho index:reindex:all
docker exec -it maho ./maho cache:flush
```

## Web server configuration

Tags for **Maho 26.7 and later** (`latest` and `nightly` included) ship a Maho site block at `/etc/caddy/Caddyfile` (hard-linked to `/etc/frankenphp/Caddyfile`, which is the path the container actually runs). It does four things that the plain `dunglas/frankenphp` Caddyfile does not:

- routes `/api/*` to the correct entry point (`rest.php`, `api.php` or `index.php`, depending on the path)
- denies access to hidden files, with exceptions for `/.well-known/` and `/.thumbs/`
- denies access to backup, log and configuration files
- answers `405` to `TRACE` and `TRACK`, and sets `X-Content-Type-Options: nosniff`

Without the `/api/*` routing the storefront works and every API call returns the storefront 404 page, so do not drop these rules.

To add directives without replacing the file, set the `CADDY_SERVER_EXTRA_DIRECTIVES` environment variable. To replace it, mount your own file over `/etc/frankenphp/Caddyfile`.

Do **not** add CORS headers or an `OPTIONS` preflight response to the web server. Maho answers both inside the API kernel. Set the allowed origins in **System > Configuration > Services > API > CORS Allowed Origins**.

Older tags keep the base FrankenPHP site block, because Maho before 26.7 has no `rest.php` entry point to route to.

Full reference: [mahocommerce.com/hosting/web-server](https://mahocommerce.com/hosting/web-server/).

## Customizing the platform

We all know an ecommerce project needs addon modules and custom development, thus, most probably, you won't be able to use this image as is. Our suggestion is to import it in your project repository and build your own on top of it. This way you'll take advantage of the official developments/support/updates, with the power of your custom implementations.
