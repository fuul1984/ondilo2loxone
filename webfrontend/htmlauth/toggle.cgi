#!/usr/bin/perl
use strict; use warnings;

use lib "/opt/loxberry/bin/plugins/ondilo2loxone";
use CGI;
use config;

my $cgi = CGI->new;
my $action = $cgi->param('action') // '';
my $cfg = config::read_config();
$cfg->{PLUGIN_ENABLED} = ($action eq 'enable') ? 'true' : 'false';
eval { config::write_config($cfg); };
print $cgi->redirect('index.cgi');
