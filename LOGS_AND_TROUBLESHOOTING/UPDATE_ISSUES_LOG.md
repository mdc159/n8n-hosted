# n8n Update Issues Log
**Date**: 2025-12-26
**Server**: n8n-ubuntu-c-2-sfo2-01
**Location**: /opt/n8n
**Issue**: FFmpeg installation failure during n8n update

---

## Summary

Attempted to update n8n from older version to latest (sha256:85214df20cd7bc020f8e4b0f60f87ea87f0a754ca7ba3d1ccdfc503ccd6e7f9c) but encountered package manager compatibility issues. The n8n base image no longer supports the package manager used in our custom Dockerfile.

---

## Timeline of Events

### 1. Initial Update Attempt
**Time**: 2025-12-26
**Command**: `docker compose build --pull`

**Error**:
```
[2/4] RUN apk add --no-cache ffmpeg:
0.717 /bin/sh: apk: not found
------
Dockerfile.n8n:8
failed to solve: process "/bin/sh -c apk add --no-cache ffmpeg" did not complete successfully: exit code: 127
```

**Analysis**:
- n8n base image previously used Alpine Linux (which uses `apk` package manager)
- Latest n8n image no longer includes Alpine package manager
- Indicates n8n team changed base image OS

**Original Dockerfile.n8n (line 8)**:
```dockerfile
RUN apk add --no-cache ffmpeg
```

---

### 2. First Fix Attempt - Switch to Debian apt-get
**Time**: 2025-12-26
**Action**: Updated Dockerfile.n8n to use Debian package manager

**Changed line 8 to**:
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
```

**Rebuild Command**: `docker compose build --pull`

**Error**:
```
[2/4] RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*:
0.261 /bin/sh: apt-get: not found
------
Dockerfile.n8n:8
failed to solve: process "/bin/sh -c apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*" did not complete successfully: exit code: 127
```

**Analysis**:
- n8n base image does NOT include `apt-get` either
- This indicates the base image may be:
  - Distroless image (minimal, no package managers)
  - Custom minimal Node.js image
  - Different OS entirely (not Alpine, not Debian/Ubuntu)

---

## Current State

### Services Status
- **n8n-stack service**: STOPPED (intentionally stopped for update)
- **Workflow status**: Active workflow preserved in n8n_data volume
- **Data integrity**: No data loss - all data in Docker volumes (n8n_data, caddy_data, videos)

### Dockerfile.n8n Current Version
```dockerfile
# Custom n8n image with FFmpeg support
FROM n8nio/n8n:latest

# Switch to root for package installation
USER root

# Install ffmpeg for video processing workflows
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*

# Create videos directory with correct ownership
RUN mkdir -p /home/node/videos && chown -R node:node /home/node/videos

# Switch back to node user for security
USER node

# Default working directory
WORKDIR /home/node
```

**Status**: ⚠️ NON-FUNCTIONAL - apt-get not available in base image

---

## Technical Investigation Needed

### Diagnostic Commands Required
Run these commands to determine the n8n base image characteristics:

```bash
# 1. Check OS release information
docker run --rm n8nio/n8n:latest cat /etc/os-release

# 2. Check for any package manager
docker run --rm n8nio/n8n:latest sh -c "which apk apt apt-get yum dnf 2>/dev/null || echo 'No package managers found'"

# 3. List available binaries in /bin
docker run --rm n8nio/n8n:latest sh -c "ls -la /bin/ | grep -E '(apk|apt|yum|dnf)'"

# 4. Inspect image metadata
docker image inspect n8nio/n8n:latest | grep -A 20 "Layers"

# 5. Check if it's a distroless image
docker run --rm n8nio/n8n:latest sh -c "ls -la / && ls -la /usr/bin" 2>&1 | head -50
```

---

## Potential Solutions

### Solution 1: Multi-Stage Build (RECOMMENDED)
Install FFmpeg in a builder stage with package manager, then copy binaries to n8n image.

**Dockerfile.n8n**:
```dockerfile
# Multi-stage build: Install FFmpeg in builder, copy to n8n
FROM debian:bookworm-slim AS builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# Final stage: n8n image
FROM n8nio/n8n:latest

USER root

# Copy FFmpeg and its dependencies from builder
COPY --from=builder /usr/bin/ffmpeg /usr/bin/ffmpeg
COPY --from=builder /usr/bin/ffprobe /usr/bin/ffprobe
COPY --from=builder /usr/lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu

# Create videos directory with correct ownership
RUN mkdir -p /home/node/videos && chown -R node:node /home/node/videos

USER node
WORKDIR /home/node
```

**Pros**:
- Works with any base image (including distroless)
- Keeps final image size reasonable
- Most reliable solution

**Cons**:
- Slightly more complex Dockerfile
- May need to copy additional library dependencies

---

### Solution 2: Use npm-based FFmpeg
Use Node.js package that includes FFmpeg binaries.

**Dockerfile.n8n**:
```dockerfile
FROM n8nio/n8n:latest

USER root

# Install ffmpeg-static npm package (includes FFmpeg binaries)
RUN npm install -g ffmpeg-static ffprobe-static && \
    ln -s $(npm root -g)/ffmpeg-static/ffmpeg /usr/local/bin/ffmpeg && \
    ln -s $(npm root -g)/ffprobe-static/bin/linux/x64/ffprobe /usr/local/bin/ffprobe

# Create videos directory
RUN mkdir -p /home/node/videos && chown -R node:node /home/node/videos

USER node
WORKDIR /home/node
```

**Pros**:
- Uses npm which is guaranteed to be in n8n image
- Simple, single-stage build
- Cross-platform (npm packages work everywhere)

**Cons**:
- Depends on third-party npm packages
- May have version lag behind official FFmpeg releases
- Larger npm package footprint

---

### Solution 3: Pin to Older n8n Version (TEMPORARY WORKAROUND)
Temporarily use older n8n version that still has package manager.

**Dockerfile.n8n**:
```dockerfile
# Use older version with Alpine
FROM n8nio/n8n:1.60.0  # or whatever version still uses Alpine

USER root
RUN apk add --no-cache ffmpeg
RUN mkdir -p /home/node/videos && chown -R node:node /home/node/videos
USER node
WORKDIR /home/node
```

**Pros**:
- Immediate fix - original Dockerfile works
- Buys time to implement proper solution

**Cons**:
- Stuck on older n8n version
- Miss out on bug fixes and new features
- Not a long-term solution

---

### Solution 4: External FFmpeg Container (ARCHITECTURAL CHANGE)
Run FFmpeg in separate container, call it from n8n via docker exec.

**NOT RECOMMENDED** - Adds complexity, breaks workflow portability

---

## Recommended Action Plan

### Immediate Actions (Restore Service)
1. **Option A - Rollback temporarily**:
   ```bash
   # Use old image if still cached
   docker images | grep n8n-stack-n8n
   # If old image exists, tag it and start
   docker tag n8n-stack-n8n:old n8n-stack-n8n:latest
   systemctl start n8n-stack
   ```

2. **Option B - Use pinned version temporarily**:
   ```bash
   # Edit Dockerfile.n8n to use FROM n8nio/n8n:1.60.0
   # Keep original apk command
   docker compose build --no-cache
   systemctl start n8n-stack
   ```

### Long-term Solution (Next 24-48 hours)
1. Run diagnostic commands to understand new base image
2. Implement **Solution 1 (Multi-Stage Build)** or **Solution 2 (npm-based FFmpeg)**
3. Test FFmpeg functionality in workflows
4. Document final solution in this log

---

## Impact Assessment

### Services Affected
- ✅ **Caddy**: Not affected (uses official caddy:2 image, no customization)
- ⚠️ **n8n**: STOPPED - Cannot start until Dockerfile is fixed
- ✅ **MCP**: Not affected (uses official ghcr.io/czlonkowski/n8n-mcp:latest)

### Workflows Affected
- ⚠️ **Content Mate v.1.9.1 Marki**:
  - Workflow uses FFmpeg in multiple nodes:
    - Combine Videos1 (Execute Command node)
    - 3 sec voice1 (Execute Command node)
    - Combine vids and music1 (Execute Command node)
    - Make video with Captions1 (Execute Command node)
    - Transform X to (Execute Command node)
  - **Impact**: Cannot execute until FFmpeg is available

### Data Safety
✅ **All data is safe** - Stored in persistent Docker volumes:
- n8n_data (workflow definitions, credentials, execution history)
- caddy_data (SSL certificates)
- caddy_config (Caddy configuration)
- mcp_data (MCP server data)
- /opt/n8n/videos (video files on host filesystem)

---

## References

### Related Files
- `/opt/n8n/Dockerfile.n8n` - Custom n8n image definition
- `/opt/n8n/docker-compose.yml` - Service orchestration
- `/opt/n8n/.env` - Environment configuration
- `/etc/systemd/system/n8n-stack.service` - Systemd service unit

### n8n Image Information
- **Current Target**: n8nio/n8n:latest
- **SHA256**: 85214df20cd7bc020f8e4b0f60f87ea87f0a754ca7ba3d1ccdfc503ccd6e7f9c
- **Docker Hub**: https://hub.docker.com/r/n8nio/n8n/tags
- **GitHub**: https://github.com/n8n-io/n8n

### FFmpeg Information
- **Required for**: Video processing workflows
- **Nodes using FFmpeg**: 5 Execute Command nodes in Content Mate workflow
- **Commands used**: ffmpeg for video concatenation, format conversion, caption overlays

---

## Next Steps

1. **IMMEDIATE**: Restore service using temporary solution (pinned version or cached image)
2. **DIAGNOSTIC**: Run investigation commands to understand new base image
3. **IMPLEMENT**: Apply proper solution (multi-stage build or npm-based)
4. **TEST**: Verify FFmpeg works in workflows
5. **DOCUMENT**: Update this log with final resolution

---

## Resolution

**Status**: 🟢 RESOLVED
**Last Updated**: 2025-12-26
**Resolved By**: Claude Code (automated)

### Solution Implemented: Multi-Stage Build with Static FFmpeg

The n8n base image (`n8nio/n8n:latest`) transitioned to a **distroless image** in v2.0:
- No shell (`sh`, `bash` not found)
- No package managers (`apk`, `apt-get` not found)
- No standard utilities (`cat`, `ls`, `mkdir`, `chown` not found)

**Fix**: Use `mwader/static-ffmpeg` pre-built static binaries in a multi-stage Docker build.

### Updated Dockerfile.n8n

```dockerfile
# Multi-stage build for FFmpeg support on distroless n8n (v2.0+)
# Stage 1: Get static FFmpeg binaries
FROM mwader/static-ffmpeg:7.1 AS ffmpeg

# Stage 2: Build final n8n image
FROM n8nio/n8n:latest

# Copy FFmpeg binaries (static, no dependencies needed)
COPY --from=ffmpeg /ffmpeg /usr/local/bin/ffmpeg
COPY --from=ffmpeg /ffprobe /usr/local/bin/ffprobe
```

### Verification

```bash
# FFmpeg 7.1 confirmed working
$ docker compose run --rm --entrypoint /usr/local/bin/ffmpeg n8n -version
ffmpeg version 7.1 Copyright (c) 2000-2024 the FFmpeg developers

# All services healthy
$ docker compose ps
NAME                STATUS
n8n-stack-caddy-1   Up (healthy)
n8n-stack-mcp-1     Up (healthy)
n8n-stack-n8n-1     Up
```

### Why This Solution Works

1. **Static binaries**: `mwader/static-ffmpeg` provides FFmpeg compiled with all dependencies statically linked
2. **No shell required**: `COPY` instruction works in distroless (doesn't need shell)
3. **Future-proof**: Works regardless of base image OS (Alpine, Debian, distroless)
4. **Fast builds**: No compilation, just copies binaries (~120MB)

### Future Update Workflow

```bash
cd /opt/n8n
git pull
docker compose build --pull
docker compose down && docker compose up -d
docker compose exec n8n /usr/local/bin/ffmpeg -version
```

---

## Lessons Learned

1. **Version Pinning**: Consider pinning n8n version in production instead of using `:latest` tag
2. **Base Image Changes**: Monitor upstream base image changes that could break customizations
3. **Multi-Stage Builds**: Use multi-stage builds for custom package installations to avoid base image dependencies
4. **Testing**: Test updates in staging environment before production
5. **Rollback Plan**: Always have rollback strategy before major updates

---

## Contact Information

**Server**: n8n-ubuntu-c-2-sfo2-01 (DigitalOcean)
**Domain**: https://n8n.pimpshizzle.com
**Repository**: mdc159/n8n-hosted (GitHub)
**Deployment Path**: /opt/n8n
