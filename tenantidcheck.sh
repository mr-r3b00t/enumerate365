#!/bin/bash
# ==============================================================
# M365 Domain → Tenant ID → CSV Exporter (v4 - No More Quitting!)
# Handles failures gracefully, no set -e crashes
# Input: list of domains (file or pipe)
# Output: domains_tenantids.csv
# Dec 2025 - Tested & Bulletproof
# ==============================================================

OUTPUT="domains_tenantids.csv"
TMP=$(mktemp)
SUCCESS=0
FAIL=0
DEBUG=false

# Print CSV header
printf "domain,tenant_id\n" > "$OUTPUT"

# Dependency checks
for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[-] Error: $cmd is missing. Install: apt install curl jq (or brew install jq)"
        exit 1
    fi
done

# Parse args for debug
if [[ "${1:-}" == "--debug" ]]; then
    DEBUG=true
    shift
fi

echo "[+] M365 Tenant ID Resolver (v4 - Loop-Safe)"
echo "[+] Output CSV: $OUTPUT"
[[ "$DEBUG" == true ]] && echo "[+] Debug mode: Raw curl/JQ shown on first failure"
echo "[+] Processing... (Ctrl+C to stop)"
echo

resolve_tenant() {
    local domain="$1"
    domain=$(echo "$domain" | sed 's|https\?://||; s|/.*||; s/,.*//; s/[[:space:]]//g')  # Clean

    [[ -z "$domain" ]] && return

    echo -n "[ ] $domain ... "

    # Curl with fail-fast and verbose if debug
    local curl_opts=("-s" "-A" "Mozilla/5.0 (compatible; TenantResolver/1.0)" "--connect-timeout" "15" "--max-time" "30" "-f")
    [[ "$DEBUG" == true ]] && curl_opts+=("-v")
    local json
    json=$(curl "${curl_opts[@]}" \
        "https://login.microsoftonline.com/$domain/.well-known/openid-configuration" 2>/dev/null || echo "")

    if [[ -z "$json" || "$json" == "" ]]; then
        echo "${RED}No response (network/DNS?)${NC}"
        [[ "$DEBUG" == true ]] && echo "    Raw curl: (empty - check firewall/proxy)"
        ((FAIL++))
        return
    fi

    # Debug: Show raw if first failure or always in debug
    [[ "$DEBUG" == true ]] && echo "    Raw JSON preview: $(echo "$json" | head -c 200)... "

    # Safe jq: Extract tenant ID with fallbacks (no crash)
    local tenant_id=""
    tenant_id=$(echo "$json" | jq -r '
        def clean_id: gsub("/+$"; "") | split("/")[-1] | gsub("^[{}]+$"; "");
        (.issuer | clean_id // (.authorization_endpoint | clean_id) // (.token_endpoint | clean_id) // empty) |
        select(test("^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$"))
    ' 2>/dev/null || echo "")

    if [[ -n "$tenant_id" && "$tenant_id" != "null" && "$tenant_id" != "" ]]; then
        echo "${GREEN}✓ $tenant_id${NC}"
        printf '"%s","%s"\n' "$domain" "$tenant_id" >> "$TMP"
        ((SUCCESS++))
    else
        echo "${RED}✗ No valid ID${NC}"
        [[ "$DEBUG" == true ]] && echo "    JQ attempt: $(echo "$json" | jq -r '{issuer, authorization_endpoint}' 2>/dev/null || echo 'JQ failed')"
        ((FAIL++))
    fi
}

# Main input handling (loop-safe, no set -e)
if [[ $# -eq 1 && -f "$1" ]]; then
    # File
    while IFS= read -r domain || [[ -n "$domain" ]]; do
        resolve_tenant "$domain"
    done < "$1"
elif [[ $# -gt 0 ]]; then
    # Args
    for domain in "$@"; do
        resolve_tenant "$domain"
    done
elif [[ -t 0 ]]; then
    # Help
    cat << EOF
Usage:
  cat domains.txt | $0
  $0 domains.txt
  $0 example.com microsoft.com
  $0 --debug  # Verbose curl/JQ on issues
EOF
    exit 1
else
    # Pipe
    while IFS= read -r domain || [[ -n "$domain" ]]; do
        resolve_tenant "$domain"
    done
fi

# Build & sort CSV
if [[ -s "$TMP" ]]; then
    (printf "domain,tenant_id\n"; sort -t',' -k1 "$TMP" | uniq) > "$OUTPUT"
fi
rm -f "$TMP"

echo
echo "[+] Summary: $SUCCESS valid tenants, $FAIL failures"
echo "[+] CSV: $OUTPUT ($(wc -l < "$OUTPUT" 2>/dev/null || echo 0) lines)"
echo
echo "[+] Preview:"
if [[ -s "$OUTPUT" && $(wc -l < "$OUTPUT") -gt 1 ]]; then
    tail -n +2 "$OUTPUT" | head -5 | while IFS=',' read -r d t; do
        d=$(echo "$d" | sed 's/^"//; s/"$//')  # Unquote
        t=$(echo "$t" | sed 's/^"//; s/"$//')
        printf "  %-20s → %s\n" "$d" "${t:-N/A}"
    done
    [[ $(wc -l < "$OUTPUT") -gt 6 ]] && echo "  ... (more)"
else
    echo "  (No valid tenants - check debug output)"
fi
