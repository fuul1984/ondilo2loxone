package udp;

use strict;
use warnings;

use IO::Socket::INET;

use constant MAX_MSG_LEN => 200;

sub sanitize_message
{
    my ($msg) = @_;
    return '' unless defined $msg;
    $msg =~ s/[\x00-\x1F\x7F]//g;
    $msg = substr($msg, 0, MAX_MSG_LEN) if length($msg) > MAX_MSG_LEN;
    return $msg;
}

sub send_udp
{
    my ($host, $port, $message) = @_;

    return 'ERROR: Host fehlt'
        unless defined $host && length $host;

    return 'ERROR: Port fehlt'
        unless defined $port && $port =~ /^\d+$/;

    return 'ERROR: Ungueltiger Port'
        if $port < 1 || $port > 65535;

    my $clean = sanitize_message($message);
    return 'ERROR: Nachricht fehlt'
        unless length $clean;

    my $socket = IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port,
        Proto    => 'udp'
    );

    unless ($socket) {
        return "ERROR: UDP Socket konnte nicht erstellt werden: $!";
    }

    my $bytes_sent = $socket->send($clean);

    unless (defined $bytes_sent) {
        $socket->close();
        return "ERROR: UDP Versand fehlgeschlagen: $!";
    }

    $socket->close();
    return "OK: $bytes_sent Bytes gesendet";
}

1;
