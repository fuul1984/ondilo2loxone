package version;

use strict;
use warnings;

our @PLUGIN_CFG_CANDIDATES = (
    "/opt/loxberry/bin/plugins/ondilo2loxone/plugin.cfg",
    "/opt/loxberry/config/plugins/ondilo2loxone/plugin.cfg",
);

# Fallback if plugin.cfg can't be found/read at all - keep in sync manually.
our $FALLBACK_VERSION = '0.1.1';

sub plugin_version
{
    my ($file) = @_;
    if (!defined $file || !length $file) {
        ($file) = grep { -f $_ } @PLUGIN_CFG_CANDIDATES;
    }

    return $FALLBACK_VERSION unless defined $file && -f $file;
    open(my $fh, '<', $file) or return $FALLBACK_VERSION;

    my $in_plugin_section = 0;
    while (my $line = <$fh>) {
        $line =~ s/\r//g;
        $in_plugin_section = 1 if $line =~ /^\s*\[PLUGIN\]\s*$/i;
        $in_plugin_section = 0 if $in_plugin_section && $line =~ /^\s*\[/ && $line !~ /^\s*\[PLUGIN\]\s*$/i;
        if ($in_plugin_section && $line =~ /^\s*VERSION\s*=\s*(.*?)\s*$/) {
            close $fh;
            return length($1) ? $1 : $FALLBACK_VERSION;
        }
    }

    close $fh;
    return $FALLBACK_VERSION;
}

1;
