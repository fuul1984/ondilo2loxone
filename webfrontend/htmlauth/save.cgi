#!/usr/bin/perl
use strict; use warnings; use utf8;

use lib "/opt/loxberry/bin/plugins/ondilo2loxone";
use CGI;
use config;
use auth_store;
use ondilo_api;
use miniservers;
use udp;
use logger;

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
    $text =~ s/&/&amp;/g; $text =~ s/</&lt;/g; $text =~ s/>/&gt;/g; $text =~ s/"/&quot;/g;
    return $text;
}
sub trim { my ($s) = @_; $s //= ''; $s =~ s/^\s+|\s+$//g; return $s; }

my $cgi = CGI->new;
my $cfg = config::read_config();
my @errors;

my $email    = trim(scalar $cgi->param('email'));
my $password = scalar($cgi->param('password')) // '';
$cfg->{ONDILO_EMAIL} = $email;

my $msno = trim(scalar $cgi->param('miniserver_no'));
my $manual_host = trim(scalar $cgi->param('udp_host_manual'));

if (length $msno) {
    my @servers = eval { miniservers::get_servers() };
    my ($match) = grep { "$_->{no}" eq $msno } @servers;
    if ($match) {
        $cfg->{MINISERVER_NO}   = $match->{no};
        $cfg->{MINISERVER_NAME} = $match->{name};
        $cfg->{UDP_HOST}        = $match->{host};
    } else {
        push @errors, 'Bitte einen gueltigen Miniserver auswaehlen.';
    }
} elsif (length $manual_host) {
    if ($manual_host !~ /^\d{1,3}(\.\d{1,3}){3}$/) {
        push @errors, 'Die manuell eingetragene Miniserver-IP ist ungueltig.';
    } else {
        $cfg->{UDP_HOST} = $manual_host;
        $cfg->{MINISERVER_NO} = '';
        $cfg->{MINISERVER_NAME} = 'manuell';
    }
} else {
    push @errors, 'Bitte einen Miniserver auswaehlen oder eine IP eintragen.';
}

my $port = trim(scalar $cgi->param('udp_port'));
if ($port !~ /^\d+$/ || $port < 1 || $port > 65535) {
    push @errors, 'Der UDP-Port muss zwischen 1 und 65535 liegen.';
} else {
    $cfg->{UDP_PORT} = $port;
}

my $interval = trim(scalar $cgi->param('interval'));
if ($interval !~ /^\d+$/ || $interval < 2 || $interval > 1440) {
    push @errors, 'Das Abfrageintervall muss zwischen 2 und 1440 Minuten liegen (Ondilo begrenzt Anfragen auf 30/Stunde).';
} else {
    $cfg->{INTERVAL} = $interval;
}

my $stale_minutes = trim(scalar $cgi->param('stale_minutes'));
if ($stale_minutes !~ /^\d+$/) {
    push @errors, 'Der Aktualitaets-Schwellwert muss eine Zahl (Minuten) sein, 0 = Pruefung deaktiviert.';
} else {
    $cfg->{STALE_MINUTES} = $stale_minutes;
}

$cfg->{HEARTBEAT_ENABLED} = defined($cgi->param('hb_enabled')) ? 'true' : 'false';
my $hb_interval = trim(scalar $cgi->param('hb_interval'));
if ($hb_interval !~ /^\d+$/ || $hb_interval < 1) {
    push @errors, 'Das Heartbeat-Intervall muss eine positive Zahl (Sekunden) sein.';
} else {
    $cfg->{HEARTBEAT_INTERVAL} = $hb_interval;
}
$cfg->{HEARTBEAT_MESSAGE} = udp::sanitize_message(scalar $cgi->param('hb_message'));

for my $type (config::sensor_types_from_config($cfg)) {
    $cfg->{"SENSOR_${type}_ENABLED"} = defined($cgi->param("sensor_${type}_enabled")) ? 'true' : 'false';
    my $msg = $cgi->param("sensor_${type}_message");
    if (defined $msg && length $msg) {
        $msg =~ s/[\x00-\x1F\x7F]//g;
        $msg = substr($msg, 0, 200);
        $cfg->{"SENSOR_${type}_MESSAGE"} = $msg;
    }

    my $min_raw = trim(scalar $cgi->param("sensor_${type}_min"));
    my $max_raw = trim(scalar $cgi->param("sensor_${type}_max"));
    my $is_num  = qr/^-?\d+(\.\d+)?$/;

    if (!length($min_raw) && !length($max_raw)) {
        # Both empty -> plausibility check explicitly disabled for this type.
        $cfg->{"SENSOR_${type}_MIN"} = '';
        $cfg->{"SENSOR_${type}_MAX"} = '';
    } elsif ($min_raw =~ $is_num && $max_raw =~ $is_num && $min_raw <= $max_raw) {
        $cfg->{"SENSOR_${type}_MIN"} = $min_raw;
        $cfg->{"SENSOR_${type}_MAX"} = $max_raw;
    } else {
        push @errors, "Plausibler Bereich fuer '$type' ist ungueltig (Min/Max muessen Zahlen sein, Min <= Max, oder beide leer lassen).";
    }
}

my $login_attempted = 0;
my $login_ok = 0;
my $login_error = '';
my @pools;

if (!@errors) {
    eval { config::write_config($cfg); };
    if ($@) {
        push @errors, "Speichern der Konfiguration fehlgeschlagen: $@";
    }
}

if (!@errors && length $password) {
    $login_attempted = 1;
    my $data = ondilo_api::login_with_password($email, $password);
    if ($data) {
        $login_ok = 1;
        eval {
            auth_store::store_token(
                email         => $email,
                access_token  => $data->{access_token},
                refresh_token => $data->{refresh_token},
                expires_at    => $data->{expires_at},
            );
            auth_store::store_password($password);
        };
        push @errors, "Anmeldung erfolgreich, aber Speichern fehlgeschlagen: $@" if $@;
    } else {
        $login_error = ondilo_api::last_error();
        push @errors, "Ondilo-Anmeldung fehlgeschlagen: $login_error";
    }
}

# If we now have a usable access token (freshly logged in, or already
# connected from before), try to fetch/refresh the pool list.
if (!@errors) {
    my $access_token = ondilo_api::get_valid_access_token();
    if ($access_token) {
        my ($pool_data, $perr) = ondilo_api::list_pools($access_token);
        if ($pool_data && ref($pool_data) eq 'ARRAY') {
            @pools = @$pool_data;
            if (@pools == 1) {
                $cfg->{POOL_ID}   = $pools[0]{id};
                $cfg->{POOL_NAME} = $pools[0]{name} // "Pool $pools[0]{id}";
                eval { config::write_config($cfg); };
            }
        }
    }
}

page_header("Ondilo2Loxone - Einstellungen gespeichert");
print '<style>*{box-sizing:border-box}body{margin:0}.o2l-wrap2{max-width:900px;margin:0 auto;padding:12px 14px 24px;font-family:Arial,Helvetica,sans-serif}.o2l-wrap2 a{color:#00a99d}@media(max-width:600px){.o2l-wrap2 select{width:100%;max-width:none;margin-bottom:8px}.o2l-wrap2 button{width:100%}}</style>';
print "<div class='o2l-wrap2'>";

if (@errors) {
    print "<section style='background:#ffebee;border:1px solid #ef9a9a;border-radius:8px;padding:18px;margin-bottom:20px'><h2 style='margin-top:0'>Es gab Probleme</h2><ul>";
    print "<li>" . html_escape($_) . "</li>" for @errors;
    print "</ul></section>";
} else {
    print "<section style='background:#e8f5e9;border:1px solid #a5d6a7;border-radius:8px;padding:18px;margin-bottom:20px'><h2 style='margin-top:0'>Gespeichert</h2>";
    print "<p>Die Einstellungen wurden gespeichert." . ($login_attempted && $login_ok ? " Die Ondilo-Anmeldung war erfolgreich." : "") . "</p></section>";
}

if (@pools > 1) {
    print "<section style='background:#fff;border:1px solid #dfe4e8;border-radius:8px;padding:18px;margin-bottom:20px'>";
    print "<h2 style='margin-top:0'>Pool/Spa auswaehlen</h2>";
    print "<form method='post' action='select_pool.cgi'>";
    print "<select name='pool_id' style='padding:8px;min-width:260px'>";
    for my $p (@pools) {
        my $sel = (defined $cfg->{POOL_ID} && "$cfg->{POOL_ID}" eq "$p->{id}") ? 'selected' : '';
        print "<option value='" . html_escape($p->{id}) . "' $sel>" . html_escape($p->{name} // "Pool $p->{id}") . "</option>";
    }
    print "</select> <button type='submit' style='padding:9px 16px;border:0;border-radius:6px;background:#00a99d;color:#fff!important;-webkit-text-fill-color:#fff!important;text-shadow:none!important;font-weight:700'>Uebernehmen</button>";
    print "</form></section>";
}

print "<p><a href='settings.cgi'>Zurueck zu den Einstellungen</a> &middot; <a href='index.cgi'>Zur Startseite</a></p>";
print "</div>";
page_footer();
