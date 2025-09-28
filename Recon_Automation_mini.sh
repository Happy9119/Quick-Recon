#!/bin/bash
# recon_simple.sh
# Minimal recon: subdomains -> live hosts/IPs -> nmap ports

set -euo pipefail

# ---- Colors ----
GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; RESET="\e[0m"

# ---- Required tools ----
REQUIRED_TOOLS=(subfinder httpx nmap)
for t in "${REQUIRED_TOOLS[@]}"; do
    command -v "$t" >/dev/null 2>&1 || { echo -e "${RED}[!] Missing $t${RESET}"; exit 1; }
done

# ---- 1. Take domain from CLI ----
if [ $# -ne 1 ]; then
    echo -e "${YELLOW}Usage:${RESET} $0 <target-domain>"
    exit 1
fi
DOMAIN="$1"

# ---- Output directories ----
BASE_DIR="RECON_OUTPUT/$DOMAIN"
mkdir -p "$BASE_DIR"
echo -e "${GREEN}[+] Results will be stored in $BASE_DIR${RESET}"

# ---- 2. Subdomain enumeration ----
echo -e "${YELLOW}[*] Enumerating subdomains with subfinder...${RESET}"
subfinder -d "$DOMAIN" -all -silent | sort -u > "$BASE_DIR/subdomains.txt"
echo -e "${GREEN}[+] $(wc -l < "$BASE_DIR/subdomains.txt") subdomains found${RESET}"

# ---- 3 & 4. Live hosts and IP details via httpx ----
echo -e "${YELLOW}[*] Probing live hosts with httpx...${RESET}"
# -ip outputs IP; we’ll parse to get unique IPs and subdomain+IP mapping
httpx -l "$BASE_DIR/subdomains.txt" -silent -ip -o "$BASE_DIR/httpx_full.txt"

# a) list of live subdomains (just the URL/host part)
awk '{print $1}' "$BASE_DIR/httpx_full.txt" > "$BASE_DIR/live_subdomains.txt"

# b) list of unique IPs
awk '{gsub(/\[|\]/,"",$2); print $2}' "$BASE_DIR/httpx_full.txt" | sort -u > "$BASE_DIR/unique_ips.txt"

# c) subdomain + IP mapping
awk '{gsub(/\[|\]/,""); print $1","$2}' "$BASE_DIR/httpx_full.txt" > "$BASE_DIR/subdomain_ip_map.csv"

echo -e "${GREEN}[+] Live hosts: $(wc -l < "$BASE_DIR/live_subdomains.txt")"
echo -e "${GREEN}[+] Unique IPs: $(wc -l < "$BASE_DIR/unique_ips.txt")${RESET}"

# ---- 5. Nmap basic scan ----
if [ -s "$BASE_DIR/unique_ips.txt" ]; then
    echo -e "${YELLOW}[*] Running nmap (top 1000 TCP ports) on unique IPs...${RESET}"
    nmap --min-rate=1000 -iL "$BASE_DIR/unique_ips.txt" -oN "$BASE_DIR/nmap_results.txt"
    echo -e "${GREEN}[+] Nmap scan complete: $BASE_DIR/nmap_results.txt${RESET}"
else
    echo -e "${RED}[!] No live IPs to scan${RESET}"
fi

echo -e "${GREEN}[✔] Recon finished for $DOMAIN${RESET}"

# ---- 6. Quick HTML summary ----
REPORT="$BASE_DIR/report.html"
cat > "$REPORT" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Recon Report – $DOMAIN</title>
<style>
 body { font-family: Arial, sans-serif; background:#f7f7f7; padding:20px; }
 h1 { color:#333; }
 h2 { color:#555; border-bottom:1px solid #ccc; }
 pre { background:#fff; padding:10px; border:1px solid #ddd; overflow:auto; }
</style>
</head>
<body>
<h1>Recon Summary for $DOMAIN</h1>

<h2>Stats</h2>
<ul>
  <li>Total subdomains found: $(wc -l < "$BASE_DIR/subdomains.txt")</li>
  <li>Live subdomains: $(wc -l < "$BASE_DIR/live_subdomains.txt")</li>
  <li>Unique IPs: $(wc -l < "$BASE_DIR/unique_ips.txt")</li>
</ul>

<h2>Live Subdomains</h2>
<pre>$(cat "$BASE_DIR/live_subdomains.txt")</pre>

<h2>Subdomain → IP Map</h2>
<pre>$(cat "$BASE_DIR/subdomain_ip_map.csv")</pre>

<h2>Nmap Results (Top 1–1000 Ports)</h2>
<pre>$(cat "$BASE_DIR/nmap_results.txt")</pre>

<p><em>Report generated on $(date)</em></p>
</body>
</html>
EOF

echo -e "${GREEN}[+] HTML report created: $REPORT${RESET}"
