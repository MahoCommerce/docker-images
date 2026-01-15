# Official docker image for Maho open source ecommerce platform

This image is specifically designed for deployment in cloud-based production environments such as Sevalla, DigitalOean, and similar PaaS providers. This image does not include MySQL or any database. You will need to provision a managed MySQL database separately through your cloud provider.

## Repository tags

- `nightly`: `dev-main` version of Maho, running on latest `FrankenPHP` +`PHP 8.5`
- `latest`: latest stable release version of Maho (26.1.0), running on latest `FrankenPHP` +`PHP 8.5`
- `26.1.0-php8.5`
- `26.1.0-php8.4`
- `26.1.0-php8.3`
- `25.11.0-php8.4`
- `25.11.0-php8.3`
- `25.9.0-php8.4`
- `25.9.0-php8.3`
- `25.7.0-php8.4`
- `25.7.0-php8.3`
- `25.5.0-php8.4`
- `25.5.0-php8.3`
- `25.5.0-php8.2`

## Deployment

### Option 1: start from local development

- Setup your docker based web server using this image
- Create an empty database, depending on how your cloud provider allows you
- Install the platform locally during development, generating a `local.xml` file with all configurations
- Copy the `local.xml` and change the configuration options as needed (eg: replacing database hostname, user, pass etc)
- Create an environment variable on your cloud provider configuration, called `MAHO_LOCAL_XML` and copy the contents of the previously edited `local.xml` into it
- Import a dump of the locally created database in your cloud database, edit the values in the `core_config_data` table, fixing the domain name for the website
- Start the infrastructure

### Option 2: online installation

- Setup your docker based web server using this image
- Create an empty database, depending on how your cloud provider allows you
- Start the whole infrastructure
- Navigate to the domain you pointed the infrastructure to, the web installation should start
- After installing Maho, navigate via ssh to the docker container, copy the contents of `app/etc/local.xml``
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

This configuration with have the app (which mainly will contain `local.xml`), media and mysql-data folders directly mapped on the host, but you can manage those the way you prefer the most.

After starting the containers, you can install Maho with:

```bash
docker exec -it maho ./maho install --license_agreement_accepted yes --locale en_US --timezone Europe/London --default_currency EUR --db_host mysql --db_name maho --db_user maho --db_pass askmd72BBSspak --url https://maho.local/ --secure_base_url https://maho.local/ --use_secure 1 --use_secure_admin 1 --admin_lastname admin --admin_firstname admin --admin_email admin@admin.com --admin_username admin --admin_password qwe123098poiqwe123098poi --sample_data=1
docker exec -it maho ./maho index:reindex:all
docker exec -it maho ./maho cache:flush
```

## Customizing the platform

We all know an ecommerce project needs addon modules and custom development, thus, most probably, you won't be able to use this image as is. Our suggestion is to import it in your project repository and build your own on top if it. This way you'll take advantage of the official developments/support/updates, with the power of your custom implementations.
