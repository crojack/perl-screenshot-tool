#!/usr/bin/env perl

use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy::Recursive qw(dircopy);
use File::Copy qw(copy);
use Cwd qw(abs_path);
use File::Basename qw(dirname basename);

# Determine if running as root
my $is_root = ($> == 0);

# Default installation paths
my $bin_dir = $is_root ? "/usr/bin" : "$ENV{HOME}/.local/bin";
my $desktop_dir = $is_root ? "/usr/share/applications" : "$ENV{HOME}/.local/share/applications";
my $app_dir = "$ENV{HOME}/.local/share/perl-screenshot-tool";

# Get current script directory
my $script_dir = dirname(abs_path($0));

# Ask user for confirmation
print "This will install Perl Screenshot Tool with the following settings:\n";
print "* Screenshot tool executable: $bin_dir/screenshot-tool\n";
print "* Desktop file: $desktop_dir/screenshot-tool.desktop\n";
print "* Application files: $app_dir\n\n";
print "Continue? [y/N] ";

my $response = <STDIN>;
chomp $response;
exit 0 unless $response =~ /^y/i;

# Create directories if they don't exist
make_path($bin_dir) unless -d $bin_dir;
make_path($desktop_dir) unless -d $desktop_dir;
make_path($app_dir) unless -d $app_dir;

# Check for dependencies
check_dependencies();

# Install files
print "\nInstalling Perl Screenshot Tool...\n";

# Install executable script
print "Installing executable script to $bin_dir/screenshot-tool...\n";
copy("$script_dir/bin/screenshot-tool.pl", "$bin_dir/screenshot-tool");
chmod 0755, "$bin_dir/screenshot-tool";

# Install desktop file
print "Installing desktop file to $desktop_dir/screenshot-tool.desktop...\n";
copy("$script_dir/applications/screenshot-tool.desktop", "$desktop_dir/screenshot-tool.desktop");

# If modifying a system directory, update the Exec path in the desktop file
if ($bin_dir eq "/usr/bin") {
    system("sed -i 's|Exec=.*|Exec=/usr/bin/screenshot-tool|g' $desktop_dir/screenshot-tool.desktop");
} else {
    system("sed -i 's|Exec=.*|Exec=$bin_dir/screenshot-tool|g' $desktop_dir/screenshot-tool.desktop");
}

# Install library files
print "Installing library files to $app_dir/lib...\n";
make_path("$app_dir/lib");
dircopy("$script_dir/lib", "$app_dir/lib");

# Install share files
print "Installing icon files to $app_dir/share...\n";
make_path("$app_dir/share");
dircopy("$script_dir/share", "$app_dir/share");

# Create bin directory
make_path("$app_dir/bin");
copy("$script_dir/bin/screenshot-tool.pl", "$app_dir/bin/screenshot-tool.pl");
chmod 0755, "$app_dir/bin/screenshot-tool.pl";

# Create applications directory
make_path("$app_dir/applications");
copy("$script_dir/applications/screenshot-tool.desktop", "$app_dir/applications/screenshot-tool.desktop");

print "\nInstallation completed successfully!\n";
print "You can now launch Perl Screenshot Tool from your application menu or by running 'screenshot-tool'\n";

if (!$is_root) {
    print "\nNOTE: Make sure $bin_dir is in your PATH environment variable.\n";
    print "If not, run: export PATH=\"\$PATH:$bin_dir\"\n";
    print "You may want to add this line to your ~/.bashrc file.\n";
}

# Check if required dependencies are installed
sub check_dependencies {
    my @dependencies = qw(
        Gtk3
        Cairo
        File::Path
        File::Spec
        File::Temp
        POSIX
    );
    
    my @missing;
    
    foreach my $module (@dependencies) {
        eval "require $module";
        if ($@) {
            push @missing, $module;
        }
    }
    
    if (@missing) {
        print "WARNING: The following Perl modules are required but not installed:\n";
        print "  ", join(", ", @missing), "\n\n";
        print "You can install them using cpanm:\n";
        print "  cpanm ", join(" ", @missing), "\n\n";
        
        # If apt is available, suggest package installation
        if (-e "/usr/bin/apt") {
            print "Or with apt (on Debian/Ubuntu):\n";
            print "  sudo apt install libgtk3-perl libcairo-perl\n\n";
        }
        
        print "Continue installation anyway? [y/N] ";
        my $resp = <STDIN>;
        chomp $resp;
        exit 0 unless $resp =~ /^y/i;
    }
}
