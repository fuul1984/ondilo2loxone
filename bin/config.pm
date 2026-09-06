package config;

use strict;
use warnings;
use File::Basename qw(dirname);
use File::Path qw(make_path);
use Fcntl qw(:flock);

our $CONFIG_FILE = "/opt/loxberry/config/plugins/ondilo2loxone/ondilo.cfg";
our $LOCK_FILE   = "/opt/loxberry/config/plugins/ondilo2loxone/.ondilo.cfg.lock";

# Sensors are discovered dynamically at runtime from whatever the Ondilo
# API actually returns for the connected pool (see ondilo_api::last_measures_all
# and ondilo_scheduler.pl) - this list only seeds sensible defaults so the
# settings page has something to show before the first successful sync.
our @KNOWN_SENSOR_TYPES = qw(temperature ph orp salt tds battery rssi);

# Sensible default plausibility ranges [min, max] per sensor type, used to
# seed SENSOR_<type>_MIN/_MAX the first time a type is seen. The user can
# freely override these in the settings page. Types without an entry here
# get no default range (i.e. no plausibility check) until the user sets one.
our %DEFAULT_RANGE = (
    temperature => [-10, 50],
    ph          => [0, 14],
    orp         => [0, 1000],
    salt        => [0, 50000],
    tds         => [0, 50000],
    battery     => [0, 100],
    rssi        => [-100, 0],
);

sub default_sensor_range
{
    my ($type) = @_;
    my $r = $DEFAULT_RANGE{$type};
    return $r ? @$r : (undef, undef);
}

our %DEFAULTS = (
    PLUGIN_ENABLED          => 'true',
    ONDILO_EMAIL            => '',
    POOL_ID                 => '',
    POOL_NAME               => '',
    MINISERVER_NO           => '',
    MINISERVER_NAME         => '',
    UDP_HOST                => '',
    UDP_PORT                => '7000',
    INTERVAL                => '15',
    STALE_MINUTES           => '0',
    HEARTBEAT_ENABLED       => 'true',
    HEARTBEAT_INTERVAL      => '60',
    # UDP format follows the same simple "KEY=VALUE" convention as the
    # FYTA Connect plugin, so it can be picked up by a Loxone virtual UDP
    # input command recognition string of the form "ONDILO_Heartbeat=\v".
    HEARTBEAT_MESSAGE       => 'ONDILO_Heartbeat=1',
);

for my $type (@KNOWN_SENSOR_TYPES) {
    $DEFAULTS{"SENSOR_${type}_ENABLED"} = 'true';
    $DEFAULTS{"SENSOR_${type}_MESSAGE"} = default_sensor_message($type);
    my ($min, $max) = default_sensor_range($type);
    $DEFAULTS{"SENSOR_${type}_MIN"} = defined $min ? $min : '';
    $DEFAULTS{"SENSOR_${type}_MAX"} = defined $max ? $max : '';
}

sub default_sensor_message
{
    my ($type) = @_;
    return 'ONDILO_' . uc($type) . '=%VALUE%';
}

# Old (pre-v0.0.5) auto-generated defaults, kept only so we can recognise
# and upgrade them - see migrate_legacy_defaults() below.
my %LEGACY_ABBR = (
    temperature => 'TEMP',
    ph          => 'PH',
    orp         => 'ORP',
    salt        => 'SALT',
    tds         => 'TDS',
    battery     => 'BATTERY',
    rssi        => 'RSSI',
);
my $LEGACY_HEARTBEAT = 'ONDILO;HEARTBEAT;1';

sub _legacy_sensor_message
{
    my ($type) = @_;
    my $abbr = $LEGACY_ABBR{$type};
    return undef unless $abbr;
    return "ONDILO;${abbr};%VALUE%";
}

# One-time, conservative upgrade: replaces a stored message ONLY if it is
# byte-for-byte identical to the OLD auto-generated default (i.e. the user
# never touched it). Anything the user customised - old format or not -
# is left exactly as-is. Returns 1 if anything changed.
sub migrate_legacy_defaults
{
    my ($cfg) = @_;
    my $changed = 0;

    if (defined $cfg->{HEARTBEAT_MESSAGE} && $cfg->{HEARTBEAT_MESSAGE} eq $LEGACY_HEARTBEAT) {
        $cfg->{HEARTBEAT_MESSAGE} = $DEFAULTS{HEARTBEAT_MESSAGE};
        $changed = 1;
    }

    for my $type (sensor_types_from_config($cfg)) {
        my $legacy = _legacy_sensor_message($type);
        next unless defined $legacy;
        my $key = "SENSOR_${type}_MESSAGE";
        if (defined $cfg->{$key} && $cfg->{$key} eq $legacy) {
            $cfg->{$key} = default_sensor_message($type);
            $changed = 1;
        }
    }

    return $changed;
}

# Turns an arbitrary label (pool name, measurement type, ...) into a
# Loxone/UDP-friendly identifier: letters/digits/underscore only, umlauts
# transliterated - same approach as the FYTA Connect plugin uses for plant
# names.
sub normalize_name
{
    my ($text) = @_;
    $text = '' unless defined $text;
    $text =~ s/ä/ae/g; $text =~ s/ö/oe/g; $text =~ s/ü/ue/g;
    $text =~ s/Ä/Ae/g; $text =~ s/Ö/Oe/g; $text =~ s/Ü/Ue/g; $text =~ s/ß/ss/g;
    $text =~ s/\s+/_/g;
    $text =~ s/[^A-Za-z0-9_]//g;
    return length($text) ? $text : 'Unbekannt';
}

sub read_config
{
    my %cfg = %DEFAULTS;

    return \%cfg unless -f $CONFIG_FILE;

    open(my $fh, '<', $CONFIG_FILE)
        or return \%cfg;

    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/\r//g;

        next if $line =~ /^\s*$/;
        next if $line =~ /^\s*[#;]/;

        if ($line =~ /^\s*([^=]+?)\s*=\s*(.*?)\s*$/) {
            $cfg{$1} = $2;
        }
    }

    close $fh;
    return \%cfg;
}

sub write_config
{
    my ($cfg) = @_;
    die "Ungueltige Konfiguration.\n"
        unless $cfg && ref($cfg) eq 'HASH';

    my %merged = (%DEFAULTS, %{$cfg});
    my $dir = dirname($CONFIG_FILE);
    make_path($dir, { mode => 0750 }) unless -d $dir;

    # Exclusive lock for the whole write+rename: the scheduler (cron, every
    # minute) and the settings web pages can both call write_config() at
    # almost the same time. Without serialising here, one process's write
    # could be silently overwritten by the other's - a blocking flock just
    # makes the second caller wait its turn instead of racing.
    open(my $lock_fh, '>>', $LOCK_FILE)
        or die "Kann Lock-Datei nicht oeffnen: $!\n";
    flock($lock_fh, LOCK_EX);

    my $temp = "$CONFIG_FILE.tmp.$$";
    open(my $fh, '>', $temp)
        or die "Kann Konfigurationsdatei nicht schreiben: $!\n";

    my @ordered = qw(
        PLUGIN_ENABLED ONDILO_EMAIL POOL_ID POOL_NAME MINISERVER_NO MINISERVER_NAME
        UDP_HOST UDP_PORT INTERVAL STALE_MINUTES
        HEARTBEAT_ENABLED HEARTBEAT_INTERVAL HEARTBEAT_MESSAGE
    );
    my %written;

    for my $key (@ordered, sort keys %merged) {
        next if $written{$key}++;
        my $value = defined $merged{$key} ? $merged{$key} : '';
        $value =~ s/[\r\n]//g;
        print {$fh} "$key=$value\n";
    }

    close $fh or die "Kann Konfigurationsdatei nicht schliessen: $!\n";
    chmod 0600, $temp;
    rename($temp, $CONFIG_FILE)
        or die "Kann Konfigurationsdatei nicht ersetzen: $!\n";

    flock($lock_fh, LOCK_UN);
    close $lock_fh;

    return 1;
}

sub ensure_defaults
{
    my $cfg = read_config();
    return write_config($cfg);
}

# Returns the sorted list of sensor type names currently known to the
# config (i.e. anything with a SENSOR_<type>_ENABLED key) - this is how
# the settings page and scheduler stay dynamic instead of using a fixed
# hardcoded sensor list.
sub sensor_types_from_config
{
    my ($cfg) = @_;
    my %types;
    for my $key (keys %{$cfg}) {
        $types{$1} = 1 if $key =~ /^SENSOR_(.+)_ENABLED$/;
    }
    return sort keys %types;
}

# Makes sure a SENSOR_<type>_ENABLED / _MESSAGE pair exists for a newly
# discovered measurement type, without overwriting an existing (possibly
# user-edited) entry. Returns 1 if a new default was added.
sub ensure_sensor_defaults
{
    my ($cfg, $type) = @_;
    my $added = 0;
    unless (exists $cfg->{"SENSOR_${type}_ENABLED"}) {
        $cfg->{"SENSOR_${type}_ENABLED"} = 'true';
        $added = 1;
    }
    unless (exists $cfg->{"SENSOR_${type}_MESSAGE"}) {
        $cfg->{"SENSOR_${type}_MESSAGE"} = default_sensor_message($type);
        $added = 1;
    }
    unless (exists $cfg->{"SENSOR_${type}_MIN"} && exists $cfg->{"SENSOR_${type}_MAX"}) {
        my ($min, $max) = default_sensor_range($type);
        $cfg->{"SENSOR_${type}_MIN"} = defined $min ? $min : '';
        $cfg->{"SENSOR_${type}_MAX"} = defined $max ? $max : '';
        $added = 1;
    }
    return $added;
}

# Returns $value unchanged if it is numeric and lies within the configured
# [SENSOR_<type>_MIN, SENSOR_<type>_MAX] range, otherwise -9999 - a sentinel
# Loxone-side logic can filter on ("Wert ignorieren wenn = -9999"). If no
# range is configured for the type, the value passes through unchecked. A
# missing/non-numeric $value (e.g. Ondilo reported is_valid=false) always
# maps to -9999.
sub plausible_value
{
    my ($cfg, $type, $value) = @_;
    return -9999 unless defined $value && $value =~ /^-?\d+(\.\d+)?$/;

    my $min = $cfg->{"SENSOR_${type}_MIN"};
    my $max = $cfg->{"SENSOR_${type}_MAX"};
    return $value unless defined $min && defined $max && length($min) && length($max);

    return ($value >= $min && $value <= $max) ? $value : -9999;
}

# Parses an Ondilo "value_time" timestamp into epoch seconds (UTC). Ondilo's
# API has been observed to return at least two shapes for this field:
#   - ISO 8601 with 'T' separator, optionally with fractional seconds and/or
#     a trailing 'Z' or numeric offset, e.g. "2024-05-01T10:23:00.000Z"
#   - a plain "YYYY-MM-DD HH:MM:SS" string with a space instead of 'T' and
#     no timezone marker at all (seen in production logs)
# Both are treated as UTC. Previously only the first shape was accepted;
# Time::Piece::strptime does NOT reject a mismatched literal like the space
# here, it silently stops parsing at that point and defaults the remainder
# (the whole time-of-day!) to 00:00:00, which made every reading look many
# hours older than it really is - the root cause of persistent "veraltete
# Daten" reports. Returns undef if it cannot be parsed - callers should
# then treat the value as "age unknown" rather than guessing.
sub parse_value_time
{
    my ($value_time) = @_;
    return undef unless defined $value_time && length $value_time;
    my $t = $value_time;
    $t =~ s/\.\d+//;                 # strip fractional seconds, if any
    $t =~ s/Z$//i;                   # strip trailing Z, if any
    $t =~ s/[+-]\d{2}:?\d{2}$//;      # strip trailing numeric UTC offset, if any
    $t =~ s/^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})$/$1T$2/;
    return undef unless $t =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/;
    my $epoch = eval {
        require Time::Piece;
        Time::Piece->strptime($t, "%Y-%m-%dT%H:%M:%S")->epoch;
    };
    return $@ ? undef : $epoch;
}

# True if a measurement's value_time is older than the configured
# STALE_MINUTES threshold. Unparseable/missing timestamps are treated as
# NOT stale (fail open), so a change in Ondilo's timestamp format never
# silently blocks all sensor data. STALE_MINUTES == 0 disables the check
# entirely (see note in settings.cgi: some APIs, possibly Ondilo's too,
# only bump the timestamp when the value actually changes, which would
# otherwise cause false "stale" positives for a stable-but-healthy sensor).
sub is_stale
{
    my ($cfg, $value_time, $now) = @_;
    $now //= time();
    my $threshold_min = $cfg->{STALE_MINUTES};
    return 0 unless defined $threshold_min && $threshold_min > 0;
    my $epoch = parse_value_time($value_time);
    return 0 unless defined $epoch;
    return ($now - $epoch) > ($threshold_min * 60) ? 1 : 0;
}

1;
