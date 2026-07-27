# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository builds Docker images for MahoCommerce using FrankenPHP. All image variants are defined in `versions.json` on the `main` branch and built from a single parameterized `Dockerfile`.

## Common Development Commands

### Local Docker Build
```bash
# Build with default args (latest nightly config)
docker build -t maho-local .

# Build a specific variant
docker build --build-arg PHP_VERSION=8.4 --build-arg DEBIAN_VARIANT=bookworm --build-arg PGSQL=false --build-arg SQLITE=false -t maho-local .

# Build with specific platform
docker buildx build --platform linux/amd64 -t maho-local .

# Run the built image
docker run -p 80:80 maho-local
```

### Adding a New MahoCommerce Version
1. Add entries to `versions.json` (one per PHP version), including an `eol` date for each (see **Support Lifecycle** below)
2. If the new version needs a different `composer.json` structure, add a template in `composer_json/`
3. Commit and push to `main`
4. Trigger the build workflow manually or wait for the schedule

### Testing Changes
```bash
# Build and run locally before pushing
docker build -t maho-test . && docker run --rm -it maho-test bash

# Inside container, verify PHP extensions
php -m

# Check composer dependencies
composer show
```

## Architecture & Key Components

### Docker Setup
- **Base Image**: `dunglas/frankenphp:php{version}-{debian}` — parameterized via build args
- **Build Args**: `PHP_VERSION`, `DEBIAN_VARIANT`, `MYSQL`, `PGSQL`, `SQLITE`
- **User**: `maho` (UID/GID 1000) — non-root user for security
- **PHP Extensions**: Base set always installed, database extensions conditionally added
- **Composer**: Installed at build time, `composer.json` selected from `composer_json/` templates

### Build Matrix (`versions.json`)
Each entry defines a Docker image variant with:
- `tag`: Docker Hub tag (e.g., `26.3.0-php8.4`)
- `php`: PHP version
- `debian`: Debian variant (`bookworm` or `trixie`)
- `maho`: MahoCommerce version or `dev-main`
- `composer_json`: which template from `composer_json/` to use
- `mysql`, `pgsql`, `sqlite`: database support booleans
- `eol`: last day (`YYYY-MM-DD`) this tag is rebuilt (see **Support Lifecycle** below). Omitted only by `nightly`, which never expires
- `aliases` (optional): list of tag names to retag onto this image after a successful build (e.g. `["latest", "latest-php8.5"]`). Retag uses `docker buildx imagetools create` — a registry-side manifest copy, no rebuild. An alias can also be passed to the `workflow_dispatch` `tag` input to retag without rebuilding the source.

### Support Lifecycle (`eol`)
A tag stops being rebuilt when its **runtime** goes EOL: its PHP version or its Debian variant. The Maho version is *not* a criterion: every historical Maho tag keeps getting rebuilt as long as the PHP and Debian underneath it are still supported.

Set `eol` when you add the row. Both upstreams publish their dates years ahead, so it is always knowable up front:

```
eol = min(PHP security-support end, Debian LTS end)
```

| PHP | security ends |     | Debian   | LTS ends   |
|-----|---------------|-----|----------|------------|
| 8.2 | 2026-12-31    |     | bookworm | 2028-06-30 |
| 8.3 | 2027-12-31    |     | trixie   | 2030-06-30 |
| 8.4 | 2028-12-31    |     |          |            |
| 8.5 | 2029-12-31    |     |          |            |

Behaviour:
- **`nightly` has no `eol` and never expires.** It tracks `dev-main` on the current PHP and Debian, so it is bumped in place rather than retired. Give it an `eol` and the daily build eventually stops silently.
- **Scheduled runs and "build all"** skip any tag past its `eol`. Skipped tags are reported as a run annotation and in the job summary.
- **Tags within 90 days of `eol`** raise a warning annotation, so a tag never drops out of rotation unannounced.
- **An explicit `workflow_dispatch` tag bypasses the filter**, so an EOL image can still be rebuilt on demand for a critical fix.
- **EOL tags are never deleted.** They stay pullable on Docker Hub forever; they just stop being refreshed.

Retiring a tag needs no code change; it ages out on its own. Verify these dates against upstream if a distro extends support; Debian LTS windows have shifted before.

Note: there is no `composer.lock` in this repo, so every rebuild re-resolves the whole dependency tree rather than reproducing the previous image. Rebuilding an old tag refreshes its transitive dependencies. That is deliberate, but it means old tags are not byte-reproducible. It also only holds because the workflow builds without a layer cache; see **Build Cache** below.

### Composer Templates (`composer_json/`)
Different MahoCommerce versions need different `composer.json` structures:
- `25.5.json`: Legacy with tinymce deps, composer-patches, CVE audit ignore
- `25.7.json`: With composer-patches and enable-patching (used by 25.7, 25.9)
- `25.11.json`: Clean, minimal (used by 25.11+, 26.x, latest, nightly)

The workflow copies the template and uses `jq` to set the correct Maho version.

### CI/CD Pipeline (`build.yml`)
- **Schedule**: Runs at 03:30 UTC daily. Builds only `nightly` on most days, all tags on alternating (even-week) Sundays
- **Manual with tag**: Builds a single specified tag (the only path that bypasses the `eol` filter)
- **Manual without tag**: Builds all tags
- **EOL filter**: Scheduled and build-all runs skip tags past their `eol` date, and warn about tags within 90 days of it
- **Platform Support**: Multi-arch. Each tag builds once per platform on a native runner (`ubuntu-latest` / `ubuntu-24.04-arm`), then the per-platform digests are merged into one manifest list
- **Registry**: Images pushed to Docker Hub as `mahocommerce/maho:{tag}`
- **Push order**: Docker Hub lists tags by last-pushed, so the workflow pushes oldest-first to keep the newest tags at the top of the repository page (see below)
- **Build cache**: none, deliberately (see below)

### Build Cache
The `build` job passes `no-cache: true` and exports no cache. Every build runs `install-php-extensions`, `apt-get upgrade` and `composer install` from scratch.

This is not an oversight to be optimised away. A rebuild exists to refresh what is *outside* the repo, namely Debian security updates and the re-resolved Composer tree, and a layer cache freezes exactly those. With `type=gha` caching the daily `nightly` build was a complete cache hit whenever the `dunglas/frankenphp` base digest was unchanged: `apt-get upgrade` never ran, `composer install` never ran (the `dev-main` constraint is a literal string, so its layer key never changes), and the run re-pushed a byte-identical image while appearing to succeed.

Because the extension/apt step sits near the top of the layer chain, busting it invalidates everything below it. There is no useful middle ground: cache that step and the rebuild is a lie, skip it and nothing else is cacheable either.

The cost is about 70s per build job, roughly 90s cold versus 20s warm. The repo is public, so Actions minutes are free; the only real cost is ~6 minutes of extra wall-clock on the biweekly full matrix. In exchange the GitHub Actions cache quota, which the old scopes had driven to 6.3 GB of 10 GB across 589 entries, stays empty.

If you reintroduce caching for local iteration, keep it out of the workflow.

### Tag Push Order
Docker Hub's tag list is sorted by last-pushed and cannot be reordered from the repo settings, so the only lever is the order in which the workflow pushes.

The matrix is sorted in `load-matrix` by Maho version, then PHP version, both compared **numerically** per component, so `25.11.0` sorts after `25.9.0` where a plain string sort gets it wrong. `dev-main` (nightly) sorts after every release. The `merge` and `retag` jobs then run with `max-parallel: 1`, so tags are created in that order rather than racing; without it the parallel matrix would push in arbitrary order and the page would shuffle on every full rebuild.

Aliases are retagged after all real tags, and each row's aliases are reverse-sorted so the barest name is pushed last, putting `latest` above `latest-php8.5` at the very top of the page.

The ordering in `versions.json` itself is therefore cosmetic; the workflow sorts regardless. Keeping the file in ascending order is still nice for reading diffs.

Note the cost: serialising the merge job means ~25 sequential runners on a full rebuild instead of a parallel fan-out. Each is cheap (download digests, `imagetools create`, inspect, no build) and it only affects the biweekly full run, but it does add roughly 20 minutes of wall-clock to the tail of that run. The per-platform `build` jobs stay fully parallel; they push by digest, untagged, so their order does not matter.

### Key Files
- `versions.json`: Build matrix defining all image variants
- `Dockerfile`: Parameterized image build instructions
- `composer_json/`: Version-specific composer.json templates
- `php.ini`: Production-optimized PHP settings
- `.github/workflows/build.yml`: Single build workflow
- `.github/workflows/dockerhub-readme.yml`: Mirrors `README.md` to the Docker Hub repository description on every push to `main` that touches it

## Important Notes

- Never commit secrets or credentials
- The `.idea/` directory is untracked (IDE settings)
- `.dockerignore` excludes build-only files (`versions.json`, `composer_json/`, etc.) from the Docker context
- All development happens on the `main` branch — no per-version branches needed
