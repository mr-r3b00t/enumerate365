#!/bin/bash
# ==================================================
# Office 365 / Microsoft 365 Tenant Enumeration Tool
# Public endpoints only - no credentials needed
# Author: Grok (2025)
# Requires: curl, jq
# ==================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check dependencies
command -v curl >/dev/null 2>&1 || { echo -e "${RED}Error: curl is required${NC}"; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo -e "${RED}Error: jq is required (install with: sudo apt install jq)${NC}"; exit 1; }

# Function to query a single domain
enumerate_domain() {
    local domain="$1"
    echo -e "${BLUE}Enumerating: $domain${NC}"
    echo -e "${YELLOW}────────────────────────────────────────────────${NC}"

    # 1. OpenID Configuration → Tenant ID (most reliable)
    echo -e "${GREEN}[+] OpenID Configuration (.well-known/openid-configuration)${NC}"
    local oidc_json
    oidc_json=$(curl -s --connect-timeout 10 \
        "https://login.microsoftonline.com/$domain/.well-known/openid-configuration" 2>/dev/null || echo "null")

    if [[ "$oidc_json" != "null" ]] && echo "$oidc_json" | jq -e . >/dev/null 2>&1; then
        local tenant_id
        tenant_id=$(echo "$oidc_json" | jq -r '.issuer // .authorization_endpoint // empty | split("/")[-2] // split("/")[-1]' | head -1)
        echo -e "    Tenant ID      : ${GREEN}$tenant_id${NC}"
    else
        echo -e "    ${RED}No OpenID metadata found (not an M365 tenant or blocked)${NC}"
        tenant_id="unknown"
    fi

    # 2. UserRealm endpoint (branding, auth type, federation)
    echo -e "${GREEN}[+] UserRealm Discovery (userrealm)${NC}"
    local userrealm_json
    userrealm_json=$(curl -s --connect-timeout 10 \
        "https://login.microsoftonline.com/common/userrealm/user@$domain?api-version=2.0" 2>/dev/null || echo "null")

    if [[ "$userrealm_json" != "null" ]] && echo "$userrealm_json" | jq -e . >/dev/null 2>&1; then
        echo "$userrealm_json" | jq -r '
            "    Tenant DisplayName : \(.DisplayName // "N/A")",
            "    Tenant Name        : \(.Name // "N/A")",
            "    Auth Type          : \(.AccountType // .CloudInstanceIssuerUri // "Unknown")",
            "    Federation         : \(.AuthURL // "Cloud-only (no ADFS)")",
            "    Seamless SSO       : \(.SeamlessSSOEnabled // false)"
        ' | sed 's/^/    /'
    else
        echo -e "    ${RED}UserRealm endpoint failed${NC}"
    fi

    # 3. ODC Federation Provider (alternative tenant ID + org name)
    echo -e "${GREEN}[+] ODC Federation Provider${NC}"
    local odc_json
    odc_json=$(curl -s --connect-timeout 10 \
        "https://odc.officeapps.live.com/odc/v2.1/federationprovider?domain=$domain" 2>/dev/null || echo "null")

    if [[ "$odc_json" != "null" ]] && echo "$odc_json" | jq -e . >/dev/null 2>&1; then
        echo "$odc_json" | jq -r '
            "    Tenant ID (ODC)    : \(.tenantid // "N/A")",
            "    Organization       : \(.organization // "N/A")",
            "    Auth Type (ODC)    : \(.authenticationtype // "N/A")"
        ' | sed 's/^/    /'
    else
        echo -e "    ${RED}ODC endpoint unavailable${NC}"
    fi

    echo -e "${YELLOW}────────────────────────────────────────────────${NC}\n"
}

# Main
echo -e "${BLUE}Microsoft 365 Tenant Enumeration Tool${NC}"
echo -e "Uses only public endpoints - no login required\n"

# Input handling
if [[ $# -eq 0 ]]; then
    echo -e "Usage: $0 <domain1> [domain2] [...]"
    echo -e "   or: cat domains.txt | $0"
    echo -e "\nExample: $0 contoso.com fabrikam.com microsoft.com"
    exit 1
fi

# If input is piped (e.g. cat list.txt | ./script.sh)
if [[ -t 0 ]]; then
    # Arguments provided
    for domain in "$@"; do
        domain=$(echo "$domain" | xargs)  # trim whitespace
        [[ -z "$domain" ]] && continue
        enumerate_domain "$domain"
    done
else
    # Input from pipe
    while IFS= read -r domain || [[ -n "$domain" ]]; do
        domain=$(echo "$domain" | xargs)
        [[ -z "$domain" ]] && continue
        enumerate_domain "$domain"
    done
fi

echo -e "${GREEN}Enumeration complete.${NC}"
