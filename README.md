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
  1. Validates prerequisites (root, Ubuntu 22/24)
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
