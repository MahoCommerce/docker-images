#!/usr/bin/env bash
# Tests a built Maho image: installs Maho through the web wizard in a real
# browser, then checks the storefront, the file rules and the /api/* routing.
# See "Image Test" in AGENTS.md.
#
# Usage: tests/image.sh <image-ref>
#   MAHO_VERSION        expected version, dev-main to skip the check
#   MYSQL PGSQL SQLITE  the database claims of the row, as in versions.json
#   PORT                host port (default 8080)
#   ARTIFACTS           where failure screenshots go (default test-artifacts)
#
# Needs docker, curl, jq, node and npm.

set -euo pipefail

IMAGE="${1:?usage: tests/image.sh <image-ref>}"
PORT="${PORT:-8080}"
BASE="http://localhost:${PORT}"
CONTAINER="maho-test-$$"
MAHO_VERSION="${MAHO_VERSION:-}"
ARTIFACTS="${ARTIFACTS:-test-artifacts}"
MYSQL="${MYSQL:-false}"
PGSQL="${PGSQL:-false}"
SQLITE="${SQLITE:-true}"
PLAYWRIGHT_VERSION="1.62.1"   # pinned: this test gates every alias

failures=0

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()  { printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; failures=$((failures + 1)); }

cleanup() {
    if [ "$failures" -ne 0 ]; then
        log "container logs"
        docker logs "$CONTAINER" 2>&1 | tail -100 || true
    fi
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

in_container() { docker exec "$CONTAINER" "$@"; }

expect_status() {   # <method> <path> <code>
    local got
    got=$(curl -s -o /dev/null -w '%{http_code}' -X "$1" "${BASE}$2")
    [ "$got" = "$3" ] && ok "$1 $2 -> $got" || bad "$1 $2 -> $got, expected $3"
}

expect_body() {     # <path> <regex> <description>
    curl -sS "${BASE}$1" | grep -qEi -- "$2" \
        && ok "GET $1 contains $3" || bad "GET $1 does not contain $3"
}

expect_redirect() { # <path> <expected substring>
    local got
    got=$(curl -s -o /dev/null -w '%{redirect_url}' "${BASE}$1")
    [[ "$got" == *"$2"* ]] && ok "GET $1 redirects to $got" \
        || bad "GET $1 redirects to '$got', expected $2"
}

# The entry point that answered shows in the content type. That is how the
# /api/* rules are told apart.
expect_content_type() { # <path> <expected substring> <description>
    local got
    got=$(curl -s -o /dev/null -w '%{content_type}' "${BASE}$1")
    [[ "$got" == *"$2"* ]] && ok "GET $1 is served by $3 ($got)" \
        || bad "GET $1 has content type '$got', expected $2 from $3"
}

# A new container is always an uninstalled store, which the retry below needs.
start_container() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    # SERVER_NAME=:80 serves plain HTTP. A hostname makes FrankenPHP get a
    # TLS certificate instead.
    docker run -d --name "$CONTAINER" -e SERVER_NAME=":80" -p "${PORT}:80" "$IMAGE" >/dev/null
    for _ in $(seq 60); do
        curl -sf -o /dev/null "${BASE}/" && return 0
        sleep 1
    done
    return 1
}

if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    log "using the local image $IMAGE"
else
    log "pulling $IMAGE"
    docker pull -q "$IMAGE"
fi

log "starting container"
start_container && ok "container answers on ${BASE}/" \
    || { bad "container did not answer within 60s"; exit 1; }

log "image contents"

# Read the module list once. `php -m | grep -q` fails at random under pipefail:
# grep exits at the first match and docker exec dies of SIGPIPE, giving 141.
modules=$(in_container php -m)
has_module() { printf '%s\n' "$modules" | grep -qix -- "$1"; }

# Only the database extensions. The rest is proved by a successful install.
db_exts=""
[ "$MYSQL" = "true" ]  && db_exts="$db_exts pdo_mysql"
[ "$PGSQL" = "true" ]  && db_exts="$db_exts pdo_pgsql pgsql"
[ "$SQLITE" = "true" ] && db_exts="$db_exts pdo_sqlite"

for ext in $db_exts; do
    has_module "$ext" && ok "php extension $ext" || bad "php extension $ext is missing"
done

if [ -n "$MAHO_VERSION" ] && [ "$MAHO_VERSION" != "dev-main" ]; then
    got=$(in_container composer show --format=json mahocommerce/maho | jq -r '.versions[0]' | sed 's/^v//')
    [ "$got" = "$MAHO_VERSION" ] && ok "mahocommerce/maho is $got" \
        || bad "mahocommerce/maho is $got, expected $MAHO_VERSION"
fi

# Match a directive, not a comment: a comment gets reworded and the check then
# fails on a correct image.
in_container grep -q 'rewrite @api_other /rest.php' /etc/frankenphp/Caddyfile \
    && ok "/etc/frankenphp/Caddyfile is the Maho site block" \
    || bad "/etc/frankenphp/Caddyfile is not the Maho site block"

# Two links proves the `ln -f` worked. One means the container still serves the
# base image config and the copy was a silent no-op.
links=$(in_container stat -c '%h' /etc/caddy/Caddyfile)
[ "$links" = "2" ] && ok "/etc/caddy/Caddyfile is still hard linked" \
    || bad "/etc/caddy/Caddyfile has $links links, expected 2"

log "before installation"

expect_status GET '/' 302
expect_redirect '/' '/install'
# public/.htaccess is the one shipped file the @hidden rule denies.
expect_status GET '/.htaccess' 404
expect_status GET '/media/.htaccess' 404
expect_status TRACE '/' 405

log "installing Maho through the web wizard"

has_module pdo_sqlite || { bad "pdo_sqlite is missing, cannot install"; exit 1; }

installed=$(node -p "require('./node_modules/playwright/package.json').version" 2>/dev/null || echo none)
if [ "$installed" != "$PLAYWRIGHT_VERSION" ]; then
    log "installing Playwright $PLAYWRIGHT_VERSION (found: $installed)"
    npm install --no-save --no-fund --no-audit "playwright@${PLAYWRIGHT_VERSION}" >/dev/null
    # --with-deps needs apt and sudo, so it is for CI only.
    if [ -n "${CI:-}" ]; then
        npx playwright install --with-deps chromium >/dev/null
    else
        npx playwright install chromium >/dev/null
    fi
fi

# One retry. A half finished wizard leaves app/etc/local.xml behind and blocks a
# second attempt, so the retry needs a new container.
wizard() { node "$(dirname "$0")/web-install.js" "$BASE" "$ARTIFACTS"; }
if wizard; then
    ok "web installation"
else
    log "restarting the container for one more attempt"
    start_container || { bad "the container did not restart"; exit 1; }
    wizard && ok "web installation (second attempt)" \
        || { bad "the web installation failed twice"; exit 1; }
fi

log "after installation"

expect_status GET '/' 200
expect_body '/' 'maho' 'the storefront'
expect_status GET '/admin' 200

# @private denies whole file extensions, so each name Maho generates needs an
# exemption. Caddy denies with no content type; PHP 404s carry one.
expect_status GET '/robots.txt' 200
expect_status GET '/llms.txt' 200
expect_status GET '/llms-full.txt' 200

log "api routing"

# Every API protocol is off on a fresh store and a disabled one answers 404, so
# turn on the two under test. Otherwise a routing bug looks like a disabled
# protocol.
in_container ./maho config:set apiplatform/protocols/rest_v2 1 --scope default --scope-id 0 >/dev/null
in_container ./maho config:set apiplatform/protocols/soap 1 --scope default --scope-id 0 >/dev/null
in_container ./maho cache:flush >/dev/null

# Proves the @private exemption and the @api_other rewrite to rest.php.
expect_status GET '/api/docs.json' 200
expect_body '/api/docs.json' '"openapi"' 'an OpenAPI document'

# @api_v2 must match before @api_legacy_rest, or this lands on api.php.
expect_status GET '/api/rest/v2/products' 200
expect_content_type '/api/rest/v2/products' 'application/ld+json' 'the API Platform'

# Legacy SOAP must reach index.php, so it must not be rewritten to rest.php.
expect_status GET '/api/soap/?wsdl' 200
expect_content_type '/api/soap/?wsdl' 'text/xml' 'the legacy SOAP controller'

log "result"
if [ "$failures" -eq 0 ]; then
    printf '\033[32mall checks passed\033[0m\n'
else
    printf '\033[31m%d check(s) failed\033[0m\n' "$failures"
fi
exit "$failures"
