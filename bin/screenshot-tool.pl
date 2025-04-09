#!/usr/bin/env perl
# screenshot-tool.pl - Main executable for the Perl Screenshot Tool

use strict;
use warnings;
use utf8;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Getopt::Long;
use Gtk3 -init;

use ScreenshotTool;

my $show_help = 0;
my $show_version = 0;
my $verbose = 0;

GetOptions(
    'help|h'    => \$show_help,
    'version|v' => \$show_version,
    'verbose'   => \$verbose,
) or usage();


if ($show_help) {
    usage();
    exit 0;
}

if ($show_version) {
 
    my $app = ScreenshotTool->new();
    print $app->app_name . " " . $app->app_version . "\n";
    exit 0;
}


my $app = ScreenshotTool->new(verbose => $verbose);
$app->run();


sub usage {
    my $script_name = $FindBin::Script;
    print <<EOF;
Perl Screenshot Tool - A screenshot utility for Linux

Usage: $script_name [OPTIONS]

Options:
  -h, --help           Show this help message and exit
  -v, --version        Show version information and exit
  --verbose            Enable verbose output

EOF
    exit 0;
}

__END__

=head1 NAME

screenshot-tool.pl - A screenshot utility for Linux

=head1 SYNOPSIS

screenshot-tool.pl [options]

=head1 DESCRIPTION

A screenshot tool for Linux that works on both X11 and Wayland.
Supports window, region, and fullscreen captures with various options.

=head1 OPTIONS

=over 4

=item B<-h, --help>

Show this help message and exit.

=item B<-v, --version>

Show version information and exit.

=item B<--verbose>

Enable verbose logging output.

=back

=head1 DEPENDENCIES

This application requires the following Perl modules:

=over 4

=item * Gtk3

=item * Cairo

=item * Moo

=item * File::Path

=item * File::Spec

=item * File::Temp

=item * POSIX

=item * X11::Protocol

=back

=head1 AUTHOR

Zeljko Vukman <zeljko.vukman@proton.me>

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
