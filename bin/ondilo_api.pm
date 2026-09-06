package ondilo_api;

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Cookies;
use HTTP::Request;
use URI;
use JSON qw(encode_json decode_json);
use Digest::SHA qw(sha256_hex);

use auth_store;
use logger;

my $CLIENT_ID    = 'customer_api';
my $AUTH_URL     = 'https://interop.ondilo.com/oauth2/authorize';
my $TOKEN_URL    = 'https://interop.ondilo.com/oauth2/token';
my $API_BASE     = 'https://interop.ondilo.com/api/customer/v1';
my $REDIRECT_URI = 'https://example.com/api'; # never actually fetched, see login_with_password()

our $LAST_ERROR = '';

sub last_error { return $LAST_ERROR; }

sub _ua
{
    my $ua = LWP::UserAgent->new(
        timeout  => 20,
        ssl_opts => { verify_hostname => 1 },
    );
    $ua->agent('Mozilla/5.0 (X11; Linux x86_64) ondilo2loxone/1.0');
    return $ua;
}

# ---------------------------------------------------------------------------
# Direct email+password login.
#
# Ondilo's Customer API only documents the browser-based OAuth2
# "Authorization Code" flow (interop.ondilo.com/oauth2/authorize shows an
# HTML login form). There is no documented direct password endpoint. To
# let the user log in with just email+password from the LoxBerry settings
# page (no browser redirect to Ondilo), this function emulates what a
# browser would do: it fetches that login form, fills in the email/password
# fields it finds, submits it, and follows the resulting redirect(s) until
# it sees our redirect_uri with a "code=" parameter - which is then
# exchanged for tokens exactly like the standard flow.
#
# This is inherently best-effort: if Ondilo changes their login page
# markup, or shows a CAPTCHA / 2FA step, this will fail. On failure, a
# snippet of the received page is written to the log to help diagnose and
# adjust the field-detection below.
# ---------------------------------------------------------------------------
sub login_with_password
{
    my ($email, $password) = @_;
    $LAST_ERROR = '';

    return _fail('E-Mail-Adresse fehlt.') unless defined $email && length $email;
    return _fail('Passwort fehlt.') unless defined $password && length $password;

    my $jar = HTTP::Cookies->new;
    my $ua  = _ua();
    $ua->cookie_jar($jar);
    $ua->requests_redirectable([]); # we follow redirects manually below

    my $state = sha256_hex(time() . rand());
    my $auth_url = URI->new($AUTH_URL);
    $auth_url->query_form(
        client_id     => $CLIENT_ID,
        response_type => 'code',
        redirect_uri  => $REDIRECT_URI,
        scope         => 'api',
        state         => $state,
    );

    # Step 1: fetch the login page (following normal GET redirects, if any).
    $ua->requests_redirectable(['GET', 'HEAD']);
    my $resp = $ua->get($auth_url);
    $ua->requests_redirectable([]);

    unless ($resp->is_success) {
        return _fail('Ondilo-Loginseite nicht erreichbar (HTTP ' . $resp->code . ').');
    }

    my $html     = $resp->decoded_content // '';
    my $page_url = $resp->request->uri;

    my ($form_block) = $html =~ m{<form\b[^>]*>(.*?)</form>}si;
    unless (defined $form_block) {
        logger::error("Ondilo-Login: kein <form> gefunden. Seitenanfang: " . substr($html, 0, 300));
        return _fail('Ondilo-Loginformular nicht erkannt (Seite evtl. geaendert). Siehe Log fuer Details.');
    }

    my ($form_tag) = $html =~ m{(<form\b[^>]*>)}si;
    my ($action) = $form_tag =~ /\baction=["']([^"']*)["']/i;
    my ($method) = $form_tag =~ /\bmethod=["']([^"']*)["']/i;
    $method = $method ? uc($method) : 'POST';

    my %fields;
    my @order;
    while ($form_block =~ m{<input\b([^>]*)>}sgi) {
        my $tag = $1;
        my ($name) = $tag =~ /\bname=["']([^"']+)["']/i;
        next unless defined $name;
        my ($value) = $tag =~ /\bvalue=["']([^"']*)["']/i;
        my ($type)  = $tag =~ /\btype=["']([^"']*)["']/i;
        $type = lc($type // 'text');
        $fields{$name} = { value => ($value // ''), type => $type };
        push @order, $name;
    }

    my ($email_field)    = grep { $fields{$_}{type} eq 'email' } @order;
    $email_field       ||= (grep { /e-?mail|user|login/i } @order)[0];
    my ($password_field) = grep { $fields{$_}{type} eq 'password' } @order;

    unless ($email_field && $password_field) {
        logger::error("Ondilo-Login: Formularfelder nicht erkannt. Gefundene Felder: " . join(',', @order));
        return _fail('E-Mail-/Passwortfeld im Ondilo-Formular nicht erkannt. Siehe Log fuer Details.');
    }

    my %post_data = map { $_ => $fields{$_}{value} } @order;
    $post_data{$email_field}    = $email;
    $post_data{$password_field} = $password;

    my $action_url = (defined $action && length $action)
        ? URI->new_abs($action, $page_url)->as_string
        : $page_url->as_string;

    # Step 2: submit the login form and follow redirects manually until we
    # see our own redirect_uri with a "code=" parameter.
    my $current_url    = $action_url;
    my $current_method = $method;
    my %current_data   = %post_data;
    my $code;

    for (my $hop = 0; $hop < 6; $hop++) {
        my $r;
        if ($current_method eq 'GET') {
            my $u = URI->new($current_url);
            $u->query_form(%current_data) if %current_data;
            $r = $ua->get($u);
        } else {
            $r = $ua->post($current_url, [ %current_data ]);
        }

        if ($r->is_redirect) {
            my $loc = $r->header('Location');
            last unless $loc;
            my $loc_abs = URI->new_abs($loc, $current_url)->as_string;

            if (index($loc_abs, $REDIRECT_URI) == 0) {
                my ($c) = $loc_abs =~ /[?&]code=([^&]+)/;
                if ($c) { $code = $c; last; }
            }
            $current_url    = $loc_abs;
            $current_method = 'GET';
            %current_data   = ();
            next;
        }

        if ($r->is_success) {
            my $body = $r->decoded_content // '';
            if ($body =~ /<form/i) {
                # Some accounts get an extra confirmation/consent form - not
                # handled automatically; surface this clearly instead of
                # silently failing.
                logger::error("Ondilo-Login: unerwartetes Zwischenformular nach Login-POST. Anfang: " . substr($body, 0, 300));
                return _fail('Ondilo zeigt nach der Anmeldung eine zusaetzliche Bestaetigungsseite an (z.B. Sicherheitsabfrage). Automatische Anmeldung derzeit nicht moeglich.');
            }
            logger::error("Ondilo-Login: keine Weiterleitung mit Code erhalten. Anfang der Antwort: " . substr($body, 0, 300));
            return _fail('Ondilo hat die Anmeldung nicht bestaetigt. Bitte E-Mail/Passwort pruefen.');
        }

        return _fail('Ondilo-Login fehlgeschlagen (HTTP ' . $r->code . ').');
    }

    unless ($code) {
        return _fail('Kein Autorisierungscode von Ondilo erhalten (moeglicherweise falsche Zugangsdaten oder zusaetzliche Sicherheitsabfrage).');
    }

    return _exchange_code($ua, $code);
}

sub _exchange_code
{
    my ($ua, $code) = @_;

    my $resp = $ua->post($TOKEN_URL, {
        grant_type   => 'authorization_code',
        code         => $code,
        client_id    => $CLIENT_ID,
        redirect_uri => $REDIRECT_URI,
    });

    unless ($resp->is_success) {
        return _fail('Token-Austausch fehlgeschlagen (HTTP ' . $resp->code . ').');
    }
    my $data = eval { decode_json($resp->decoded_content) };
    return _fail('Ungueltige Token-Antwort von Ondilo.') unless $data && $data->{access_token};

    $data->{expires_at} = time() + ($data->{expires_in} || 3600) - 60;
    return $data;
}

sub _fail
{
    my ($msg) = @_;
    $LAST_ERROR = $msg;
    logger::warning("ondilo_api: $msg");
    return undef;
}

# ---------------------------------------------------------------------------
# Token refresh / access
# ---------------------------------------------------------------------------

sub refresh_token
{
    my ($refresh_token) = @_;
    return _fail('Kein Refresh-Token vorhanden.') unless $refresh_token;

    my $ua = _ua();
    my $resp = $ua->post($TOKEN_URL, {
        grant_type    => 'refresh_token',
        refresh_token => $refresh_token,
        client_id     => $CLIENT_ID,
    });

    unless ($resp->is_success) {
        return _fail('Token-Erneuerung fehlgeschlagen (HTTP ' . $resp->code . ').');
    }
    my $data = eval { decode_json($resp->decoded_content) };
    return _fail('Ungueltige Antwort bei Token-Erneuerung.') unless $data && $data->{access_token};

    $data->{expires_at} = time() + ($data->{expires_in} || 3600) - 60;
    return $data;
}

# Returns a valid access token, refreshing (and if necessary re-logging in
# with a stored password) as needed. Returns undef + last_error() on failure.
sub get_valid_access_token
{
    my $auth = auth_store::load_auth();

    if ($auth->{access_token} && $auth->{expires_at} && time() < $auth->{expires_at}) {
        return $auth->{access_token};
    }

    if ($auth->{refresh_token}) {
        my $data = refresh_token($auth->{refresh_token});
        if ($data) {
            auth_store::store_token(
                access_token  => $data->{access_token},
                refresh_token => $data->{refresh_token} || $auth->{refresh_token},
                expires_at    => $data->{expires_at},
            );
            return $data->{access_token};
        }
        logger::warning('Token-Erneuerung fehlgeschlagen: ' . last_error());
    }

    # Refresh failed or no refresh token at all: try an automatic re-login
    # if we have a stored (encrypted) password.
    if (auth_store::has_password() && $auth->{email}) {
        my $password = eval { auth_store::load_password() };
        if ($password) {
            my $data = login_with_password($auth->{email}, $password);
            if ($data) {
                auth_store::store_token(
                    email         => $auth->{email},
                    access_token  => $data->{access_token},
                    refresh_token => $data->{refresh_token},
                    expires_at    => $data->{expires_at},
                );
                return $data->{access_token};
            }
        }
    }

    return _fail('Nicht bei Ondilo angemeldet.') unless $LAST_ERROR;
    return undef;
}

# ---------------------------------------------------------------------------
# Ondilo Customer API calls
# ---------------------------------------------------------------------------

sub api_get
{
    my ($access_token, $path) = @_;
    my $ua = _ua();
    my $req = HTTP::Request->new(GET => "$API_BASE$path");
    $req->header('Authorization' => "Bearer $access_token");
    $req->header('Accept' => 'application/json');
    my $resp = $ua->request($req);

    unless ($resp->is_success) {
        return (undef, 'API-Aufruf fehlgeschlagen (HTTP ' . $resp->code . "): $path");
    }
    my $data = eval { decode_json($resp->decoded_content) };
    return (undef, 'Ungueltige JSON-Antwort von Ondilo') if $@;
    return ($data, undef);
}

sub list_pools
{
    my ($access_token) = @_;
    return api_get($access_token, '/pools');
}

sub last_measures
{
    my ($access_token, $pool_id, @types) = @_;
    my $q = join('&', map { 'types[]=' . $_ } @types);
    return api_get($access_token, "/pools/$pool_id/lastmeasures?$q");
}

# Fetches every measurement type Ondilo currently reports for the pool,
# instead of a fixed hardcoded list - this is what makes sensor discovery
# dynamic. The Customer API's "types[]" filter parameter may or may not be
# strictly required, so we first try an unfiltered request; if that comes
# back empty, we fall back to explicitly asking for every documented type.
sub last_measures_all
{
    my ($access_token, $pool_id) = @_;
    my ($data, $err) = api_get($access_token, "/pools/$pool_id/lastmeasures");
    if ($data && ref($data) eq 'ARRAY' && @$data) {
        return ($data, undef);
    }
    my @known = qw(temperature ph orp salt tds battery rssi);
    return last_measures($access_token, $pool_id, @known);
}

1;
