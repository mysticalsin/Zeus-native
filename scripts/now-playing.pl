#!/usr/bin/perl
use strict;
use warnings;

# The caller is the signed binary built into the app bundle. This script never
# compiles anything and never searches the path. It runs that one file only
# after lstat says it is a regular file owned by root or this user.

my $caller = $ARGV[0] // "";
die "now-playing caller refused\n"
    unless $caller =~ m{\A(/[^/\n]+(?:/[^/\n]+)*\.app/Contents/Resources/zeus-now-playing)\z};
my @stat = lstat($caller) or die "now-playing caller missing\n";
my $type = $stat[2] & 0170000;
die "now-playing caller is a symlink\n" if $type == 0120000;
die "now-playing caller is not a file\n" unless $type == 0100000;
my $owner = $stat[4];
die "now-playing caller owner refused\n" unless $owner == 0 || $owner == $>;
exec {$caller} $caller;
die "now-playing caller could not start: $!\n";
