#! /usr/bin/perl

use warnings;
use strict;
use v5.10;

use Email::MIME 1.901;
use Mail::IMAPClient;
use Config::IniFiles;
use Getopt::Std;
use File::Basename;


my %opts;
getopts('vo:c:', \%opts);

my $conffile = $opts{c} ||  dirname($0)."/imapextract.ini";

my $exit = 0;
my $cfg = Config::IniFiles->new( -file => $conffile );

if( ! $cfg->exists( "server", 'user' ) ||
    ! $cfg->exists( "server", 'pass' ) ||
    ! $cfg->exists( "server", 'host' ) ) {
    die "missing config key";
}

my $verbose =  $opts{v} || $cfg->val('local', 'verbose', 0);
my $outdir =  $opts{o} ||$cfg->val('local', 'outdir', '.');
my $mailfolder = $cfg->val( "server", 'folder', 'INBOX');
my $wait = $cfg->val( "server", 'wait', 300);

die "output directory '$outdir' does not exist" if ( ! -d $outdir );

my $imap = Mail::IMAPClient->new(
    Debug       => $verbose,
    User        => $cfg->val( "server", 'user'),
    Password    => $cfg->val( "server", 'pass'),
    Uid         => 1,
    Server      => $cfg->val( "server", 'host'),
    Port        => $cfg->val( "server", 'port', 993),
    Ssl         => $cfg->val( "server", 'ssl', 1),
);

die "$0: login: $@" if $@;

$imap->select($mailfolder)
    or die "$0: select $mailfolder: ", $imap->LastError, "\n";

while($imap->IsConnected && !$exit){
    my @messages = $imap->messages();
    die "$0: search: $@" if $@;

    $SIG{'INT'} = $SIG{'TERM'} = \&use_next_exit;

    foreach my $id (@messages) {
        die "$0: funky ID ($id)" unless $id =~ /\A\d+\z/;

        my $str = $imap->message_string($id)
            or die "$0: message_string: $@";

        my $n = 1;
        Email::MIME->new($str)->walk_parts(sub {
                my($part) = @_;
                return unless $part->content_type =~ /\bname="([^"]+)"/;  # " grr...

                my $name = $outdir . "/" . time . $n++ . "-$1";
                print "$0: writing $name...\n";
                open my $fh, ">", $name
                    or die "$0: open $name: $!";
                print $fh $part->content_type =~ m!^text/!
                ? $part->body_str
                : $part->body
                    or die "$0: print $name: $!";
                close $fh
                    or warn "$0: close $name: $!";
            });
        $imap->delete_message($id);
    }

    $imap->expunge("INBOX") or die "Could not expunge: $@\n";

    $SIG{'INT'} = $SIG{'TERM'} = 'DEFAULT';

    last if $exit;
    if ( $cfg->val( "server", 'idle')) {
        my $tag = $imap->idle or warn "idle failed: $@\n";
        $imap->idle_data($cfg->val( "server", 'wait')) or warn "idle_data error: $@\n";
        $imap->done($tag) or warn "Error from done: $@\n";
    } else {
        sleep $cfg->val( "server", 'wait');
    }

}

$imap->disconnect or warn "Could not logout: $@\n";

sub use_next_exit() {
    $exit = 1;
}
