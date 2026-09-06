#!/bin/bash
# Ondilo2Loxone: Einstellungen/Auth-Daten nach Upgrade wiederherstellen.
set -u
LBHOME="${LBHOMEDIR:-/opt/loxberry}"
CFG_DIR="$LBHOME/config/plugins/ondilo2loxone"
CFG="$CFG_DIR/ondilo.cfg"
DATA_DIR="$LBHOME/data/plugins/ondilo2loxone"
BACKUP_DIR="/tmp/ondilo2loxone_upgrade"
mkdir -p "$CFG_DIR" "$DATA_DIR"
[ -f "$BACKUP_DIR/ondilo.cfg" ] && cp -p "$BACKUP_DIR/ondilo.cfg" "$CFG"
[ -f "$BACKUP_DIR/auth.json" ] && cp -p "$BACKUP_DIR/auth.json" "$DATA_DIR/auth.json"
[ -f "$BACKUP_DIR/.auth.key" ] && cp -p "$BACKUP_DIR/.auth.key" "$DATA_DIR/.auth.key"
[ -f "$CFG" ] || touch "$CFG"
chown -R loxberry:loxberry "$CFG_DIR" "$DATA_DIR" 2>/dev/null || true
chmod 600 "$CFG" 2>/dev/null || true
[ -f "$DATA_DIR/auth.json" ] && chmod 600 "$DATA_DIR/auth.json" 2>/dev/null || true
[ -f "$DATA_DIR/.auth.key" ] && chmod 600 "$DATA_DIR/.auth.key" 2>/dev/null || true
rm -rf "$BACKUP_DIR"
exit 0
