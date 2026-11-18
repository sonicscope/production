Quick Deployment Guide for SonicScope Latest Multvendor engine.
---------------------------------------------------------------  
  # 1. Create a directory, put their licence.env in it
  mkdir sonicscope && cd sonicscope
  # (copy licence.env here)

  # 2. Run the installer
  curl -fsSL https://raw.githubusercontent.com/sonicscope/production/main/deploy.sh | sudo bash
  # OR download deploy.sh first alongside licence.env:
  sudo bash deploy.sh

  What the deploy script does:
  1. Validates prerequisites (root, Ubuntu 22.04+ or Debian 13+)
  2. Reads and validates licence.env — shows the customer details before starting
  3. Downloads ss-multivendor-latest.tar.gz from GitHub with a live spinner
  4. Runs install.sh (DB, venv, systemd, TLS certs)
  5. Patches licence + SMTP from licence.env into collector.env
  6. Starts the collector and verifies the licence is accepted
  7. Downloads GeoIP automatically if MAXMIND_KEY is in licence.env
  8. Installs Grafana dashboards
  9. Installs the Reports UI
  10. Shows a final summary box with URLs, default credentials, licence info, and whether flows are already arriving

  Optional keys the customer can add to licence.env:
  MAXMIND_KEY=<free MaxMind key>          # enables GeoIP enrichment automatically
  
  SMTP_HOST=smtp.their-isp.co.za          # pre-configures email delivery
  
  SMTP_PORT=465
  
  SMTP_USER=reports@customer.co.za
  
  SMTP_PASSWORD=<password>
  
  SMTP_FROM=reports@customer.co.za
  
  SMTP_USE_TLS=true

Third-party data
----------------
Web categories for vendors without native categories (e.g. OPNsense) use the UT1 blacklists
maintained by the Université Toulouse 1 Capitole (https://dsi.ut-capitole.fr/blacklists/),
licensed CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/). The lists are
downloaded daily and mapped to SonicScope category names; the derived category data remains
under CC BY-SA 4.0. SonicWall, Fortinet, Palo Alto and Sophos use their native categories.

Supported operating systems: Ubuntu 22.04 / 24.04 / 26.04 LTS and Debian 13 (trixie, new in 1.4.4; installer fixes through 1.4.6). New in 1.5.0: Investigate, a bring-your-own-key AI assistant for MSP staff (Settings > AI Assistant).
