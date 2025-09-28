# Domain Recon Script

A minimal Bash pipeline for fast reconnaissance:

* Enumerates subdomains with [subfinder](https://github.com/projectdiscovery/subfinder)
* Probes live hosts & gathers IPs with [httpx](https://github.com/projectdiscovery/httpx)
* Runs a quick top-1000 TCP port scan with nmap
* Generates a single-page HTML summary

## Dependencies

* subfinder
* httpx
* nmap

Install on macOS (Homebrew):

```bash
brew install subfinder httpx nmap
