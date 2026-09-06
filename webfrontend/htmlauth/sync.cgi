#!/usr/bin/perl
use strict; use warnings; use utf8;

use lib "/opt/loxberry/bin/plugins/ondilo2loxone";
use CGI;

binmode STDOUT, ':encoding(UTF-8)';

my $SCHEDULER = "/opt/loxberry/bin/plugins/ondilo2loxone/ondilo_scheduler.pl";
my $STATUS_FILE = "/opt/loxberry/data/plugins/ondilo2loxone/status.cfg";

# Force the next scheduler run to poll immediately, regardless of the
# configured interval, by clearing the stored "last poll" timestamp.
if (-f $STATUS_FILE) {
    my @lines;
    if (open(my $fh, '<', $STATUS_FILE)) {
        @lines = grep { $_ !~ /^LAST_POLL_EPOCH=/ } <$fh>;
        close $fh;
    }
    if (open(my $out, '>', $STATUS_FILE)) {
        print {$out} @lines;
        print {$out} "LAST_POLL_EPOCH=0\n";
        close $out;
    }
}

# Run the scheduler as a detached background process instead of waiting for
# it here: an Ondilo re-login can take several sequential HTTP requests
# (login page, form POST, redirects, token exchange), which can easily
# exceed LoxBerry's own web server request timeout - if that happens, the
# web server kills this CGI itself and returns a bare 500, regardless of
# any timeout handling inside this script. Returning immediately avoids
# that entirely; the result becomes visible on the status page a few
# seconds later.
my $pid = fork();
if (defined $pid && $pid == 0) {
    # child: detach and exec the scheduler
    close STDIN;  open(STDIN,  '<', '/dev/null');
    close STDOUT; open(STDOUT, '>', '/dev/null');
    close STDERR; open(STDERR, '>', '/dev/null');
    POSIX::setsid() if eval { require POSIX; 1 };
    exec('/usr/bin/perl', $SCHEDULER) or exit(1);
}
# parent: do not wait - continue immediately regardless of fork() success,
# so a fork failure (rare) still lets the page render instead of hanging.

my $cgi = CGI->new;
print $cgi->header(-type => 'text/html', -charset => 'utf-8');
print "<!DOCTYPE html><html lang='de'><head><meta charset='utf-8'>";
print "<meta name='viewport' content='width=device-width, initial-scale=1'>";
print "<meta http-equiv='refresh' content='4;url=index.cgi'>";
print "<title>Ondilo2Loxone - Synchronisation</title></head>";
print "<body style='font-family:Arial,Helvetica,sans-serif;margin:16px;background:#f5f5f5'>";
print "<div style='max-width:700px;margin:0 auto'>";
print "<section style='background:#e3f2fd;border:1px solid #90caf9;border-radius:8px;padding:16px;margin-bottom:16px'>";
print "<h2 style='margin-top:0'>Synchronisation gestartet</h2>";
print "<p>Die Abfrage laeuft im Hintergrund. Diese Seite leitet in wenigen Sekunden automatisch zur Startseite weiter, dort erscheint das Ergebnis.</p>";
print "</section>";
print "<p><a href='index.cgi' style='display:inline-block;padding:10px 16px;border-radius:6px;background:#00a99d;color:#fff!important;-webkit-text-fill-color:#fff!important;text-shadow:none!important;text-decoration:none!important;font-weight:700'>Jetzt zur Startseite</a></p>";
print "</div></body></html>";
