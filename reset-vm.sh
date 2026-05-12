#!/bin/bash
# SonicScope — VM Reset Script
# Wipes a partial or failed SonicScope install so deploy.sh can run cleanly.
# Safe to run on a fresh Ubuntu VM that has never had a successful deployment.
#
# Removes:
#   - ss-collector and ss-reports services + all installed files
#   - PostgreSQL (all versions installed by apt), clusters, and data
#   - TimescaleDB packages
#   - Grafana
#   - APT sources and GPG keys added by the installer
#   - sonicscope system user
#
# Does NOT remove: Python3, curl, wget, openssl, or other base OS packages.
#
# Usage:
#   sudo bash reset-vm.sh

set -uo pipefail   # no -e so cleanup continues even if individual steps fail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()      { echo -e "  ${GREEN}✓${NC}  $*"; }
info()    { echo -e "  ${CYAN}→${NC}  $*"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $*"; }
section() { echo; echo -e "${CYAN}── $* ──${NC}"; }

[ "$(id -u)" -ne 0 ] && { echo -e "${RED}Must be run as root: sudo bash reset-vm.sh${NC}"; exit 1; }

echo
echo -e "${RED}  ╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}  ║  SonicScope VM Reset — removes ALL installed state   ║${NC}"
echo -e "${RED}  ╚══════════════════════════════════════════════════════╝${NC}"
echo
echo "  This will remove PostgreSQL, Grafana, and all SonicScope files."
echo "  Run on a clean test VM only."
echo
read -r -p "  Type YES to continue: " confirm
[[ "$confirm" == "YES" ]] || { echo "Aborted."; exit 0; }

# ── SonicScope services ───────────────────────────────────────────────────────
section "Stopping and removing SonicScope services"
for svc in ss-collector ss-reports; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl stop "$svc" && ok "Stopped $svc"
    fi
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        systemctl disable "$svc" 2>/dev/null
    fi
    rm -f "/etc/systemd/system/${svc}.service"
done
systemctl daemon-reload 2>/dev/null
ok "SonicScope services removed"

# ── SonicScope files ─────────────────────────────────────────────────────────
section "Removing SonicScope files"
rm -rf /opt/ss-multivendor /etc/ss-multivendor /var/lib/ss-multivendor \
       /var/log/ss-multivendor /etc/sudoers.d/ss-collector 2>/dev/null
ok "Application files removed"

# ── System user ───────────────────────────────────────────────────────────────
if id ss-collector &>/dev/null; then
    userdel ss-collector 2>/dev/null && ok "System user ss-collector removed"
fi

# ── Grafana ───────────────────────────────────────────────────────────────────
section "Removing Grafana"
systemctl stop grafana-server 2>/dev/null
systemctl disable grafana-server 2>/dev/null
apt-get remove --purge -y -qq grafana 2>/dev/null && ok "Grafana removed"
rm -rf /etc/grafana /var/lib/grafana /var/log/grafana \
       /etc/apt/sources.list.d/grafana.list \
       /usr/share/keyrings/grafana.gpg 2>/dev/null

# ── PostgreSQL ────────────────────────────────────────────────────────────────
section "Removing PostgreSQL (all versions)"

# Stop all clusters
for ver in $(pg_lsclusters -h 2>/dev/null | awk '{print $1}' | sort -u); do
    for cluster in $(pg_lsclusters -h 2>/dev/null | awk -v v="$ver" '$1==v {print $2}'); do
        pg_dropcluster --stop "$ver" "$cluster" 2>/dev/null && ok "Dropped cluster ${ver}/${cluster}"
    done
done

# Remove all postgresql packages
PGPKGS=$(dpkg -l 'postgresql*' 'timescaledb*' 2>/dev/null | awk '/^ii/{print $2}' | tr '\n' ' ')
if [[ -n "$PGPKGS" ]]; then
    # shellcheck disable=SC2086
    apt-get remove --purge -y -qq $PGPKGS 2>/dev/null && ok "PostgreSQL + TimescaleDB packages removed"
fi
apt-get autoremove -y -qq 2>/dev/null

# Remove leftover data dirs
rm -rf /var/lib/postgresql /etc/postgresql /var/log/postgresql 2>/dev/null
ok "PostgreSQL data directories removed"

# ── APT sources and keys ──────────────────────────────────────────────────────
section "Removing APT sources"
rm -f /etc/apt/sources.list.d/pgdg.list \
      /etc/apt/sources.list.d/timescaledb.list \
      /etc/apt/sources.list.d/grafana.list \
      /usr/share/keyrings/postgresql.gpg \
      /usr/share/keyrings/timescaledb.gpg 2>/dev/null
apt-get update -qq 2>/dev/null
ok "APT sources cleaned"

# ── Temp deploy files ─────────────────────────────────────────────────────────
rm -rf /tmp/sonicscope_deploy_* /tmp/ss_install.log /tmp/ss_*.sql 2>/dev/null

echo
echo -e "  ${GREEN}Reset complete.${NC} The VM is ready for a fresh deploy:"
echo
echo "    curl -fsSL https://raw.githubusercontent.com/sonicscope/production/main/deploy.sh | sudo bash"
echo
