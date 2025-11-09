# Quick Fix Guide - ARK Survival Ascended Container

**TL;DR**: Pelican Panel's ARK server works because it installs Steam client libraries. We don't. Here's the fix.

---

## The Problem

Your ARK server crashes silently because it can't find Steam client libraries (`steamclient.so`) when initializing the Steam API.

## The Solution (90% confidence this will work)

Add this to `/home/jacob/Repos/ark-survival-ascended-linux-container-image-troubleshoot-against-pelican/root/usr/bin/start_server` after line 348 (after STAGE 4 completes):

```bash
# ============================================================================
# STAGE 4.1: Steam Client Libraries Installation
# ============================================================================

log_stage "4.1" "Steam Client Libraries Installation"
log_info "Installing Steam Linux Runtime (App 1007) for Steam API support..."

cd /home/gameserver/steamcmd
./steamcmd.sh +force_install_dir /home/gameserver/server-files +login anonymous +app_update 1007 +quit

if [ $? -ne 0 ]; then
  log_error "Failed to install Steam client libraries"
  exit 204
fi

# Copy steamclient.so to expected locations
log_info "Copying Steam client libraries to .steam/sdk directories..."
mkdir -p /home/gameserver/server-files/.steam/sdk32
mkdir -p /home/gameserver/server-files/.steam/sdk64

cp -v /home/gameserver/steamcmd/linux32/steamclient.so /home/gameserver/server-files/.steam/sdk32/steamclient.so
cp -v /home/gameserver/steamcmd/linux64/steamclient.so /home/gameserver/server-files/.steam/sdk64/steamclient.so

log_success "Steam client libraries installed and configured"
```

## Why This Works

Pelican Panel's configuration does this:
1. Downloads Steam Linux Runtime (App ID 1007)
2. Copies `steamclient.so` to `.steam/sdk32/` and `.steam/sdk64/`
3. ARK finds the Steam client libraries
4. Server starts successfully

We were missing steps 1 and 2.

## Additional Recommended Changes

### 1. Add SRCDS_APPID Environment Variable

In `docker-compose.yml`, add:

```yaml
environment:
  - SRCDS_APPID=2430930
```

### 2. Update Proton to Latest Version

Change in `start_server` line 364:

```bash
# From:
PROTON_VERSION="10-17"

# To (auto-detect latest):
PROTON_VERSION=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep tag_name | cut -d'"' -f4 | sed 's/GE-Proton//' || echo "10-25")
```

Or just update to latest stable:
```bash
PROTON_VERSION="10-25"
```

## Testing

After making changes:

```bash
# Rebuild
task build

# Test
task dev

# Watch for:
# 1. "STAGE 4.1: Steam Client Libraries Installation" in logs
# 2. Server process staying alive (not exiting after 1-2 seconds)
# 3. RCON becoming available
# 4. Server log file being created and updated
```

## Expected Results

**Before Fix**:
```
[INFO] Starting ARK server in background...
[SUCCESS] ARK server launched with PID: 12345
[ERROR] ARK server process died while waiting for RCON
```

**After Fix**:
```
[INFO] Starting ARK server in background...
[SUCCESS] ARK server launched with PID: 12345
[INFO] Waiting for RCON to become available...
[SUCCESS] RCON is ready after 120 seconds
[INFO] Server is accepting RCON connections on port 27020
```

## If This Doesn't Work

See `PELICAN_COMPARISON_REPORT.md` for additional changes to try:
- Steam Compat Path restructuring (Test 2)
- Different Proton version (Test 3)
- Combined approach (Test 4)

## Confidence Level

**HIGH (90%)** - This is the most critical difference between Pelican's working setup and ours.

Pelican explicitly installs App 1007 and copies steamclient.so. Every other aspect of our setup (Wine prefix, environment variables, startup parameters) matches Pelican's approach.

## References

- Full analysis: `PELICAN_COMPARISON_REPORT.md`
- Pelican's Dockerfile: `ghcr.io/parkervcp/steamcmd:proton`
- Pelican's entrypoint: https://github.com/parkervcp/yolks/blob/master/steamcmd/entrypoint.sh
