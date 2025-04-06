package ScreenshotTool;

use strict;
use warnings;
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

# Import other classes
use ScreenshotTool::Config;
use ScreenshotTool::UI;
use ScreenshotTool::Utils;
use ScreenshotTool::CaptureManager;
use ScreenshotTool::RegionSelector;
use ScreenshotTool::CursorUtils;
use ScreenshotTool::Logger;

# Constructor
sub new {
    my ($class, %args) = @_;
    
    my $self = bless {
        # Application constants
        APP_NAME => 'Perl Screenshot Tool',
        APP_VERSION => '0.2',
        
        # Flags
        verbose => $args{verbose} || 0,
        log_to_file => $args{log_to_file} || 0,
        background => $args{background} || 0,
        
        # Paths
        custom_icons_dir => $args{custom_icons_dir} || "$ENV{HOME}/.local/share/perl-screenshot-tool/share/icons",
        
        # Components
        config => undef,
        ui => undef,
        utils => undef,
        capture_manager => undef,
        keyboard_shortcuts => undef,
        cursor_utils => undef,
        logger => undef,
        
        # State
        window_system => undef,
        desktop_env => undef,
        _cleaned_up => 0,
    }, $class;
    
    # Initialize logger first so we can log during initialization
    $self->{logger} = ScreenshotTool::Logger->new(
        verbose => $self->{verbose},
        log_to_file => $self->{log_to_file},
        log_file => "$ENV{HOME}/.local/share/perl-screenshot-tool/logs/screenshot-tool.log",
    );
    
    # Initialize
    $self->initialize();
    
    return $self;
}

# Initialize application
sub initialize {
    my ($self) = @_;
    
    $self->log_message('info', "Initializing " . $self->app_name() . " " . $self->app_version());
    
    # Detect system environment
    $self->{desktop_env} = $self->detect_desktop_environment();
    $self->{window_system} = $self->detect_window_system();
    
    # Initialize utilities first - other components may need it
    $self->{utils} = ScreenshotTool::Utils->new(app => $self);
    
    # Create configuration
    $self->{config} = ScreenshotTool::Config->new(app => $self);
    
    # Initialize cursor utilities
    $self->initialize_cursor_utils();
    
    # Create the capture manager
    $self->{capture_manager} = ScreenshotTool::CaptureManager->new(app => $self);
    
    # Initialize UI
    $self->{ui} = ScreenshotTool::UI->new(app => $self);
    
    # Create thumbnail directory
    my $thumbnail_dir = $self->{utils}->get_path_for_cache('thumbnails');
    if (!-d $thumbnail_dir) {
        $self->log_message('info', "Creating thumbnail cache directory: $thumbnail_dir");
        
        if ($self->{utils}->ensure_path_exists($thumbnail_dir, 0755)) {
            $self->log_message('info', "Thumbnail directory created successfully");
        }
    }
}


sub initialize_cursor_utils {
    my ($self) = @_;
    
    eval {
        require ScreenshotTool::CursorUtils;
        $self->{cursor_utils} = ScreenshotTool::CursorUtils->new(app => $self);
        $self->log_message('info', "Cursor utilities loaded successfully");
    };
    if ($@) {
        $self->log_message('error', "Failed to load CursorUtils module: $@");
        # Create a basic stub if the module can't be loaded
        $self->{cursor_utils} = bless {
            app => $self,
            add_cursor_to_screenshot => sub { return 0; }
        }, 'ScreenshotTool::CursorUtils::Stub';
    }
}

sub initialize_keyboard_shortcuts {
    my ($self) = @_;
    
    eval {
        require ScreenshotTool::KeyboardShortcuts;
        $self->{keyboard_shortcuts} = ScreenshotTool::KeyboardShortcuts->new(app => $self);
        $self->{keyboard_shortcuts}->initialize();
        $self->log_message('info', "Keyboard shortcuts initialized");
    };
    if ($@) {
        $self->log_message('warning', "Failed to initialize keyboard shortcuts: $@");
    }
    
    return $self->{keyboard_shortcuts};
}

sub run {
    my ($self) = @_;
    
    # Add signal handlers
    $SIG{INT} = $SIG{TERM} = sub { 
        $self->log_message('info', "Received termination signal");
        if ($self->{ui}) {
            $self->{ui}->{is_quitting} = 1;
        }
        $self->cleanup();
        Gtk3->main_quit();
    };
    
    # Register an atexit handler too
    END {
        if (defined $self && !$self->{_cleaned_up}) {
            $self->{_cleaned_up} = 1;
            $self->cleanup();
        }
    }
    
    # Create the main window
    $self->{ui}->show_main_window();
    
    # Initialize keyboard shortcuts
    $self->initialize_keyboard_shortcuts();
    
    # Hide the window if in background mode
    if ($self->{background}) {
        $self->log_message('info', "Starting in background mode");
        $self->{ui}->{main_window}->hide();
        
        # Create tray icon
        $self->create_tray_icon();
    }
    
    # Start the main loop
    eval {
        Gtk3->main();
    };
    
    if ($@) {
        $self->log_message('error', "Error in Gtk main loop: $@");
    }
    
    # Cleanup will be called by signal handler or END block
    return 1;
}

sub run_in_background {
    my ($self) = @_;
    
    # Set background flag
    $self->{background} = 1;
    
    # Just run in normal mode with background flag set
    return $self->run();
}

# Create tray icon menu
sub create_tray_menu {
    my ($self) = @_;
    
    my $menu = Gtk3::Menu->new();
    
    # Capture options - use UI's create_menu_item method
    $menu->append($self->{ui}->create_menu_item('normal', "Capture Window", sub {
        $self->{config}->selection_mode(0);
        $self->{capture_manager}->start_capture();
    }));
    
    $menu->append($self->{ui}->create_menu_item('normal', "Capture Region", sub {
        $self->{config}->selection_mode(1);
        $self->{capture_manager}->start_capture();
    }));
    
    $menu->append($self->{ui}->create_menu_item('normal', "Capture Desktop", sub {
        $self->{config}->selection_mode(2);
        $self->{capture_manager}->start_capture();
    }));
    
    # Separator
    $menu->append($self->{ui}->create_menu_item('separator', ""));
    
    # Settings
    $menu->append($self->{ui}->create_menu_item('normal', "Settings", sub {
        $self->{ui}->show_options_menu(undef);
    }));
    
    # Show main window
    $menu->append($self->{ui}->create_menu_item('normal', "Show Main Window", sub {
        $self->{ui}->restore_main_window();
    }));
    
    # Separator
    $menu->append($self->{ui}->create_menu_item('separator', ""));
    
    # Quit
    $menu->append($self->{ui}->create_menu_item('normal', "Quit", sub {
        $self->log_message('info', "Quitting from tray menu");
        $self->cleanup();
        Gtk3->main_quit();
    }));
    
    $menu->show_all();
    return $menu;
}

# Create a system tray icon
sub create_tray_icon {
    my ($self) = @_;
    
    # Create a status icon in the system tray
    my $status_icon = Gtk3::StatusIcon->new();
    $status_icon->set_from_icon_name('camera-photo');
    $status_icon->set_tooltip_text($self->app_name());
    $status_icon->set_visible(TRUE);
    
    # Store it for later use
    $self->{status_icon} = $status_icon;
    
    # Right-click menu handling
    $status_icon->signal_connect('button-press-event' => sub {
        my ($widget, $event) = @_;
        
        if ($event->button == 3) {  # Right-click
            my $menu = $self->create_tray_menu();
            $menu->popup(undef, undef, sub {
                Gtk3::StatusIcon::position_menu($menu, $status_icon);
            }, $status_icon, $event->button, $event->time);
            return TRUE;
        } elsif ($event->button == 1) {  # Left-click
            # Toggle main window visibility
            if (defined $self->{ui} && defined $self->{ui}->{main_window}) {
                if ($self->{ui}->{main_window}->is_visible()) {
                    $self->{ui}->{main_window}->hide();
                } else {
                    $self->{ui}->restore_main_window();
                }
            }
            return TRUE;
        }
        
        return FALSE;
    });
}

# Get application name
sub app_name {
    my ($self) = @_;
    return $self->{APP_NAME};
}

# Get application version
sub app_version {
    my ($self) = @_;
    return $self->{APP_VERSION};
}

# Detect the desktop environment
sub detect_desktop_environment {
    my ($self) = @_;
    my $desktop = $ENV{XDG_CURRENT_DESKTOP} || $ENV{DESKTOP_SESSION} || '';
    return $desktop;
}

# Detect window system (Wayland or X11) - Enhanced with better detection
sub detect_window_system {
    my ($self) = @_;
    
    # Collect all environment variables that might indicate Wayland
    my $wayland_indicators = {
        WAYLAND_DISPLAY => $ENV{WAYLAND_DISPLAY},
        XDG_SESSION_TYPE => ($ENV{XDG_SESSION_TYPE} || '') eq 'wayland' ? 1 : 0,
        GNOME_SHELL_SESSION_MODE => $ENV{GNOME_SHELL_SESSION_MODE} ? 1 : 0,
        # KDE Plasma on Wayland
        KDE_FULL_SESSION => ($ENV{KDE_FULL_SESSION} && $ENV{XDG_SESSION_TYPE} eq 'wayland') ? 1 : 0,
    };
    
    # Log all indicators
    foreach my $key (keys %$wayland_indicators) {
        $self->log_message('debug', "$key: " . (defined $wayland_indicators->{$key} ? 
            $wayland_indicators->{$key} : 'not set'));
    }
    
    # Determine if we're running under Wayland
    my $is_wayland = $wayland_indicators->{WAYLAND_DISPLAY} || 
                     $wayland_indicators->{XDG_SESSION_TYPE} ||
                     ($wayland_indicators->{GNOME_SHELL_SESSION_MODE} && 
                      $wayland_indicators->{XDG_SESSION_TYPE});
    
    if ($is_wayland) {
        # Check available tools for Wayland screenshot capture
        my @tools = (
            { cmd => 'gnome-screenshot', type => 'wayland' },
            { cmd => 'grim', type => 'wayland-grim' },
            { cmd => 'slurp', type => 'wayland-slurp' },
            { cmd => 'ksnip', type => 'wayland-ksnip' },
        );
        
        foreach my $tool (@tools) {
            if (system("which $tool->{cmd} >/dev/null 2>&1") == 0) {
                $self->log_message('info', "Found $tool->{cmd} for Wayland capture");
                return $tool->{type};
            }
        }
        
        $self->log_message('warning', "Wayland detected but no compatible tools found");
        return 'wayland-limited';
    }
    
    # Fall back to X11
    $self->log_message('info', "Using X11/Xorg screenshot methods");
    return 'xorg';
}

# Logging function - delegates to Logger class
sub log_message {
    my ($self, $level, $message) = @_;
    
    if ($self->{logger}) {
        $self->{logger}->log($level, $message);
    } else {
        # Fallback if logger is not yet initialized
        my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
        print "[$timestamp] [$level] $message\n";
    }
}

# Clean up resources when shutting down
sub cleanup {
    my ($self) = @_;
    
    if ($self->{_cleaned_up}) {
        return; # Prevent multiple cleanup runs
    }
    
    $self->log_message('info', "Cleaning up resources");
    
    # Save config before exiting
    if ($self->{config}) {
        $self->{config}->save_config();
    }
    
    # Clean up UI resources
    if ($self->{ui}) {
        $self->{ui}->destroy_resources();
    }
    
    # Clean up region selector if active
    if ($self->{capture_manager} && $self->{capture_manager}->{region_selector}) {
        $self->{capture_manager}->{region_selector}->destroy_overlay();
    }
    
    # Clean up capture manager resources
    if ($self->{capture_manager}) {
        $self->{capture_manager}->cleanup();
    }
    
    # Clean up keyboard shortcuts
    if ($self->{keyboard_shortcuts}) {
        $self->{keyboard_shortcuts}->cleanup();
    }
    
    # Clean up cursor utils cache
    if ($self->{cursor_utils} && $self->{cursor_utils}->can('clear_cache')) {
        $self->{cursor_utils}->clear_cache();
    }
    
    # Close log file
    if ($self->{logger}) {
        $self->{logger}->close();
    }
    
    # Set cleaned up flag
    $self->{_cleaned_up} = 1;
    
    $self->log_message('info', "Application resources cleaned up");
}

# Show help information
sub show_help {
    my ($self) = @_;
    
    print <<EOF;
$self->{APP_NAME} $self->{APP_VERSION}
A screenshot tool for Linux that works on both Xorg and Wayland.

Usage: $0 [OPTIONS]

Options:
  -h, --help         Show this help message and exit
  -v, --version      Show version information and exit
  --verbose          Enable verbose output
  --background       Start in background/tray mode
  --minimize         Same as --background
  --log-to-file      Write logs to file in addition to stdout

Keyboard Shortcuts:
  Ctrl+W or Ctrl+1   Capture active window
  Ctrl+R or Ctrl+2   Capture selected region
  Ctrl+D or Ctrl+3   Capture entire desktop
  PrintScreen        Capture entire desktop
  Alt+PrintScreen    Capture active window
  Shift+PrintScreen  Capture selected region

EOF
}

1;   