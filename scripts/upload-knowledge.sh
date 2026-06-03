#!/usr/bin/env bash
# upload-knowledge.sh — upload Markdown / PDF / DOCX files to an Azure SRE
# Agent's Knowledge settings so the agent grounds future answers in them
# (with clickable citations).
#
# Two transport options are implemented:
#   1. Direct data-plane REST call (PUT /api/v2/.../knowledge), tried first.
#      The exact endpoint may not yet be public for all tenants; we probe and
#      gracefully fall back to step (2).
#   2. Manual portal steps printed for the operator.
#
# Authentication uses the Azure SRE data-plane audience
# (https://azuresre.ai). The agent endpoint is resolved from the ARM resource
# properties.agentEndpoint so the script can target the correct agent instance.
#
# Prereqs: az logged in, jq, curl, bash 5+.
#
# Usage:
#   ./upload-knowledge.sh \
#     --subscription <your-subscription-id> \
#     --resource-group <agent-rg> \
#     --agent <agent-name> \
#     --docs DEMO-RUNBOOK.md,docs/why-and-when-to-use-skills.md
#
# Or via env: SUB=... RG=... AGENT=... DOCS=... ./upload-knowledge.sh

set -euo pipefail

SUB="${SUB:-}"
RG="${RG:-}"
AGENT="${AGENT:-}"
DOCS="${DOCS:-}"
ARM_API_VERSION="${ARM_API_VERSION:-2025-05-01-preview}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription)   SUB="$2"; shift 2 ;;
    --resource-group) RG="$2"; shift 2 ;;
    --agent)          AGENT="$2"; shift 2 ;;
    --docs)           DOCS="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$SUB" || -z "$RG" || -z "$AGENT" || -z "$DOCS" ]]; then
  echo "Need --subscription, --resource-group, --agent, --docs (comma-separated paths)." >&2
  echo "Or set SUB / RG / AGENT / DOCS env vars." >&2
  exit 2
fi

# Resolve agent data-plane endpoint
AGENT_URL=$(az resource show \
  --ids "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.App/agents/$AGENT" \
  --api-version "$ARM_API_VERSION" \
  --query "properties.agentEndpoint" -o tsv 2>/dev/null || true)

if [[ -z "$AGENT_URL" || "$AGENT_URL" == "null" ]]; then
  echo "Could not resolve agent endpoint. Is the agent provisioned?" >&2
  exit 3
fi

TOKEN=$(az account get-access-token --resource "https://azuresre.ai" --query accessToken -o tsv)

print_portal_steps() {
  cat <<EOF

The data-plane upload endpoint isn't reachable from this token / region yet.
Fall back to the portal (5-step manual flow):

  1. Go to https://sre.azure.com and open agent: $AGENT
  2. Left sidebar -> Builder -> Knowledge settings
  3. Click 'Add file'
  4. For each of the following, drag-and-drop or browse:
EOF
  IFS=',' read -ra paths <<<"$DOCS"
  for p in "${paths[@]}"; do
    printf "       - %s\n" "$p"
  done
  cat <<'EOF'
  5. Wait for Status to flip from "Pending" to "Indexed" (~30s per doc).

Verify in the agent chat:
  "Use the runbook in your knowledge to walk me through ..."
The agent's response will include clickable citations to the doc.

EOF
}

upload_one() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "  ✗ $path — file not found, skipping" >&2
    return 1
  fi
  local filename
  filename=$(basename "$path")
  echo "  → Uploading $filename ($(stat -c%s "$path" 2>/dev/null || stat -f%z "$path") bytes)..."
  local resp_body
  local http
  local script_dir
  script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  resp_body="$script_dir/.upload-knowledge-response-$$.json"
  rm -f "$resp_body"
  http=$(curl -sS -o "$resp_body" -w "%{http_code}" \
    -X POST "$AGENT_URL/api/v2/knowledge-documents" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: multipart/form-data" \
    -F "file=@$path" \
    -F "filename=$filename" 2>&1 || true)
  if [[ "$http" == "200" || "$http" == "201" || "$http" == "202" ]]; then
    echo "    ✓ HTTP $http"
    rm -f "$resp_body"
    return 0
  fi
  echo "    ✗ HTTP $http — falling back to portal flow"
  if [[ -f "$resp_body" ]]; then
    cat "$resp_body" >&2
    rm -f "$resp_body"
  fi
  return 1
}

# Try uploading every doc. If ANY fails with non-2xx, print portal fallback.
IFS=',' read -ra paths <<<"$DOCS"
any_failed=0
for p in "${paths[@]}"; do
  p_trim=$(echo "$p" | xargs)
  upload_one "$p_trim" || any_failed=1
done

if [[ "$any_failed" -ne 0 ]]; then
  print_portal_steps
  exit 4
fi

cat <<EOF

✓ All ${#paths[@]} document(s) uploaded.

Indexing typically completes in ~30 seconds per document. Verify at:
  https://sre.azure.com -> $AGENT -> Builder -> Knowledge settings
Status should show "Indexed" before you query.

EOF
