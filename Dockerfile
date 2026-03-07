ARG PHP_VERSION=8.5
ARG DEBIAN_VARIANT=trixie
FROM dunglas/frankenphp:php${PHP_VERSION}-${DEBIAN_VARIANT}

ARG MYSQL=true
ARG PGSQL=true
ARG SQLITE=true

RUN groupadd -g 1000 maho && useradd -u 1000 -g 1000 -m maho

RUN set -eux; \
  PHP_EXTS="gd intl zip opcache ctype curl dom fileinfo filter ftp hash iconv json libxml mbstring openssl session simplexml soap spl zlib"; \
  APT_PKGS="git patch unzip"; \
  if [ "$MYSQL" = "true" ]; then \
    PHP_EXTS="$PHP_EXTS pdo_mysql"; \
    APT_PKGS="$APT_PKGS default-mysql-client"; \
  fi; \
  if [ "$PGSQL" = "true" ]; then \
    PHP_EXTS="$PHP_EXTS pdo_pgsql pgsql"; \
    APT_PKGS="$APT_PKGS postgresql-client"; \
  fi; \
  if [ "$SQLITE" = "true" ]; then \
    PHP_EXTS="$PHP_EXTS pdo_sqlite"; \
    APT_PKGS="$APT_PKGS sqlite3"; \
  fi; \
  install-php-extensions $PHP_EXTS \
  && apt update \
  && apt-get upgrade -y \
  && apt install -y $APT_PKGS \
  && apt-get autoremove -y \
  && apt clean \
  && rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/* /tmp/* /root/.cache

#Uncomment the next lines if you want libvips image processing to work
# RUN install-php-extensions ffi vips

COPY . /app
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer
COPY php.ini $PHP_INI_DIR/php.ini

RUN rm -rf php.ini
RUN COMPOSER_ALLOW_SUPERUSER=1 composer install --optimize-autoloader --prefer-dist --no-interaction --no-progress --no-dev --no-cache \
  && rm -rf /root/.composer/cache
