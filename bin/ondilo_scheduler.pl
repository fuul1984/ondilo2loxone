#!/usr/bin/perl

use strict;
use warnings;

use lib "/opt/loxberry/bin/plugins/ondilo2loxone";

use POSIX qw(strftime);
use File::Path qw(make_path);
use JSON qw(encode_json);
use Fcntl qw(:flock);

use config;
use logger;
use udp;
use auth_store;
use ondilo_api;

my $STATUS_FILE = "/opt/loxberry/data/plugins/ondilo2loxone/status.cfg";
my $DEBUG_FILE  = "/opt/loxberry/data/plugins/ondilo2loxone/last_run.json";
my $DATA_DIR    = "/opt/loxberry/data/plugins/ondilo2loxone";
my $LOCK_FILE   = "/opt/loxberry/data/plugins/ondilo2loxone/scheduler.lock";

# Prevents two scheduler runs from overlapping - can otherwise happen when
# the manual "Jetzt synchronisieren" button (sync.cgi, forked immediately)
# lands in the same minute as the regular cron tick, or when one run takes
# unusually long (e.g. a multi-request Ondilo re-login). Without this,
# both instances write status.cfg/last_run.json independently and
# "last writer wins" can silently swallow one run's result. A non-blocking
# flock means a second, overlapping run simply skips itself instead of
# waiting or corrupting output - there will be another chance next minute.
make_path($DATA_DIR, { mode => 0750 }) unless -d $DATA_DIR;
open(my $LOCK_FH, '>>', $LOCK_FILE) or die "Kann Lock-Datei nicht oeffnen: $!\n";
unless (flock($LOCK_FH, LOCK_EX | LOCK_NB)) {
    logger::info('Vorheriger Lauf noch aktiv - dieser Durchlauf wird uebersprungen.');
    exit 0;
}

sub write_status
{
    my (%kv) = @_;
    make_path($DATA_DIR, { mode => 0750 }) unless -d $DATA_DIR;
    my $tmp = "$STATUS_FILE.tmp.$$";
    my $fh;
    unless (open($fh, '>', $tmp)) {
        logger::error("Statusdatei konnte nicht geschrieben werden: $!");
        return;
    }
    for my $k (sort keys %kv) {
        my $v = defined $kv{$k} ? $kv{$k} : '';
        $v =~ s/[\r\n]//g;
        print {$fh} "$k=$v\n";
    }
    close $fh;
    rename($tmp, $STATUS_FILE)
        or logger::error("Statusdatei konnte nicht ersetzt werden: $!");
}

sub read_status
{
    my %kv;
    return \%kv unless -f $STATUS_FILE;
    open(my $fh, '<', $STATUS_FILE) or return \%kv;
    while (my $line = <$fh>) {
        chomp $line;
        $kv{$1} = $2 if $line =~ /^([^=]+)=(.*)$/;
    }
    close $fh;
    return \%kv;
}

# Writes a detailed record of exactly what was received from Ondilo and
# what was sent via UDP for this run, so the settings/status page can show
# it to the user ("was fuer Infos erhalten werden und was gesendet wird").
sub write_debug
{
    my ($record) = @_;
    make_path($DATA_DIR, { mode => 0750 }) unless -d $DATA_DIR;
    my $tmp = "$DEBUG_FILE.tmp.$$";
    my $fh;
    unless (open($fh, '>', $tmp)) {
        logger::error("Debug-/Detaildatei konnte nicht geschrieben werden: $!");
        return;
    }
    print {$fh} encode_json($record);
    close $fh;
    chmod 0640, $tmp;
    rename($tmp, $DEBUG_FILE)
        or logger::error("Debug-/Detaildatei konnte nicht ersetzt werden: $!");
}

my $start_time = time();
my $cfg = config::read_config();

my $debug = {
    run_time    => scalar(localtime($start_time)),
    run_epoch   => $start_time,
    received    => [],   # every measurement Ondilo returned, as-is
    sent        => [],   # every UDP telegram actually sent (or attempted)
    note        => '',
};

if (($cfg->{PLUGIN_ENABLED} // 'true') ne 'true') {
    logger::info('Plugin deaktiviert - ueberspringe Lauf.');
    $debug->{note} = 'Plugin deaktiviert.';
    write_debug($debug);
    exit 0;
}

my $old_status = read_status();
my $now = time();

if (config::migrate_legacy_defaults($cfg)) {
    eval { config::write_config($cfg); };
    logger::info('Alte UDP-Nachrichten-Vorlagen auf neues Format (KEY=VALUE) migriert.');
}

my $udp_host = $cfg->{UDP_HOST} // '';
my $udp_port = $cfg->{UDP_PORT} || 7000;

if (!$udp_host) {
    logger::warning('Kein UDP-Ziel konfiguriert - Einstellungsseite oeffnen.');
    $debug->{note} = 'Kein UDP-Ziel (Miniserver) konfiguriert.';
    write_debug($debug);
    write_status(%$old_status, STATUS => 'ERROR', MESSAGE => $debug->{note}, LAST_RUN => scalar(localtime($now)), LAST_RUN_EPOCH => $now);
    exit 0;
}

my $telegrams = 0;
my $errors    = 0;

sub send_and_log {
    my ($label, $message, $record) = @_;
    $record = 1 unless defined $record;
    my $result = udp::send_udp($udp_host, $udp_port, $message);
    my $ok = ($result =~ /^OK/) ? 1 : 0;
    if ($record) {
        push @{$debug->{sent}}, {
            label   => $label,
            message => $message,
            target  => "$udp_host:$udp_port",
            ok      => $ok,
            result  => $result,
        };
        logger::info("UDP gesendet: $message") if $ok;
    }
    logger::error("$label fehlgeschlagen: $message -> $result") unless $ok;
    return $ok;
}

# ---------------------------------------------------------------------------
# Heartbeat - runs every minute, independent of the Ondilo data interval.
# Deliberately NOT logged at INFO level and NOT included in the "Letzte
# Ausfuehrung im Detail" list: only the actual ICO data poll (below) should
# show up there, so the log/detail stays focused on the interesting part.
# ---------------------------------------------------------------------------
if (($cfg->{HEARTBEAT_ENABLED} // 'true') eq 'true') {
    my $interval = $cfg->{HEARTBEAT_INTERVAL} || 60;
    my $last_hb  = $old_status->{LAST_HEARTBEAT_EPOCH} || 0;
    if ($now - $last_hb >= $interval) {
        # ONDILO_CONNECTED reflects the outcome of the last actual poll
        # (below, every INTERVAL minutes) - not a fresh API call on every
        # heartbeat tick, since Ondilo's Customer API is rate-limited
        # (30 req/h/user) and heartbeat fires every minute. Before the very
        # first successful poll this is pessimistically 0.
        my $connected = ($old_status->{ONDILO_CONNECTED} // 0) ? 1 : 0;
        (my $hb_msg = $cfg->{HEARTBEAT_MESSAGE} // '') =~ s/1(\D*)$/$connected$1/;
        if (send_and_log('Heartbeat', $hb_msg, 0)) {
            $old_status->{LAST_HEARTBEAT_EPOCH} = $now;
        }
    }
}

# ---------------------------------------------------------------------------
# Sensor polling (only every INTERVAL minutes)
# ---------------------------------------------------------------------------
my $poll_interval = ($cfg->{INTERVAL} || 15) * 60;
my $last_poll = $old_status->{LAST_POLL_EPOCH} || 0;

if ($now - $last_poll < $poll_interval) {
    # Only heartbeat ran this minute - leave the last real poll's detail
    # record (last_run.json) untouched instead of overwriting it with an
    # empty one, so "Letzte Ausfuehrung im Detail" keeps showing the last
    # actual ICO data sync until the next one happens.
    write_status(%$old_status, LAST_RUN => scalar(localtime($now)), LAST_RUN_EPOCH => $now, STATUS => ($old_status->{STATUS} // 'UNKNOWN'));
    exit 0;
}

if (!$cfg->{POOL_ID}) {
    logger::warning('Kein Pool ausgewaehlt - Einstellungsseite oeffnen.');
    $debug->{note} = 'Kein Pool/Spa ausgewaehlt.';
    write_debug($debug);
    write_status(%$old_status, STATUS => 'ERROR', MESSAGE => $debug->{note}, LAST_RUN => scalar(localtime($now)), LAST_RUN_EPOCH => $now);
    exit 0;
}

logger::info('Ondilo2Loxone Synchronisation gestartet');
logger::info("UDP-Ziel: $udp_host:$udp_port");

my $access_token = ondilo_api::get_valid_access_token();
if (!$access_token) {
    my $err = ondilo_api::last_error();
    logger::error("Nicht bei Ondilo angemeldet: $err");
    $old_status->{ONDILO_CONNECTED} = 0;
    $debug->{note} = "Ondilo-Anmeldung fehlgeschlagen: $err";
    write_debug($debug);
    write_status(%$old_status, STATUS => 'ERROR', MESSAGE => $debug->{note}, LAST_RUN => scalar(localtime($now)), LAST_RUN_EPOCH => $now);
    exit 0;
}
$old_status->{ONDILO_CONNECTED} = 1;

# Dynamic discovery: ask Ondilo for every measurement type it currently
# reports, instead of relying on a fixed hardcoded list.
my ($measures, $api_err) = ondilo_api::last_measures_all($access_token, $cfg->{POOL_ID});
if (!$measures) {
    logger::error("Abruf der Messwerte fehlgeschlagen: $api_err");
    $old_status->{ONDILO_CONNECTED} = 0;
    $debug->{note} = $api_err;
    write_debug($debug);
    write_status(%$old_status, STATUS => 'ERROR', MESSAGE => $api_err, LAST_RUN => scalar(localtime($now)), LAST_RUN_EPOCH => $now);
    exit 0;
}

logger::info(scalar(@$measures) . " Messwerte von Ondilo erhalten (Pool: " . ($cfg->{POOL_NAME} || $cfg->{POOL_ID}) . ")");

# Record exactly what Ondilo returned, valid or not, enabled or not - this
# is the raw "was fuer Infos erhalten werden" view. Also written directly
# to the log (not just last_run.json) so the age/stale decision is visible
# without opening the settings page - this was previously only visible in
# the detail view, which made diagnosing staleness issues from the log
# alone impossible.
for my $m (@$measures) {
    my $type       = $m->{data_type};
    my $value_time = $m->{value_time};
    my $epoch      = config::parse_value_time($value_time);
    my $age_min    = defined $epoch ? sprintf('%.1f', ($now - $epoch) / 60) : 'unbekannt';
    my $is_stale   = config::is_stale($cfg, $value_time, $now) ? 1 : 0;

    push @{$debug->{received}}, {
        type        => $type,
        value       => $m->{value},
        is_valid    => $m->{is_valid} ? 1 : 0,
        value_time  => $value_time,
        exclusion   => $m->{exclusion_reason},
        stale       => $is_stale,
    };

    logger::info(
        "Empfangen: $type=" . (defined $m->{value} ? $m->{value} : '(kein Wert)')
        . " | value_time=" . (defined $value_time ? $value_time : '(fehlt)')
        . " | Alter=${age_min}min | stale=" . ($is_stale ? 'ja' : 'nein')
        . " | is_valid=" . ($m->{is_valid} ? 'ja' : 'nein')
    );
}

# Make sure every discovered type has a config entry (auto-enabled with a
# sensible default UDP message) so it shows up on the settings page and
# gets sent without any manual step.
my $config_changed = 0;
for my $m (@$measures) {
    $config_changed = 1 if config::ensure_sensor_defaults($cfg, $m->{data_type});
}
if ($config_changed) {
    eval { config::write_config($cfg); };
    logger::warning("Konnte neu erkannte Sensoren nicht speichern: $@") if $@;
}

my %values;
my %stale;
for my $m (@$measures) {
    next unless $m->{is_valid};
    $values{ $m->{data_type} } = $m->{value};
    $stale{ $m->{data_type} }  = config::is_stale($cfg, $m->{value_time}, $now);
}

my @errmsgs;
my $skipped = 0;
for my $m (@$measures) {
    my $type = $m->{data_type};
    if (($cfg->{"SENSOR_${type}_ENABLED"} // 'false') ne 'true') {
        $skipped++;
        next;
    }
    next unless exists $values{$type};

    my $tmpl  = $cfg->{"SENSOR_${type}_MESSAGE"} // config::default_sensor_message($type);
    # A stale reading (older than STALE_MINUTES) is sent as -9999 just like
    # an implausible one - Ondilo itself only refreshes roughly hourly, so
    # this only fires if the ICO has actually stopped reporting.
    my $value = $stale{$type} ? -9999 : config::plausible_value($cfg, $type, $values{$type});
    (my $msg = $tmpl) =~ s/%VALUE%/$value/g;
    $msg =~ s/%TYPE%/$type/g;
    $msg =~ s/%POOL%/$cfg->{POOL_ID}/g;
    $msg =~ s/%POOL_NAME%/config::normalize_name($cfg->{POOL_NAME})/ge;

    if (send_and_log("Sensor $type", $msg)) {
        $telegrams++;
    } else {
        $errors++;
        push @errmsgs, "$type: " . $debug->{sent}[-1]{result};
    }
}
logger::info("$skipped Wert(e) deaktiviert - nicht gesendet.") if $skipped;

my $duration = time() - $start_time;
my $status_text = $errors ? 'ERROR' : 'OK';
my $message = @errmsgs
    ? join('; ', @errmsgs)
    : "Synchronisation erfolgreich: " . scalar(@$measures) . " Werte erhalten, $telegrams Telegramme, ${duration}s";

logger::info($message);
$debug->{note} = $message;
$debug->{duration} = $duration;
write_debug($debug);

write_status(
    %$old_status,
    STATUS              => $status_text,
    MESSAGE             => $message,
    LAST_RUN            => scalar(localtime($now)),
    LAST_RUN_EPOCH      => $now,
    LAST_POLL_EPOCH     => $now,
    LAST_SUCCESS        => ($errors ? ($old_status->{LAST_SUCCESS} // 'Noch keine erfolgreiche Uebertragung') : scalar(localtime($now))),
    LAST_SUCCESS_EPOCH  => ($errors ? ($old_status->{LAST_SUCCESS_EPOCH} // '') : $now),
    TELEGRAMS           => $telegrams,
    ERRORS              => $errors,
    DURATION            => $duration,
    RECEIVED_COUNT      => scalar(@$measures),
);

exit 0;
