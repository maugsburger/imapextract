#! /usr/bin/perl

use warnings;
use strict;

use Email::MIME 1.901;
use IO::Socket::SSL;
use Mail::IMAPClient;
use POSIX qw/ strftime /;

my $imap = Mail::IMAPClient->new(
 #Debug    => 1,
  User     => "you\@domain.com",
  Password => $pw,
  Uid      => 1,
  Peek     => 1,  # don't set \Seen flag
  Socket   => IO::Socket::SSL->new(
                Proto    => 'tcp',
                PeerAddr => 'imap.domain.com',
                PeerPort => 993,
              ),
);

die "$0: connect: $@" if defined $@;

$imap->select("INBOX")
  or die "$0: select INBOX: ", $imap->LastError, "\n";

my $today = strftime "%Y%m%d", localtime $^T;
my @messages = $imap->search(SUBJECT => $today);
die "$0: search: $@" if defined $@;

foreach my $id (@messages) {
  die "$0: funky ID ($id)" unless $id =~ /\A\d+\z/;

  my $str = $imap->message_string($id)
    or die "$0: message_string: $@";

  my $n = 1;
  Email::MIME->new($str)->walk_parts(sub {
    my($part) = @_;
    return unless $part->content_type =~ /\bname="([^"]+)"/;  # " grr...

    my $name = "./$today-$id-" . $n++ . "-$1";
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
}
