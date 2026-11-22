#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║           SonicScope Multi-Vendor — One-Shot Deployment Script           ║
# ║                                                                          ║
# ║  Usage:                                                                  ║
# ║    1. Place this script and your  licence.env  in the same directory     ║
# ║    2. Run:  sudo bash deploy.sh                                          ║
# ║                                                                          ║
# ║  Optional keys in licence.env:                                           ║
# ║    MAXMIND_KEY=<key>   → auto-downloads GeoIP databases                  ║
# ║    SMTP_HOST / SMTP_PORT / SMTP_USER / SMTP_PASSWORD / SMTP_FROM         ║
# ║                        → pre-configures email delivery                   ║
# ╚══════════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ── Colour palette ─────────────────────────────────────────────────────────
TEAL='\033[38;5;43m'; BLUE='\033[38;5;69m'; WHITE='\033[1;37m'
DIM='\033[2m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BOLD='\033[1m'; NC='\033[0m'

TOTAL_STEPS=8

# ── Helper functions ────────────────────────────────────────────────────────

banner() {
    # clear needs a terminal (TERM); don't abort under automation / non-interactive ssh
    if [[ -t 1 && -n "${TERM:-}" ]]; then clear 2>/dev/null || true; fi
    echo
    echo -e "${TEAL}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${TEAL}  ║${NC}                                                                  ${TEAL}║${NC}"
    echo -e "${TEAL}  ║${NC}   ${BOLD}${WHITE}◈  S O N I C S C O P E  ◈${NC}                                      ${TEAL}║${NC}"
    echo -e "${TEAL}  ║${NC}      ${DIM}Multi-Vendor Network Reporter${NC}                               ${TEAL}║${NC}"
    echo -e "${TEAL}  ║${NC}      ${DIM}Deployment Installer${NC}                                        ${TEAL}║${NC}"
    echo -e "${TEAL}  ║${NC}                                                                  ${TEAL}║${NC}"
    echo -e "${TEAL}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

step() {
    local n="$1" msg="$2"
    echo
    echo -e "  ${BLUE}┌──────────────────────────────────────────────────────────────────┐${NC}"
    printf  "  ${BLUE}│${NC}  ${BOLD}Step %s of %s${NC}  —  %-48s${BLUE}│${NC}\n" "$n" "$TOTAL_STEPS" "$msg"
    echo -e "  ${BLUE}└──────────────────────────────────────────────────────────────────┘${NC}"
    echo
}

ok()      { echo -e "  ${GREEN}  ✓${NC}  $*"; }
info()    { echo -e "  ${TEAL}  →${NC}  $*"; }
warn()    { echo -e "  ${YELLOW}  ⚠${NC}  $*"; }
fail()    { echo -e "  ${RED}  ✗${NC}  $*"; echo; exit 1; }
hdr()     { echo -e "\n  ${DIM}────────────────────────────────────────────${NC}"; }

spinner() {
    local pid=$1 msg="$2"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${TEAL}  %s${NC}  %s..." "${frames[$i]}" "$msg"
        i=$(( (i+1) % ${#frames[@]} ))
        sleep 0.12
    done
    printf "\r"
}

progress_bar() {
    local label="$1" total="${2:-20}"
    printf "  ${TEAL}  [${NC}"
    for ((i=0; i<total; i++)); do
        printf "${TEAL}█${NC}"
        sleep 0.04
    done
    printf "${TEAL}]${NC}  %s\n" "$label"
}

read_env() {
    local file="$1" key="$2" default="${3:-}"
    grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d "'\"\r" || echo "$default"
}

patch_env() {
    local file="$1" key="$2" value="$3"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

# ── Sanity checks ───────────────────────────────────────────────────────────

banner

echo -e "  ${DIM}Checking system requirements...${NC}"
echo

[[ "$(id -u)" -ne 0 ]] && fail "This script must be run as root. Try: sudo bash deploy.sh"

# Detect OS: Ubuntu 22.04+ or Debian 13+
OS_ID=$(grep -E '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
OS_VER=$(grep -E '^VERSION_ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
OS_MAJOR=$(echo "$OS_VER" | cut -d'.' -f1)
case "$OS_ID" in
    ubuntu)
        [[ "$OS_MAJOR" =~ ^[0-9]+$ && "$OS_MAJOR" -ge 22 ]] \
            || fail "Ubuntu $OS_VER is not supported. Requires Ubuntu 22.04 or later."
        ok "Ubuntu $OS_VER" ;;
    debian)
        [[ "$OS_MAJOR" =~ ^[0-9]+$ && "$OS_MAJOR" -ge 13 ]] \
            || fail "Debian $OS_VER is not supported. Requires Debian 13 (trixie) or later."
        ok "Debian $OS_VER" ;;
    *)
        fail "This installer requires Ubuntu 22.04+ or Debian 13+." ;;
esac

# Locate licence.env — same directory as this script.
# When piped via "curl | bash", BASH_SOURCE array is completely unset and
# $0 is just "bash". Fall back to the current working directory so that
# licence.env is found wherever the command was run.
if [[ -n "${BASH_SOURCE+x}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$(pwd)"
fi
LICENCE_ENV="${SCRIPT_DIR}/licence.env"

# An existing SonicScope install is upgraded in place (scripts/upgrade.sh: version gate, backups,
# automatic rollback). A new install needs licence.env; an upgrade keeps the stored licence and
# only applies licence.env when one is supplied and differs.
EXISTING_INSTALL=false
if [[ -f /opt/ss-multivendor/VERSION || -f /opt/ss-multivendor/main.py ]] && [[ -f /etc/ss-multivendor/collector.env ]]; then
    EXISTING_INSTALL=true
    info "Existing SonicScope installation detected: this run will UPGRADE it (data and settings are kept)"
fi
if [[ ! -f "$LICENCE_ENV" ]]; then
    $EXISTING_INSTALL || fail "licence.env not found in $SCRIPT_DIR — please place your licence file next to deploy.sh"
    info "No licence.env supplied: the stored licence is kept"
fi
[[ -f "$LICENCE_ENV" ]] && ok "Licence file: $LICENCE_ENV"

# Parse licence fields
if [[ -f "$LICENCE_ENV" ]]; then
LIC_KEY=$(read_env "$LICENCE_ENV" "SONICSCOPE_LICENSE")
LIC_PRODUCT=$(read_env "$LICENCE_ENV" "SONICSCOPE_PRODUCT" "SS-MULTIVENDOR")
LIC_CUSTOMER=$(read_env "$LICENCE_ENV" "SONICSCOPE_CUSTOMER_ID")
LIC_EXPIRY=$(read_env "$LICENCE_ENV" "SONICSCOPE_EXPIRY")
LIC_SENSORS=$(read_env "$LICENCE_ENV" "SONICSCOPE_MAX_SENSORS" "1")

if [[ -f "$LICENCE_ENV" ]]; then
[[ -z "$LIC_KEY" ]]      && fail "SONICSCOPE_LICENSE is missing from licence.env"
[[ -z "$LIC_CUSTOMER" ]] && fail "SONICSCOPE_CUSTOMER_ID is missing from licence.env"
[[ -z "$LIC_EXPIRY" ]]   && fail "SONICSCOPE_EXPIRY is missing from licence.env"
fi

ok "Licence valid for: ${BOLD}$LIC_CUSTOMER${NC} — expires ${LIC_EXPIRY} — ${LIC_SENSORS} sensor(s)"
else
    LIC_KEY=""; LIC_PRODUCT=""; LIC_CUSTOMER="(stored licence)"; LIC_EXPIRY="(unchanged)"; LIC_SENSORS="-"
fi

# Optional fields
MAXMIND_KEY=$(read_env "$LICENCE_ENV" "MAXMIND_KEY")
SMTP_HOST=$(read_env "$LICENCE_ENV" "SMTP_HOST")
SMTP_PORT=$(read_env "$LICENCE_ENV" "SMTP_PORT" "465")
SMTP_USER=$(read_env "$LICENCE_ENV" "SMTP_USER")
SMTP_PASS=$(read_env "$LICENCE_ENV" "SMTP_PASSWORD")
SMTP_FROM=$(read_env "$LICENCE_ENV" "SMTP_FROM")
SMTP_TLS=$(read_env "$LICENCE_ENV" "SMTP_USE_TLS" "true")

[[ -n "$MAXMIND_KEY" ]] && ok "MaxMind key found — GeoIP will be downloaded automatically" \
                        || warn "MAXMIND_KEY not in licence.env — GeoIP enrichment will be disabled"
[[ -n "$SMTP_HOST" ]]   && ok "SMTP configured: $SMTP_HOST" \
                        || warn "SMTP_HOST not in licence.env — scheduled report emails disabled"

# ── Deployment plan ─────────────────────────────────────────────────────────

echo
echo -e "  ${TEAL}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${TEAL}║${NC}  ${BOLD}Deployment Plan${NC}                                                 ${TEAL}║${NC}"
echo -e "  ${TEAL}╠══════════════════════════════════════════════════════════════════╣${NC}"
printf  "  ${TEAL}║${NC}  %-64s${TEAL}║${NC}\n" "Customer:  $LIC_CUSTOMER"
printf  "  ${TEAL}║${NC}  %-64s${TEAL}║${NC}\n" "Licence:   expires $LIC_EXPIRY, $LIC_SENSORS sensor(s)"
printf  "  ${TEAL}║${NC}  %-64s${TEAL}║${NC}\n" "GeoIP:     $([ -n "$MAXMIND_KEY" ] && echo "Enabled (MaxMind)" || echo "Disabled — add MAXMIND_KEY to licence.env")"
printf  "  ${TEAL}║${NC}  %-64s${TEAL}║${NC}\n" "Email:     $([ -n "$SMTP_HOST" ] && echo "$SMTP_HOST" || echo "Disabled — add SMTP_HOST to licence.env")"
echo -e "  ${TEAL}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "  Press ${BOLD}Enter${NC} to begin deployment or ${BOLD}Ctrl+C${NC} to abort."
# Read from /dev/tty so the prompt works when the script is piped via curl | bash.
# Without this, bash and read compete for the same stdin pipe, causing read to
# consume script lines and skip them during execution.
read -r </dev/tty 2>/dev/null || true

# ── Step 1: Download ─────────────────────────────────────────────────────────

step 1 "Downloading SonicScope"

# Minimal Debian images ship without curl (Ubuntu server images include it).
if ! command -v curl >/dev/null 2>&1; then
    info "Installing curl (required to download the package)..."
    apt-get update -qq >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates >/dev/null 2>&1 \
        || fail "Could not install curl. Install it manually (apt-get install curl) and re-run."
fi

REPO_URL="https://raw.githubusercontent.com/sonicscope/production/main"
TARBALL="ss-multivendor-latest.tar.gz"
DOWNLOAD_DIR=$(mktemp -d /tmp/sonicscope_deploy_XXXXXX)
TARBALL_PATH="$DOWNLOAD_DIR/$TARBALL"

# SS_LOCAL_TARBALL=/path/to/ss-multivendor-X.tar.gz installs or upgrades from a local file
# instead of downloading (air-gapped hosts, release-candidate testing).
if [[ -n "${SS_LOCAL_TARBALL:-}" ]]; then
    [[ -s "$SS_LOCAL_TARBALL" ]] || fail "SS_LOCAL_TARBALL is set but '$SS_LOCAL_TARBALL' is not a readable file."
    info "Source: local file $SS_LOCAL_TARBALL"
    cp "$SS_LOCAL_TARBALL" "$TARBALL_PATH"
else
info "Source: github.com/sonicscope/production"
info "Package: $TARBALL"

# Redirect stdin to /dev/null so the background curl does not inherit the
# script pipe when this script is run via curl | bash.
(curl -fsSL --connect-timeout 30 --retry 3 --retry-delay 5 --speed-time 60 --speed-limit 1024 \
    "${REPO_URL}/${TARBALL}" -o "$TARBALL_PATH" </dev/null) &
DL_PID=$!
spinner $DL_PID "Downloading"
wait $DL_PID || fail "Download failed. Check your internet connection and that github.com/sonicscope/production is accessible."
fi

[[ -s "$TARBALL_PATH" ]] || fail "Downloaded file is empty — possible network error or repository access issue."

# Verify the file is a valid gzip archive before attempting to read it.
# Show the actual file type in the error to help diagnose download issues
# (e.g. GitHub returning HTML, an LFS pointer, or a truncated file).
if ! gzip -t "$TARBALL_PATH" 2>/dev/null; then
    fail "Downloaded file is not a valid gzip archive. Got: $(file "$TARBALL_PATH" 2>&1 | cut -d: -f2-). Check network connectivity and try again."
fi

# Detect version: use sed -n '1p' (reads all tar output) rather than head -1
# to avoid sending SIGPIPE to tar which triggers pipefail even on success.
DETECTED_VER=$(tar -tzf "$TARBALL_PATH" 2>/dev/null | sed -n '1p' | cut -d'/' -f1 | sed 's/ss-multivendor-//')
[[ -n "$DETECTED_VER" ]] || fail "Could not detect version from package — tarball may be corrupt."
ok "Downloaded: ss-multivendor ${DETECTED_VER} ($(du -sh "$TARBALL_PATH" | cut -f1))"

# ── Step 2: Extract ──────────────────────────────────────────────────────────

step 2 "Extracting package"

(tar -xzf "$TARBALL_PATH" -C "$DOWNLOAD_DIR") &
spinner $! "Extracting"
wait $!

EXTRACT_DIR="$DOWNLOAD_DIR/ss-multivendor-${DETECTED_VER}"
[[ -d "$EXTRACT_DIR" ]] || fail "Extraction failed — directory not found: $EXTRACT_DIR"
ok "Extracted to: $EXTRACT_DIR"

# ── Upgrade path (existing installation) ──────────────────────────────────────
# Delegates to scripts/upgrade.sh: version gate, rollback copies, config backup, update.sh,
# health checks with automatic rollback, TimescaleDB extension update. The first-time steps
# below (system install, database, TLS, admin account, Grafana password) are NOT run.
if $EXISTING_INSTALL; then
    echo
    echo -e "  ${BOLD}Upgrading the existing installation${NC}"
    echo -e "  ${DIM}Backups are taken first. If the health checks fail afterwards the upgrade rolls back by itself.${NC}"
    echo
    UPG_ARGS=(--yes)
    [[ -f "$LICENCE_ENV" ]] && UPG_ARGS+=(--apply-licence "$LICENCE_ENV")
    if bash "$EXTRACT_DIR/scripts/upgrade.sh" "${UPG_ARGS[@]}"; then
        if [[ -n "$MAXMIND_KEY" && -f "$EXTRACT_DIR/scripts/download-geoip.sh" ]]; then
            info "Refreshing GeoIP databases (MAXMIND_KEY supplied)"
            (bash "$EXTRACT_DIR/scripts/download-geoip.sh" "$MAXMIND_KEY" > /tmp/ss_geoip.log 2>&1 \
                && systemctl restart ss-collector) || warn "GeoIP refresh failed — see /tmp/ss_geoip.log"
        fi
        rm -rf "$DOWNLOAD_DIR"
        echo
        ok "Upgrade finished. Log: /var/log/ss-multivendor/upgrade-*.log"
        exit 0
    fi
    fail "The upgrade did not complete (it was rolled back where possible). See /var/log/ss-multivendor/upgrade-*.log and the messages above."
fi

# ── Step 3: System install ───────────────────────────────────────────────────

step 3 "Installing system packages and database"

info "This step installs PostgreSQL, TimescaleDB and Python packages, then creates"
info "the database schema — usually ~2–5 minutes. The installer normalises slow"
info "regional mirrors and fails loud (with the log) if Postgres won't restart, so"
info "it should not hang. Follow progress in /tmp/ss_install.log."
echo

(bash "$EXTRACT_DIR/scripts/install.sh" > /tmp/ss_install.log 2>&1) &
INSTALL_PID=$!
spinner $INSTALL_PID "Installing (see /tmp/ss_install.log for details)"
wait $INSTALL_PID || {
    echo
    fail "install.sh failed. Check /tmp/ss_install.log for details."
}

ok "System packages installed"
ok "PostgreSQL + TimescaleDB configured"
ok "Application deployed to /opt/ss-multivendor/"
ok "Service user ss-collector created"
ok "TLS certificate generated"
ok "ss-collector service installed and enabled"

# ── Step 4: Apply licence ────────────────────────────────────────────────────

step 4 "Applying licence and configuration"

CONFIG_FILE="/etc/ss-multivendor/collector.env"
[[ -f "$CONFIG_FILE" ]] || fail "collector.env not found — install.sh may have failed"

info "Writing licence to $CONFIG_FILE"

patch_env "$CONFIG_FILE" "SONICSCOPE_LICENSE"     "$LIC_KEY"
patch_env "$CONFIG_FILE" "SONICSCOPE_PRODUCT"     "$LIC_PRODUCT"
patch_env "$CONFIG_FILE" "SONICSCOPE_CUSTOMER_ID" "$LIC_CUSTOMER"
patch_env "$CONFIG_FILE" "SONICSCOPE_EXPIRY"      "$LIC_EXPIRY"
patch_env "$CONFIG_FILE" "SONICSCOPE_MAX_SENSORS"  "$LIC_SENSORS"

ok "Licence applied: $LIC_CUSTOMER / $LIC_EXPIRY / $LIC_SENSORS sensor(s)"

if [[ -n "$SMTP_HOST" ]]; then
    info "Writing SMTP configuration"
    patch_env "$CONFIG_FILE" "SMTP_HOST"     "$SMTP_HOST"
    patch_env "$CONFIG_FILE" "SMTP_PORT"     "$SMTP_PORT"
    patch_env "$CONFIG_FILE" "SMTP_USER"     "$SMTP_USER"
    patch_env "$CONFIG_FILE" "SMTP_PASSWORD" "$SMTP_PASS"
    patch_env "$CONFIG_FILE" "SMTP_FROM"     "$SMTP_FROM"
    patch_env "$CONFIG_FILE" "SMTP_USE_TLS"  "$SMTP_TLS"
    ok "SMTP configured: $SMTP_HOST:$SMTP_PORT"
fi

# Restore correct permissions — sed -i rewrites the file from scratch which
# resets ownership to root:root 644. The Flask app (ss-collector user) needs
# group write access to update the allowlist when firewalls are registered.
chown root:ss-collector "$CONFIG_FILE"
chmod 660 "$CONFIG_FILE"
ok "collector.env permissions restored (660 root:ss-collector)"

# ── Step 5: Start collector ──────────────────────────────────────────────────

step 5 "Starting collector"

systemctl start ss-collector
sleep 4

if systemctl is-active --quiet ss-collector; then
    ok "ss-collector is running"
else
    fail "ss-collector failed to start. Check: sudo journalctl -u ss-collector -n 30"
fi

# Verify licence accepted
# Capture first: a journalctl-to-quiet-grep pipeline fails on SIGPIPE under pipefail when grep exits early.
JOURNAL_TXT=$(journalctl -u ss-collector --since "30 seconds ago" 2>/dev/null || true)
if grep -qi "licence valid" <<<"$JOURNAL_TXT"; then
    ok "Licence validated successfully"
elif grep -qi "expired\|invalid\|violation" <<<"$JOURNAL_TXT"; then
    fail "Licence rejected by collector. Check journalctl -u ss-collector -n 20"
else
    info "Licence check pending — verify with: sudo journalctl -u ss-collector -f"
fi

# ── Step 6: GeoIP databases ──────────────────────────────────────────────────

step 6 "GeoIP databases"

if [[ -n "$MAXMIND_KEY" ]]; then
    info "Downloading MaxMind GeoLite2 databases..."
    (bash "$EXTRACT_DIR/scripts/download-geoip.sh" "$MAXMIND_KEY" > /tmp/ss_geoip.log 2>&1) &
    spinner $! "Downloading GeoIP"
    wait $! && ok "GeoIP databases installed" || warn "GeoIP download failed — check /tmp/ss_geoip.log"
    systemctl restart ss-collector
    sleep 2
    ok "Collector restarted with GeoIP enrichment"
else
    warn "Skipped — add MAXMIND_KEY=<your-key> to licence.env and re-run to enable"
    info "Free MaxMind key: maxmind.com → Account → Manage Licence Keys"
fi

# ── Step 7: Grafana dashboards ───────────────────────────────────────────────

step 7 "Installing Grafana dashboards"

(bash "$EXTRACT_DIR/scripts/install-grafana-dashboards.sh" > /tmp/ss_grafana.log 2>&1) &
spinner $! "Installing dashboards"
wait $! || warn "Grafana install had warnings — check /tmp/ss_grafana.log"

sleep 2
if systemctl is-active --quiet grafana-server; then
    ok "Grafana running on port 3000"
else
    warn "Grafana not running — check: sudo systemctl status grafana-server"
fi
ok "10 dashboards deployed with multi-tenant dropdown"

# ── Step 8: Reports UI ───────────────────────────────────────────────────────

step 8 "Installing Reports UI and scheduler"

(bash "$EXTRACT_DIR/scripts/install-reports.sh" > /tmp/ss_reports.log 2>&1) &
REPORTS_PID=$!
spinner $REPORTS_PID "Installing Reports UI"
wait $REPORTS_PID || fail "install-reports.sh failed. Check /tmp/ss_reports.log"

sleep 3
if systemctl is-active --quiet ss-reports; then
    ok "ss-reports running on port 8080"
else
    fail "ss-reports failed to start. Check: sudo journalctl -u ss-reports -n 30"
fi

# Read admin credentials from the install log
ADMIN_EMAIL="admin@sonicscope.local"
ADMIN_PASS=$(cat /etc/ss-multivendor/grafana-admin-password 2>/dev/null || echo "(see /tmp/ss_reports.log)")

# ── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$DOWNLOAD_DIR"

# ── Verify data is flowing ───────────────────────────────────────────────────
sleep 5
FLOW_COUNT=$(sudo -u postgres psql -d sonicscope -tAc \
    "SELECT COUNT(*) FROM fw_events WHERE time > NOW() - INTERVAL '5 minutes';" 2>/dev/null || echo "0")

# ── Final summary ────────────────────────────────────────────────────────────

SERVER_IP=$(hostname -I | awk '{print $1}')

echo
echo -e "  ${TEAL}╔══════════════════════════════════════════════════════════════════╗${NC}"
printf  "  ${TEAL}║${NC}  ${BOLD}${GREEN}✓  Deployment Complete${NC}  —  SonicScope v%-25s${TEAL}║${NC}\n" "${DETECTED_VER}"
echo -e "  ${TEAL}╠══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "  ${TEAL}║${NC}                                                                  ${TEAL}║${NC}"
echo -e "  ${TEAL}║${NC}  ${BOLD}Service URLs${NC}                                                    ${TEAL}║${NC}"
printf  "  ${TEAL}║${NC}    %-62s${TEAL}║${NC}\n" "Reports UI:  http://${SERVER_IP}:8080"
printf  "  ${TEAL}║${NC}    %-62s${TEAL}║${NC}\n" "Grafana:     http://${SERVER_IP}:3000"
echo -e "  ${TEAL}║${NC}                                                                  ${TEAL}║${NC}"
echo -e "  ${TEAL}║${NC}  ${BOLD}Default Admin Credentials${NC}  (change immediately after login)     ${TEAL}║${NC}"
printf  "  ${TEAL}║${NC}    %-62s${TEAL}║${NC}\n" "Email:    $ADMIN_EMAIL"
printf  "  ${TEAL}║${NC}    %-62s${TEAL}║${NC}\n" "Password: $ADMIN_PASS"
echo -e "  ${TEAL}║${NC}                                                                  ${TEAL}║${NC}"
echo -e "  ${TEAL}║${NC}  ${BOLD}Licence${NC}                                                         ${TEAL}║${NC}"
printf  "  ${TEAL}║${NC}    %-62s${TEAL}║${NC}\n" "Customer: $LIC_CUSTOMER"
printf  "  ${TEAL}║${NC}    %-62s${TEAL}║${NC}\n" "Expires:  $LIC_EXPIRY   Sensors: $LIC_SENSORS"
echo -e "  ${TEAL}║${NC}                                                                  ${TEAL}║${NC}"
echo -e "  ${TEAL}║${NC}  ${BOLD}Data Flow${NC}                                                       ${TEAL}║${NC}"
if [[ "$FLOW_COUNT" -gt 0 ]] 2>/dev/null; then
    printf  "  ${TEAL}║${NC}    ${GREEN}✓${NC}  %-59s${TEAL}║${NC}\n" "$FLOW_COUNT flows received in the last 5 minutes"
else
    printf  "  ${TEAL}║${NC}    ${YELLOW}⚠${NC}  %-59s${TEAL}║${NC}\n" "No flows yet — point your firewall IPFIX to ${SERVER_IP}:2055"
fi
echo -e "  ${TEAL}║${NC}                                                                  ${TEAL}║${NC}"
echo -e "  ${TEAL}╠══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "  ${TEAL}║${NC}  ${BOLD}Next Steps${NC}                                                      ${TEAL}║${NC}"
echo -e "  ${TEAL}║${NC}  1. Log in to Reports UI and change the admin password           ${TEAL}║${NC}"
echo -e "  ${TEAL}║${NC}  2. Create your MSP profile (logo, colours, contact details)     ${TEAL}║${NC}"
echo -e "  ${TEAL}║${NC}  3. Add tenants and register firewalls                           ${TEAL}║${NC}"
echo -e "  ${TEAL}║${NC}  4. Configure IPFIX on each firewall to send to this server      ${TEAL}║${NC}"
echo -e "  ${TEAL}║${NC}  5. Set up scheduled reports in the Reports UI                   ${TEAL}║${NC}"
echo -e "  ${TEAL}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "  ${DIM}Logs: /tmp/ss_install.log  /tmp/ss_grafana.log  /tmp/ss_reports.log${NC}"
echo -e "  ${DIM}Support: sales@sonicscope.co.za  |  sonicscope.co.za${NC}"
echo
