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
use List::Util qw(pairmap);
use Time::Piece;
use Time::Seconds;
use Date::Parse;
use Path::Tiny;

use FindBin qw($RealBin $Script);

#my $IS_INTERACTIVE = -t STDIN && (-t STDOUT || !(-f STDOUT || -c STDOUT || -p STDOUT)) ;

BEGIN {
    # probably would make the args mutually exclusive in a real util
    our (\%opt, $usage) = describe_options(
        "%c [-v | --verbose] [-a | --auth] [-l | --top-language] [--stale=<repository>] [--top-starred=<user>] [--compare-repos=<user>]",
        ['auth|a', 'Test authentication'],
        ['top-language|l', 'Display most used language'],
        ['stale|s=s', 'List stale branches for a repo'], # username/repo
        ['top-starred|ts=s', 'Display a user\'s top 3 starred projects descending'],
        ['compare-repos|c=s', 'List common repos between authed user and some other user'],
        [],
        ['verbose|v+', 'Verbose level (-vv or -vvv for more)'],
        ['help|h', 'Print usage info', {shortcircuit => 1}],
    );
    print(join "\n", $usage->text, "\n", 'GitHub token is read from { \'githubToken\': foo } ./config.json'), exit if $::opt{help} || !%::opt || %::opt == 1 && $::opt{'verbose'};
}
use Smart::Comments map {'###' . '#' x $_} 0..($::opt{verbose}//0); # just a bit of fun :)

#chdir($RealBin) || croak "Failed to chdir($RealBin): $!"; # 

my $json = JSON()->new;
my $cl = REST::Client->new;

my @conf_keys = qw(githubToken);
my \%conf = try {
    $json->decode(scalar read_file(path($RealBin)->child('config.json')));
} catch {
    croak "Failed to read config: $_";
};
# No reason to check like this for only 1 key but i left it in for demonstration
###### read config: %conf;
map {croak "$_ missing from config" unless $conf{$_}} @conf_keys;

$cl->setFollow(1); # for auth/redirect
$cl->setHost('https://api.github.com');
$cl->addHeader('Authorization', "Bearer $conf{githubToken}");
$cl->addHeader('Accept', 'application/vnd.github+json');

# Retrieve username beforehand to see if 403 would be invalid token vs no access to resource
my $githubUser = try {
    GET('/user')->{login};
} catch {
    say $STDERR 'Invalid auth token' if /403/;
    croak $_;
};
#### Authenticated as: $githubUser

if( $::opt{'auth'} ){
    say "Successful auth for user '$githubUser'";
}

# There are a couple of ways this could be done, I was thinking to get all commits and then compare the language
# but there doesn't seem to be a way to retrieve this
if( $::opt{'top_language'} ){
    my @repos = map {$_->{full_name}} GET_all('/user/repos');

    #### checking top langs for repos: @repos
    
    my $totalsize;
    my %stats;
    pairmap {$stats{$a} += $b; $totalsize += $b} GET("/repos/$_/languages?affiliation=owner")->%* for @repos;
    
    my @top = sort {$stats{$b} <=> $stats{$a}} keys %stats;
    ### Top languages for: $githubUser

    for( @top[0..2] ){ 
        next unless $_;
        #printf "%s %.1f%%\n", $_, ($stats{$_} / $totalsize * 100);
        say;
    }
}

if( $::opt{'stale'} ){
    # superfluous input validation
    croak "Invalid repo name" if $::opt{'list_stale'} !~ m{[\w.-]/[\w.-]}; 

    my %branches = map {$_->{'name'}, $_->{'commit'}{'sha'}} GET_all('/repos/', $::opt{'list_stale'}, '/branches');
    
    my $now = Time::Piece->localtime;
    for my($name, $ref) ( %branches ){
        my $commit = GET('/repos/', $::opt{'stale'}, "/commits/$ref");
        my $then = Time::Piece->new(str2time($commit->{'commit'}{'committer'}{'date'}));
        my $dif = Time::Seconds->new($now - $then);
        if( $dif->months > 3 ){ # going by github doc definition of stale
            #printf "%s is stale by %.2f months\n", $name, $dif->months;
            say $name;
        }
    }
}

if( $::opt{'top_starred'} ){
    #my %repos = map {$_->@[qw(full_name stargazers_count)]} ;
    my @repos = sort {$b->{stargazers_count} <=> $a->{stargazers_count}} GET_all('/users/',$::opt{top_starred} , '/repos');
    for( @repos ){
        printf "%s %d\n", $_->@{qw(name stargazers_count)};
    }
}

if( $::opt{'compare_repos'} ){
    my @user_repos = map {$_->{'full_name'}} GET_all('/user/repos?type=all');
    my %other_repos = map {$_->{'full_name'}, 1} GET_all('/users/', $::opt{'compare_repos'}, '/repos?type=all');

    my @common = grep {exists $other_repos{$_}} @user_repos;
    say for @common;
}

#checkResponse($res);

sub GET {
    my $path = join '', @_; # var needed for the verbose print
    ##### GET: $path
    # can just join it because no extra headers are needed

    return checkResponse($cl->GET(join '', $path));
}

sub GET_all {
    my $path = join '', @_;
    ##### GET paginated: $path
    my $sep = ($path =~ /\?/) ? "&" : "?";
    my @all;
    my $page;

    while( my $res = GET($path, $sep, 'per_page=100', $page++ ? "&page=$page" : "" )){
        ##### got page: $page
        push @all, $res->@*;
        last unless ($cl->responseHeader('Link')//'') =~ /rel="next"/;
    }
    return @all;
}

sub checkResponse( $res ){
    ##### response code: $res->responseCode
    state %complaints = (
        403 => 'No permission to access that resource',
        204 => 'Response empty', 
    );
    
    my $code = $res->responseCode;

    my $decoded = try {
        $json->decode($res->responseContent);
    } catch {
        croak "Malformed response: '", $res->responseContent, "'" unless $code eq '204'; # very unlikely except 204
    };

    # it would be easier to just die with code + message but extra for fun
    if( $code !~ /^2/ ){
        say $STDERR $decoded->{message};
        croak $complaints{$code}//('Request failed with code ', $code, "'");
    } elsif( $code ne '200' ){
        say $STDERR $decoded->{message};
        croak $complaints{$code}//('Something happened with code ', $code); # somewhat unlikely except 204
    }
    # not sure if github ever gives 204 actually
    
    return $decoded;
}