# Ondilo2Loxone – LoxBerry Plugin (v0.0.12)

Liest Messwerte deines **Ondilo ICO** (Pool/Spa-Sensor) über die offizielle
Ondilo Customer API aus und sendet sie als konfigurierbare **UDP-Telegramme**
an einen Loxone Miniserver. Zusätzlich wird ein **Heartbeat** gesendet.

## Was sich seit v0.0.11 geändert hat

- **Sensor-Checkbox liess sich nicht mehr bedienen:** Die v0.0.11-Loesung
  nutzte JavaScript (onchange-Handler) fuer die Live-Optik. Falls LoxBerrys
  Oberflaeche Inline-Skripte per Content-Security-Policy blockiert oder das
  JS aus anderen Gruenden nicht lief, konnte das die Interaktion stoeren.
  **Jetzt komplett ohne JavaScript:** Checkbox, Status-Anzeige und
  Sensor-Name liegen in einem einzigen nativen `<label>`-Element - das
  Umschalten funktioniert dadurch rein per HTML/Browser, unabhaengig von
  Skript-Ausfuehrung. Einziger Kompromiss: die AKTIV/INAKTIV-Anzeige und
  die gruene/graue Kartenfarbe aktualisieren sich erst nach dem Speichern
  (nicht mehr live beim Klicken) - dafuer ist die Checkbox selbst
  garantiert in jedem Browser bedienbar.

## Was sich seit v0.0.10 geändert hat

- **Ueberlagerung nochmals behoben - diesmal strukturell:** Der vorherige
  Fix nutzte einen ausgeblendeten nativen Checkbox + eigene Schalter-Grafik
  (zwei uebereinanderliegende Elemente). Falls LoxBerrys Skin-CSS irgendwo
  pauschale Regeln fuer Checkboxen erzwingt, konnte die native Checkbox
  wieder auftauchen und sich mit der Grafik ueberlagern. Jetzt gibt es pro
  Sensor nur noch **eine** sichtbare, groessere Checkbox plus **ein
  einziges** Text-Element fuer den Status, das per JavaScript umgeschaltet
  wird - es gibt technisch keine zwei Elemente mehr, die sich ueberlagern
  koennten.

## Was sich seit v0.0.9 geändert hat

- **Ueberlagerte Aktiv/Inaktiv-Anzeige behoben:** Die Umschaltung lief bisher
  rein ueber den CSS-Selektor `:has()`, den nicht jeder mobile Browser
  unterstuetzt - ohne Unterstuetzung blieben AKTIV und INAKTIV gleichzeitig
  sichtbar (Ueberlagerung). Jetzt wird die Sichtbarkeit beim Laden direkt
  korrekt serverseitig gesetzt und beim Klicken zuverlaessig per einfachem
  JavaScript umgeschaltet - funktioniert unabhaengig vom Browser.
- **Heartbeat nicht mehr im Log/in der Detailansicht:** Der Heartbeat laeuft
  weiterhin jede Minute im Hintergrund, taucht aber nicht mehr als
  eigene Zeile im Log oder in "Letzte Ausfuehrung im Detail" auf - dort
  erscheint nur noch die eigentliche ICO-Datenabfrage (im konfigurierten
  Intervall). Ausserdem wird die Detailansicht nicht mehr bei jedem reinen
  Heartbeat-Tick durch einen leeren Platzhalter ueberschrieben, sondern
  zeigt bis zur naechsten echten Synchronisation weiterhin die letzten
  tatsaechlichen Werte.

## Was sich seit v0.0.8 geändert hat

- **Aktiv/Inaktiv viel deutlicher sichtbar:** In den Einstellungen ist die
  Checkbox jetzt ein grosser Toggle-Schalter, und die ganze Sensor-Karte
  faerbt sich beim Umschalten sofort gruen (aktiv) bzw. grau/transparent
  (inaktiv) - ganz ohne Neuladen. Auf der Startseite hat die "Aktiv"-Spalte
  jetzt farbige Pill-Badges (gruen/rot) statt reinem Text, und die
  komplette Tabellenzeile wird passend eingefaerbt bzw. abgeblendet.
- **Log wird taeglich zurueckgesetzt:** Zusaetzlich zur bisherigen
  1-MB-Grenze wird die Logdatei jetzt auch automatisch geleert, sobald ein
  neuer Kalendertag beginnt - dadurch bleibt sie dauerhaft klein, unabhaengig
  davon, wie viel an einem Tag protokolliert wird.

## Wichtig: v0.0.8 behebt Datenverlust bei jeder Neuinstallation

Bis einschliesslich v0.0.7 loeschte `uninstall/uninstall.sh` bei jeder
(De-)Installation kommentarlos die komplette Konfiguration, den
Ondilo-Login-Token und das verschluesselte Passwort. Wird ein neues
Plugin-ZIP manuell ueber den LoxBerry Plugin-Manager hochgeladen (statt
ueber einen echten Auto-Update-Mechanismus), verwendet LoxBerry dafuer
offenbar denselben Uninstall-Schritt wie bei einer vollstaendigen
Deinstallation - jedes Update hat dadurch alle Einstellungen
zurueckgesetzt.

**Ab v0.0.8 loescht die Deinstallation nur noch das Logverzeichnis.**
Konfiguration und Zugangsdaten unter `config/plugins/ondilo2loxone` und
`data/plugins/ondilo2loxone` bleiben bei jeder zukuenftigen Installation
erhalten. `preupgrade.sh`/`postupgrade.sh` sichern zusaetzlich als zweites
Sicherheitsnetz nach `/tmp` und stellen automatisch wieder her, falls
LoxBerry bei einem echten Update-Mechanismus doch einmal den Ordner
zwischendurch leert.

Nach dem Einspielen von v0.0.8 muessen die Einstellungen (Ondilo-Login,
Pool, Miniserver, Sensoren) noch **einmal letztmalig** neu eingegeben
werden - ab dann bleiben sie bei jedem weiteren Update erhalten.

## Was sich seit v0.0.6 geändert hat

- **Log jetzt wie bei FYTA Connect lesbar:** Jeder gesendete Wert wird auf
  Stufe INFO protokolliert (`UDP gesendet: ONDILO_TEMPERATURE=24.5`) statt
  nur auf DEBUG-Stufe (die standardmaessig unsichtbar war). Dazu je
  Synchronisation eine Start- und eine Abschlusszeile
  (`Synchronisation erfolgreich: N Werte erhalten, M Telegramme, Xs`),
  analog zu FYTA - aber kompakter, da nur ein Pool statt mehrerer Pflanzen
  protokolliert wird, und nur bei tatsaechlichem Abruf (nicht bei jedem
  reinen Heartbeat-Minutentakt).
- **Aktiv/Inaktiv klarer sichtbar:** Auf der Startseite zeigt die Tabelle
  "Von Ondilo erhalten" jetzt eine eigene Aktiv-Spalte (&#9989;/&#10060;)
  pro Wert. In den Einstellungen ist die Checkbox pro Sensor jetzt
  zusaetzlich mit "aktiv"/"inaktiv" beschriftet statt nur als nacktes
  Kaestchen.

## Was sich seit v0.0.5 geändert hat

- **Migration alter Nachrichten-Vorlagen:** Wer das Plugin schon vor der
  Formatumstellung installiert hatte, hatte weiterhin die alten
  `ONDILO;TEMP;%VALUE%`-Nachrichten gespeichert (neue Defaults gelten nur
  fuer neu entdeckte Sensoren). Beim naechsten Aufruf der Einstellungsseite
  oder Cronjob-Lauf werden **ausschliesslich unveraenderte Alt-Standards**
  automatisch auf das neue Format gehoben - eigene Anpassungen bleiben
  unangetastet.

## Was sich seit v0.0.4 geändert hat

- **UDP-Format an FYTA Connect angeglichen:** Standardformat ist jetzt
  `ONDILO_<TYP>=<WERT>` (z.B. `ONDILO_TEMPERATURE=24.5`,
  `ONDILO_Heartbeat=1`) statt `ONDILO;TEMP;<WERT>` – passt direkt zu einer
  Loxone-Befehlserkennung wie `ONDILO_TEMPERATURE=\v`.
- **Dynamische Sensor-Erkennung:** Statt einer festen Liste fragt das
  Plugin bei jeder Synchronisation alles ab, was Ondilo fuer den Pool
  tatsaechlich liefert (`ondilo_api::last_measures_all`). Neue Messwerte
  (z.B. falls Ondilo weitere Typen ergaenzt) werden automatisch mit einem
  Standard-Eintrag versehen und erscheinen direkt in den Einstellungen –
  kein manuelles Nachpflegen noetig. Auf der Einstellungsseite steht bei
  jedem Sensor zusaetzlich der zuletzt gemessene Live-Wert sowie die
  passende Loxone-Befehlserkennung als Beispiel.
- **Sichtbarkeit bei der Ausfuehrung:** Jeder Lauf schreibt ein
  Detailprotokoll (`data/plugins/ondilo2loxone/last_run.json`): alle von
  Ondilo erhaltenen Rohwerte (auch ungueltige, mit Grund) und jede
  tatsaechlich gesendete UDP-Nachricht inkl. Ergebnis. Die Startseite zeigt
  das nach jedem Lauf direkt an ("Letzte Ausfuehrung im Detail").

## Was sich seit v0.0.1 geändert hat

Nach Vergleich mit einem produktiv laufenden LoxBerry-Plugin wurde die
Architektur grundlegend robuster gemacht:

- **Feste Pfade** (`/opt/loxberry/...`) statt dynamischer `LoxBerry::System`-
  Variablen, deren genaues Export-Verhalten nicht zuverlässig dokumentiert
  ist und in v0.0.1 vermutlich die 500-Fehler verursacht hat.
- **Eigenständige, kleine Perl-Module** (`config.pm`, `logger.pm`, `udp.pm`,
  `version.pm`, `auth_store.pm`, `ondilo_api.pm`, `miniservers.pm`) statt
  einer großen Bibliothek – jedes für sich einfach zu testen.
- **Cronjob per `cron/cron.01min`** im Plugin-Paket: LoxBerry installiert
  diese Datei automatisch in `system/cron/cron.01min/` – kein manuelles
  Symlink-Skript mehr nötig.
- **Icons** in 64/128/256/512 px aus deinem Ondilo-Logo (`icons/`).
- **Miniserver-Auswahl per Dropdown** (`miniservers.pm`, mit Fallback über
  LoxBerry's `general.cfg`, falls `LoxBerry::System::get_miniservers()`
  nicht verfügbar ist).
- **Direkte Anmeldung mit E-Mail/Passwort** statt Browser-Weiterleitung zu
  Ondilo (siehe wichtiger Hinweis unten!).

## Direkte Ondilo-Anmeldung – wichtiger Hinweis

Ondilo dokumentiert **offiziell nur** einen browserbasierten OAuth2-Login
(Weiterleitung zu einer Ondilo-Loginseite). Es gibt **keine dokumentierte
Möglichkeit**, Benutzername/Passwort direkt per API einzureichen.

Damit du trotzdem nur E-Mail/Passwort in der LoxBerry-Oberfläche eingeben
musst, emuliert `ondilo_api.pm` serverseitig, was ein Browser tun würde:
Login-Seite laden, Formular erkennen, ausfüllen, absenden, der
Weiterleitung bis zum Autorisierungscode folgen.

**Das ist Best-Effort und kann brechen**, wenn Ondilo:
- die Login-Seite strukturell ändert,
- eine Sicherheitsabfrage (Captcha, 2FA, Bestätigungs-E-Mail) einblendet.

Schlägt die Anmeldung fehl, wird das im Log
(`/opt/loxberry/log/plugins/ondilo2loxone/ondilo2loxone.log`) mit einem
Ausschnitt der empfangenen Seite protokolliert – das hilft, die
Felderkennung in `ondilo_api::login_with_password()` gezielt nachzubessern.
**Bitte nach dem ersten Test kurz Rückmeldung geben**, ob die Anmeldung
geklappt hat – falls nicht, bitte den relevanten Log-Ausschnitt schicken,
dann passen wir die Formular-Erkennung gezielt an die tatsächliche
Ondilo-Seite an.

Das Passwort wird (falls angegeben) **verschlüsselt** lokal gespeichert
(AES-256-CBC via OpenSSL, Schlüssel in `data/plugins/ondilo2loxone/.auth.key`,
0600), damit nach einem eventuellen Tokenverfall automatisch neu angemeldet
werden kann, ohne dass du es erneut eingeben musst.

## Installation

1. Plugin-ZIP im LoxBerry Plugin-Manager hochladen.
2. **Plugins → Ondilo2Loxone → Einstellungen** öffnen.
3. E-Mail/Passwort eingeben, Miniserver aus der Dropdown-Liste wählen,
   UDP-Port, Intervall und Sensoren festlegen, **Speichern & verbinden**.
4. Bei mehreren Pools/Spas erscheint danach eine Auswahl.

## Miniserver-Einrichtung

Peripherie → Netzwerk-Geräte → **Virtueller UDP-Eingang** auf dem
konfigurierten Port. Für Heartbeat und jeden aktivierten Sensor einen
**virtuellen UDP-Eingangsbefehl**, z. B. bei der Standard-Vorlage
`ONDILO;TEMP;<v>`: Befehlserkennung `ONDILO;TEMP;\v`.

Die Nachrichten-Vorlagen sind frei editierbar (Platzhalter `%VALUE%`,
`%TYPE%`, `%POOL%`).

## Sicherheit

- Konfigurationsseiten liegen unter `webfrontend/htmlauth/` – nur nach
  LoxBerry-Login erreichbar.
- Token und (optional) Passwort liegen verschlüsselt/mit 0600-Rechten in
  `data/plugins/ondilo2loxone/` (`auth.json`, `.auth.key`), niemals im
  Web-Verzeichnis.
- Alle Ondilo-Aufrufe laufen über HTTPS mit Zertifikatsprüfung.
- UDP-Nachrichten werden vor dem Versand von Steuerzeichen befreit und in
  der Länge begrenzt.
- Eingaben (IP, Port, Intervalle) werden serverseitig validiert.

## API-Limits

Ondilo begrenzt auf 5 Anfragen/Sekunde und 30 Anfragen/Stunde pro Nutzer.
Der Standard-Intervall von 15 Minuten bleibt deutlich darunter (ICO liefert
ohnehin nur stündlich neue Werte).

## Bekannte Einschränkungen

- Die Formular-Emulation für die Direktanmeldung wurde **nicht gegen die
  echte Ondilo-Website getestet** (keine Internetverbindung in der
  Entwicklungsumgebung) – siehe Hinweis oben.
- Alle Perl-Dateien wurden mit `perl -c` syntaktisch geprüft, aber nicht in
  einer echten LoxBerry-Umgebung ausgeführt.
