#!/usr/bin/env perl
use v5.36;
use experimental qw(refaliasing declared_refs defer);
no warnings 'experimental';
use Try::Tiny;
use Carp;

use Getopt::Long::Descriptive;
use File::Slurp;
use JSON::MaybeXS;
use REST::Client;
use DDS;
use Smart::Comments;

use FindBin qw($RealBin $Script);

my ($opt, $usage) = describe_options(
    "$Script %o",
    ['auth|a', 'Test authentication'],
    ['top-language', 'Display most used language'],
    ['list-stale|ls:s', 'List stale branches for a repo'],
    ['top-starred|ts:s', 'Display user\'s top 3 starred projects descending'],
    ['compare-repos|cr:s', 'List common repos between authed user and some other user'],
);

chdir($RealBin) || croak "Failed to chdir($RealBin): $!"; 

my $json = JSON()->new;
my $cl = REST::Client->new;

my $conf = $json->decode(read_file('config.json'));

$cl->setHost('https://api.github.com');

__DATA__

    Authenticates with the server using a personal access token
    Display the authenticated user's most used language
    For a given repo, list all the stale branches
    Display a user's top 3 most starred projects in order of most to least stars with the numbers of stars for each project
    Display all the repositories that both the authenticated user and some other user have in common