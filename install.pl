#!/usr/bin/env perl

use strict;
use warnings;
use File::Basename;
use File::Path qw(make_path);
use File::Copy;
use File::Copy::Recursive qw(dircopy);
use File::Temp qw(tempfile); # Add this import

# Define installation paths
my $HOME = $ENV{HOME}; # This will be /root when run with sudo
my $REAL_USER = $ENV{SUDO_USER} || $ENV{USER} || getpwuid($<);
my $REAL_HOME = $REAL_USER ? (getpwnam($REAL_USER))[7] : $HOME;

my $BIN_DIR = "/usr/bin";  # System binary directory
my $CONFIG_DIR = "$REAL_HOME/.config/perl-screenshot-tool";
my $DATA_DIR = "$REAL_HOME/.local/share/perl-screenshot-tool";
my $LIB_DIR = "$DATA_DIR/lib";
my $SHARE_DIR = "$DATA_DIR/share";
my $APPLICATIONS_DIR = "$REAL_HOME/.local/share/applications";

print "Installing Perl Screenshot Tool...\n";
print "Installing for user: $REAL_USER (home: $REAL_HOME)\n";

# Create user directories
print "Creating user directories...\n";
make_path($CONFIG_DIR, $LIB_DIR, $SHARE_DIR, $APPLICATIONS_DIR);

# Copy library files
print "Installing library files...\n";
# Main module
if (-d "lib") {
    print "Copying lib directory to $LIB_DIR...\n";
    dircopy("lib", $LIB_DIR) or die "Error copying lib directory: $!";
}

# Copy share files (including icons)
if (-d "share") {
    print "Copying share directory to $SHARE_DIR...\n";
    dircopy("share", $SHARE_DIR) or die "Error copying share directory: $!";
}

# Create default config file
print "Creating default config file...\n";
my $config_content = qq{# Perl Screenshot Tool configuration
# Generated automatically by installation script

# Default save location
save_location = $REAL_HOME/Pictures

# Capture settings
show_mouse_pointer = 0
capture_window_decoration = 1
remember_last_selection = 1
show_floating_thumbnail = 1

# Interface settings
icon_size = 64
theme = system
};

open(my $fh, '>', "$CONFIG_DIR/config.ini") 
    or die "Cannot write config file: $!";
print $fh $config_content;
close($fh);

# Install executable script to system directory (requires sudo)
print "Installing executable to $BIN_DIR (requires sudo)...\n";
system("sudo cp bin/screenshot-tool.pl $BIN_DIR/screenshot-tool");
system("sudo chmod 755 $BIN_DIR/screenshot-tool");

# Create desktop file
print "Creating desktop entry...\n";
my $desktop_content = qq{
[Desktop Entry]
Name=Perl Screenshot Tool
Comment=Take screenshots of your desktop
Exec=screenshot-tool
Icon=$SHARE_DIR/icons/64x64/perl-screenshot-tool.svg
Terminal=false
Type=Application
Categories=Graphics;Utility;
Keywords=screenshot;screen;capture;
};

open($fh, '>', "$APPLICATIONS_DIR/perl-screenshot-tool.desktop") 
    or die "Cannot write desktop file: $!";
print $fh $desktop_content;
close($fh);

# Update desktop database
system("update-desktop-database $REAL_HOME/.local/share/applications 2>/dev/null");

# Modify the script to update PERL5LIB to include the user's lib directory
print "Updating executable to use the user's lib directory...\n";
my $script_content = qq{#!/usr/bin/env perl
# Modified installer script to include user lib path

use lib "$LIB_DIR";
use FindBin qw(\$Bin);
use Getopt::Long;
use Gtk3 -init;

# Import the main application class
use ScreenshotTool;

# Parse command line arguments
my \$show_help = 0;
my \$show_version = 0;
my \$verbose = 0;

GetOptions(
    'help|h'    => \\\$show_help,
    'version|v' => \\\$show_version,
    'verbose'   => \\\$verbose,
) or usage();

# Process simple commands
if (\$show_help) {
    usage();
    exit 0;
}

if (\$show_version) {
    # Create a temporary app just to get version info
    my \$app = ScreenshotTool->new();
    print \$app->app_name . " " . \$app->app_version . "\\n";
    exit 0;
}

# Create and run the application
my \$app = ScreenshotTool->new(verbose => \$verbose);
\$app->run();

# Usage information
sub usage {
    print <<EOF;
Perl Screenshot Tool - A screenshot utility for Linux

Usage: screenshot-tool [OPTIONS]

Options:
  -h, --help           Show this help message and exit
  -v, --version        Show version information and exit
  --verbose            Enable verbose output

EOF
    exit 0;
}
};

# Write the script to a temporary file and use sudo to move it
my ($temp_fh, $temp_file) = tempfile();
print $temp_fh $script_content;
close $temp_fh;
system("sudo cp $temp_file $BIN_DIR/screenshot-tool");
unlink $temp_file;
system("sudo chmod 755 $BIN_DIR/screenshot-tool");

# Fix permissions for the user's files
print "Setting correct permissions...\n";
if ($REAL_USER && $REAL_USER ne $ENV{USER}) {
    system("sudo chown -R $REAL_USER:$REAL_USER $CONFIG_DIR");
    system("sudo chown -R $REAL_USER:$REAL_USER $DATA_DIR");
    system("sudo chown -R $REAL_USER:$REAL_USER $APPLICATIONS_DIR/perl-screenshot-tool.desktop");
}

print "\nInstallation complete!\n";
print "The Screenshot Tool has been installed.\n";
print "Configuration files are in: $CONFIG_DIR\n";
print "Application data is in: $DATA_DIR\n";
print "You can now run it from your application menu or by typing 'screenshot-tool'\n";
