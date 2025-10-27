# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository provides a Docker container image for running ARK: Survival Ascended dedicated servers on Linux. The container uses Ubuntu 24.04 as the base OS and runs Windows game binaries through Proton (GE-Proton10-17). The image is published to GitHub Container Registry at `ghcr.io/jdogwilly/asa-linux-server` and includes a Python-based control tool (`asa-ctrl`) for server management.

## Important Documentation

- **[CONTRIBUTING.md](CONTRIBUTING.md)**: Guidelines for external contributors, versioning strategy, commit conventions, and testing procedures
- **[TO-DO.md](TO-DO.md)**: Project roadmap with planned improvements organized by phase and priority
- **[CHANGELOG.md](CHANGELOG.md)**: Version history following [Keep a Changelog](https://keepachangelog.com/) format
- **[README.md](README.md)**: User-facing documentation with installation guide and server administration

## Building the Container Image

The container image is built using a standard Dockerfile:

```bash
# Using Taskfile (recommended)
task build         # Build the image
task dev          # Build and run test server
task push         # Push to ghcr.io
task --list       # Show all tasks

# Using Docker directly
docker build -t ghcr.io/jdogwilly/asa-linux-server:latest .
```

**Important Dockerfile details**:
- Base OS: Ubuntu 24.04 (Noble Numbat)
- System packages: 32-bit libs, Python3 (no build tools needed)
- User `gameserver` (UID/GID: 25000)
- Python package `asa-ctrl` installed via `uv` (ultra-fast Python package installer)
- Entry point: `/usr/bin/start_server`

## Development Workflow

### Testing Changes Locally

Build and test using Taskfile:

```bash
# Build and run a test container
task dev

# View logs
task logs

# Stop test container
task stop
```

For Python development and testing:
```bash
# Navigate to the Python package
cd root/usr/share/asa-ctrl

# Run tests with uv
uv run pytest

# Run tests with coverage
uv run pytest --cov=asa_ctrl

# Install in development mode locally
uv pip install -e .
```

### Container Entry Points

- Main entry point: `/usr/bin/start_server` (Bash script)
- Server control CLI: `/usr/local/bin/asa-ctrl` (Python package entry point)
- Mod management helper: `/usr/local/bin/cli-asa-mods` (Python package entry point)
- Health check scripts:
  - `/usr/bin/healthcheck-liveness` - Process-based liveness check (used by Docker HEALTHCHECK)
  - `/usr/bin/healthcheck-readiness` - RCON-based readiness check (for Kubernetes)

### Health Checks

The container includes two health check scripts for monitoring server status:

**Liveness Check** (`/usr/bin/healthcheck-liveness`):
- Checks if ARK server process (`ArkAscendedServer.exe` or `AsaApiLoader.exe`) is running
- Uses `pgrep` to verify process existence
- Exit 0 = healthy, Exit 1 = unhealthy
- Automatically used by Docker's HEALTHCHECK directive
- Recommended for Kubernetes liveness probes

**Readiness Check** (`/usr/bin/healthcheck-readiness`):
- Validates server is accepting RCON connections
- Executes lightweight RCON command via `asa-ctrl rcon --exec "help"`
- Requires RCON to be enabled and configured
- Exit 0 = ready, Exit 1 = not ready
- Recommended for Kubernetes readiness probes

**Docker HEALTHCHECK Configuration**:
- Interval: 30s (checks every 30 seconds)
- Timeout: 10s (each check gets 10 seconds)
- Start period: 10m (allows time for SteamCMD, server files, and Proton downloads)
- Retries: 3 (requires 3 consecutive failures before marking unhealthy)

### Important Paths in Container

- Server files: `/home/gameserver/server-files/`
- Server configs: `/home/gameserver/server-files/ShooterGame/Saved/Config/WindowsServer/`
- Config import source: `/config` (optional user mount)
- Steam: `/home/gameserver/Steam/`
- SteamCMD: `/home/gameserver/steamcmd/`
- Cluster data: `/home/gameserver/cluster-shared/`
- Proton: `/home/gameserver/Steam/compatibilitytools.d/GE-Proton10-17/`
- Game binary: `/home/gameserver/server-files/ShooterGame/Binaries/Win64/ArkAscendedServer.exe`

## Architecture

### Server Startup Flow

1. `start_server` script checks for debug mode (`ENABLE_DEBUG=1`)
2. Downloads/validates SteamCMD if not present
3. Installs/updates ASA server files via SteamCMD (AppID: 2430930)
4. **STAGE 4.5**: Imports user-provided config files from `/config` (if mounted)
5. Downloads/validates Proton if not present (with SHA512 checksum)
6. Initializes Proton compatibility layer (Wine prefix)
7. Checks for mod configuration via `cli-asa-mods`
8. Optionally installs ASA Server API plugin loader (if `AsaApi_*.zip` exists)
9. Launches server through Proton (or AsaApiLoader if plugin loader is present)

### `asa-ctrl` CLI Tool

Python-based tool for server administration (stdlib only, zero dependencies). Architecture:
- **Package Location**: `/usr/share/asa-ctrl/asa_ctrl/`
- **Core Modules**:
  - `__main__.py`: CLI entry point using `argparse`
  - `rcon.py`: Valve RCON protocol implementation using `socket` and `struct`
  - `config.py`: INI and start parameter parsing using `configparser`
  - `mods.py`: JSON-based mod database management
  - `cli_mods.py`: Standalone mod parameter generator
  - `errors.py`: Custom exception classes
  - `exit_codes.py`: Exit code constants
- **Testing**: Unit tests in `/usr/share/asa-ctrl/tests/` (run with `uv run pytest`)
- **Package Management**: Installed via `uv` with entry points defined in `pyproject.toml`

### Mod Management

- Mods stored in `/home/gameserver/server-files/mods.json`
- Format: Array of `{mod_id: int, name: string, enabled: bool, scanned: bool}`
- `cli-asa-mods` reads database and outputs `-mods=` parameter for enabled mods
- Start parameter format: `-mods=12345,67891`

### Configuration File Management

The container supports automatic importing of configuration files from a mounted `/config` directory. This feature is implemented in STAGE 4.5 of the startup sequence.

**Implementation Details:**

- **Location**: `/usr/bin/start_server:37-111` (functions: `validate_ini_file()`, `copy_config_files()`)
- **Execution**: STAGE 4.5, runs after SteamCMD download completes (line 354-356)
- **Source**: `/config` (user-mounted directory)
- **Destination**: `/home/gameserver/server-files/ShooterGame/Saved/Config/WindowsServer/`

**Workflow:**
1. Check if `/config` directory exists (non-fatal if missing)
2. Recursively find all `.ini` files in `/config`
3. Validate each file using Python's `configparser` (strict=False)
4. Copy valid files to destination (always overwrites existing configs)
5. Log each operation (copied/skipped) with reason
6. Continue startup even if validation fails (non-blocking)

**Functions:**
- `validate_ini_file(ini_file)`: Uses Python configparser to validate INI syntax, returns exit code
- `copy_config_files()`: Orchestrates discovery, validation, and copying of config files

**Mount Options:**
```yaml
# Bind mount (recommended for version control)
- ./config:/config:ro

# Named volume (for persistent storage)
- asa-config:/config:ro
```

**Supported Files:**
- `GameUserSettings.ini` - Server settings, player limits, RCON config
- `Game.ini` - Game rules, XP multipliers, taming speeds
- Any other `.ini` files (custom mod configs, etc.)

**Validation:**
- Uses Python's `configparser.ConfigParser(strict=False)`
- Non-strict mode allows duplicate keys (common in ARK configs)
- Invalid files are logged as warnings and skipped
- Server startup continues regardless of validation failures

**Logging:**
```bash
# View import logs
docker logs asa-server | grep -A 20 "STAGE 4.5"

# Example output:
# [INFO] Processing: GameUserSettings.ini
# [SUCCESS] Copied: GameUserSettings.ini -> /home/gameserver/server-files/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini
# [WARNING] Skipped (invalid INI syntax): broken-config.ini
# [SUCCESS] Config import complete: 2 copied, 1 skipped
```

### RCON Implementation

The `asa-ctrl` tool includes a custom implementation of the Valve RCON protocol over TCP (stdlib only, zero dependencies).

**Configuration Discovery (Priority Order):**

The tool supports multiple configuration methods, checked in this order:

1. **Environment Variables** (Recommended for Kubernetes/Production):
   - `ADMIN_PASSWORD` - RCON admin password
   - `RCON_PORT` - RCON port (defaults to 27020 if not specified)
   - `RCON_ENABLED` - Enable/disable RCON (accepts: true/false/1/0, defaults to true)

2. **ASA_START_PARAMS** (Legacy/Docker Compose):
   - `?ServerAdminPassword=yourpassword` - RCON password parameter
   - `?RCONPort=27020` - RCON port parameter
   - `?RCONEnabled=True` - RCON enabled flag

3. **GameUserSettings.ini** (Fallback):
   - `[ServerSettings]` section
   - `ServerAdminPassword=yourpassword`
   - `RCONPort=27020`
   - `RCONEnabled=True`

**Usage Examples:**

```bash
# Using environment variables (Kubernetes recommended)
docker exec asa-server-1 asa-ctrl rcon --exec 'saveworld'

# The tool auto-discovers configuration from ADMIN_PASSWORD and RCON_PORT env vars
```

**Configuration Methods:**

```yaml
# Kubernetes ConfigMap/Secret approach
environment:
  - ADMIN_PASSWORD: "your-secure-password"  # From secret
  - RCON_PORT: "27020"
  - RCON_ENABLED: "true"
```

```yaml
# Docker Compose ASA_START_PARAMS approach (legacy)
environment:
  - ASA_START_PARAMS: "?ServerAdminPassword=yourpass?RCONPort=27020?RCONEnabled=True"
```

## CI/CD

### GitHub Actions

The repository uses GitHub Actions for automated builds and publishing:
- **Workflow**: `.github/workflows/docker-publish.yml`
- **Triggers**: Push to main, version tags (`v*`), pull requests
- **Output**: Images tagged as `latest` and semantic versions
- **Registry**: GitHub Container Registry (ghcr.io)
- **Authentication**: Automatic via `GITHUB_TOKEN`

### Versioning

Version tags should follow semantic versioning (e.g., `v1.5.0`). GitHub Actions will automatically create corresponding image tags.

## Configuration Files

### `Dockerfile`

- Standard Dockerfile for building the container
- Multi-layer build: base packages → user setup → application files → Python package
- Version managed via git tags (not in Dockerfile)
- All dependencies explicitly declared

### `docker-compose.yml`

- Example compose file for testing and development
- Defines volumes: `server-files`, `steam`, `steamcmd`, `cluster-shared`
- Single server configuration (easily duplicated for clusters)
- Custom network: `asa-network` (bridge driver, named `asanet`)
- Includes permission-fixing init container using Ubuntu 24.04

### `Taskfile.yml`

- Local development and build tasks
- Tasks: build, run, stop, logs, push, clean, dev
- Uses git tags for version detection
- Simplifies common Docker operations

## Common Development Tasks

### Building and Testing

```bash
# Build locally
task build

# Build and run test server
task dev

# View container logs
task logs

# Push to registry (requires authentication)
task push
```

### Modifying Start Parameters

Edit `ASA_START_PARAMS` in `docker-compose.yml`:
- Map name goes before `?listen`
- Port parameters: `?Port=7777?RCONPort=27020?RCONEnabled=True`
- Player limit: `-WinLiveMaxPlayers=50`
- Cluster: `-clusterid=default -ClusterDirOverride="/home/gameserver/cluster-shared"`
- Mods added automatically by `cli-asa-mods`

### Updating Proton Version

1. Update `PROTON_VERSION` in `root/usr/bin/start_server` (e.g., `10-17` → `10-18`)
2. Add new SHA512 checksum file to `root/usr/share/proton/`
3. Rebuild the Docker image
4. Old Proton installations remain in volumes until deleted

### Debugging Container Issues

Enable debug mode in `docker-compose.yml`:
```yml
environment:
  - ENABLE_DEBUG=1
```

Container will sleep instead of starting server. Access with:
```bash
docker exec -ti asa-server bash          # as gameserver
docker exec -ti -u root asa-server bash  # as root
```

### Updating Dependencies

**System packages**: Edit `Dockerfile` and rebuild
**Python packages**: The `asa-ctrl` package has zero runtime dependencies (stdlib only)
- Development dependencies defined in `pyproject.toml` under `[project.optional-dependencies]`
- Update with: `cd root/usr/share/asa-ctrl && uv sync --extra dev`

### Testing RCON Locally

RCON requires:
- `RCONEnabled=True` in start parameters or `GameUserSettings.ini`
- `ServerAdminPassword` set in `GameUserSettings.ini` (not as start parameter)
- `RCONPort` defined

## Map Names Reference

Official map IDs for start parameters:
- TheIsland_WP
- ScorchedEarth_WP
- TheCenter_WP
- Aberration_WP
- Extinction_WP
- Ragnarok_WP
- Valguero_WP

Mod maps use custom IDs from CurseForge.

## Image Publishing

### Manual Push

```bash
# Login to GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u jdogwilly --password-stdin

# Push using Taskfile
task push

# Or push directly
docker push ghcr.io/jdogwilly/asa-linux-server:latest
```

### Automated Publishing

Push to `main` branch or create a version tag:
```bash
git tag v1.5.1
git push origin v1.5.1
```

GitHub Actions will automatically build and push to ghcr.io.

## File Size Requirements

When updating the Dockerfile or build configuration, be aware:
- Base image (Ubuntu 24.04): ~77 MB
- Server files (downloaded at runtime): ~13 GB
- Each server instance RAM usage: ~13 GB
- Proton download (at runtime): ~400-500 MB

## Security Notes

- Server runs as non-root user `gameserver` (UID 25000)
- Permission fixes via separate `set-permissions` init container
- RCON password must be set in `GameUserSettings.ini` under `[ServerSettings]`
- Cluster ID should be changed from `default` to prevent cross-server contamination
- Container images are scanned by GitHub Actions (Dependabot, security advisories)
