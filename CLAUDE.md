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
1. Add entries to `versions.json` (one per PHP version)
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

### Composer Templates (`composer_json/`)
Different MahoCommerce versions need different `composer.json` structures:
- `25.5.json`: Legacy with tinymce deps, composer-patches, CVE audit ignore
- `25.7.json`: With composer-patches and enable-patching (used by 25.7, 25.9)
- `25.11.json`: Clean, minimal (used by 25.11+, 26.x, latest, nightly)

The workflow copies the template and uses `jq` to set the correct Maho version.

### CI/CD Pipeline (`build.yml`)
- **Schedule**: Runs at 03:30 UTC daily — builds only `nightly` on weekdays, all tags on Sundays
- **Manual with tag**: Builds a single specified tag
- **Manual without tag**: Builds all tags
- **Platform Support**: Multi-arch builds (linux/amd64, linux/arm64)
- **Registry**: Images pushed to Docker Hub as `mahocommerce/maho:{tag}`
- **Builder**: Uses Docker BuildKit cloud builder (`mahocommerce/maho` endpoint)

### Key Files
- `versions.json`: Build matrix defining all image variants
- `Dockerfile`: Parameterized image build instructions
- `composer_json/`: Version-specific composer.json templates
- `php.ini`: Production-optimized PHP settings
- `.github/workflows/build.yml`: Single build workflow

## Important Notes

- Never commit secrets or credentials
- The `.idea/` directory is untracked (IDE settings)
- `.dockerignore` excludes build-only files (`versions.json`, `composer_json/`, etc.) from the Docker context
- All development happens on the `main` branch — no per-version branches needed
