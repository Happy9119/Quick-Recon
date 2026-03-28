#!/bin/bash
# recon_simple.sh
# Minimal recon: subdomains -> live hosts/IPs -> nmap ports + Wayback URLs

set -euo pipefail

# ---- Colors ----
GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; RESET="\e[0m"

# ---- Required tools ----
REQUIRED_TOOLS=(subfinder httpx nmap curl grep awk sort wc)
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

# ---- 2.5 Wayback URL Collection ----
echo -e "${YELLOW}[*] Collecting Wayback URLs...${RESET}"

WAYBACK_FILE="$BASE_DIR/web_archive_urls.txt"
WAYBACK_LIVE="$BASE_DIR/live_urls.txt"
WAYBACK_TEMP="$BASE_DIR/raw_live_wayback.txt"

WAYBACK_URL="https://web.archive.org/cdx/search/cdx?url=${DOMAIN}&matchType=domain&fl=original&collapse=urlkey&limit=10000&filter=!original:.*\\.(jpg|jpeg|png|gif|svg|css|js|woff|woff2|ttf|ico|mp4|mp3|avi|pdf)$"

curl -s "$WAYBACK_URL" | sort -u > "$WAYBACK_FILE"

WB_TOTAL=$(wc -l < "$WAYBACK_FILE")
echo -e "${GREEN}[+] Wayback URLs collected: $WB_TOTAL${RESET}"

# ---- Pre-filter (remove static files incl. query bypass) ----
grep -Evi "\.(jpg|jpeg|png|gif|svg|css|js|woff|woff2|ttf|ico|mp4|mp3|avi|pdf|axd)(\?|$)" "$WAYBACK_FILE" > "$WAYBACK_FILE.tmp"
mv "$WAYBACK_FILE.tmp" "$WAYBACK_FILE"

echo -e "${YELLOW}[*] Probing Wayback URLs with httpx...${RESET}"

httpx -l "$WAYBACK_FILE" \
    -mc 200 \
    -silent \
    -threads 100 \
    -timeout 5 \
    -o "$WAYBACK_TEMP"

# ---- Post-filter (strict cleanup again) ----
grep -Evi "\.(jpg|jpeg|png|gif|svg|css|js|woff|woff2|ttf|ico|mp4|mp3|avi|pdf|axd)(\?|$)" "$WAYBACK_TEMP" > "$WAYBACK_LIVE"

rm -f "$WAYBACK_TEMP"

WB_LIVE_COUNT=$(wc -l < "$WAYBACK_LIVE")
echo -e "${GREEN}[+] Clean Wayback live URLs: $WB_LIVE_COUNT${RESET}"

# ---- 3 & 4. Live hosts and IP details via httpx ----
echo -e "${YELLOW}[*] Probing live hosts with httpx...${RESET}"
httpx -l "$BASE_DIR/subdomains.txt" -silent -ip -o "$BASE_DIR/httpx_full.txt"

# a) list of live subdomains
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
  <li>Wayback URLs collected: $WB_TOTAL</li>
  <li>Wayback live URLs (filtered): $WB_LIVE_COUNT</li>
</ul>

<h2>Live Subdomains</h2>
<pre>$(cat "$BASE_DIR/live_subdomains.txt")</pre>

<h2>Unique IP List</h2>
<pre>$(cat "$BASE_DIR/unique_ips.txt")</pre>

<h2>Subdomain → IP Map</h2>
<pre>$(cat "$BASE_DIR/subdomain_ip_map.csv")</pre>

<h2>Wayback Live URLs (Filtered)</h2>
<pre>$(cat "$BASE_DIR/live_urls.txt")</pre>

<h2>Nmap Results (Top 1–1000 Ports)</h2>
<pre>$(cat "$BASE_DIR/nmap_results.txt")</pre>

<p><em>Report generated on $(date)</em></p>
</body>
</html>
EOF

echo -e "${GREEN}[+] HTML report created: $REPORT${RESET}"