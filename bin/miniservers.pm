package miniservers;

use strict;
use warnings;

# Returns a list of hashrefs: { no => ..., name => ..., host => ... }
#
# LoxBerry::System::get_miniservers() is the documented way to get this,
# but its exact return shape isn't guaranteed to stay identical across
# LoxBerry versions, so we scan defensively for anything that looks like
# an IP/host field, the way the (in-production, working) FYTA Connect
# plugin does. If that yields nothing, we fall back to parsing LoxBerry's
# own general.cfg directly.
sub get_servers
{
    my @raw = eval {
        require LoxBerry::System;
        LoxBerry::System::get_miniservers();
    };
    if (!$@ && @raw) {
        my @candidates;
        _collect(\@candidates, \@raw, 0);
        my @out = _normalize(\@candidates);
        return @out if @out;
    }

    return _from_general_cfg();
}

sub _collect
{
    my ($out, $node, $depth) = @_;
    return if $depth > 8;

    if (ref($node) eq 'ARRAY') {
        _collect($out, $_, $depth + 1) for @{$node};
        return;
    }
    return unless ref($node) eq 'HASH';

    my $host = _first($node, qw(IPAddress IPADDRESS Ipaddress ipaddress IP ip HOST Host host HOSTNAME Hostname hostname ADDRESS Address address));
    push @{$out}, $node if defined $host && length $host;

    for my $value (values %{$node}) {
        _collect($out, $value, $depth + 1) if ref($value) eq 'HASH' || ref($value) eq 'ARRAY';
    }
}

sub _normalize
{
    my ($candidates) = @_;
    my @out;
    my %seen;
    my $fallback_no = 0;

    for my $entry (@{$candidates}) {
        next unless ref($entry) eq 'HASH';
        my $host = _first($entry, qw(IPAddress IPADDRESS Ipaddress ipaddress IP ip HOST Host host HOSTNAME Hostname hostname ADDRESS Address address));
        next unless defined $host && length $host;
        next if $seen{lc($host)}++;

        $fallback_no++;
        my $no = _first($entry, qw(MSNO msno NO no NUMBER number NR nr INDEX index));
        $no = $fallback_no unless defined $no && length $no;
        my $name = _first($entry, qw(NAME Name name MSNAME msname LOCATION Location location FRIENDLYNAME FriendlyName friendlyname));
        $name = "Miniserver $no" unless defined $name && length $name;

        push @out, { no => $no, name => $name, host => $host };
    }
    return @out;
}

sub _first
{
    my ($h, @keys) = @_;
    for my $key (@keys) {
        return $h->{$key} if defined $h->{$key} && length $h->{$key};
    }
    return undef;
}

# Fallback: directly parse LoxBerry's general.cfg.
sub _from_general_cfg
{
    my $file = '/opt/loxberry/config/system/general.cfg';
    return () unless -f $file;

    my %vals;
    open(my $fh, '<', $file) or return ();
    my $section = '';
    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/\r//g;
        next if $line =~ /^\s*[#;]/;
        if ($line =~ /^\s*\[([^\]]+)\]\s*$/) { $section = uc($1); next; }
        if ($line =~ /^\s*([^=]+?)\s*=\s*(.*?)\s*$/) {
            $vals{"$section.\U$1"} = $2;
        }
    }
    close $fh;

    my $count = $vals{'BASE.MINISERVERS'} // 0;
    my @out;
    for my $i (1 .. $count) {
        my $host = $vals{"MINISERVER$i.IPADDRESS"};
        next unless defined $host && length $host;
        my $name = $vals{"MINISERVER$i.NAME"} || "Miniserver $i";
        push @out, { no => $i, name => $name, host => $host };
    }
    return @out;
}

1;
