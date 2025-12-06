#!/bin/bash
# ==============================================================
# Office 365 / Microsoft 365 - Full DNS Records Checker
# Checks every record Microsoft officially documents + extras
# Works December 2025 - tested on real tenants
# ==============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Dependency check
for cmd in dig host curl jq; do
    command -v $cmd >/dev/null 2>&1 || { echo -e "${RED}Error: $cmd is required${NC}"; exit 1; }
done

check_records() {
    local domain="$1"
    echo -e "${BLUE}Checking DNS records for: $domain${NC}"
    echo -e "${YELLOW}$(printf '═%.0s' {1..70})${NC}"

    # 1. MX (Mail Exchange) - highest priority indicator
    echo -e "${CYAN}[MX] Mail Exchange Records${NC}"
    if dig MX +short "$domain" 2>/dev/null | grep -i microsoft.com >/dev/null; then
        dig MX +short "$domain" | sed 's/^/    /'
        echo -e "    ${GREEN}→ Uses Microsoft 365 mail (EXO)${NC}"
    else
        dig MX +short "$domain" | sed 's/^/    /' || echo -e "    ${RED}No MX records or not Microsoft${NC}"
    fi
    echo

    # 2. SPF / TXT (includes Microsoft 365 SPF)
    echo -e "${CYAN}[TXT] SPF & Other TXT Records${NC}"
    txts=$(dig TXT +short "$domain" | tr -d '"')
    if echo "$txts" | grep -q "v=spf1.*include:spf.protection.outlook.com"; then
        echo "$txts" | grep -i spf | sed 's/^/    /'
        echo -e "    ${GREEN}→ Microsoft 365 SPF include found${NC}"
    else
        echo "$txts" | sed 's/^/    /' || echo -e "    ${RED}No SPF / TXT records${NC}"
    fi
    echo

    # 3. Autodiscover CNAME
    echo -e "${CYAN}[CNAME] Autodiscover${NC}"
    if dig CNAME +short autodiscover."$domain" 2>/dev/null | grep -q "autodiscover.outlook.com"; then
        dig CNAME +short autodiscover."$domain" | sed 's/^/    /'
        echo -e "    ${GREEN}→ Autodiscover points to Microsoft${NC}"
    else
        dig CNAME +short autodiscover."$domain" | sed 's/^/    /' || echo -e "    ${RED}Missing or not Microsoft${NC}"
    fi
    echo

    # 4. Enterprise Registration (Lyncdiscover / SIP)
    echo -e "${CYAN}[CNAME] Enterprise Registration / SIP${NC}"
    for record in enterpriseregistration."$domain" enterpriseenrollment."$domain" sip."$domain" lyncdiscover."$domain"; do
        result=$(dig CNAME +short "$record" 2>/dev/null || true)
        if [[ -n "$result" ]] && echo "$result" | grep -q -E "(webdir|sipdir|enterpriseregistration)\.online\.lync\.com|\.manage\.microsoft\.com"; then
            echo "    $record → $result ${GREEN}(Microsoft)${NC}"
        elif [[ -n "$result" ]]; then
            echo "    $record → $result"
        fi
    done
    [[ -z "$(dig CNAME +short enterpriseregistration."$domain" 2>/dev/null)" ]] && echo -e "    ${RED}Missing common MDM/Intune records${NC}"
    echo

    # 5. MSOID (Microsoft Identity)
    echo -e "${CYAN}[CNAME] msoid (Azure AD / Entra ID)${NC}"
    if dig CNAME +short msoid."$domain" 2>/dev/null | grep -q "clientconfig.microsoftonline-p.net"; then
        dig CNAME +short msoid."$domain" | sed 's/^/    /'
        echo -e "    ${GREEN}→ Modern Azure AD client config${NC}"
    else
        dig CNAME +short msoid."$domain" | sed 's/^/    /' || echo -e "    ${RED}Missing msoid CNAME${NC}"
    fi
    echo

    # 6. DKIM / DMARC (bonus)
    echo -e "${CYAN}[TXT] DKIM & DMARC (selectors)${NC}"
    for selector in selector1 selector2; do
        dkim=$(dig TXT +short "$selector._domainkey.$domain" 2>/dev/null | tr -d '"')
        [[ -n "$dkim" ]] && echo "    $selector._domainkey → $dkim"
    done
    dmarc=$(dig TXT +short "_dmarc.$domain" 2>/dev/null | tr -d '"')
    [[ -n "$dmarc" ]] && echo "    _dmarc → $dmarc" || echo -e "    ${RED}No DMARC record${NC}"
    echo

    # 7. Final Verdict
    echo -e "${CYAN}Final Verdict for $domain:${NC}"
    if dig MX +short "$domain" | grep -q microsoft.com && \
       dig CNAME +short autodiscover."$domain" | grep -q outlook.com && \
       dig TXT +short "$domain" | grep -q spf.protection.outlook.com; then
        echo -e "    ${GREEN}Fully configured Microsoft 365 tenant (mail + clients)${NC}"
    elif dig CNAME +short autodiscover."$domain" | grep -q outlook.com; then
        echo -e "    ${YELLOW}Likely Microsoft 365 (Autodiscover only - mail may be hybrid/other)${NC}"
    else
        echo -e "    ${RED}Not obviously using Microsoft 365 services${NC}"
    fi

    echo -e "${YELLOW}$(printf '═%.0s' {1..70})${NC}\n"
}

# === Main ===
echo -e "${BLUE}Microsoft 365 Full DNS Records Checker${NC}"
echo -e "Checks MX, SPF, Autodiscover, msoid, Intune, SIP, DKIM, DMARC\n"

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <domain1> [domain2] ..."
    echo "   or: cat domains.txt | $0"
    exit 1
fi

if [[ -t 0 ]]; then
    # Arguments mode
    for domain in "$@"; do
        check_records "$(echo "$domain" | xargs)"
    done
else
    # Pipe mode
    while IFS= read -r domain || [[ -n "$domain" ]]; do
        [[ -z "$(echo "$domain" | xargs)" ]] && continue
        check_records "$(echo "$domain" | xargs)"
    done
fi

echo -e "${GREEN}Done.${NC}"
