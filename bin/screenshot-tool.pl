#!/usr/bin/env perl
# screenshot-tool.pl - Main executable for the Perl Screenshot Tool

use strict;
use warnings;
use utf8;
use lib "$ENV{HOME}/.local/share/perl-screenshot-tool/lib";
use Getopt::Long;
use Gtk3 -init;
use ScreenshotTool;

# Parse command line arguments
my $show_help = 0;
my $show_version = 0;
my $verbose = 0;
my $background_mode = 0;
my $log_to_file = 0;

# Suppress GTK warnings in Wayland
BEGIN {
    # Redirect STDERR to /dev/null for GTK warnings
    if ($ENV{XDG_SESSION_TYPE} eq 'wayland') {
        $ENV{G_ENABLE_DIAGNOSTIC} = 0;
        $ENV{G_DEBUG} = "";
        $ENV{WAYLAND_DEBUG} = "";
        open(STDERR, ">>", "/dev/null") or warn "Could not redirect STDERR: $!";
    }
}

GetOptions(
    'help|h'     => \$show_help,
    'version|v'  => \$show_version,
    'verbose'    => \$verbose,
    'background' => \$background_mode,
    'minimize'   => \$background_mode,
    'log-to-file' => \$log_to_file,
) or usage();

# Process simple commands
if ($show_help) {
    usage();
    exit 0;
}

if ($show_version) {
    # Create a temporary app just to get version info
    my $app = ScreenshotTool->new();
    print $app->app_name() . " " . $app->app_version() . "\n";
    exit 0;
}

# Create and run the application
my $app = ScreenshotTool->new(
    verbose => $verbose,
    log_to_file => $log_to_file,
    background => $background_mode,
    custom_icons_dir => "$ENV{HOME}/.local/share/perl-screenshot-tool/share/icons",
);

# Run the application in regular or background mode
if ($background_mode) {
    $app->run_in_background();
} else {
    $app->run();
}

# Don't forget to include the usage subroutine
sub usage {
    print <<EOF;
Perl Screenshot Tool - A screenshot utility for Linux

Usage: $0 [OPTIONS]

Options:
  -h, --help           Show this help message and exit
  -v, --version        Show version information and exit
  --verbose            Enable verbose output
  --background         Start in background/tray mode
  --minimize           Same as --background
  --log-to-file        Write logs to file in addition to stdout

Keyboard Shortcuts:
  Ctrl+W or Ctrl+1     Capture active window
  Ctrl+R or Ctrl+2     Capture selected region
  Ctrl+D or Ctrl+3     Capture entire desktop
  PrintScreen          Capture entire desktop
  Alt+PrintScreen      Capture active window
  Shift+PrintScreen    Capture selected region

EOF
    exit 0;
}

__END__

=head1 NAME

screenshot-tool.pl - A screenshot utility for Linux

=head1 SYNOPSIS

screenshot-tool.pl [options]

=head1 DESCRIPTION

A flexible screenshot tool for Linux that works on both X11 and Wayland.
Supports window, region, and fullscreen captures with various options.

=head1 OPTIONS

=over 4

=item B<-h, --help>

Show this help message and exit.

=item B<-v, --version>

Show version information and exit.

=item B<--verbose>

Enable verbose logging output.

=item B<--background, --minimize>

Start in background mode with a system tray icon.

=item B<--log-to-file>

Write logs to a file in addition to standard output.

=back

=head1 KEYBOARD SHORTCUTS

=over 4

=item B<PrintScreen>

Capture entire desktop.

=item B<Shift+PrintScreen>

Capture selected region.

=item B<Alt+PrintScreen>

Capture active window.

=item B<Ctrl+1, Ctrl+W>

Capture active window.

=item B<Ctrl+2, Ctrl+R>

Capture selected region.

=item B<Ctrl+3, Ctrl+D>

Capture entire desktop.

=back

=head1 DEPENDENCIES

This application requires the following Perl modules:

=over 4

=item * Gtk3

=item * Cairo

=item * File::Path

=item * File::Spec

=item * File::Temp

=item * POSIX

=item * X11::Protocol (optional but recommended)

=back

=head1 AUTHOR

Screenshot Tool Project <zeljko.vukman@proton.me>

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut