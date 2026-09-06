#!/usr/bin/perl
use strict; use warnings; use utf8;

use lib "/opt/loxberry/bin/plugins/ondilo2loxone";
use CGI;
use config;
use ondilo_api;

my $cgi = CGI->new;
my $pool_id = $cgi->param('pool_id') // '';

if (length $pool_id) {
    my $cfg = config::read_config();
    my $access_token = ondilo_api::get_valid_access_token();
    my $name = "Pool $pool_id";
    if ($access_token) {
        my ($pools, $err) = ondilo_api::list_pools($access_token);
        if ($pools && ref($pools) eq 'ARRAY') {
            my ($match) = grep { "$_->{id}" eq "$pool_id" } @$pools;
            $name = $match->{name} if $match && $match->{name};
        }
    }
    $cfg->{POOL_ID}   = $pool_id;
    $cfg->{POOL_NAME} = $name;
    eval { config::write_config($cfg); };
}

print $cgi->redirect('index.cgi');
