#!/bin/bash
# Ondilo2Loxone: Einstellungen und geschuetzte Auth-Daten vor Upgrade sichern.
set -u
LBHOME="${LBHOMEDIR:-/opt/loxberry}"
CFG="$LBHOME/config/plugins/ondilo2loxone/ondilo.cfg"
DATA_DIR="$LBHOME/data/plugins/ondilo2loxone"
BACKUP_DIR="/tmp/ondilo2loxone_upgrade"
# 0700 statt der Standard-Umask: auth.json (verschluesseltes Passwort) UND
# der dazugehoerige Schluessel .auth.key landen sonst zusammen in einem
# fuer alle lesbaren /tmp-Unterverzeichnis - die Dateiberechtigungen (600)
# schuetzen zwar bereits vor anderen lokalen Benutzern, aber ein explizit
# verschlossenes Verzeichnis ist die sauberere Absicherung waehrend des
# kurzen Upgrade-Fensters.
mkdir -m 700 -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
[ -f "$CFG" ] && cp -p "$CFG" "$BACKUP_DIR/ondilo.cfg"
[ -f "$DATA_DIR/auth.json" ] && cp -p "$DATA_DIR/auth.json" "$BACKUP_DIR/auth.json"
[ -f "$DATA_DIR/.auth.key" ] && cp -p "$DATA_DIR/.auth.key" "$BACKUP_DIR/.auth.key"
exit 0
