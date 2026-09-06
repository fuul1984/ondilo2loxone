package auth_store;

use strict;
use warnings;
use File::Path qw(make_path);
use JSON qw(encode_json decode_json);
use IPC::Open3;
use Symbol qw(gensym);
use Fcntl qw(:flock);

our $DATA_DIR  = '/opt/loxberry/data/plugins/ondilo2loxone';
our $AUTH_FILE = "$DATA_DIR/auth.json";
our $KEY_FILE  = "$DATA_DIR/.auth.key";
our $LOCK_FILE = "$DATA_DIR/.auth.lock";

sub load_auth
{
    return {} unless -f $AUTH_FILE;
    open(my $fh, '<', $AUTH_FILE) or return {};
    local $/;
    my $raw = <$fh>;
    close $fh;
    my $data;
    eval { $data = decode_json($raw // ''); };
    return {} if $@ || ref($data) ne 'HASH';
    return $data;
}

sub save_auth
{
    my ($auth) = @_;
    die "Ungueltige Authentifizierungsdaten.\n" unless ref($auth) eq 'HASH';
    _ensure_dir();
    my $tmp = "$AUTH_FILE.tmp.$$";
    open(my $fh, '>', $tmp) or die "Kann Authentifizierungsdaten nicht schreiben: $!\n";
    print {$fh} encode_json($auth);
    close $fh or die "Kann Authentifizierungsdaten nicht schliessen: $!\n";
    chmod 0600, $tmp;
    rename($tmp, $AUTH_FILE) or die "Kann Authentifizierungsdaten nicht ersetzen: $!\n";
    chmod 0600, $AUTH_FILE;
    return 1;
}

# Runs $code with an exclusive lock held, for callers that need to
# load_auth() -> modify -> save_auth() as one atomic unit. The scheduler
# (token refresh on every poll) and the settings page (manual login) can
# trigger such a read-modify-write at the same time; without serialising
# the whole sequence, whichever finishes last would silently overwrite the
# other's change (e.g. a fresh token clobbered by a stale one).
sub _with_lock
{
    my ($code) = @_;
    _ensure_dir();
    open(my $lock_fh, '>>', $LOCK_FILE) or die "Kann Lock-Datei nicht oeffnen: $!\n";
    flock($lock_fh, LOCK_EX);
    my @result = eval { $code->() };
    my $err = $@;
    flock($lock_fh, LOCK_UN);
    close $lock_fh;
    die $err if $err;
    return wantarray ? @result : $result[0];
}

# Stores the Ondilo password encrypted, so a lost/revoked refresh token can
# trigger a fully automatic re-login without asking the user again.
sub store_password
{
    my ($password) = @_;
    die "Leeres Passwort kann nicht gespeichert werden.\n" unless defined $password && length $password;
    my $cipher = _openssl_crypt(1, $password);
    _with_lock(sub {
        my $auth = load_auth();
        $auth->{password_enc}    = $cipher;
        $auth->{password_format} = 'openssl-aes-256-cbc-pbkdf2-v1';
        save_auth($auth);
    });
    return 1;
}

sub load_password
{
    my $auth = load_auth();
    return '' unless defined $auth->{password_enc} && length $auth->{password_enc};
    return _openssl_crypt(0, $auth->{password_enc});
}

sub has_password
{
    my $auth = load_auth();
    return defined $auth->{password_enc} && length($auth->{password_enc} // '') ? 1 : 0;
}

sub store_token
{
    my (%args) = @_;
    _with_lock(sub {
        my $auth = load_auth();
        $auth->{email}         = $args{email}         if defined $args{email};
        $auth->{access_token}  = $args{access_token}  if defined $args{access_token};
        $auth->{refresh_token} = $args{refresh_token} if defined $args{refresh_token};
        $auth->{expires_at}    = $args{expires_at}    if defined $args{expires_at};
        $auth->{updated_at}    = time();
        save_auth($auth);
    });
    return 1;
}

sub clear_token
{
    _with_lock(sub {
        my $auth = load_auth();
        delete @{$auth}{qw(access_token refresh_token expires_at)};
        save_auth($auth);
    });
    return 1;
}

sub clear_all
{
    _with_lock(sub { save_auth({}); });
    return 1;
}

sub _ensure_dir
{
    make_path($DATA_DIR, { mode => 0750 }) unless -d $DATA_DIR;
    chmod 0750, $DATA_DIR;
}

sub _ensure_key
{
    _ensure_dir();
    if (!-f $KEY_FILE) {
        open(my $ur, '<:raw', '/dev/urandom') or die "Kann Zufallsquelle nicht lesen: $!\n";
        my $bytes = '';
        my $got = read($ur, $bytes, 32);
        close $ur;
        die "Konnte keinen sicheren Schluessel erzeugen.\n" unless defined $got && $got == 32;
        my $hex = unpack('H*', $bytes);
        my $tmp = "$KEY_FILE.tmp.$$";
        open(my $fh, '>', $tmp) or die "Kann Schluesseldatei nicht schreiben: $!\n";
        print {$fh} $hex;
        close $fh;
        chmod 0600, $tmp;
        rename($tmp, $KEY_FILE) or die "Kann Schluesseldatei nicht ersetzen: $!\n";
    }
    chmod 0600, $KEY_FILE;
    return $KEY_FILE;
}

sub _openssl_crypt
{
    my ($encrypt, $input) = @_;
    my $openssl = -x '/usr/bin/openssl' ? '/usr/bin/openssl' : (-x '/bin/openssl' ? '/bin/openssl' : '');
    die "OpenSSL ist nicht verfuegbar; Daten koennen nicht sicher gespeichert werden.\n" unless length $openssl;
    my $keyfile = _ensure_key();
    my @cmd = ($openssl, 'enc', '-aes-256-cbc', '-pbkdf2', '-salt', '-a', '-A', '-pass', "file:$keyfile");
    push @cmd, '-d' unless $encrypt;

    my $err = gensym;
    my ($in, $out);
    my $pid = open3($in, $out, $err, @cmd);
    binmode $in;
    binmode $out;
    print {$in} $input;
    close $in;
    local $/;
    my $result = <$out> // '';
    my $error  = <$err> // '';
    close $out;
    close $err;
    waitpid($pid, 0);
    my $rc = $? >> 8;
    die "Ver-/Entschluesselung fehlgeschlagen.\n" if $rc != 0;
    $result =~ s/[\r\n]+$//;
    return $result;
}

1;
