#!/usr/bin/perl

use Term::Shelly;

$sh = Term::Shelly->new();

$time = time();
$end = time() + 15;
$count = 0;

while (1) {
	$sh->do_one_loop();
	if ($time < time()) {
		$count++;
		$time = time();
		$sh->prompt(sprintf("Download: %.2f", $count / 15) . "% >");
		exit if ($time == $end);
	}
}
