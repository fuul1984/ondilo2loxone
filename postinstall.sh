#!/bin/bash
# Ondilo2Loxone: Verzeichnisse/Rechte bei einer Erstinstallation anlegen.
#
# Bewusst KEINE Default-Werte mehr hier hineinschreiben (fruehere Version
# tat das mit einer inzwischen veralteten Kopie der Vorlagen, die aus dem
# Takt mit config.pm::%DEFAULTS geraten war). config::read_config() liefert
# beim Lesen ohnehin immer erst %DEFAULTS und ueberschreibt sie nur mit dem,
# was tatsaechlich in der Datei steht - eine leere Datei ist also fachlich
# identisch zu einer mit allen Standardwerten vorbefuellten, aber es gibt
# nur noch eine einzige Quelle der Wahrheit fuer diese Werte (config.pm).
set -u
LBHOME="${LBHOMEDIR:-/opt/loxberry}"
CFG_DIR="$LBHOME/config/plugins/ondilo2loxone"
CFG="$CFG_DIR/ondilo.cfg"
DATA_DIR="$LBHOME/data/plugins/ondilo2loxone"
LOG_DIR="$LBHOME/log/plugins/ondilo2loxone"
mkdir -p "$CFG_DIR" "$DATA_DIR" "$LOG_DIR"
[ -f "$CFG" ] || touch "$CFG"
chown -R loxberry:loxberry "$CFG_DIR" "$DATA_DIR" "$LOG_DIR" 2>/dev/null || true
chmod 600 "$CFG" 2>/dev/null || true
find "$LBHOME/webfrontend/htmlauth/plugins/ondilo2loxone" -name "*.cgi" -exec chmod +x {} \; 2>/dev/null || true
find "$LBHOME/bin/plugins/ondilo2loxone" -name "*.pl" -exec chmod +x {} \; 2>/dev/null || true
exit 0
