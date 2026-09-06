package logger;

use strict;
use warnings;

use POSIX qw(strftime);
use File::Path qw(make_path);

our $LOG_DIR  = "/opt/loxberry/log/plugins/ondilo2loxone";
our $LOG_FILE = "$LOG_DIR/ondilo2loxone.log";

our $MAX_LOG_SIZE = 1024 * 1024; # 1 MB
our $CONSOLE      = 1;
our $DEBUG        = 0;

sub set_debug { my ($enabled) = @_; $DEBUG = $enabled ? 1 : 0; }

sub info    { _write("INFO",    shift); }
sub warning { _write("WARNING", shift); }
sub error   { _write("ERROR",   shift); }
sub debug   { return unless $DEBUG; _write("DEBUG", shift); }

sub _write
{
    my ($level, $text) = @_;
    $text //= "";
    $text =~ s/\r//g;
    $text =~ s/\n/ /g;

    _prepare_log_directory();
    _rotate_log_if_needed();

    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime());
    my $line = sprintf("%s %-7s %s\n", $timestamp, $level, $text);

    print $line if $CONSOLE;

    if (open(my $fh, ">>", $LOG_FILE)) {
        print $fh $line;
        close($fh);
    }
}

sub _prepare_log_directory
{
    return if -d $LOG_DIR;
    eval { make_path($LOG_DIR, { mode => 0750 }); };
}

sub _rotate_log_if_needed
{
    return unless -f $LOG_FILE;

    my @stat = stat($LOG_FILE);
    my $mtime = $stat[9];
    my $today   = strftime("%Y-%m-%d", localtime());
    my $log_day = defined $mtime ? strftime("%Y-%m-%d", localtime($mtime)) : $today;

    my $size_exceeded = (-s $LOG_FILE > $MAX_LOG_SIZE);
    my $day_changed   = ($log_day ne $today);

    return unless $size_exceeded || $day_changed;

    unlink($LOG_FILE);
    if (open(my $fh, ">", $LOG_FILE)) {
        my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime());
        my $reason = $size_exceeded ? "Groesse > 1 MB" : "taeglicher Rollover";
        print $fh "$timestamp INFO    Logdatei automatisch zurueckgesetzt ($reason)\n";
        close($fh);
    }
}

1;
