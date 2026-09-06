# Release-Prozess (Git + LoxBerry Auto-Update)

Ablauf für ein neues Release, sobald das Repo auf GitHub liegt
(`https://github.com/fuul1984/ondilo2loxone`):

1. **Version anheben** an drei Stellen (müssen übereinstimmen):
   - `plugin.cfg` → `[PLUGIN]` → `VERSION=`
   - `bin/version.pm` → `$FALLBACK_VERSION`
   - `release.cfg` (und ggf. `prerelease.cfg`) → `VERSION=`

2. **`release.cfg` aktualisieren** (`ARCHIVEURL`/`INFOURL` auf das neue Tag zeigen lassen):
   ```
   VERSION=0.1.2
   ARCHIVEURL=https://github.com/fuul1984/ondilo2loxone/archive/refs/tags/v0.1.2.zip
   INFOURL=https://github.com/fuul1984/ondilo2loxone/releases/tag/v0.1.2
   ```

3. **Committen und pushen:**
   ```bash
   git add -A
   git commit -m "Release v0.1.2"
   git push
   ```

4. **Tag setzen und pushen** (Tag-Name muss exakt zur `ARCHIVEURL` oben passen):
   ```bash
   git tag v0.1.2
   git push origin v0.1.2
   ```

5. **GitHub Release anlegen** (auf GitHub → Releases → "Draft a new release", das eben
   gepushte Tag auswählen, Änderungen kurz beschreiben, veröffentlichen). Das ist rein
   für die Anzeige unter `INFOURL` gedacht - LoxBerry braucht dafür kein GitHub-Release,
   nur den Tag und die dadurch existierende `ARCHIVEURL`-ZIP.

Danach erkennt jeder LoxBerry, der diese Version noch nicht hat, beim nächsten
automatischen Update-Check (oder manuell in der Plugin-Verwaltung unter
"Nach Updates suchen") die neue Version über `RELEASECFG` und bietet das Update an
bzw. installiert es automatisch (`AUTOMATIC_UPDATES=true`).

## Erstinstallation

Auto-Update funktioniert nur für **bereits installierte** Plugins. Die allererste
Installation läuft weiterhin klassisch über eine hochgeladene ZIP-Datei in der
LoxBerry Plugin-Verwaltung (z.B. das aktuell gebaute `ondilo2loxone_v0.1.1.zip`,
oder alternativ direkt der `https://github.com/fuul1984/ondilo2loxone/archive/refs/heads/master.zip`-Link
sobald das Repo öffentlich ist).

## Identität nicht ändern

`[AUTHOR]` (NAME/EMAIL) und `[PLUGIN]` NAME/FOLDER in `plugin.cfg` niemals ändern -
LoxBerry identifiziert das Plugin darüber. Eine Änderung würde bei allen
bestehenden Installationen wie ein komplett neues Plugin aussehen statt wie ein
Update.
