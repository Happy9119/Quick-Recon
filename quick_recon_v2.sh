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

# ---- Pre-filter ----
grep -Evi "\.(jpg|jpeg|png|gif|svg|css|js|woff|woff2|ttf|ico|mp4|mp3|avi|pdf|axd)(\?|$)" "$WAYBACK_FILE" > "$WAYBACK_FILE.tmp"
mv "$WAYBACK_FILE.tmp" "$WAYBACK_FILE"

echo -e "${YELLOW}[*] Probing Wayback URLs with httpx...${RESET}"

httpx -l "$WAYBACK_FILE" \
    -mc 200 \
    -silent \
    -threads 100 \
    -timeout 5 \
    -o "$WAYBACK_TEMP"

# ---- Post-filter ----
grep -Evi "\.(jpg|jpeg|png|gif|svg|css|js|woff|woff2|ttf|ico|mp4|mp3|avi|pdf|axd)(\?|$)" "$WAYBACK_TEMP" > "$WAYBACK_LIVE"
rm -f "$WAYBACK_TEMP"

WB_LIVE_COUNT=$(wc -l < "$WAYBACK_LIVE")
echo -e "${GREEN}[+] Clean Wayback live URLs: $WB_LIVE_COUNT${RESET}"

# ---- 3 & 4. Live hosts ----
echo -e "${YELLOW}[*] Probing live hosts with httpx...${RESET}"
httpx -l "$BASE_DIR/subdomains.txt" -silent -ip -o "$BASE_DIR/httpx_full.txt"

awk '{print $1}' "$BASE_DIR/httpx_full.txt" > "$BASE_DIR/live_subdomains.txt"
awk '{gsub(/\[|\]/,"",$2); print $2}' "$BASE_DIR/httpx_full.txt" | sort -u > "$BASE_DIR/unique_ips.txt"
awk '{gsub(/\[|\]/,""); print $1","$2}' "$BASE_DIR/httpx_full.txt" > "$BASE_DIR/subdomain_ip_map.csv"

echo -e "${GREEN}[+] Live hosts: $(wc -l < "$BASE_DIR/live_subdomains.txt")"
echo -e "${GREEN}[+] Unique IPs: $(wc -l < "$BASE_DIR/unique_ips.txt")${RESET}"

# ---- 5. Nmap ----
if [ -s "$BASE_DIR/unique_ips.txt" ]; then
    echo -e "${YELLOW}[*] Running nmap...${RESET}"
    nmap --min-rate=1000 -iL "$BASE_DIR/unique_ips.txt" -oN "$BASE_DIR/nmap_results.txt"
else
    echo -e "${RED}[!] No live IPs to scan${RESET}"
fi

echo -e "${GREEN}[✔] Recon finished for $DOMAIN${RESET}"

# ---- 6. Dashboard HTML ----
REPORT="$BASE_DIR/report.html"

cat > "$REPORT" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Recon Dashboard – $DOMAIN</title>

<style>
body {
    margin: 0;
    font-family: 'Segoe UI', Arial;
    background: #0f172a;
    color: #e2e8f0;
}

.header {
    background: #020617;
    padding: 20px;
    border-bottom: 1px solid #1e293b;
}
.header h1 { color:#38bdf8; margin:0; }

.container { width:95%; margin:auto; padding:20px 0; }

.stats {
    display:grid;
    grid-template-columns:repeat(auto-fit,minmax(200px,1fr));
    gap:15px;
}

.card {
    background:#1e293b;
    padding:15px;
    border-radius:10px;
}
.card h3 { margin:0; font-size:13px; color:#94a3b8; }
.card p { font-size:22px; color:#22c55e; margin:5px 0 0; }

details {
    margin-top:15px;
    background:#1e293b;
    padding:10px;
    border-radius:10px;
}
summary {
    cursor:pointer;
    font-weight:bold;
    color:#38bdf8;
}
summary::before { content:"➖ "; }
details:not([open]) summary::before { content:"➕ "; }

pre {
    background:#020617;
    padding:10px;
    border-radius:6px;
    max-height:400px;
    overflow:auto;
    margin-top:10px;
}

.footer {
    text-align:center;
    margin-top:20px;
    color:#64748b;
}
</style>
</head>

<body>

<div class="header">
<h1>Recon Dashboard – $DOMAIN</h1>
</div>

<div class="container">

<div class="stats">
<div class="card"><h3>Subdomains</h3><p>$(wc -l < "$BASE_DIR/subdomains.txt")</p></div>
<div class="card"><h3>Live Hosts</h3><p>$(wc -l < "$BASE_DIR/live_subdomains.txt")</p></div>
<div class="card"><h3>IPs</h3><p>$(wc -l < "$BASE_DIR/unique_ips.txt")</p></div>
<div class="card"><h3>Wayback</h3><p>$WB_TOTAL</p></div>
<div class="card"><h3>Live Wayback</h3><p>$WB_LIVE_COUNT</p></div>
</div>

<details open><summary>Live Subdomains</summary>
<pre>$(cat "$BASE_DIR/live_subdomains.txt")</pre></details>

<details open><summary>Unique IPs</summary>
<pre>$(cat "$BASE_DIR/unique_ips.txt")</pre></details>

<details open><summary>Subdomain → IP Map</summary>
<pre>$(cat "$BASE_DIR/subdomain_ip_map.csv")</pre></details>

<details open><summary>Wayback Live URLs</summary>
<pre>$(cat "$BASE_DIR/live_urls.txt")</pre></details>

<details open><summary>Nmap Results</summary>
<pre>$(cat "$BASE_DIR/nmap_results.txt")</pre></details>

<div class="footer">
Report generated on $(date)
</div>

</div>
</body>
</html>
EOF

echo -e "${GREEN}[+] HTML report created: $REPORT${RESET}"