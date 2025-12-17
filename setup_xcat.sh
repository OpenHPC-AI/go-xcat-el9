#!/usr/bin/env bash
# setup_xcat_el9.sh
# Purpose: Clean install/fix xCAT on EL9 (Rocky/Alma/RHEL 9)
# - Removes existing xCAT packages (if any)
# - Installs go-xcat (latest by default)
# - Applies small certificate/opessl fixes needed on EL9
# - Reinitializes and restarts xCAT services
#
# Usage:
#   sudo ./setup_xcat_el9.sh [xcat_version]
# Example:
#   sudo ./setup_xcat_el9.sh latest

set -euo pipefail

# ----------------------------
# Configuration (change if needed)
# ----------------------------
XCAT_VERSION="${1:-latest}"
TMP_GO="/tmp/go-xcat"
OPENSSL_FILE="/opt/xcat/share/xcat/ca/openssl.cnf.tmpl"
OPENSSL_BACKUP_FILE="/opt/xcat/share/xcat/ca/openssl.cnf.tmpl.orig"
DOCKERHOST_CERT_FILE="/opt/xcat/share/xcat/scripts/setup-dockerhost-cert.sh"
DOCKERHOST_CERT_BACKUP_FILE="/opt/xcat/share/xcat/scripts/setup-dockerhost-cert.sh.orig"

LOG() { printf "==> %s\n" "$*"; }

# ----------------------------
# Basic pre-flight checks
# ----------------------------
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Use sudo."
  exit 2
fi

# Ensure package manager available
if ! command -v dnf >/dev/null 2>&1 && ! command -v yum >/dev/null 2>&1; then
  echo "No dnf/yum package manager found. Aborting."
  exit 3
fi

PKG_CMD="dnf"
if ! command -v dnf >/dev/null 2>&1; then
  PKG_CMD="yum"
fi

# ----------------------------
# Helper: install package if missing
# ----------------------------
ensure_pkg() {
  local pkg="$1"
  if ! rpm -q --quiet "$pkg"; then
    LOG "Installing missing package: $pkg"
    $PKG_CMD install -y "$pkg"
  else
    LOG "Package already installed: $pkg"
  fi
}

# ----------------------------
# 1) Remove existing xCAT packages (if any)
# ----------------------------
LOG "Checking for installed xCAT packages..."
# Match commonly named xcat packages (case-insensitive)
installed_xcat_pkgs=$(rpm -qa | awk 'tolower($0) ~ /^xcat/ || tolower($0) ~ /^xcat-/ {print $0}' || true)

if [[ -n "$installed_xcat_pkgs" ]]; then
  LOG "Found existing xCAT packages, removing them:"
  printf "%s\n" "$installed_xcat_pkgs"
  $PKG_CMD remove -y $installed_xcat_pkgs
else
  LOG "No pre-existing xCAT RPM packages found."
fi

# Also remove older meta package name "xCAT" if present:
if rpm -q --quiet xCAT; then
  LOG "Removing package 'xCAT'"
  $PKG_CMD remove -y xCAT || true
fi

# ----------------------------
# 2) Ensure prerequisites for EL9 (initscripts etc.)
# ----------------------------
LOG "Ensuring prerequisites (initscripts, wget/curl) are installed..."
ensure_pkg epel-release
ensure_pkg initscripts
ensure_pkg wget
ensure_pkg ca-certificates

# Enable repo of epel and crb
dnf config-manager --set-enabled epel crb

# ----------------------------
# 3) Download and run go-xcat installer
# ----------------------------
cp -ar ./go-xcat "$TMP_GO"

chmod +x "$TMP_GO"
LOG "Running go-xcat installer (version: ${XCAT_VERSION})"
/bin/bash "$TMP_GO" -x "${XCAT_VERSION}" install -y || {
  LOG "go-xcat install returned non-zero exit code. Continuing with the remaining fixes (some parts may have failed due to cert issues)."
}

# ----------------------------
# 4) Patch OpenSSL template: comment authorityKeyIdentifier lines
# ----------------------------
if [[ -f "$OPENSSL_FILE" ]]; then
  LOG "Backing up openssl template (if not already present): $OPENSSL_BACKUP_FILE"
  cp -n "$OPENSSL_FILE" "$OPENSSL_BACKUP_FILE" || LOG "Backup already exists."

  LOG "Commenting out lines starting with 'authorityKeyIdentifier' in $OPENSSL_FILE"
  # This will only comment lines that begin (optionally with whitespace) with authorityKeyIdentifier
  sed -i 's/^[[:space:]]*authorityKeyIdentifier/#&/' "$OPENSSL_FILE"
else
  LOG "OpenSSL template not found at $OPENSSL_FILE — skipping OpenSSL patch."
fi

# ----------------------------
# 5) Patch setup-dockerhost-cert.sh: remove '-extensions server' from the openssl req call
# ----------------------------
if [[ -f "$DOCKERHOST_CERT_FILE" ]]; then
  LOG "Backing up $DOCKERHOST_CERT_FILE to $DOCKERHOST_CERT_BACKUP_FILE (no overwrite)"
  cp -n "$DOCKERHOST_CERT_FILE" "$DOCKERHOST_CERT_BACKUP_FILE" || LOG "Backup already exists."

  LOG "Removing '-extensions server' from the dockerhost openssl request line (if present)."
  # Only operate on the specific openssl req line to be safe
  sed -i '/openssl req -config ca\/openssl.cnf -new -key ca\/dockerhost-key.pem/ s/-extensions[[:space:]]*server[[:space:]]*//g' "$DOCKERHOST_CERT_FILE"

  # Show the updated line for verification
  LOG "Updated openssl req lines (matching file):"
  grep -n "openssl req -config ca/openssl.cnf" "$DOCKERHOST_CERT_FILE" || true
else
  LOG "File $DOCKERHOST_CERT_FILE not found — skipping dockerhost cert script patch."
fi

# ----------------------------
# 6) Reinitialize xCAT and restart services
# ----------------------------
# Source xCAT profile if available (so xcatconfig/restartxcatd in PATH)
if [[ -f /etc/profile.d/xcat.sh ]]; then
  LOG "Sourcing /etc/profile.d/xcat.sh to add xCAT tools to PATH"
  # shellcheck disable=SC1090
  source /etc/profile.d/xcat.sh
fi

# Run xcatconfig if available
if command -v xcatconfig >/dev/null 2>&1; then
  LOG "Running xcatconfig -i -c -s to reinitialize xCAT configuration"
  xcatconfig -i -c -s || LOG "xcatconfig returned non-zero exit code."
else
  LOG "xcatconfig command not found. Skipping xcatconfig step."
fi

# Restart xcatd
if command -v restartxcatd >/dev/null 2>&1; then
  LOG "Using restartxcatd to restart xCAT daemon"
  restartxcatd || LOG "restartxcatd returned non-zero exit code."
elif systemctl list-unit-files | grep -q '^xcatd'; then
  LOG "Using systemctl to restart xcatd"
  systemctl daemon-reload || true
  systemctl restart xcatd || LOG "systemctl restart xcatd returned non-zero exit code."
else
  LOG "No known method to restart xcatd (no restartxcatd, xcatd service missing)."
fi

# Brief verification
LOG "Verifying xCAT daemon connectivity (lsxcatd -a)"
if command -v lsxcatd >/dev/null 2>&1; then
  lsxcatd -a || LOG "lsxcatd -a failed. Check /var/log/xcat/xcat.log and SSL configuration."
else
  LOG "lsxcatd command not available for verification."
fi

LOG "Done. If you still see xcatd errors, check /var/log/xcat/xcat.log and ensure SSL certs are present."
