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
use List::Util qw(pairmap);

use FindBin qw($RealBin $Script);

BEGIN {
    # probably would make the args mutually exclusive in a real util
    our (\%opt, $usage) = describe_options(
        "$Script %o",
        ['auth|a', 'Test authentication'],
        ['top-language|tl', 'Display most used language'],
        ['list-stale|ls:s', 'List stale branches for a repo'],
        ['top-starred|ts:s', 'Display user\'s top 3 starred projects descending'],
        ['compare-repos|cr:s', 'List common repos between authed user and some other user'],
        [],
        ['verbose|v+', 'Verbose level (-vv -vvv etc for more)'],
        ['help|h', 'Print usage info', {shortcircuit => 1}],
    );
    print($usage->text), exit if $::opt{help};
    $::opt{verbose} = 3; # TODO delete this line when done testing
}
use Smart::Comments map {'###' . '#' x $_} 0..($::opt{verbose}//0); # just a bit of fun :)

chdir($RealBin) || croak "Failed to chdir($RealBin): $!"; 

my $json = JSON()->new;
my $cl = REST::Client->new;

my @conf_keys = qw(githubToken);
my \%conf = try {
    $json->decode(scalar read_file('config.json'));
} catch {
    croak "Failed to read config: $_";
};
# no reason to check like this for only 1 key but i left it in for demonstration
###### read config: %conf;
map {die "$_ missing from config" unless $conf{$_}} @conf_keys;

$cl->setFollow(1); # for auth/redirect
$cl->setHost('https://api.github.com');
$cl->addHeader('Authorization', "Bearer $conf{githubToken}");
$cl->addHeader('Accept', 'application/vnd.github+json');

# retrieve username beforehand to see if 403 would be invalid token vs no access to resource
my $githubUser = try {
    GET('/user')->{login};
} catch {
    say $STDERR 'Invalid auth token' if /403/;
    croak $_;
};

if( $::opt{'auth'} ){
    say "Successful auth for user '$githubUser'";
}

if( $::opt{'top_language'} ){
    my @repos = map {$_->{full_name}} GET('/user/repos')->@*;
    #### checking top langs for repos: @repos
    
    my $totalsize;
    my %stats;
    pairmap {$stats{$a} += $b; $totalsize += $b} GET("/repos/$_/languages")->%* for @repos;
    
    my @top = sort {$stats{$b} <=> $stats{$a}} keys %stats;
    say "Top languages for $githubUser:";
    for( @top[0..2] ){ 
        next unless $_;
        printf "%s: %.1f%%\n", $_, ($stats{$_} / $totalsize * 100);
    }
}

if( $::opt{'list_stale'} ){
    
}

#checkResponse($res);

sub GET {
    ##### GET: $_[0]
    return checkResponse($cl->GET(@_));
}

sub checkResponse( $res ){
    ##### response code: $res->responseCode
    ###### content: $res->responseContent
    state %complaints = (
        403 => 'No permission to access that resource',
        204 => 'Response empty', 
    );
    
    my $code = $res->responseCode;

    my $decoded = try {
        $json->decode($res->responseContent);
    } catch {
        croak "Malformed response: '", $res->responseContent, "'", unless $code eq '204';
    };

    # it would be easier to just die with code + message but i wanted to demonstrate 'error handling'
    if( $code !~ /^2/ ){
        say $STDERR $decoded->{message};
        croak $complaints{$code}//('Request failed with code ', $code, "'");
    } elsif( $code ne '200' ){
        say $STDERR $decoded->{message};
        croak $complaints{$code}//('Something happened with code ', $code); # unlikely except 204
    }
    
    return $decoded;
}



__DATA__

    Authenticates with the server using a personal access token
    Display the authenticated user's most used language
    For a given repo, list all the stale branches
    Display a user's top 3 most starred projects in order of most to least stars with the numbers of stars for each project
    Display all the repositories that both the authenticated user and some other user have in common