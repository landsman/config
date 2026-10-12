#!/usr/bin/perl
# The fake Anthropic API: stores every request body as <dir>/req-N.json, notes
# its arrival in <dir>/timeline.log, answers 401. What it stores is exactly
# what the model would have been sent. Exits after 120 s, so nothing lingers.
use strict; use warnings; use IO::Socket::INET; use IO::Select; use Time::HiRes qw(time);
my ($port, $dir) = @ARGV;
my $srv = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => $port, Listen => 5, ReuseAddr => 1) or die "listen: $!";
$SIG{ALRM} = sub { exit 0 }; alarm 120;
sub note { open my $t, '>>', "$dir/timeline.log" or die; printf $t "%.2f %s\n", time, shift; close $t }
my $n = 0;
while (my $c = $srv->accept) {
	# A connection that says nothing (preconnect, keep-alive) must not hold up
	# the next one: give up on it after 5 s without data.
	my $sel = IO::Select->new($c);
	my ($line, %h) = ('');
	if ($sel->can_read(5)) { $line = <$c> // ''; }
	while ($line && $sel->can_read(5) && defined(my $l = <$c>)) { last if $l =~ /^\r?\n$/; $h{lc $1} = $2 if $l =~ /^([^:]+):\s*(.*?)\r?$/; }
	unless ($line) { close $c; next }
	my $body = '';
	if ($h{'transfer-encoding'} && $h{'transfer-encoding'} =~ /chunked/i) {
		# Chunked: size line in hex, data, CRLF, until a zero size.
		while ($sel->can_read(5) && defined(my $s = <$c>)) {
			my $len = hex($s =~ /^([0-9a-fA-F]+)/ ? $1 : 0);
			last unless $len;
			my $chunk = ''; read($c, $chunk, $len); $body .= $chunk; <$c>;
		}
	} elsif ($h{'content-length'}) {
		read($c, $body, $h{'content-length'});
	}
	$line =~ s/\s+$//;
	$n++;
	open my $b, '>', "$dir/req-$n.json" or die; print $b $body; close $b;
	note(sprintf 'request %d: %s (%d bytes)', $n, $line, length $body);
	note("request $n has an EMPTY BODY, so an 'absent' check on it proves nothing") unless length $body;
	my $r = '{"type":"error","error":{"type":"authentication_error","message":"sandbox"}}';
	print $c "HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\nContent-Length: " . length($r) . "\r\nConnection: close\r\n\r\n$r";
	close $c;
}
