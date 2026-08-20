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

COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# composer.json alone first, so unrelated file changes don't bust this layer
COPY composer.json /app/
RUN COMPOSER_ALLOW_SUPERUSER=1 composer install --optimize-autoloader --prefer-dist --no-interaction --no-progress --no-dev --no-cache \
  && rm -rf /root/.composer/cache

COPY php.ini $PHP_INI_DIR/php.ini

# The Maho site block: /api/* routing, file access rules, security headers.
# Selected from caddyfiles/ by the workflow, the same way composer.json is.
# An empty file means "keep the Caddyfile of the base image", which is what the
# rows of versions.json before Maho 26.7 ask for. COPY cannot be skipped, so the
# emptiness test does the skipping.
#
# The base image runs --config /etc/frankenphp/Caddyfile, which it hard-links to
# /etc/caddy/Caddyfile. Copying over /etc/caddy/Caddyfile breaks that link, so
# the link is re-created; without that the container keeps serving the base
# image's Caddyfile and the copy is a silent no-op.
COPY Caddyfile /tmp/maho.Caddyfile
RUN set -eux; \
  if [ -s /tmp/maho.Caddyfile ]; then \
    cp /tmp/maho.Caddyfile /etc/caddy/Caddyfile; \
    ln -f /etc/caddy/Caddyfile /etc/frankenphp/Caddyfile; \
  fi; \
  rm -f /tmp/maho.Caddyfile
