#!/usr/bin/env perl
use strict;
use warnings;
# System-wide now playing, as one tab-separated line for Zeus.
# Fields: title, artist, album, 1 or 0, position seconds, duration seconds.
# The owner turns this on. Until then Zeus does not launch it.
my $title = $ENV{ZEUS_NOW_TITLE} // "";
my $artist = $ENV{ZEUS_NOW_ARTIST} // "";
my $album = $ENV{ZEUS_NOW_ALBUM} // "";
my $playing = $ENV{ZEUS_NOW_PLAYING} // "0";
my $position = $ENV{ZEUS_NOW_POSITION} // "0";
my $duration = $ENV{ZEUS_NOW_DURATION} // "0";
print join("\t", $title, $artist, $album, $playing, $position, $duration), "\n";
