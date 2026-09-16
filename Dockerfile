ARG PHP_VERSION=8.5
ARG DEBIAN_VARIANT=trixie
ARG NODEJS=true
ARG NODE_MAJOR=24

# Where Node comes from: the official image, built from the same tarball as
# nodejs.org and multi-arch, or nothing. The stage is picked by NODEJS, so a
# row without Node never pulls the Node image.
FROM node:${NODE_MAJOR}-trixie-slim AS node-true
FROM scratch AS node-false
FROM node-${NODEJS} AS node

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
ARG CADDYFILE=26.9
ARG MAHO_VERSION=dev-main

# Node.js and the shared libraries of Chromium, for the accessibility scanner
# of Maho 26.9+ (Maho_AccessibilityScan). The scanner spawns `node` and `npm`
# from PHP, installs Playwright and axe-core under var/ on first use and drives
# a headless Chromium. Without Node the admin reports "Node.js was not found",
# and without the libraries Chromium does not start. Only for trixie rows: the
# Node image and Playwright's package list are the Debian 13 ones.
ARG NODEJS

RUN groupadd -g 1000 maho && useradd -u 1000 -g 1000 -m maho

# With NODEJS, the same layer copies Node and npm out of the Node stage and
# installs CHROMIUM_PKGS: the chromium list of Playwright's nativeDeps.ts for
# debian13, identical on x64 and arm64, plus two font packages so screenshots
# do not render blank glyphs. No xvfb: the scanner runs headless. The list is
# spelled out because Playwright's Chromium is not an apt package but a bare
# binary downloaded at runtime, so apt has nothing to resolve for it.
# `playwright install-deps chromium` was tried instead and rejected: it names
# the whole simulated apt closure explicitly, so it reinstalls the real Mesa
# over the stub below and marks xvfb's tree manual, 200 MB more for the same
# libraries. Drift is caught by the test, not by this list: Playwright checks
# the linked libraries of its Chromium at launch and names any missing one,
# and tests/image.sh runs that launch on every build.
#
# libgbm1, which Chromium links, depends on mesa-libgallium at an exact
# version, and that pulls in LLVM and Z3: about 180 MB for a software GL
# renderer. libgbm only dlopens Mesa when a program creates a GBM device, which
# headless Chromium never does (it renders with its bundled SwiftShader, as its
# own log shows). An empty package with that name and version stands in for
# it, so apt is satisfied and never fetches the real one. The version is read
# from the candidate libgbm1 at build time, so the stub follows every upgrade.
RUN --mount=type=bind,from=node,source=/,target=/mnt/node \
  set -eux; \
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
  CHROMIUM_PKGS="libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 libcairo2 libcups2t64 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0t64 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 fonts-liberation fonts-noto-color-emoji"; \
  install-php-extensions $PHP_EXTS \
  && apt update \
  && apt-get upgrade -y \
  && apt install -y $APT_PKGS \
  && if [ "$NODEJS" = "true" ]; then \
    mkdir -p /usr/local/lib/node_modules; \
    cp -a /mnt/node/usr/local/bin/node /usr/local/bin/node; \
    cp -a /mnt/node/usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm; \
    cp -a /mnt/node/usr/local/bin/npm /mnt/node/usr/local/bin/npx /usr/local/bin/; \
    node --version; npm --version; \
    ver=$(apt-cache show libgbm1 | awk '/^Version:/ { print $2; exit }'); \
    mkdir -p /tmp/stub/DEBIAN; \
    printf 'Package: mesa-libgallium\nVersion: %s\nArchitecture: all\nMaintainer: Maho <https://mahocommerce.com>\nDescription: empty stand-in for mesa-libgallium\n Installed by the mahocommerce/maho Dockerfile so that libgbm1, which headless\n Chromium links, does not pull in the Mesa software renderer and LLVM, about\n 180 MB that a headless browser never loads. Remove this package before\n installing anything that renders with Mesa.\n' "$ver" > /tmp/stub/DEBIAN/control; \
    dpkg-deb -b /tmp/stub /tmp/mesa-libgallium-stub.deb; \
    apt install -y --no-install-recommends /tmp/mesa-libgallium-stub.deb $CHROMIUM_PKGS; \
  fi \
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
