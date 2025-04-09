package ScreenshotTool;

use strict;
use warnings;
use Moo;
use Gtk3 -init;
use Glib qw(TRUE FALSE);
use Cairo;
use File::Temp qw(tempfile);
use File::Basename qw(basename);
use File::Path qw(make_path);
use File::Spec;
use POSIX qw(strftime);
use Getopt::Long;
use utf8;
use open ':encoding(UTF-8)';
use namespace::clean;


use ScreenshotTool::Config;
use ScreenshotTool::UI;
use ScreenshotTool::Utils;
use ScreenshotTool::CaptureManager;
use ScreenshotTool::RegionSelector;
use ScreenshotTool::KeyboardShortcuts;


has 'APP_NAME' => (
    is      => 'ro',
    default => sub { 'Perl Screenshot Tool' },
);

has 'APP_VERSION' => (
    is      => 'ro',
    default => sub { '0.1.0' },
);


has 'verbose' => (
    is      => 'rw',
    default => sub { 0 },
);


has 'config' => (
    is      => 'rw', 
    lazy    => 1,
    builder => '_build_config',
);

has 'ui' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_ui',
);

has 'capture_manager' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_capture_manager',
);

has 'window_system' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_window_system',
);

has 'desktop_env' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_desktop_env',
);

has 'wayland_tools' => (
    is      => 'rw',
    default => sub { {} },
);

has 'keyboard_shortcuts' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_keyboard_shortcuts',
);


sub BUILD {
    my ($self) = @_;
    
    $self->initialize();
}


sub _build_config {
    my ($self) = @_;
    return ScreenshotTool::Config->new(app => $self);
}

sub _build_ui {
    my ($self) = @_;
    return ScreenshotTool::UI->new(app => $self);
}

sub _build_capture_manager {
    my ($self) = @_;
    return ScreenshotTool::CaptureManager->new(app => $self);
}

sub _build_desktop_env {
    my ($self) = @_;
    return $self->detect_desktop_environment();
}

sub _build_window_system {
    my ($self) = @_;
    return $self->detect_window_system();
}

sub _build_keyboard_shortcuts {
    my ($self) = @_;
    return ScreenshotTool::KeyboardShortcuts->new(app => $self);
}


sub initialize {
    my ($self) = @_;
    
    $self->desktop_env;
    $self->window_system;
    
    if ($self->window_system =~ /^wayland/) {
        $self->log_message('info', "Detected Wayland environment - setting up desktop integration");
        
        if ($self->desktop_env =~ /GNOME/i) {
            $self->log_message('info', "GNOME Wayland detected - screenshot shortcuts can be configured in Settings");
     
            my $can_use_gsettings = system("which gsettings >/dev/null 2>&1") == 0;
            if ($can_use_gsettings) {
                $self->log_message('info', "gsettings available for GNOME integration");
          
                system("gsettings get org.gnome.settings-daemon.plugins.media-keys screenshot");
                system("gsettings get org.gnome.settings-daemon.plugins.media-keys window-screenshot");
                system("gsettings get org.gnome.settings-daemon.plugins.media-keys area-screenshot");
            }
        } else {
            $self->log_message('info', "Non-GNOME Wayland environment detected - gnome-screenshot will be used");
        }
        
        $self->detect_wayland_tools();
    }
    
    $self->config;
    $self->capture_manager;
    
    $self->{init_keyboard_shortcuts} = 1;
    
    my $thumbnail_dir = "$ENV{HOME}/.cache/thumbnails/normal";
    if (!-d $thumbnail_dir) {
        $self->log_message('info', "Creating thumbnail cache directory: $thumbnail_dir");
        eval {
            make_path($thumbnail_dir, {
                mode => 0755  
            });
        };
        if ($@) {
            $self->log_message('error', "Failed to create thumbnail directory: $@");
        } else {
            $self->log_message('info', "Thumbnail directory created successfully");
        }
    }

    if (-d $thumbnail_dir) {
        if (-w $thumbnail_dir) {
            $self->log_message('info', "Thumbnail directory is writable");
        } else {
            $self->log_message('warning', "Thumbnail directory exists but is not writable");
        }
    } else {
        $self->log_message('warning', "Thumbnail directory still does not exist after creation attempt");
    }
}

sub init_keyboard_shortcuts {
    my ($self) = @_;
    
    return unless $self->ui && $self->ui->{main_window};
    
    $self->log_message('info', "Initializing keyboard shortcuts");
    
    my $shortcuts = ScreenshotTool::KeyboardShortcuts->new(app => $self);
    $shortcuts->initialize();
    $self->{keyboard_shortcuts} = $shortcuts;
}


sub run {
    my ($self) = @_;
    
    $SIG{INT} = sub { 
        $self->log_message('info', "Received termination signal, exiting...");
        $self->ui->{is_quitting} = 1;
        Gtk3->main_quit();
        exit(0);
    };
    
    $self->ui->show_main_window();
    
    if (!$self->{keyboard_shortcuts}) {
        $self->{keyboard_shortcuts} = ScreenshotTool::KeyboardShortcuts->new(app => $self);
    }
    
    $self->{keyboard_shortcuts}->initialize();
    
    $self->ui->{main_window}->present();
    
    Gtk3->main();
    
    $self->log_message('info', "Application exiting cleanly");
}


sub app_name {
    my ($self) = @_;
    return $self->APP_NAME;
}

sub app_version {
    my ($self) = @_;
    return $self->APP_VERSION;
}


sub detect_desktop_environment {
    my ($self) = @_;
    my $desktop = $ENV{XDG_CURRENT_DESKTOP} || $ENV{DESKTOP_SESSION} || '';
    return $desktop;
}


sub detect_window_system {
    my ($self) = @_;
    
    my $wayland = $ENV{WAYLAND_DISPLAY} ? 1 : 0;
    my $session_type = $ENV{XDG_SESSION_TYPE} || 'unknown';
    my $desktop_session = $ENV{XDG_SESSION_DESKTOP} || $ENV{DESKTOP_SESSION} || 'unknown';
    
    $self->log_message('info', "Session type: $session_type");
    $self->log_message('info', "Desktop environment: $desktop_session");
    $self->log_message('info', "WAYLAND_DISPLAY: " . ($ENV{WAYLAND_DISPLAY} || 'not set'));
    
    if ($wayland || $session_type eq 'wayland') {
 
        my $has_gnome_screenshot = system("which gnome-screenshot >/dev/null 2>&1") == 0;
        
        if ($has_gnome_screenshot) {
            $self->log_message('info', "Detected Wayland environment with gnome-screenshot available");
            return 'wayland';
        } else {
            $self->log_message('warning', "Wayland detected but gnome-screenshot not found");
            $self->log_message('warning', "Please install gnome-screenshot:");
            $self->log_message('warning', "sudo apt install gnome-screenshot");
            return 'wayland-limited';
        }
    }
    
    $self->log_message('info', "Using Xorg screenshot methods");
    return 'xorg';
}

sub detect_wayland_tools {
    my ($self) = @_;
    
    $self->log_message('info', "Detecting available Wayland screenshot tools...");
    
    my %tools = (
        'gnome-screenshot' => 0,
    );
    
    foreach my $tool (keys %tools) {
        $tools{$tool} = 1 if system("which $tool >/dev/null 2>&1") == 0;
    }
    
    $self->wayland_tools(\%tools);
    
    foreach my $tool (keys %tools) {
        if ($tools{$tool}) {
            $self->log_message('info', "Wayland tool available: $tool");
        } else {
            $self->log_message('debug', "Wayland tool not found: $tool");
        }
    }
}

sub log_message {
    my ($self, $level, $message) = @_;
    
    return if $level eq 'debug' && !$self->verbose;
    
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    print "[$timestamp] [$level] $message\n";
}

sub show_help {
    my ($self) = @_;
    
    print <<EOF;
@{[$self->APP_NAME]} @{[$self->APP_VERSION]}
A screenshot tool for Linux that works on both Xorg and Wayland.

Usage: $0 [OPTIONS]

Options:
  -h, --help     Show this help message and exit
  -v, --version  Show version information and exit
  --verbose      Enable verbose output

EOF
}

1;
