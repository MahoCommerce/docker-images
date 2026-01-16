FROM dunglas/frankenphp:php8.5-bookworm

RUN groupadd -g 1000 maho && useradd -u 1000 -g 1000 -m maho

RUN install-php-extensions pdo_mysql pdo_pgsql pgsql pdo_sqlite sqlite3 gd intl zip opcache ctype curl dom fileinfo filter ftp hash iconv json libxml mbstring openssl session simplexml soap spl zlib \
  && apt update && apt install -y git patch unzip default-mysql-client postgresql-client \
  && apt clean \
  && rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/* /tmp/* /root/.cache

#Uncomment the next lines if you want libvips image processing to work
# RUN install-php-extensions ffi vips

COPY . /app
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer
COPY php.ini $PHP_INI_DIR/php.ini

RUN rm -rf .github .dockerignore Dockerfile php.ini
RUN COMPOSER_ALLOW_SUPERUSER=1 composer install --optimize-autoloader --prefer-dist --no-interaction --no-progress --no-dev --no-cache \
  && rm -rf /root/.composer/cache
