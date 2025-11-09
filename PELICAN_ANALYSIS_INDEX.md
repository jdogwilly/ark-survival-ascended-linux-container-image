# Pelican Panel ARK SA Analysis - Complete Index

**Last Updated**: November 8, 2025
**Status**: Complete Analysis & Actionable Fixes Ready

This directory now contains a comprehensive analysis of Pelican Panel's working ARK: Survival Ascended implementation, with detailed comparisons to our container and concrete fixes.

---

## Quick Start

If you just want to fix the container, read these in order:

1. **START HERE**: [PELICAN_ACTIONABLE_FIXES.md](./PELICAN_ACTIONABLE_FIXES.md)
   - 4 critical fixes to implement
   - Quick implementation guide
   - Testing checklist
   - Expected results

2. **IF NEEDED**: [PELICAN_PANEL_ANALYSIS.md](./PELICAN_PANEL_ANALYSIS.md)
   - Detailed explanation of why fixes work
   - Differences between implementations
   - Architecture discussion

3. **FOR REFERENCE**: [PELICAN_IMPLEMENTATION_REFERENCE.md](./PELICAN_IMPLEMENTATION_REFERENCE.md)
   - Complete code snippets
   - Key patterns and examples
   - Directory structures

---

## Document Descriptions

### 1. PELICAN_ACTIONABLE_FIXES.md ⭐ START HERE

**Purpose**: Translate analysis into concrete code changes

**Contains**:
- 7 numbered fixes with specific file locations
- Phase 1 (Critical) - Must fix
- Phase 2 (Important) - Should fix
- Phase 3 (Nice-to-Have) - Optional
- Implementation order and priority
- Testing checklist for each fix
- Expected results before/after

**Read when**: You want to actually fix the container

**Key sections**:
- Fix #1: Machine-ID Reset (prevents "unit test mode")
- Fix #2: Steam Client Libraries (enables Proton)
- Fix #3: App ID 1007 (provides runtime)
- Fix #4: Proton Environment Variables (setup paths)
- Fix #5-7: Optional improvements

---

### 2. PELICAN_PANEL_ANALYSIS.md ⭐ COMPREHENSIVE GUIDE

**Purpose**: Deep technical analysis of Pelican's implementation

**Contains**:
- Executive summary of key differences
- Complete Dockerfile analysis
- Steam client components explanation
- Proton configuration details
- Entrypoint script walkthrough
- Egg configuration format
- Critical installation steps
- Environment variables reference
- Startup command structure
- RCON integration details
- Key insights & differences
- Critical implementation items

**Read when**: You want to understand WHY things work

**Key sections**:
- Section 3: Dockerfile Analysis (What's different)
- Section 4: Steam Client Components (Why App ID 1007 matters)
- Section 8: Critical Installation Steps (Step-by-step breakdown)
- Section 12: Key Insights (Root causes of failures)

---

### 3. PELICAN_IMPLEMENTATION_REFERENCE.md ⭐ CODE EXAMPLES

**Purpose**: Complete code snippets and implementation patterns

**Contains**:
- Complete Dockerfile (copy-paste ready)
- Complete entrypoint script
- Installation script
- Egg configuration JSON
- 6 key code patterns with explanations
- Environment variable patterns
- Directory structure after installation
- SteamCMD command patterns

**Read when**: You want to see exact code or copy patterns

**Key sections**:
- Complete Dockerfile (lines 1-72)
- Pattern 1: Proton Detection & Setup
- Pattern 2: Conditional Bash Expansion
- Pattern 3: Graceful Shutdown Handler
- Pattern 4: Background Process Management
- SteamCMD Command Patterns

---

## Analysis Findings Summary

### Critical Issues in Our Container

1. **No Machine-ID Reset**
   - Causes "ProtonFixes unit test mode" errors
   - Prevents Proton from applying game-specific fixes
   - FIX: Add dbus-uuidgen calls to Dockerfile

2. **Missing Steam Client Libraries**
   - `.steam/sdk32` and `.steam/sdk64` not populated
   - Proton can't find Windows DLLs
   - FIX: Copy `linux32/steamclient.so` and `linux64/steamclient.so` from SteamCMD

3. **No App ID 1007 Installation**
   - Steam runtime bootstrap not downloaded
   - Missing essential compatibility components
   - FIX: Add `+app_update 1007` to SteamCMD commands

4. **Proton Environment Variables Not Set**
   - `STEAM_COMPAT_CLIENT_INSTALL_PATH` missing
   - `STEAM_COMPAT_DATA_PATH` missing
   - Proton can't find Steam or Wine prefix
   - FIX: Export these variables in entrypoint

### What Pelican Does Right

1. **Dynamic Proton Version**
   - Automatically downloads latest Proton-GE
   - Gets updates with each image rebuild
   - vs our pinned GE-Proton10-17

2. **Streamlined Entrypoint**
   - Minimal but complete
   - Delegates heavy lifting to SteamCMD
   - vs our complex multi-stage approach

3. **Proper Signal Handling**
   - Uses tini as PID 1
   - Proper signal forwarding
   - vs our direct bash execution

4. **Clean Process Management**
   - Trap-based graceful shutdown
   - RCON integration for save/exit
   - vs our simple exec approach

---

## Implementation Timeline

### Phase 1: Critical Fixes (30 minutes)
- Machine-ID reset
- Steam client libraries
- App ID 1007 installation
- Proton environment variables

**Result**: Server should start and stay running

### Phase 2: Important Fixes (20 minutes)
- XDG_RUNTIME_DIR setup
- ProtonFixes config directory
- Proton version upgrade

**Result**: Cleaner logs, no warnings

### Phase 3: Nice-to-Have (15 minutes)
- Add tini for PID 1
- Graceful shutdown handler

**Result**: Better signal handling, clean shutdowns

---

## Key Metrics

### Pelican's Base Image

| Component | Details |
|-----------|---------|
| Base | debian:bookworm-slim |
| User | container (UID 1000) |
| Proton | Latest GE-Proton (auto-updated) |
| Init | tini |
| RCON | rcon-cli v0.10.3 |
| Wine | Installed by Proton-GE |
| Winetricks | Yes |
| Protontricks | Yes |

### Our Container

| Component | Current | Issue |
|-----------|---------|-------|
| Base | ubuntu:24.04 | Heavier but okay |
| User | gameserver (UID 25000) | Different paths |
| Proton | GE-Proton10-17 | Outdated |
| Init | bash directly | Poor signal handling |
| RCON | Custom Python | Works but untested |
| Wine | Not installed | Auto-installed by Proton |
| Winetricks | No | Could help |
| Protontricks | No | Not essential |

---

## File Locations in Repository

### Analysis Documents (New)
```
PELICAN_ACTIONABLE_FIXES.md                 ← START HERE
PELICAN_PANEL_ANALYSIS.md                   ← COMPREHENSIVE
PELICAN_IMPLEMENTATION_REFERENCE.md         ← CODE EXAMPLES
PELICAN_ANALYSIS_INDEX.md                   ← THIS FILE
```

### Existing Related Documents
```
FIX_REPORT.md                               ← Previous analysis
PELICAN_COMPARISON_REPORT.md                ← Earlier comparison
QUICK_FIX_GUIDE.md                          ← Quick reference
QUICK_SUMMARY.md                            ← Executive summary
```

### Files to Modify
```
Dockerfile                                  ← Add machine-ID reset
root/usr/bin/start_server                   ← Add all 4 critical fixes
docker-compose.yml                          ← Optional: add tini entrypoint
```

---

## Quick Reference: Critical Code Changes

### Change 1: Dockerfile - Machine-ID Reset
```dockerfile
# Add after dbus installation
RUN rm -f /etc/machine-id
RUN dbus-uuidgen --ensure=/etc/machine-id
RUN rm /var/lib/dbus/machine-id
RUN dbus-uuidgen --ensure
```

### Change 2: start_server - Steam Libraries
```bash
# Add after SteamCMD install
mkdir -p /home/gameserver/.steam/sdk32
cp -v /home/gameserver/steamcmd/linux32/steamclient.so /home/gameserver/.steam/sdk32/
mkdir -p /home/gameserver/.steam/sdk64
cp -v /home/gameserver/steamcmd/linux64/steamclient.so /home/gameserver/.steam/sdk64/
```

### Change 3: start_server - App ID 1007
```bash
# Modify SteamCMD call
+app_update 1007 \      # Add this line
+app_update 2430930 \
```

### Change 4: start_server - Environment Variables
```bash
# Add at script start
export SRCDS_APPID=2430930
export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/gameserver/.steam/steam"
export STEAM_COMPAT_DATA_PATH="/home/gameserver/.steam/steam/steamapps/compatdata/${SRCDS_APPID}"
mkdir -p /home/gameserver/.steam/steam/steamapps/compatdata/${SRCDS_APPID}
```

---

## Testing Commands

### Verify Machine-ID Reset
```bash
docker exec asa-server cat /etc/machine-id
# Should show unique ID
```

### Verify Steam Libraries
```bash
docker exec asa-server ls -la /home/gameserver/.steam/sdk32/steamclient.so
docker exec asa-server ls -la /home/gameserver/.steam/sdk64/steamclient.so
# Both should exist
```

### Verify Environment Variables
```bash
docker exec asa-server env | grep STEAM_COMPAT
# Should show both variables set
```

### Verify Server Runs
```bash
docker logs asa-server | head -50
# Should show Proton startup messages, not crash
```

---

## Common Questions Answered

### Q: Why does Pelican's image work but ours doesn't?

**A**: Four critical components:
1. Machine-ID reset for Proton initialization
2. Steam client libraries in `.steam/sdk{32,64}`
3. App ID 1007 providing runtime components
4. Explicit Proton environment variables

Without these, Proton fails to initialize.

### Q: Can we just use Pelican's Dockerfile?

**A**: Partially. Their setup is simpler but our approach is more flexible:
- We support config imports (STAGE 4.5)
- We support mod management
- We have better logging
- We run as non-root user for security

Instead, adopt their critical fixes within our structure.

### Q: What's the minimum we need to fix?

**A**: Phase 1 (4 fixes) is the minimum to get it working:
1. Machine-ID reset
2. Steam libraries
3. App ID 1007
4. Proton env vars

Estimate 30 minutes implementation.

### Q: Should we upgrade Proton version?

**A**: Yes, but it's not the root cause. GE-Proton10-17 works; newer versions (10-25) are just better.

Fix the 4 critical issues first, then upgrade.

### Q: Do we need tini?

**A**: Not critical, but recommended. Makes signal handling cleaner.

Add as Phase 3 improvement.

---

## Architecture Comparison

### Pelican's Flow
```
Container Start
  ↓
Entrypoint executes
  ↓
Check Proton exists, setup env vars
  ↓
cd to working directory
  ↓
Run SteamCMD update (App 1007 + 2430930)
  ↓
Eval startup command with Proton
  ↓
Server runs in background
  ↓
Monitor logs and RCON readiness
  ↓
Container stays running
```

### Our Current Flow
```
Container Start
  ↓
start_server script
  ↓
Check/download SteamCMD
  ↓
Install game via SteamCMD
  ↓
Check/download Proton
  ↓
Initialize Proton prefix
  ↓
Check mods
  ↓
Optionally install API plugin
  ↓
Launch server via exec
  ↓
Process replaces shell
  ↓
Server crashes in 2-10 seconds
```

### The Difference

Pelican's entrypoint is simple because SteamCMD installation happens separately (during container install). Their entrypoint just runs updates + launches.

Our `start_server` tries to do everything in one script, making it complex.

Both approaches can work, but ours is missing the 4 critical components.

---

## File Changes Summary

### Files to Modify (Must)

1. **Dockerfile** (1 change)
   - Add machine-ID reset after dbus
   - 4 lines of code
   - Critical for Proton initialization

2. **root/usr/bin/start_server** (3 changes)
   - Add `.steam/sdk{32,64}` setup
   - Add `+app_update 1007` to SteamCMD
   - Add STEAM_COMPAT_* env variables
   - 20-30 lines total
   - Critical for server startup

### Files to Modify (Optional)

3. **Dockerfile** (1 change)
   - Add tini package
   - Better signal handling

4. **docker-compose.yml** (1 change)
   - Configure tini entrypoint
   - Only if adding tini

---

## Next Steps

### For Immediate Fix
1. Read: PELICAN_ACTIONABLE_FIXES.md
2. Apply: Phase 1 fixes (4 items)
3. Test: Build and verify
4. Deploy: New container version

### For Deep Understanding
1. Read: PELICAN_PANEL_ANALYSIS.md (all sections)
2. Study: PELICAN_IMPLEMENTATION_REFERENCE.md (code examples)
3. Compare: Our Dockerfile vs Pelican's
4. Document: What we learned

### For Production Deployment
1. Apply: Phase 1 + Phase 2 fixes
2. Test: Full server startup and shutdown
3. Monitor: Container logs and process
4. Deploy: Update image in production
5. Plan: Phase 3 improvements for next iteration

---

## Document Statistics

### What We Analyzed

- **Dockerfile**: 73 lines of Pelican's Proton base
- **Entrypoint Script**: 85 lines of SteamCMD startup logic
- **Installation Script**: 60 lines of SteamCMD game download
- **Egg Configuration**: 400+ lines of Pterodactyl egg JSON
- **Code Patterns**: 6 key patterns documented with examples
- **Environment Variables**: 14+ critical variables identified

### What We Created

- **PELICAN_ACTIONABLE_FIXES.md**: 350+ lines (fixes + implementation)
- **PELICAN_PANEL_ANALYSIS.md**: 900+ lines (comprehensive analysis)
- **PELICAN_IMPLEMENTATION_REFERENCE.md**: 600+ lines (code examples)
- **PELICAN_ANALYSIS_INDEX.md**: This file (~400 lines)

### Total Analysis
- 2,250+ lines of documentation
- 6 key patterns identified
- 4 critical fixes with implementation guide
- 3+ phase improvement roadmap
- Complete code reference

---

## Conclusion

Pelican Panel's ARK SA implementation works because it correctly:

1. Resets Proton's machine-id
2. Installs and links Steam client libraries
3. Runs the Steam runtime bootstrap (App ID 1007)
4. Sets up Proton environment variables

These are not optional features - they're fundamental requirements for Proton to function on Linux.

Our container is missing these components, causing the startup failures we've been investigating.

The fixes are straightforward, the implementation is clear, and the testing is simple.

**Start with PELICAN_ACTIONABLE_FIXES.md and implement Phase 1 for a working container.**

---

## References

### Pelican Panel & Pterodactyl
- **Repository**: https://github.com/pelican-eggs/eggs
- **Yolks Images**: https://github.com/pelican-eggs/yolks
- **ARK SA Egg**: game_eggs/steamcmd_servers/ark_survival_ascended/

### Proton & Wine
- **Proton-GE**: https://github.com/GloriousEggroll/proton-ge-custom
- **Wine**: https://www.winehq.org/
- **Winetricks**: https://github.com/Winetricks/winetricks
- **Protontricks**: https://github.com/Winetricks/protontricks

### SteamCMD & Tools
- **SteamCMD Docs**: https://developer.valvesoftware.com/wiki/SteamCMD
- **RCON-CLI**: https://github.com/gorcon/rcon-cli
- **Tini Init**: https://github.com/krallin/tini

### ARK: Survival Ascended
- **App ID**: 2430930
- **Official**: https://www.playark.com/
- **Steam Page**: https://store.steampowered.com/app/2430930/

---

## Document Versions

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Nov 8, 2025 | Initial analysis complete |
| 1.1 | Nov 8, 2025 | Added actionable fixes document |
| 1.2 | Nov 8, 2025 | Added implementation reference |
| 1.3 | Nov 8, 2025 | Created this index |

---

## Support & Questions

### If something is unclear
1. Check PELICAN_PANEL_ANALYSIS.md for detailed explanation
2. Check PELICAN_IMPLEMENTATION_REFERENCE.md for code examples
3. Check PELICAN_ACTIONABLE_FIXES.md for specific implementation

### If fixes don't work
1. Verify all Phase 1 fixes are applied
2. Check testing commands in PELICAN_ACTIONABLE_FIXES.md
3. Review Dockerfile and start_server for correct implementation
4. Compare with code examples in PELICAN_IMPLEMENTATION_REFERENCE.md

### For future reference
- Keep all 4 analysis documents in repository
- Link to them in README.md
- Reference them when making Proton-related changes
- Update them if new Proton/Wine issues arise

---

**Analysis Complete** ✓
**Ready for Implementation** ✓
**Estimated Fix Time: 30-60 minutes** ⏱️

