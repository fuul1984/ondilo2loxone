#!/usr/bin/perl
use strict; use warnings; use utf8;

use lib "/opt/loxberry/bin/plugins/ondilo2loxone";
use config;
use version;
use JSON qw(decode_json);

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

sub read_status {
    my $file = "/opt/loxberry/data/plugins/ondilo2loxone/status.cfg";
    my %kv;
    return \%kv unless -f $file;
    open(my $fh, '<', $file) or return \%kv;
    while (my $line = <$fh>) {
        chomp $line;
        $kv{$1} = $2 if $line =~ /^([^=]+)=(.*)$/;
    }
    close $fh;
    return \%kv;
}

sub read_debug {
    my $file = "/opt/loxberry/data/plugins/ondilo2loxone/last_run.json";
    return undef unless -f $file;
    open(my $fh, '<', $file) or return undef;
    local $/;
    my $raw = <$fh>;
    close $fh;
    my $data;
    eval { $data = decode_json($raw // ''); };
    return (ref($data) eq 'HASH') ? $data : undef;
}

my $plugin_version = version::plugin_version();
my $cfg    = config::read_config();
my $status = read_status();
my $debug  = read_debug();

my $enabled = ($cfg->{PLUGIN_ENABLED} // 'true') eq 'true';
my $safe_message = html_escape($status->{MESSAGE} // 'Noch keine Synchronisation.');
my $safe_last_run = html_escape($status->{LAST_RUN} // 'Noch keine Synchronisation');
my $safe_last_success = html_escape($status->{LAST_SUCCESS} // 'Noch keine erfolgreiche Uebertragung');
my $status_text = $status->{STATUS} // 'UNKNOWN';
my $status_class = $status_text eq 'OK' ? 'ok' : ($status_text eq 'ERROR' ? 'err' : 'warn');
my $toggle_action = $enabled ? 'disable' : 'enable';
my $toggle_label  = $enabled ? 'Plugin deaktivieren' : 'Plugin aktivieren';

page_header("Ondilo2Loxone");

print <<'CSS';
<style>
*{box-sizing:border-box}
body{margin:0}
.o2l-wrap{max-width:900px;margin:0 auto;padding:12px 14px 24px;font-family:Arial,Helvetica,sans-serif}
.o2l-nav{display:flex;flex-wrap:wrap;gap:10px;margin:0 0 18px}
.o2l-nav a,.o2l-btn{display:inline-flex;align-items:center;justify-content:center;min-height:44px;padding:10px 16px;border-radius:7px;background:#00a99d;color:#fff!important;-webkit-text-fill-color:#fff!important;text-shadow:none!important;font-family:Arial,Helvetica,sans-serif!important;font-size:15px!important;line-height:1.25!important;font-weight:700!important;letter-spacing:0!important;text-decoration:none!important;border:0!important;box-shadow:none!important;cursor:pointer}
.o2l-nav a:link,.o2l-nav a:visited,.o2l-nav a:hover,.o2l-nav a:active,.o2l-nav a:focus,.o2l-btn:link,.o2l-btn:visited,.o2l-btn:hover,.o2l-btn:active,.o2l-btn:focus{color:#fff!important;-webkit-text-fill-color:#fff!important;text-shadow:none!important;text-decoration:none!important}
.o2l-nav a:hover,.o2l-btn:hover{background:#00867c!important}
.o2l-card{background:#fff;border:1px solid #dfe4e8;border-radius:10px;box-shadow:0 2px 8px rgba(0,0,0,.06);padding:18px;margin-bottom:16px}
.o2l-banner{padding:14px;margin-bottom:16px;border-radius:8px;font-weight:700;word-break:break-word}
.ok{color:#1b5e20;background:#e8f5e9;border:1px solid #a5d6a7}
.err{color:#b71c1c;background:#ffebee;border:1px solid #ef9a9a}
.warn{color:#5d4037;background:#fff8e1;border:1px solid #ffe082}
.o2l-details{display:grid;grid-template-columns:220px 1fr;gap:10px 20px}
.o2l-label{color:#607d8b;font-weight:700}
.o2l-version{padding:6px 10px;background:#eceff1;border-radius:6px;color:#455a64;font-size:13px;font-weight:700;white-space:nowrap}
.o2l-header-row{display:flex;justify-content:space-between;align-items:flex-start;gap:14px;flex-wrap:wrap}
.o2l-scroll{overflow-x:auto;-webkit-overflow-scrolling:touch}
.o2l-table{border-collapse:collapse;width:100%;font-size:14px;white-space:nowrap}
.o2l-table th,.o2l-table td{padding:.4em .6em;text-align:left;border-bottom:1px solid #eee}
.o2l-table code{white-space:nowrap}
.ok-text{color:#1b5e20;font-weight:700}
.err-text{color:#b71c1c;font-weight:700}
.o2l-pill{display:inline-block;padding:3px 10px;border-radius:12px;font-size:13px;font-weight:700;white-space:nowrap}
.o2l-pill.on{background:#e8f5e9;color:#1b5e20}
.o2l-pill.off{background:#ffebee;color:#b71c1c}
.o2l-table tr.inactive-row{opacity:.6}
.o2l-table tr.active-row{background:#f4faf5}
@media (max-width:600px){
  .o2l-details{grid-template-columns:1fr}
  .o2l-details .o2l-label{margin-top:8px}
  .o2l-nav a,.o2l-btn{flex:1 1 auto;width:100%}
  .o2l-nav{flex-direction:column}
  h2{font-size:1.15em}
  .o2l-table{font-size:13px}
}
</style>
CSS

print "<div class='o2l-wrap'>";
print "<nav class='o2l-nav'><a href='index.cgi'>Startseite</a><a href='settings.cgi'>Einstellungen</a><a href='sync.cgi'>Jetzt synchronisieren</a></nav>";

print "<section class='o2l-card'><div style='display:flex;justify-content:space-between;align-items:flex-start'>";
print "<div><h2 style='margin-top:0'>Ondilo2Loxone</h2><p>Ondilo-ICO-Poolsensor auslesen und Messwerte per UDP an den Loxone Miniserver senden.</p></div>";
print "<div class='o2l-version'>Version " . html_escape($plugin_version) . "</div></div></section>";

print "<section class='o2l-card'><h2>Status</h2><div class='o2l-banner $status_class'>$safe_message</div>";
print "<div class='o2l-details'>";
print "<div class='o2l-label'>Plugin</div><div>" . ($enabled ? 'aktiv' : 'deaktiviert') . "</div>";
print "<div class='o2l-label'>Ondilo-Konto</div><div>" . html_escape($cfg->{ONDILO_EMAIL} || '(nicht verbunden)') . "</div>";
print "<div class='o2l-label'>Pool/Spa</div><div>" . html_escape($cfg->{POOL_NAME} || '(nicht ausgewaehlt)') . "</div>";
print "<div class='o2l-label'>Miniserver</div><div>" . html_escape($cfg->{MINISERVER_NAME} || '-') . " (" . html_escape($cfg->{UDP_HOST} || '-') . ":" . html_escape($cfg->{UDP_PORT} // '') . ")</div>";
print "<div class='o2l-label'>Letzter Lauf</div><div>$safe_last_run</div>";
print "<div class='o2l-label'>Letzte erfolgreiche Uebertragung</div><div>$safe_last_success</div>";
print "<div class='o2l-label'>Intervall</div><div>" . html_escape($cfg->{INTERVAL} // '15') . " Minuten</div>";
print "</div>";
print "<form method='post' action='toggle.cgi' style='margin-top:16px'><input type='hidden' name='action' value='$toggle_action'><button class='o2l-btn' type='submit'>$toggle_label</button></form>";
print "</section>";

if ($debug) {
    print "<section class='o2l-card'><h2>Letzte Ausfuehrung im Detail</h2>";
    print "<p><small class='hint'>" . html_escape($debug->{run_time} // '') . "" . (defined $debug->{duration} ? " &middot; Dauer " . html_escape($debug->{duration}) . "s" : "") . "</small></p>";

    if ($debug->{received} && @{$debug->{received}}) {
        print "<h3 style='margin-bottom:6px'>Von Ondilo erhalten</h3>";
        print "<div class='o2l-scroll'><table class='o2l-table'><tr><th>Typ</th><th>Wert</th><th>Gueltig</th><th>Aktuell</th><th>Aktiv</th><th>Zeitstempel</th></tr>";
        for my $r (@{$debug->{received}}) {
            my $valid = $r->{is_valid} ? 'ja' : 'nein (' . html_escape($r->{exclusion} // '?') . ')';
            my $fresh = $r->{stale} ? "<span class='err-text'>veraltet</span>" : 'ja';
            my $sensor_enabled = (($cfg->{"SENSOR_$r->{type}_ENABLED"} // 'false') eq 'true');
            my $active = $sensor_enabled ? "<span class='o2l-pill on'>&#9989; AKTIV</span>" : "<span class='o2l-pill off'>&#10060; INAKTIV</span>";
            my $row_class = $sensor_enabled ? 'active-row' : 'inactive-row';
            print "<tr class='$row_class'><td>" . html_escape($r->{type}) . "</td><td>" . html_escape($r->{value}) . "</td><td>$valid</td><td>$fresh</td><td>$active</td><td>" . html_escape($r->{value_time} // '') . "</td></tr>";
        }
        print "</table></div>";
        print "<p><small class='hint'>Aktiv/inaktiv wird pro Wert in den <a href='settings.cgi'>Einstellungen</a> festgelegt.</small></p>";
    } else {
        print "<p><small class='hint'>In diesem Lauf wurden keine Messwerte abgefragt" . ($debug->{note} ? " (" . html_escape($debug->{note}) . ")" : "") . ".</small></p>";
    }

    if ($debug->{sent} && @{$debug->{sent}}) {
        print "<h3 style='margin-bottom:6px'>Per UDP gesendet</h3>";
        print "<div class='o2l-scroll'><table class='o2l-table'><tr><th>Label</th><th>UDP-Nachricht</th><th>Ziel</th><th>Ergebnis</th></tr>";
        for my $s (@{$debug->{sent}}) {
            my $res_class = $s->{ok} ? 'ok-text' : 'err-text';
            print "<tr><td>" . html_escape($s->{label}) . "</td><td><code>" . html_escape($s->{message}) . "</code></td><td>" . html_escape($s->{target}) . "</td><td class='$res_class'>" . html_escape($s->{result}) . "</td></tr>";
        }
        print "</table></div>";
    }
    print "</section>";
}

print "<section class='o2l-card'><h2>Aktionen</h2><div style='display:flex;gap:12px;flex-wrap:wrap'>";
print "<a class='o2l-btn' href='sync.cgi'>Jetzt synchronisieren</a>";
print "<a class='o2l-btn' href='settings.cgi'>Einstellungen</a>";
print "</div></section>";

print "</div>";
page_footer();
