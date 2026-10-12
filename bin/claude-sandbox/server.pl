#!/usr/bin/perl
# The fake Anthropic API: stores every request body as <dir>/req-N.json, notes
# its arrival in <dir>/timeline.log, answers 401. What it stores is exactly
# what the model would have been sent. Exits after 120 s, so nothing lingers.
use strict; use warnings; use IO::Socket::INET; use Time::HiRes qw(time);
my ($port, $dir) = @ARGV;
my $srv = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => $port, Listen => 5, ReuseAddr => 1) or die "listen: $!";
$SIG{ALRM} = sub { exit 0 }; alarm 120;
my $n = 0;
while (my $c = $srv->accept) {
	my ($line, %h) = (scalar <$c>);
	while (my $l = <$c>) { last if $l =~ /^\r?\n$/; $h{lc $1} = $2 if $l =~ /^([^:]+):\s*(.*?)\r?$/; }
	my $body = '';
	read($c, $body, $h{'content-length'}) if $h{'content-length'};
	$line =~ s/\s+$//;
	$n++;
	open my $b, '>', "$dir/req-$n.json" or die; print $b $body; close $b;
	open my $t, '>>', "$dir/timeline.log" or die;
	printf $t "%.2f request %d: %s (%d bytes)\n", time, $n, $line, length $body; close $t;
	my $r = '{"type":"error","error":{"type":"authentication_error","message":"sandbox"}}';
	print $c "HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\nContent-Length: " . length($r) . "\r\nConnection: close\r\n\r\n$r";
	close $c;
}
