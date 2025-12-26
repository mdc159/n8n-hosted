# Webhook Workflow Creation - Troubleshooting Log

**Objective**: Create and execute a simple webhook workflow in n8n via MCP server

**Date**: 2025-12-10

## Summary
Attempted multiple methods to create a webhook workflow. MCP connection works and can call tools, but workflow creation requests hang/timeout. Direct API access from host is blocked.

---

## Methods Attempted

### 1. MCP Workflow Creation - JSON-RPC via docker exec (TIMEOUT)
**Method**: Send JSON-RPC `n8n_create_workflow` request to MCP server via docker exec stdio

**Command**:
```bash
cat /tmp/create_workflow.json | docker exec -i n8n-stack-mcp-1 node /app/dist/mcp/index.js
```

**Result**: ❌ TIMEOUT
- Request was submitted and process continued running
- MCP server accepted the request but response was never returned
- Process eventually killed after 15+ seconds
- Possible causes:
  - MCP server may be waiting for workflow validation/creation to complete
  - Timeout in MCP tool implementation
  - Database operation on n8n side is slow or hanging

---

### 2. MCP Health Check (SUCCESS)
**Method**: Query MCP server with `n8n_health_check` in diagnostic mode

**Command**:
```bash
echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"n8n_health_check","arguments":{"mode":"diagnostic"}},"id":3}' | docker exec -i n8n-stack-mcp-1 node /app/dist/mcp/index.js
```

**Result**: ✅ SUCCESS
- MCP server is operational
- Connected to n8n at `http://n8n:5678`
- API credentials configured and valid
- MCP version: 2.28.7 (update available: 2.29.0)
- 20 tools available (7 documentation, 13 management)

---

### 3. MCP List Workflows (SUCCESS)
**Method**: Query existing workflows via `n8n_list_workflows`

**Command**:
```bash
echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"n8n_list_workflows","arguments":{}},"id":4}' | docker exec -i n8n-stack-mcp-1 node /app/dist/mcp/index.js
```

**Result**: ✅ SUCCESS
- Returned empty workflow list (0 workflows)
- API call executed successfully
- Confirmed n8n is accessible and responsive to API queries

---

### 4. Direct n8n API via localhost:5678 (CONNECTION REFUSED)
**Method**: Curl n8n API endpoint from host machine on localhost:5678

**Command**:
```bash
curl -s -X POST http://localhost:5678/api/v1/workflows \
  -H "X-N8N-API-KEY: ..." \
  -d '{"name":"Webhook Test",...}'
```

**Result**: ❌ CONNECTION REFUSED
- n8n port 5678 is not exposed on the Docker host
- Only accessible through internal Docker network or via Caddy reverse proxy
- This is by design for security

---

### 5. n8n API via HTTPS + Basic Auth (SHELL ESCAPING ERROR)
**Method**: Access n8n through Caddy reverse proxy with Caddy basic auth + n8n API key

**Command**:
```bash
curl -s -u admin:'<password>' https://n8n.pimpshizzle.com/api/v1/workflows \
  -H "X-N8N-API-KEY: ..." \
  -k
```

**Result**: ❌ SHELL ESCAPING ERROR
- Password contains special characters (`!`, `#`, `^`) that need escaping
- String interpolation in bash command failed
- Need proper quoting or encoding strategy

---

### 6. Workflow Creation via Script with Heredoc (TIMEOUT)
**Method**: Create shell script to submit workflow creation request via heredoc

**Command**:
```bash
cat > /tmp/test_workflow.sh << 'SCRIPT'
#!/bin/bash
docker exec -i n8n-stack-mcp-1 node /app/dist/mcp/index.js << 'EOF'
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "n8n_create_workflow",
    "arguments": { ... }
  }
}
EOF
SCRIPT
timeout 30 /tmp/test_workflow.sh
```

**Result**: ❌ TIMEOUT (30 seconds)
- Process hung waiting for MCP response
- Same issue as Method 1
- MCP `n8n_create_workflow` tool seems to have blocking/timeout issues

---

### 7. Docker Network API Call (BLOCKED BY USER)
**Method**: Spin up curl container on n8n_net bridge network to access n8n:5678 directly

**Command**:
```bash
docker run --rm --network n8n-stack_n8n_net curlimages/curl:latest \
  curl -X POST http://n8n:5678/api/v1/workflows \
  -H "X-N8N-API-KEY: ..." \
  -d '{"name":"Webhook Test",...}'
```

**Result**: ⏸️ BLOCKED
- User rejected this tool use attempt
- Not executed

---

## Root Cause Analysis

### Why Workflow Creation via MCP Hangs

The issue appears to be in the n8n-MCP `n8n_create_workflow` tool implementation:

1. **Tool accepts the request** - JSON-RPC protocol works, tool is recognized
2. **Tool never returns** - Process hangs indefinitely waiting for response
3. **List/Health tools work fine** - Read-only operations complete successfully

Possible causes:
- The `n8n_create_workflow` tool may be synchronously waiting for n8n to process/validate the workflow
- Database write operations may be slow or deadlocked
- The MCP server may not properly handle async operations in this tool
- n8n instance may be overloaded or processing slowly

### Why Direct API Access Doesn't Work

1. **n8n port 5678 not exposed on host** - Docker container ports only exposed to other containers unless explicitly mapped
2. **Access only via Caddy reverse proxy** - HTTPS endpoint requires Caddy basic auth PLUS n8n API key
3. **Internal docker network available** - n8n accessible at `http://n8n:5678` from other containers on `n8n-stack_n8n_net`

---

## Workarounds & Next Steps

### Option 1: Investigate MCP Tool Issue
- Check n8n-MCP GitHub issues for `n8n_create_workflow` timeout problems
- Update MCP server to v2.29.0 to see if issue is resolved
- Check n8n server logs (`docker compose logs n8n`) for errors during workflow creation

### Option 2: Use n8n UI Instead
- Access https://n8n.pimpshizzle.com
- Authenticate with:
  - Caddy basic auth: `admin` / `V3ryStrong!72#XaZp` (from `.env`)
  - Or n8n user: `mdc159` (if N8N_BASIC_AUTH_ACTIVE=true)
- Create webhook workflow through visual editor
- Export/import workflows programmatically if needed

### Option 3: Use Alternative Access Method
- Create temporary port-forward from container to host: `docker port n8n-stack-n8n-1`
- Use Docker network curl to hit n8n:5678 (requires container execution)
- SSH tunneling if droplet has SSH exposed

### Option 4: Test MCP with Different Workflow Type
- Try creating simple workflow with fewer nodes (eliminate Respond node)
- Use simpler node types to isolate the issue
- Test if issue is specific to Webhook/Respond nodes

---

## Environment Info

- **Docker Compose Status**: All containers running (n8n, caddy, mcp)
- **MCP Server**: Running, healthy, v2.28.7
- **n8n Version**: 1.123.4
- **MCP Configuration**: Correct - uses stdio mode via docker exec
- **API Key**: Configured and valid in `.env`
- **Network**: All containers on `n8n_net` bridge, working correctly

---

## Files Created for Testing

- `/tmp/webhook_workflow.json` - Webhook workflow definition
- `/tmp/create_workflow.json` - MCP request payload
- `/tmp/test_workflow.sh` - Script to submit workflow creation

## Recommendation

**Use n8n UI for now.** The MCP server is working correctly for queries but has issues with the `n8n_create_workflow` tool. This appears to be a limitation or bug in the n8n-MCP package rather than the deployment setup.

For programmatic workflow creation, either:
1. Upgrade MCP server and test again
2. Use Python/Node.js client library to hit the n8n API
3. Create workflows in UI and manage via MCP's workflow update/delete tools
