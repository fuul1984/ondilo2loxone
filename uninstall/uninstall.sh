#!/bin/bash
# Ondilo2Loxone: Uninstall.
#
# IMPORTANT: this deliberately does NOT delete config/plugins/ondilo2loxone
# or data/plugins/ondilo2loxone anymore (which holds ondilo.cfg, the
# Ondilo login token and the encrypted password). Earlier versions did
# delete them here, which meant every reinstall of a newer plugin ZIP via
# LoxBerry's plugin manager (which can go through this same uninstall step
# even for what looks like an "update") silently wiped all settings and
# required reconnecting to Ondilo from scratch every time.
#
# Only the log directory - which is genuinely disposable - is removed.
# If you want to fully remove all plugin data (e.g. before handing the
# LoxBerry over to someone else), delete these manually:
#   /opt/loxberry/config/plugins/ondilo2loxone
#   /opt/loxberry/data/plugins/ondilo2loxone
PLUGIN="ondilo2loxone"
rm -rf "/opt/loxberry/log/plugins/${PLUGIN}"
exit 0
