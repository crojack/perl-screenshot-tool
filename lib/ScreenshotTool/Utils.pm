package ScreenshotTool::Utils;

use strict;
use warnings;
use Moo;
use File::Path qw(make_path);
use File::Spec;
use POSIX qw(strftime);
use namespace::clean;

has 'app' => (
    is       => 'ro',
    required => 1,
);

sub generate_filename {
    my ($self, $format) = @_;
    
    my $timestamp = strftime("%Y-%m-%d-%H%M%S", localtime);
    return "Screenshot-$timestamp.$format";
}

sub ensure_directory {
    my ($self, $dir) = @_;
    
    if (!-d $dir) {
        $self->app->log_message('info', "Creating directory: $dir");
        make_path($dir);
        return 1;
    }
    
    return 0;
}

sub min {
    my ($self, $a, $b) = @_;
    return $a < $b ? $a : $b;
}

sub normalize_rect {
    my ($self, $x, $y, $w, $h) = @_;
    
    if ($w < 0) {
        $x += $w;
        $w = abs($w);
    }
    
    if ($h < 0) {
        $y += $h;
        $h = abs($h);
    }
    
    return ($x, $y, $w, $h);
}

sub map_format_string {
    my ($self, $format) = @_;
    
    if ($format eq "jpg") {
        return "jpeg";
    } elsif ($format eq "webp") {
        return "webp";
    } else {
        return $format;
    }
}

sub get_timestamp {
    my ($self) = @_;
    return strftime("%Y-%m-%d %H:%M:%S", localtime);
}

sub get_datetime_for_filename {
    my ($self) = @_;
    return strftime("%Y-%m-%d-%H%M%S", localtime);
}

1;
