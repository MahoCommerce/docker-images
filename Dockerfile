ARG PHP_VERSION=8.5
ARG DEBIAN_VARIANT=trixie
FROM dunglas/frankenphp:php${PHP_VERSION}-${DEBIAN_VARIANT}

ARG MYSQL=true
ARG PGSQL=true
ARG SQLITE=true

# Which files under config/ this image is built from. The defaults name the
# newest generation, so a plain `docker build .` builds the current one.
# COPY expands these in its source path, which is why no file has to sit at the
# repository root. An empty CADDYFILE keeps the Caddyfile of the base image,
# which is what the rows of versions.json before Maho 26.7 ask for.
# Not named COMPOSER: build args are exported to RUN as environment variables,
# and Composer reads $COMPOSER as the name of its manifest file, so it would
# try to open "25.11" instead of composer.json.
ARG COMPOSER_TEMPLATE=25.11
ARG CADDYFILE=26.7
ARG MAHO_VERSION=dev-main

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

# The template carries a "VERSION" placeholder for mahocommerce/maho, which is
# replaced here rather than by the workflow, so the build is self-contained.
COPY config/composer/${COMPOSER_TEMPLATE}.json /app/composer.json
RUN set -eux; \
  php -r '$f = "/app/composer.json"; \
    $j = json_decode(file_get_contents($f), true); \
    $j["require"]["mahocommerce/maho"] = getenv("MAHO_VERSION"); \
    file_put_contents($f, json_encode($j, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");'; \
  COMPOSER_ALLOW_SUPERUSER=1 composer install --optimize-autoloader --prefer-dist --no-interaction --no-progress --no-dev --no-cache; \
  rm -rf /root/.composer/cache

COPY config/php.ini $PHP_INI_DIR/php.ini

# The Maho site block: /api/* routing, file access rules, security headers.
# The whole directory is copied because this selection is optional and COPY
# cannot be skipped: an empty CADDYFILE installs nothing and the base image
# keeps its own Caddyfile. The files are removed in the same layer.
#
# The base image runs --config /etc/frankenphp/Caddyfile, which it hard-links to
# /etc/caddy/Caddyfile. Copying over /etc/caddy/Caddyfile breaks that link, so
# the link is re-created; without that the container keeps serving the base
# image's Caddyfile and the copy is a silent no-op.
COPY config/caddyfile/ /tmp/caddyfile/
RUN set -eux; \
  if [ -n "$CADDYFILE" ]; then \
    cp "/tmp/caddyfile/${CADDYFILE}.caddyfile" /etc/caddy/Caddyfile; \
    ln -f /etc/caddy/Caddyfile /etc/frankenphp/Caddyfile; \
  fi; \
  rm -rf /tmp/caddyfile
