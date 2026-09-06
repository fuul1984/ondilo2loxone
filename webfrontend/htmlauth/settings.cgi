#!/usr/bin/perl
use strict; use warnings; use utf8;

use lib "/opt/loxberry/bin/plugins/ondilo2loxone";
use config;
use auth_store;
use miniservers;
use ondilo_api;

binmode STDOUT, ':encoding(UTF-8)';

my $HAVE_LBWEB = eval { require LoxBerry::Web; require LoxBerry::System; 1 };

sub page_header {
    my ($title) = @_;
    if ($HAVE_LBWEB) {
        my $ok = eval { LoxBerry::Web::lbheader($title, "", ""); 1 };
        return if $ok;
    }
    print "Content-type: text/html; charset=utf-8\n\n";
    print "<!DOCTYPE html><html lang='de'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'><title>$title</title></head><body style='font-family:sans-serif;margin:0;background:#f5f5f5'>";
}
sub page_footer {
    if ($HAVE_LBWEB) {
        my $ok = eval { LoxBerry::Web::lbfooter(); 1 };
        return if $ok;
    }
    print "</body></html>";
}

sub html_escape {
    my ($text) = @_;
    $text = "" unless defined $text;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    return $text;
}

my $cfg = config::read_config();
if (config::migrate_legacy_defaults($cfg)) {
    eval { config::write_config($cfg); };
}
my $auth = auth_store::load_auth();
my $connected = $auth->{access_token} || $auth->{refresh_token} ? 1 : 0;

my %labels = (
    temperature => 'Wassertemperatur (&deg;C)',
    ph          => 'pH-Wert',
    orp         => 'Redoxpotential ORP (mV)',
    salt        => 'Salzgehalt (mg/l)',
    tds         => 'TDS (ppm)',
    battery     => 'Batterie ICO (%)',
    rssi        => 'Funkfeldstaerke RSSI (%)',
);

my @servers = eval { miniservers::get_servers() };
@servers = () if $@;

# Dynamic sensor discovery: if we're connected and a pool is selected, ask
# Ondilo directly what it currently reports, instead of a fixed list. New
# types get a default config entry (auto-enabled) so nothing has to be
# added manually. Falls back to whatever is already in the config if the
# live call isn't possible (not connected yet, API hiccup, ...).
my %live_values;
my $live_error = '';
if ($connected && $cfg->{POOL_ID}) {
    my $access_token = eval { ondilo_api::get_valid_access_token() };
    if ($access_token) {
        my ($measures, $err) = ondilo_api::last_measures_all($access_token, $cfg->{POOL_ID});
        if ($measures) {
            my $changed = 0;
            for my $m (@$measures) {
                $live_values{ $m->{data_type} } = {
                    value    => $m->{value},
                    is_valid => $m->{is_valid} ? 1 : 0,
                };
                $changed = 1 if config::ensure_sensor_defaults($cfg, $m->{data_type});
            }
            eval { config::write_config($cfg); } if $changed;
        } else {
            $live_error = $err;
        }
    } else {
        $live_error = ondilo_api::last_error();
    }
}

my @sensor_types = config::sensor_types_from_config($cfg);

page_header("Ondilo2Loxone - Einstellungen");

print <<'CSS';
<style>
*{box-sizing:border-box}
body{margin:0}
.o2l-wrap{max-width:900px;margin:0 auto;padding:12px 14px 24px;font-family:Arial,Helvetica,sans-serif}
.o2l-nav{display:flex;flex-wrap:wrap;gap:10px;margin:0 0 18px}
.o2l-nav a,.o2l-btn{display:inline-flex;align-items:center;justify-content:center;min-height:44px;padding:10px 16px;border-radius:7px;background:#00a99d;color:#fff!important;-webkit-text-fill-color:#fff!important;text-shadow:none!important;font-family:Arial,Helvetica,sans-serif!important;font-size:15px!important;line-height:1.25!important;font-weight:700!important;letter-spacing:0!important;text-decoration:none!important;border:0!important;box-shadow:none!important;cursor:pointer}
.o2l-nav a:link,.o2l-nav a:visited,.o2l-nav a:hover,.o2l-nav a:active,.o2l-nav a:focus,.o2l-btn:link,.o2l-btn:visited,.o2l-btn:hover,.o2l-btn:active,.o2l-btn:focus{color:#fff!important;-webkit-text-fill-color:#fff!important;text-shadow:none!important;text-decoration:none!important}
.o2l-nav a:hover,.o2l-btn:hover{background:#00867c!important}
.o2l-btn.danger{background:#b71c1c!important}
.o2l-card{background:#fff;border:1px solid #dfe4e8;border-radius:10px;box-shadow:0 2px 8px rgba(0,0,0,.06);padding:18px;margin-bottom:16px}
.o2l-row{display:grid;grid-template-columns:220px 1fr;gap:8px 20px;align-items:center;margin-bottom:10px}
.o2l-row label{font-weight:700;color:#455a64}
input[type=text],input[type=password],input[type=number],select{padding:9px;width:100%;max-width:320px;border:1px solid #b0bec5;border-radius:5px;box-sizing:border-box;font-size:15px}
.o2l-sensor-list{display:flex;flex-direction:column;gap:12px}
.o2l-sensor{border:2px solid #e1e6e9;border-left-width:6px;border-radius:8px;padding:12px;transition:opacity .15s}
.o2l-sensor.active{border-color:#a5d6a7;border-left-color:#2e7d32;background:#f4faf5}
.o2l-sensor.inactive{border-color:#e1e6e9;border-left-color:#b0bec5;background:#f7f7f7;opacity:.7}
.o2l-sensor-head{display:flex;align-items:center;gap:10px;margin-bottom:8px;font-weight:700;flex-wrap:wrap;cursor:pointer}
.o2l-sensor input[type=text]{max-width:none;width:100%}
.o2l-sensor-head input[type=checkbox]{width:24px;height:24px;flex:0 0 auto;margin:0;accent-color:#2e7d32;cursor:pointer}
.o2l-state{font-size:13px;padding:3px 10px;border-radius:12px;background:#eceff1;white-space:nowrap}
small.hint{color:#78909c}
.status-on{color:#1b5e20;font-weight:700}
.status-off{color:#b71c1c;font-weight:700}
.ok-text{color:#1b5e20;font-weight:700}
.err-text{color:#b71c1c;font-weight:700}
@media (max-width:600px){
  .o2l-row{grid-template-columns:1fr}
  input[type=text],input[type=password],input[type=number],select{max-width:none}
  .o2l-nav a,.o2l-btn{flex:1 1 auto;width:100%}
  .o2l-nav{flex-direction:column}
  h2{font-size:1.15em}
}
</style>
CSS

print "<div class='o2l-wrap'>";
print "<nav class='o2l-nav'><a href='index.cgi'>Startseite</a><a href='settings.cgi'>Einstellungen</a><a href='sync.cgi'>Jetzt synchronisieren</a></nav>";

print "<form method='post' action='save.cgi'>";

print "<section class='o2l-card'><h2>Ondilo-Konto</h2>";
print "<p>Status: <span class='" . ($connected ? 'status-on' : 'status-off') . "'>" . ($connected ? 'verbunden' : 'nicht verbunden') . "</span>" . ($auth->{email} ? " (" . html_escape($auth->{email}) . ")" : "") . "</p>";
print "<div class='o2l-row'><label>E-Mail</label><input type='text' name='email' value='" . html_escape($cfg->{ONDILO_EMAIL} // '') . "' autocomplete='username'></div>";
print "<div class='o2l-row'><label>Passwort</label><input type='password' name='password' autocomplete='current-password' placeholder='" . ($connected ? 'unveraendert lassen = leer' : '') . "'></div>";
print "<p><small class='hint'>Wird nur zur einmaligen Anmeldung bei Ondilo verwendet, um Zugangs-Token zu erhalten. Fuer eine automatische Neuanmeldung nach einem eventuellen Tokenverfall wird das Passwort verschluesselt lokal gespeichert (siehe README). Leer lassen, um Zugangsdaten unveraendert zu lassen.</small></p>";
print "</section>";

print "<section class='o2l-card'><h2>Miniserver &amp; UDP</h2>";
if (@servers) {
    print "<div class='o2l-row'><label>Miniserver</label><select name='miniserver_no'>";
    print "<option value=''>-- bitte waehlen --</option>";
    for my $s (@servers) {
        my $sel = (defined $cfg->{MINISERVER_NO} && "$cfg->{MINISERVER_NO}" eq "$s->{no}") ? 'selected' : '';
        print "<option value='" . html_escape($s->{no}) . "' $sel>" . html_escape($s->{name}) . " (" . html_escape($s->{host}) . ")</option>";
    }
    print "</select></div>";
} else {
    print "<p><small class='hint'>Keine LoxBerry-Miniserver gefunden - bitte Ziel-IP manuell eintragen.</small></p>";
    print "<div class='o2l-row'><label>Miniserver-IP</label><input type='text' name='udp_host_manual' value='" . html_escape($cfg->{UDP_HOST} // '') . "'></div>";
}
print "<div class='o2l-row'><label>UDP-Port</label><input type='number' name='udp_port' min='1' max='65535' value='" . html_escape($cfg->{UDP_PORT} // '7000') . "'></div>";
print "<div class='o2l-row'><label>Abfrageintervall (Minuten)</label><input type='number' name='interval' min='2' max='1440' value='" . html_escape($cfg->{INTERVAL} // '15') . "'></div>";
print "<p><small class='hint'>Ondilo begrenzt Anfragen auf 30 pro Stunde und Nutzer - deshalb mindestens 2 Minuten.</small></p>";
print "<div class='o2l-row'><label>Werte gueltig bis (Minuten)</label><input type='number' name='stale_minutes' min='0' value='" . html_escape($cfg->{STALE_MINUTES} // '90') . "'></div>";
print "<p><small class='hint'>Auf dem Miniserver einen virtuellen UDP-Eingang auf diesem Port anlegen (Peripherie &rarr; Netzwerk-Geraete). Ist der letzte Messwert eines Sensors aelter als die eingestellte Anzahl Minuten (z.B. weil das ICO offline ist), wird -9999 statt des veralteten Werts gesendet. <strong>0 = Pruefung deaktiviert.</strong> Hinweis: Manche APIs (moeglicherweise auch Ondilo) aktualisieren den Zeitstempel eines Wertes nur, wenn er sich tatsaechlich veraendert hat - ein seit Tagen stabiler Wert (z.B. Batterie) koennte dann faelschlich als veraltet gelten. Beobachte dazu ein paar Tage lang die Spalte \"Zeitstempel\" in der Startseiten-Detailansicht: bleibt sie bei unveraenderten Werten stehen, solltest du diese Pruefung deaktivieren (0) oder den Schwellwert deutlich hochsetzen.</small></p>";
print "</section>";

print "<section class='o2l-card'><h2>Heartbeat</h2>";
my $hb_checked = (($cfg->{HEARTBEAT_ENABLED} // 'true') eq 'true') ? 'checked' : '';
print "<div class='o2l-row'><label>Aktiv</label><input type='checkbox' name='hb_enabled' $hb_checked></div>";
print "<div class='o2l-row'><label>Intervall (Sekunden)</label><input type='number' name='hb_interval' min='1' value='" . html_escape($cfg->{HEARTBEAT_INTERVAL} // '60') . "'></div>";
print "<div class='o2l-row'><label>UDP-Nachricht</label><input type='text' name='hb_message' value='" . html_escape($cfg->{HEARTBEAT_MESSAGE} // '') . "'></div>";
print "<p><small class='hint'>Loxone Virtueller UDP-Eingang &ndash; Befehlserkennung z.B.: <code>" . html_escape($cfg->{HEARTBEAT_MESSAGE} // '') . "</code> (kein Platzhalter noetig - die abschliessende 1 wird automatisch durch 0 ersetzt, wenn beim letzten Datenabruf keine Verbindung zu Ondilo bestand)</small></p>";
print "</section>";

print "<section class='o2l-card'><h2>Sensorwerte</h2>";
print "<p><small class='hint'>Werte werden dynamisch von Ondilo abgefragt - was hier erscheint, richtet sich danach, was dein ICO tatsaechlich liefert (z.B. bei Salzwasser-Pools <em>salt</em> statt <em>tds</em>). Platzhalter in der UDP-Nachricht: %VALUE%, %TYPE%, %POOL%, %POOL_NAME%. Min/Max definieren den plausiblen Wertebereich - liegt ein Messwert ausserhalb (oder meldet Ondilo ihn als ungueltig), wird stattdessen -9999 gesendet. Leer lassen, um keine Pruefung durchzufuehren.</small></p>";
if ($live_error) {
    print "<p><small class='hint'>Live-Werte konnten gerade nicht abgerufen werden (" . html_escape($live_error) . "). Es werden die zuletzt bekannten Sensoren angezeigt.</small></p>";
} elsif (!$connected || !$cfg->{POOL_ID}) {
    print "<p><small class='hint'>Noch nicht verbunden bzw. kein Pool ausgewaehlt - unten die Standard-Sensoren. Nach dem Verbinden werden automatisch alle tatsaechlich verfuegbaren Werte erkannt.</small></p>";
}
print "<div class='o2l-sensor-list'>";
for my $type (@sensor_types) {
    my $chk = (($cfg->{"SENSOR_${type}_ENABLED"} // 'false') eq 'true') ? 'checked' : '';
    my $label = $labels{$type} || html_escape($type);
    my $message = $cfg->{"SENSOR_${type}_MESSAGE"} // config::default_sensor_message($type);
    my $live = $live_values{$type};
    my $live_text = '';
    if ($live) {
        $live_text = $live->{is_valid} ? "aktueller Wert: " . html_escape($live->{value}) : "aktueller Wert ungueltig";
    }
    (my $lox_example = $message) =~ s/%VALUE%/\\v/g;
    $lox_example =~ s/%TYPE%/$type/g;
    my $pool_id_str = $cfg->{POOL_ID} // '';
    $lox_example =~ s/%POOL%/$pool_id_str/g;
    my $pool_name_str = config::normalize_name($cfg->{POOL_NAME});
    $lox_example =~ s/%POOL_NAME%/$pool_name_str/g;

    my $is_active = $chk ? 1 : 0;
    print "<div class='o2l-sensor " . ($is_active ? 'active' : 'inactive') . "'>";
    print "<label class='o2l-sensor-head'>";
    print "<input type='checkbox' name='sensor_${type}_enabled' $chk>";
    print "<span class='o2l-state " . ($is_active ? 'ok-text' : 'err-text') . "'>" . ($is_active ? '&#9989; AKTIV' : '&#10060; INAKTIV') . "</span>";
    print "<span>$label</span>" . ($live_text ? " <small class='hint'>&middot; $live_text</small>" : "");
    print "</label>";
    print "<input type='text' name='sensor_${type}_message' value='" . html_escape($message) . "'>";
    my $min_val = $cfg->{"SENSOR_${type}_MIN"} // '';
    my $max_val = $cfg->{"SENSOR_${type}_MAX"} // '';
    print "<div class='o2l-row' style='margin-top:6px'>";
    print "<label style='min-width:auto;margin-right:8px'>Plausibel Min</label>";
    print "<input type='number' step='any' name='sensor_${type}_min' value='" . html_escape($min_val) . "' style='width:100px'>";
    print "<label style='min-width:auto;margin:0 8px'>Max</label>";
    print "<input type='number' step='any' name='sensor_${type}_max' value='" . html_escape($max_val) . "' style='width:100px'>";
    print "</div>";
    print "<p style='margin:6px 0 0'><small class='hint'>Loxone Virtueller UDP-Eingang &ndash; Befehlserkennung: <code>" . html_escape($lox_example) . "</code></small></p>";
    print "</div>";
}
print "</div></section>";
print "<p><small class='hint'>Nach dem Anklicken einer Checkbox wird die AKTIV/INAKTIV-Anzeige erst nach dem Speichern aktualisiert - die Checkbox selbst reagiert aber sofort.</small></p>";

print "<section class='o2l-card'><button class='o2l-btn' type='submit'>Speichern &amp; verbinden</button></section>";
print "</form>";

print "</div>";
page_footer();
