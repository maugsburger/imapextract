#! /usr/bin/perl

use warnings;
use strict;
use v5.10;

use Email::MIME 1.901;
use Mail::IMAPClient;
use Config::IniFiles;

# default values
my $conffile = "imapextract.ini";

my $exit = 0;
my $cfg = Config::IniFiles->new( -file => $conffile );

my $imap = Mail::IMAPClient->new(
    Debug       => 0,
    User        => $cfg->val( "server", 'user'),
    Password    => $cfg->val( "server", 'pass'),
    Uid         => 1,
    Server      => $cfg->val( "server", 'host'),
    Port        => $cfg->val( "server", 'port'),
    Ssl         => $cfg->val( "server", 'ssl'),
);

die "$0: login: $@" if $@;

$imap->select("INBOX")
    or die "$0: select INBOX: ", $imap->LastError, "\n";

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

                my $name = "./" . time . $n++ . "-$1";
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
