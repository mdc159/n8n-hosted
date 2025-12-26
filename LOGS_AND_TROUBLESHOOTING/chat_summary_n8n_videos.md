# Chat Summary — n8n Video File Writes + Docker Paths + IG Metrics API

Date range: **Dec 16–26, 2025 (America/Tijuana)**  
Goal: reliably write generated media (e.g., `*.mp4`) from a self-hosted **n8n** instance to disk, and understand where files land when using Docker + filesystem binary mode.

---

## 1) Initial goal: write MP4s to `/videos/<filename>.mp4`

You wanted n8n to be able to write files to a folder called:

- **Container path**: `/videos`
- Desired output example: `/videos/file_name.mp4`

You also wanted step-by-step terminal guidance to create the directory and ensure disk persistence.

---

## 2) Docker Compose + Traefik configuration issues (YAML)

You shared a `docker-compose.yml` snippet where the `n8n:` service was not indented under `services:` and one Traefik label line had bad indentation / duplicate entries.

Key fix:
- Ensure **all services** are children of `services:`
- Correct YAML indentation
- Remove duplicated/misindented label lines

Result: `docker compose` could parse the file correctly and start containers.

---

## 3) First failure: “The file … is not writable”

n8n’s **Read/Write File** node (`n8n-nodes-base.readWriteFile`, operation `write`) produced errors like:

- `The file "/videos/<id>_xvideo.mp4" is not writable.`

### What we verified:
Inside the container, n8n runs as:
- `node` with UID/GID `1000:1000`

You confirmed container visibility and write ability with:
- `touch /videos/n8n_write_test.txt` ✅

This proved:
- Docker mount existed
- Linux permissions for the mounted directory were fine
- The container user could write to `/videos`

### Common “false causes” discussed:
- Filename collision / overwrite setting
- Directory creation
- Permissions/ownership mismatch between host and container
- Incorrect host path (using `/videos` on host vs `./videos` bind mount)

---

## 4) Key Docker concept clarified: host path vs container path

You hit confusion when running host commands like:
- `chown /videos` → “No such file or directory”

Reason:
- `/videos` existed **inside the container**, not necessarily on the host
- Your compose used a bind mount like `./videos:/videos`

So the real folder on the host was something like:
- `/root/videos` (depending on where `docker-compose.yml` lived)

**Mental model**:
- Host path is the “real disk” location
- Container path is the view inside the container
- A bind mount makes them appear as “linked” views of the same files

---

## 5) Root cause discovered: n8n filesystem access restrictions in binary mode

Eventually you uncovered the real message:

> `Access to the file is not allowed. Allowed paths: /home/node/.n8n-files`

This was the actual blocker.

### Meaning:
When `N8N_DEFAULT_BINARY_DATA_MODE=filesystem` is enabled, n8n restricts file read/write paths to its binary storage directory (default):

- **Allowed container path**: `/home/node/.n8n-files`

Even if Linux permissions allow `/videos`, n8n will block writes outside the allowed path set.

This explains why:
- `touch` worked in shell
- but the **n8n node** still refused to write

---

## 6) Working solution: map your host “videos” folder to n8n’s allowed binary directory

Instead of trying to force n8n to write to `/videos`, you map your host folder to the allowed directory:

### Docker Compose volume mapping (recommended)
Use something like:

- Host: `./videos`
- Container: `/home/node/.n8n-files`

Example (n8n service volumes):
```yaml
volumes:
  - n8n_data:/home/node/.n8n
  - ./videos:/home/node/.n8n-files
  - /usr/share/fonts:/usr/share/fonts
```

### In n8n nodes
Write your output to:
- `/home/node/.n8n-files/<filename>.mp4`
  - or sometimes just `<filename>.mp4` if the node resolves relative to the binary store path (behavior can vary by node/version)

### How to locate files from terminal
- **From the host**: look in the mapped folder (e.g., `./videos` or `/root/videos`)
- **From inside the container**:
  - `cd /home/node/.n8n-files && ls -la`

Important clarification:
- `/home/node/.n8n-files` exists **inside the container**, not on the host
- The host sees the same files at the bind-mounted path you chose (e.g., `/root/videos`)

---

## 7) Additional operational notes that came up

- `docker compose exec n8n sh` is the correct way to test writes inside the container.
- The warning `version is obsolete` in compose v2 is harmless; it can be removed for cleanliness.
- The “not writable” message is sometimes misleading; it can appear due to:
  - path restrictions (the real cause here)
  - missing/incorrect binary property
  - overwrite/exists behavior depending on node settings

---

## 8) Final question: Meta Business Suite / Instagram daily views API

You asked whether Meta Business Suite has an API to retrieve daily Instagram views.

Summary response:
- There is no dedicated “Business Suite API” for that UI product.
- Daily metrics can be accessed via the **Instagram Graph API** (part of Meta’s Graph API) **for Business/Creator accounts** linked to a Facebook Page.
- Typical metrics: impressions, reach, video views/plays, etc., usually queryable by day with the appropriate permissions/scopes and token setup.

---

## Outcome

### The effective fix for “cannot write MP4 to disk” in n8n (filesystem binary mode):
✅ Don’t fight `/videos` directly.  
✅ Bind mount your desired host folder into **`/home/node/.n8n-files`**, then write there from n8n.

This makes n8n’s internal path allowlist and your host storage goals align.

---

## Quick “known-good” command snippets

### Check files inside the container
```sh
docker compose exec n8n sh -c "ls -la /home/node/.n8n-files | tail"
```

### Check files on the host (example)
```bash
cd /root/videos
ls -la | tail
```

---

*End of summary.*
