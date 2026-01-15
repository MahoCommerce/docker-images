# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository builds Docker images for MahoCommerce using FrankenPHP. Each Git branch produces a corresponding Docker image tag (e.g., branch `nightly` → `mahocommerce/maho:nightly`).

## Common Development Commands

### Local Docker Build
```bash
# Build the Docker image locally
docker build -t maho-local .

# Build with specific platform
docker buildx build --platform linux/amd64 -t maho-local .

# Run the built image
docker run -p 80:80 maho-local
```

### Working with Branches
```bash
# Create a new branch for a new MahoCommerce version
git checkout -b new-version

# Push branch to trigger automated Docker build
git push -u origin new-version
```

### Modifying PHP Configuration
The `php.ini` file is copied into the Docker image. To enable additional features:
- Uncomment lines 9-10 in Dockerfile to enable libvips image processing
- Modify `php.ini` for PHP settings (memory limits, opcache, etc.)

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
- **Base Image**: `dunglas/frankenphp:php8.x-bookworm` - Modern PHP application server (PHP version varies by branch, e.g., php8.5 on nightly)
- **User**: `maho` (UID/GID 1000) - Non-root user for security
- **PHP Extensions**: All e-commerce essentials pre-installed (MySQL, GD, intl, etc.)
- **Composer**: Installed and dependencies auto-loaded during build

### CI/CD Pipeline
- **build.yml**: Builds individual branches on-demand
- **build-all.yml**: Runs at 03:30 UTC daily - builds only `nightly` on weekdays, ALL branches on Sundays
- **Platform Support**: Multi-arch builds (linux/amd64, linux/arm64)
- **Registry**: Images pushed to Docker Hub as `mahocommerce/maho:{branch-name}`
- **Branch Naming**: Version branches follow `{maho-version}-php{php-version}` pattern (e.g., `25.11.0-php8.4`)

### Key Files
- `composer.json`: Defines MahoCommerce dependency (dev-main)
- `php.ini`: Production-optimized PHP settings
- `Dockerfile`: Image build instructions
- `.github/workflows/`: Automated build workflows

## Important Notes

- Never commit secrets or credentials
- The `.idea/` directory is untracked (IDE settings)
- Docker builds use BuildKit cloud builder for multi-platform support
- Each branch represents a different MahoCommerce version/configuration