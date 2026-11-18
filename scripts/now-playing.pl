#!/usr/bin/perl
use strict;
use warnings;
use DynaLoader ();
use File::Basename qw(dirname);
use Digest::SHA qw(sha256_hex);

# One tab-separated line: title, artist, album, playing, position, duration.
# System perl can load MediaRemote but cannot call a C function pointer, so the
# script loads the framework itself and builds a small caller that uses it.

my $framework = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote";
my $loaded = DynaLoader::dl_load_file($framework, 0x01)
    or die "Could not load MediaRemote\n";
my @symbols = qw(
    MRMediaRemoteGetNowPlayingInfo
    kMRMediaRemoteNowPlayingInfoTitle
    kMRMediaRemoteNowPlayingInfoArtist
    kMRMediaRemoteNowPlayingInfoAlbum
    kMRMediaRemoteNowPlayingInfoDuration
    kMRMediaRemoteNowPlayingInfoElapsedTime
    kMRMediaRemoteNowPlayingInfoPlaybackRate
);
for my $name (@symbols) {
    DynaLoader::dl_find_symbol($loaded, $name)
        or die "MediaRemote is missing $name\n";
}

my $source = caller_source();
my $digest = sha256_hex($source);
my $cache = ($ENV{TMPDIR} || "/tmp") . "/zeus-now-playing-$digest";
my $binary = "$cache/now-playing";
unless (-x $binary) {
    mkdir $cache, 0700 or die "Could not create $cache: $!\n";
    my $c = "$cache/now-playing.c";
    open my $out, ">", $c or die "Could not write $c: $!\n";
    print {$out} $source;
    close $out;
    my $log = "$cache/compile.log";
    my $status = system("cc", "-fblocks", "-O2", "-o", $binary, $c, "-framework", "CoreFoundation");
    if ($status != 0 || !-x $binary) {
        die "Could not build the MediaRemote caller\n";
    }
    unlink $log;
}

open my $pipe, "-|", $binary or die "Could not run the MediaRemote caller: $!\n";
my $line = do { local $/; <$pipe> };
close $pipe;
exit 1 if $?;
print $line if defined $line;
exit 0;

sub caller_source {
    return <<'C';
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

typedef void (^InfoBlock)(CFDictionaryRef info);
typedef void (*GetInfo)(dispatch_queue_t queue, InfoBlock block);

static CFStringRef key(void *library, const char *name) {
    CFStringRef *slot = dlsym(library, name);
    return slot ? *slot : NULL;
}

static void write_field(CFDictionaryRef info, CFStringRef field) {
    char text[512];
    text[0] = 0;
    if (info && field) {
        CFTypeRef value = CFDictionaryGetValue(info, field);
        if (value && CFGetTypeID(value) == CFStringGetTypeID()) {
            CFStringGetCString(value, text, sizeof text, kCFStringEncodingUTF8);
        } else if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
            double number = 0;
            CFNumberGetValue(value, kCFNumberDoubleType, &number);
            snprintf(text, sizeof text, "%.3f", number);
        }
    }
    for (char *cursor = text; *cursor; cursor++) {
        if (*cursor == '\t' || *cursor == '\n' || *cursor == '\r') *cursor = ' ';
    }
    fputs(text, stdout);
}

int main(void) {
    void *library = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (!library) return 1;
    GetInfo getInfo = (GetInfo)dlsym(library, "MRMediaRemoteGetNowPlayingInfo");
    if (!getInfo) return 1;
    CFStringRef title = key(library, "kMRMediaRemoteNowPlayingInfoTitle");
    CFStringRef artist = key(library, "kMRMediaRemoteNowPlayingInfoArtist");
    CFStringRef album = key(library, "kMRMediaRemoteNowPlayingInfoAlbum");
    CFStringRef duration = key(library, "kMRMediaRemoteNowPlayingInfoDuration");
    CFStringRef elapsed = key(library, "kMRMediaRemoteNowPlayingInfoElapsedTime");
    CFStringRef rate = key(library, "kMRMediaRemoteNowPlayingInfoPlaybackRate");
    __block CFDictionaryRef info = NULL;
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    getInfo(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(CFDictionaryRef dictionary) {
        if (dictionary) info = CFRetain(dictionary);
        dispatch_semaphore_signal(gate);
    });
    if (dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(800 * NSEC_PER_MSEC))) != 0 || !info) {
        fputc('\n', stdout);
        return 0;
    }
    write_field(info, title);
    fputc('\t', stdout);
    write_field(info, artist);
    fputc('\t', stdout);
    write_field(info, album);
    fputc('\t', stdout);
    double playback = 0;
    if (rate) {
        CFTypeRef value = CFDictionaryGetValue(info, rate);
        if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
            CFNumberGetValue(value, kCFNumberDoubleType, &playback);
        }
    }
    fputs(playback > 0.01 ? "1" : "0", stdout);
    fputc('\t', stdout);
    write_field(info, elapsed);
    fputc('\t', stdout);
    write_field(info, duration);
    fputc('\n', stdout);
    CFRelease(info);
    return 0;
}
C
}
