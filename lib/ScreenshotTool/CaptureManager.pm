package ScreenshotTool::CaptureManager;

use strict;
use warnings;
use Gtk3 qw(-init);
use Glib qw(TRUE FALSE);
use File::Path qw(make_path);
use Digest::MD5 qw(md5_hex);
use URI::file;
use File::Basename qw(basename dirname);
use File::Spec;
use POSIX qw(strftime);

# Check if X11::Protocol module is available and load it if possible
BEGIN {
    eval {
        require X11::Protocol;
        X11::Protocol->import();
    };
    if ($@) {
        my $has_protocol = 0;
    } else {
        my $has_protocol = 1;
    }
}

# Import region selector
use ScreenshotTool::RegionSelector;

# Constructor
sub new {
    my ($class, %args) = @_;
    
    my $app = $args{app} || die "App reference is required";
    
    my $self = bless {
        app => $app,
        
        # Components
        region_selector => undef,
        
        # State
        preview_pixbuf => undef,
        ui => undef,
        
        # Selection state
        selection_start_x => 0,
        selection_start_y => 0,
        selection_width => 0,
        selection_height => 0,
        
        # Capability flags
        has_x11_protocol => 0,
        has_xfixes => 0,
        
        # Track active captures to prevent overlapping operations
        active_capture => 0,
        
        # Track timeouts
        timeouts => [],
    }, $class;
    
    # Check for X11::Protocol and XFIXES extension availability
    eval {
        require X11::Protocol;
        $self->{has_x11_protocol} = 1;
        
        # Only try to check XFIXES if not on Wayland
        if ($app->{window_system} ne 'wayland' && $app->{window_system} ne 'wayland-limited') {
            my $x11 = X11::Protocol->new($ENV{'DISPLAY'});
            if ($x11->init_extension('XFIXES')) {
                $self->{has_xfixes} = 1;
                $app->log_message('info', "XFIXES extension available for cursor capture");
            } else {
                $app->log_message('info', "XFIXES extension not available, will use fallback cursor capture method");
            }
        }
    };
    
    if ($@) {
        $app->log_message('warning', "X11::Protocol module not available: $@");
        $app->log_message('warning', "Advanced cursor capture will be limited");
    }
    
    # Create region selector
    $self->{region_selector} = ScreenshotTool::RegionSelector->new(
        app => $app,
        capture_manager => $self
    );
    
    return $self;
}


# Helper method to ensure directory exists
sub ensure_directory {
    my ($self, $dir) = @_;
    
    if (!-d $dir) {
        $self->app->log_message('info', "Creating directory: $dir");
        eval {
            make_path($dir);
        };
        if ($@) {
            $self->app->log_message('error', "Failed to create directory: $dir: $@");
            $self->ui->show_error_dialog("Directory Error", 
                "Could not create directory:\n$dir\n\nPlease check permissions or choose another location.");
            return 0;
        }
    }
    
    # Check if directory is writable
    if (!-w $dir) {
        $self->app->log_message('error', "Directory is not writable: $dir");
        $self->ui->show_error_dialog("Permission Error", 
            "Cannot write to directory:\n$dir\n\nPlease check permissions or choose another location.");
        return 0;
    }
    
    return 1;
}

# Helper to generate filenames with timestamps
sub generate_filename {
    my ($self, $format) = @_;
    
    my $timestamp = strftime("%Y-%m-%d-%H%M%S", localtime);
    return "Screenshot-$timestamp.$format";
}

# Helper to check if a command is available
sub is_command_available {
    my ($self, $command) = @_;
    
    my $result = system("which $command >/dev/null 2>&1") == 0;
    $self->app->log_message('debug', "Command '$command' " . ($result ? "is" : "is not") . " available");
    return $result;
}

# Helper to prepare for capture
sub prepare_for_capture {
    my ($self) = @_;
    
    # Hide the window completely by moving it off-screen first
    $self->ui->{main_window}->move(-9000, -9000);  # Move far off-screen
    $self->ui->{main_window}->hide();
    $self->ui->{main_window}->set_opacity(0.0);    # Make fully transparent
    
    # Process events to ensure changes take effect
    Gtk3::main_iteration() while Gtk3::events_pending();
    sleep(0.3); # Give time for window to hide
}

# Helper to restore UI after capture
sub restore_after_capture {
    my ($self) = @_;
    
    my $timeout_id = Glib::Timeout->add(500, sub {
        $self->ui->restore_main_window();
        $self->{active_capture} = 0; # Mark capture as complete
        return FALSE; # Run once
    });
    
    # Add to timeout tracking
    push @{$self->{timeouts}}, $timeout_id;
}

# Get/set selection state with improved error checking
sub selection_start_x {
    my ($self, $value) = @_;
    if (defined $value) {
        $self->{selection_start_x} = $value;
    }
    return $self->{selection_start_x};
}

sub selection_start_y {
    my ($self, $value) = @_;
    if (defined $value) {
        $self->{selection_start_y} = $value;
    }
    return $self->{selection_start_y};
}

sub selection_width {
    my ($self, $value) = @_;
    if (defined $value) {
        $self->{selection_width} = $value;
    }
    return $self->{selection_width};
}

sub selection_height {
    my ($self, $value) = @_;
    if (defined $value) {
        $self->{selection_height} = $value;
    }
    return $self->{selection_height};
}

# Get references
sub app {
    my ($self) = @_;
    return $self->{app};
}

sub config {
    my ($self) = @_;
    return $self->app->{config};
}

sub ui {
    my ($self) = @_;
    return $self->app->{ui};
}

# Start the capture process
sub start_capture {
    my ($self) = @_;
    
    # Prevent multiple captures from running simultaneously
    if ($self->{active_capture}) {
        $self->app->log_message('warning', "Capture already in progress, ignoring request");
        return;
    }
    
    # Set active_capture flag
    $self->{active_capture} = 1;
    
    # Reset state
    $self->{preview_pixbuf} = undef;
    
    # Only clear selection if we're not remembering the last one
    if (!$self->config->remember_last_selection) {
        $self->selection_width(0);
        $self->selection_height(0);
    }
    
    # For region selection mode in X11, we handle capturing differently
    if ($self->config->selection_mode == 1 && $self->app->{window_system} !~ /^wayland/) {
        # Region mode in X11
        # Start region selection immediately without timer
        $self->{in_region_selection} = 1;
        $self->app->log_message('info', "Starting region selection in X11 mode");
        $self->{region_selector}->interactive_region_selection();
        return;  # Exit here, as region_selector will handle the capture
    }
    
    # We're not in region selection mode, or we're in Wayland
    $self->{in_region_selection} = 0;
    
    # For window and fullscreen modes, or Wayland region mode
    if ($self->config->timer_value > 0) {
        # Start countdown timer
        $self->start_silent_timer($self->config->timer_value, sub {
            $self->perform_capture();
        });
    } else {
        # Add delay before capture to let the UI hide properly
        if (!$self->config->allow_self_capture) {
            my $timeout_id = Glib::Timeout->add(
                $self->config->hide_delay,
                sub {
                    $self->perform_capture();
                    return FALSE; # Run once
                }
            );
            push @{$self->{timeouts}}, $timeout_id;
        } else {
            # Capture immediately if we're allowing self-capture
            $self->perform_capture();
        }
    }
}

# Helper for silent timer
sub start_silent_timer {
    my ($self, $seconds, $callback) = @_;
    
    $self->app->log_message('info', "Starting $seconds-second timer (silent)");
    
    my $timeout_id = Glib::Timeout->add(
        $seconds * 1000,  # Convert seconds to milliseconds
        sub {
            $callback->();
            return FALSE; # Run once
        }
    );
    
    # Track the timeout
    push @{$self->{timeouts}}, $timeout_id;
}


# Main capture function
sub perform_capture {
    my ($self) = @_;
    
    # Processing all pending events to ensure UI is fully updated
    Gtk3::main_iteration() while Gtk3::events_pending();
    
    # An extra small delay to ensure everything is ready
    sleep(0.3);
    
    # For Wayland environments
    if ($self->app->{window_system} =~ /^wayland/) {
        # For region mode in Wayland, don't use our own selector
        if ($self->config->selection_mode == 1) {
            # Use Wayland's built-in region capture directly
            $self->capture_wayland();
            return;
        } else {
            # For window and fullscreen modes
            $self->capture_wayland();
        }
    } else {
        # For X11/Xorg environments
        $self->capture_xorg();
    }
    
    # Ensure the active_capture flag is reset when capture completes
    $self->{active_capture} = 0;
}


sub capture_xorg {
    my ($self) = @_;
    
    $self->app->log_message('info', "Using X11 capture method");
    
    if ($self->config->selection_mode == 0) {  # Window mode
        $self->capture_window_xorg();
    } elsif ($self->config->selection_mode == 1) {  # Region mode
        $self->{region_selector}->interactive_region_selection();
    } elsif ($self->config->selection_mode == 2) {  # Fullscreen mode
        $self->capture_fullscreen_xorg();
    }
}


sub capture_wayland {
    my ($self) = @_;
    
    $self->app->log_message('info', "Using Wayland capture method");
    
    # Check for all available tools and use the most appropriate one
    my @tools = (
        {
            name => 'gnome-screenshot', 
            check => sub { $self->is_command_available('gnome-screenshot') },
            capture => sub { 
                my ($mode, $filepath) = @_; 
                return $self->capture_wayland_gnome_screenshot($mode, $filepath); 
            }
        },
        {
            name => 'grim + slurp', 
            check => sub { $self->is_command_available('grim') && $self->is_command_available('slurp') },
            capture => sub { 
                my ($mode, $filepath) = @_; 
                return $self->capture_wayland_grim_slurp($mode, $filepath); 
            }
        },
        {
            name => 'ksnip',
            check => sub { $self->is_command_available('ksnip') },
            capture => sub {
                my ($mode, $filepath) = @_;
                return $self->capture_wayland_ksnip($mode, $filepath);
            }
        }
    );
    
    # Find the first available tool
    my $tool = undef;
    foreach my $t (@tools) {
        if ($t->{check}->()) {
            $tool = $t;
            $self->app->log_message('info', "Using " . $tool->{name} . " for Wayland capture");
            last;
        }
    }
    
    if (!$tool) {
        $self->app->log_message('error', "No suitable screenshot tool found for Wayland");
        $self->ui->show_error_dialog("Missing Dependency", 
            "A screenshot tool is required for captures in Wayland environment.\n\n" .
            "Please install one of the following:\n" .
            " - gnome-screenshot\n" .
            " - grim + slurp\n" .
            " - ksnip");
        $self->restore_after_capture();
        return;
    }
    
    # Create filename
    my $format = $self->config->image_format;
    my $filename = $self->generate_filename($format);
    my $filepath = File::Spec->catfile($self->config->save_location, $filename);
    
    # Ensure save directory exists
    if ($self->config->save_location ne "clipboard" && 
        !$self->ensure_directory($self->config->save_location)) {
        $self->restore_after_capture();
        return;
    }
    
    # Hide main window before capture
    $self->prepare_for_capture();
    
    # Capture using the selected tool
    my $success = $tool->{capture}->($self->config->selection_mode, $filepath);
    
    if ($success) {
        # Process results
        $self->process_captured_file($filepath);
    } else {
        $self->app->log_message('error', "Capture failed with " . $tool->{name});
        $self->ui->show_error_dialog("Capture Failed", 
            "The screenshot capture failed. Please try again or use a different capture method.");
    }
    
    # Restore UI
    $self->restore_after_capture();
}

# Capture using gnome-screenshot
sub capture_wayland_gnome_screenshot {
    my ($self, $mode, $filepath) = @_;
    
    # Add cursor capture option if enabled
    my $cursor_option = $self->config->show_mouse_pointer ? "--include-pointer" : "";
    
    # Capture based on mode
    my $cmd;
    if ($mode == 0) {  # Window mode
        # Add decoration option if requested
        my $decoration = $self->config->capture_window_decoration ? "--include-border" : "";
        $cmd = "gnome-screenshot --window $decoration $cursor_option --file=\"$filepath\"";
    } elsif ($mode == 1) {  # Region mode
        # For Wayland, we'll use gnome-screenshot's area selection
        $cmd = "gnome-screenshot --area $cursor_option --file=\"$filepath\"";
    } elsif ($mode == 2) {  # Fullscreen mode
        $cmd = "gnome-screenshot $cursor_option --file=\"$filepath\"";
    }
    
    # Execute capture command
    $self->app->log_message('info', "Executing: $cmd");
    my $exit_status = system($cmd);
    
    return $exit_status == 0;
}

# Capture using grim + slurp
sub capture_wayland_grim_slurp {
    my ($self, $mode, $filepath) = @_;
    
    my $cmd;
    if ($mode == 0) {  # Window mode
        # grim + slurp doesn't have native window capture, fall back to region
        $self->app->log_message('info', "Window capture not supported with grim+slurp, falling back to region");
        $cmd = "slurp | grim -g - \"$filepath\"";
    } elsif ($mode == 1) {  # Region mode
        $cmd = "slurp | grim -g - \"$filepath\"";
    } elsif ($mode == 2) {  # Fullscreen mode
        $cmd = "grim \"$filepath\"";
    }
    
    # Execute capture command
    $self->app->log_message('info', "Executing: $cmd");
    my $exit_status = system($cmd);
    
    return $exit_status == 0;
}

# Capture using ksnip
sub capture_wayland_ksnip {
    my ($self, $mode, $filepath) = @_;
    
    my $capture_mode;
    if ($mode == 0) {  # Window mode
        $capture_mode = "active";
    } elsif ($mode == 1) {  # Region mode
        $capture_mode = "rect";
    } elsif ($mode == 2) {  # Fullscreen mode
        $capture_mode = "full";
    }
    
    my $cmd = "ksnip -c $capture_mode -s \"$filepath\"";
    
    # Execute capture command
    $self->app->log_message('info', "Executing: $cmd");
    my $exit_status = system($cmd);
    
    return $exit_status == 0;
}


sub process_captured_file {
    my ($self, $filepath) = @_;
    
    if (-f $filepath && -s $filepath > 0) {
        $self->app->log_message('info', "Screenshot captured successfully: $filepath");
        
        # Special handling for clipboard destination
        if ($self->config->save_location eq "clipboard") {
            my $pixbuf = eval { Gtk3::Gdk::Pixbuf->new_from_file($filepath); };
            if ($pixbuf) {
                my $clipboard = Gtk3::Clipboard::get(Gtk3::Gdk::Atom::intern('CLIPBOARD', FALSE));
                $clipboard->set_image($pixbuf);
                $self->app->log_message('info', "Screenshot copied to clipboard");
                $self->ui->show_notification("Success", "Screenshot copied to clipboard");
                unlink($filepath); # Remove file since we only wanted clipboard
            } else {
                $self->app->log_message('error', "Failed to load screenshot for clipboard: $@");
                $self->ui->show_error_dialog("Clipboard Error", 
                    "Failed to copy screenshot to clipboard: $@");
            }
        } else {
            $self->ui->show_notification("Success", "Screenshot saved to: $filepath");
            
            # Show floating thumbnail if enabled
            if ($self->config->show_floating_thumbnail) {
                my $pixbuf = eval { Gtk3::Gdk::Pixbuf->new_from_file($filepath); };
                if ($pixbuf) {
                    $self->ui->show_floating_thumbnail($pixbuf, $filepath);
                    
                    # Generate thumbnail for the system cache
                    $self->generate_thumbnail($pixbuf, $filepath);
                } else {
                    $self->app->log_message('warning', "Could not load screenshot for thumbnail: $@");
                }
            }
        }
    } else {
        $self->app->log_message('warning', "Screenshot capture failed or was canceled");
        $self->ui->show_notification("Information", "Screenshot was not taken. The operation may have been cancelled.");
    }
}

sub capture_window_xorg {
    my ($self) = @_;
    
    $self->prepare_for_capture();
    
    # Check if xdotool is available
    if (!$self->is_command_available('xdotool')) {
        $self->app->log_message('error', "xdotool not found. Please install it: sudo apt install xdotool");
        $self->ui->show_error_dialog("Error: xdotool not found", 
            "The xdotool utility is required for window selection in X11 environment.\n\n" .
            "Please install it using:\nsudo apt install xdotool\n\n" .
            "Falling back to region selection.");
        
        # Fall back to region selection
        $self->{region_selector}->interactive_region_selection();
        return;
    }
    
    # Get active window ID
    my ($exit_code, $window_id) = $self->app->{utils}->run_command('xdotool', 'getactivewindow');
    
    if ($exit_code != 0 || !$window_id) {
        $self->app->log_message('warning', "Could not identify active window, falling back to fullscreen");
        $self->ui->show_notification("Could not identify active window", "Falling back to fullscreen capture");
        
        # Fallback to fullscreen
        $self->capture_fullscreen_xorg();
        return;
    }
    
    # Remove any whitespace from window_id
    chomp($window_id);
    $window_id =~ s/\s+//g;
    
    $self->capture_specific_window_xorg($window_id);
    
    $self->restore_after_capture();
}


sub capture_fullscreen_xorg {
    my ($self) = @_;
    
    my $screen = Gtk3::Gdk::Screen::get_default();
    my $root_window = $screen->get_root_window();
    my $root_width = $screen->get_width();
    my $root_height = $screen->get_height();
    
    # Make sure main window is thoroughly hidden
    $self->prepare_for_capture();
    
    # Process all pending events
    Gtk3::main_iteration() while Gtk3::events_pending();
    
    # Add a small delay to ensure window is completely hidden
    sleep(0.2);
    
    # Process events again
    Gtk3::main_iteration() while Gtk3::events_pending();
    
    # Verify we have valid dimensions to capture
    if ($root_width <= 0 || $root_height <= 0) {
        $self->app->log_message('error', "Invalid screen dimensions: ${root_width}x${root_height}");
        $self->ui->show_error_dialog("Capture Error", "Could not determine screen dimensions for fullscreen capture");
        $self->restore_after_capture();
        return;
    }
    
    # Capture the screen
    my $screenshot = eval {
        Gtk3::Gdk::pixbuf_get_from_window($root_window, 0, 0, $root_width, $root_height);
    };
    
    if (!$screenshot || $@) {
        $self->app->log_message('error', "Failed to capture fullscreen: $@");
        $self->ui->show_error_dialog("Capture Error", "Failed to capture fullscreen. Please try again or use a different method.");
        $self->restore_after_capture();
        return;
    }
    
    # Add cursor if cursor capture is enabled
    if ($self->config->show_mouse_pointer) {
        $self->app->log_message('debug', "Adding cursor to fullscreen capture");
        $self->add_cursor($screenshot, 0, 0);
    }
    
    # Save the screenshot
    $self->save_screenshot($screenshot);
    
    # Restore the main window
    $self->ui->restore_main_window();
}


sub capture_specific_window_xorg {
    my ($self, $window_id) = @_;
    
    if (!$window_id) {
        $self->app->log_message('warning', "No window ID provided");
        $self->ui->show_error_dialog("Error", "Failed to identify window to capture");
        $self->ui->restore_main_window();
        return;
    }
    
    # Simple status message
    $self->app->log_message('info', "Capturing window with ID: $window_id");
    
    eval {
        # Check if xwininfo is available
        if (!$self->is_command_available('xwininfo')) {
            die "xwininfo command not found. Please install x11-utils package.";
        }
        
        # Get window geometry
        my ($exit_code, $output) = $self->app->{utils}->run_command('xwininfo', "-id $window_id");
        
        # Check if command failed
        if ($exit_code != 0) {
            die "xwininfo command failed with status $exit_code";
        }
        
        # Extract the window geometry
        my ($x, $y, $width, $height);
        
        if ($self->config->capture_window_decoration) {
            # For capturing with decoration, we want the outer window coordinates
            ($x) = $output =~ /Absolute upper-left X:\s+(\d+)/;
            ($y) = $output =~ /Absolute upper-left Y:\s+(\d+)/;
            ($width) = $output =~ /Width:\s+(\d+)/;
            ($height) = $output =~ /Height:\s+(\d+)/;
            
            # Use xprop to get frame extents if needed
            if ($self->is_command_available('xprop')) {
                my ($xprop_exit, $xprop_output) = 
                    $self->app->{utils}->run_command('xprop', "-id $window_id _NET_FRAME_EXTENTS");
                
                # Check if command failed
                if ($xprop_exit != 0) {
                    $self->app->log_message('warning', "xprop command failed, continuing without frame adjustments");
                }
                else {
                    # Try to parse frame extents if available
                    if ($xprop_output =~ /_NET_FRAME_EXTENTS.*?(\d+),\s*(\d+),\s*(\d+),\s*(\d+)/) {
                        my ($left, $right, $top, $bottom) = ($1, $2, $3, $4);
                        
                        # Adjust coordinates to include window frame
                        $x -= $left;
                        $y -= $top;
                        $width += $left + $right;
                        $height += $top + $bottom;
                    }
                }
            }
        } else {
            # For capturing without decoration, extract client area coordinates
            # First get the window position
            ($x) = $output =~ /Absolute upper-left X:\s+(\d+)/;
            ($y) = $output =~ /Absolute upper-left Y:\s+(\d+)/;
            
            # Then adjust for client area offset
            my ($client_x) = $output =~ /Relative upper-left X:\s+(\d+)/;
            my ($client_y) = $output =~ /Relative upper-left Y:\s+(\d+)/;
            
            if (defined $client_x && defined $client_y) {
                $x += $client_x;
                $y += $client_y;
            }
            
            # Extract client area dimensions
            my ($client_width) = $output =~ /Width:\s+(\d+)/;
            my ($client_height) = $output =~ /Height:\s+(\d+)/;
            
            $width = $client_width;
            $height = $client_height;
        }
        
        # Check if we got valid dimensions
        if (!defined $x || !defined $y || !defined $width || !defined $height) {
            die "Could not get window geometry";
        }
        
        # Ensure valid coordinates (bounds check)
        my $screen = Gtk3::Gdk::Screen::get_default();
        my $screen_width = $screen->get_width();
        my $screen_height = $screen->get_height();
        
        # Constrain to screen bounds
        ($x, $y, $width, $height) = $self->constrain_to_screen($x, $y, $width, $height, $screen_width, $screen_height);
        
        # Capture window
        my $screenshot = undef;
        my $root_window = Gtk3::Gdk::get_default_root_window();
        
        # Capture window without cursor first
        $screenshot = eval {
            Gtk3::Gdk::pixbuf_get_from_window($root_window, $x, $y, $width, $height);
        };
        
        if (!$screenshot) {
            die "Failed to capture window";
        }
        
        # Add cursor to screenshot if enabled
        if ($self->config->show_mouse_pointer) {
            $self->app->log_message('debug', "Adding cursor to window capture");
            $self->add_cursor($screenshot, $x, $y);
        }
        
        $self->save_screenshot($screenshot);
    };
    
    if ($@) {
        my $error_msg = $@;
        if ($error_msg =~ /Could not get window geometry/) {
            $self->app->log_message('error', "Could not determine window size. Please try another capture method.");
            $self->ui->show_error_dialog("Window Capture Error", 
                "Could not determine window size. Please try another capture method.");
        } elsif ($error_msg =~ /Failed to capture window/) {
            $self->app->log_message('error', "Failed to capture window. Please try again or use region capture.");
            $self->ui->show_error_dialog("Window Capture Error", 
                "Failed to capture window. Please try again or use region capture.");
        } elsif ($error_msg =~ /command not found/) {
            $self->app->log_message('error', "X11 command not found: $error_msg");
            $self->ui->show_error_dialog("Missing Dependency", 
                "A required X11 command was not found. Please install required packages:\n" .
                "sudo apt install x11-utils");
        } elsif ($error_msg =~ /command failed/) {
            $self->app->log_message('error', "X11 command failed: $error_msg");
            $self->ui->show_error_dialog("Command Error", 
                "A required X11 command failed. Please ensure xwininfo and xprop are installed:\n" .
                "sudo apt install x11-utils");
        } else {
            $self->app->log_message('error', "Error capturing window: $error_msg");
            $self->ui->show_error_dialog("Capture Error", 
                "An error occurred while capturing the window. Please try again or use region capture.");
        }
    }
}
    
# Helper to constrain coordinates to screen
sub constrain_to_screen {
    my ($self, $x, $y, $width, $height, $screen_width, $screen_height) = @_;
    
    if ($x < 0) {
        $width += $x;  # Reduce width
        $x = 0;
    }
    if ($y < 0) {
        $height += $y;  # Reduce height
        $y = 0;
    }
    if ($x + $width > $screen_width) {
        $width = $screen_width - $x;
    }
    if ($y + $height > $screen_height) {
        $height = $screen_height - $y;
    }
    
    # Ensure minimum dimensions
    $width = 1 if $width < 1;
    $height = 1 if $height < 1;
    
    return ($x, $y, $width, $height);
}


sub add_cursor {
    my ($self, $screenshot, $region_x, $region_y) = @_;
    
    # Safety check for parameters
    if (!defined $screenshot) {
        $self->app->log_message('error', "Screenshot is undefined in add_cursor");
        return 0;
    }
    
    if (!defined $region_x || !defined $region_y) {
        $self->app->log_message('warning', "Region coordinates are undefined in add_cursor");
        $region_x = 0 if !defined $region_x;
        $region_y = 0 if !defined $region_y;
    }
    
    $self->app->log_message('info', "Adding cursor to screenshot (region at $region_x, $region_y)");
    
    # Use CursorUtils to add cursor to the screenshot
    return $self->app->{cursor_utils}->add_cursor_to_screenshot($screenshot, $region_x, $region_y);
}


sub save_screenshot {
    my ($self, $pixbuf) = @_;
    
    if (!defined $pixbuf) {
        $self->app->log_message('error', "Undefined pixbuf in save_screenshot()");
        $self->ui->show_error_dialog("Screenshot Error", "Failed to capture screenshot. Please try again.");
        return;
    }
    
    if ($self->config->save_location eq 'clipboard') {
        # Save to clipboard
        eval {
            my $clipboard = Gtk3::Clipboard::get(Gtk3::Gdk::Atom::intern('CLIPBOARD', FALSE));
            $clipboard->set_image($pixbuf);
            $self->app->log_message('info', "Screenshot copied to clipboard");
            $self->ui->show_notification("Success", "Screenshot copied to clipboard");
        };
        if ($@) {
            $self->app->log_message('error', "Failed to copy to clipboard: $@");
            $self->ui->show_error_dialog("Clipboard Error", 
                "Could not copy screenshot to clipboard. Please check system permissions.");
        }
    } else {
        # Save to file in the selected location
        my $timestamp = strftime("%Y-%m-%d-%H%M%S", localtime);
        
        # Map image format to format string
        my $format_string;
        if ($self->config->image_format eq "jpg") {
            $format_string = "jpeg";
        } elsif ($self->config->image_format eq "webp") {
            $format_string = "webp";
        } elsif ($self->config->image_format eq "avif" && $self->config->avif_supported()) {
            $format_string = "avif";
        } else {
            $format_string = $self->config->image_format; # png or others
        }
        
        my $file_extension = $self->config->image_format;  # Keep extension as-is
        
        my $filename = "Screenshot-$timestamp.$file_extension";
        my $filepath = File::Spec->catfile($self->config->save_location, $filename);
        
        # Ensure directory exists
        if (!$self->ensure_directory($self->config->save_location)) {
            return;
        }
        
        $self->app->log_message('info', "Saving screenshot to: $filepath");
        
        # Save the file
        eval {
            if ($format_string eq "jpeg") {
                $pixbuf->savev($filepath, $format_string, ['quality'], ['100']);
            } elsif ($format_string eq "webp") {
                # WebP can have quality setting as well
                $pixbuf->savev($filepath, $format_string, ['quality'], ['100']);
            } elsif ($format_string eq "avif") {
                # AVIF also supports quality setting
                $pixbuf->savev($filepath, $format_string, ['quality'], ['90']);
            } else {
                $pixbuf->savev($filepath, $format_string, [], []);
            }
            $self->app->log_message('info', "Screenshot saved successfully");
            $self->ui->show_notification("Success", "Screenshot saved to: $filepath");
            
            # Generate thumbnail for the system cache
            $self->generate_thumbnail($pixbuf, $filepath);
            
            # Show floating thumbnail if enabled
            if ($self->config->show_floating_thumbnail) {
                $self->ui->show_floating_thumbnail($pixbuf, $filepath);
            }
        };
        
        if ($@) {
            $self->app->log_message('error', "Error saving screenshot: $@");
            
            # We can try with png if other formats failed for some reason
            if ($format_string ne "png") {
                $self->ui->show_notification("Warning", 
                    "Failed to save as $file_extension, trying PNG format instead...");
                    
                eval {
                    my $png_path = $filepath;
                    $png_path =~ s/\.\w+$/.png/;
                    $self->app->log_message('info', "Attempting to save as PNG instead: $png_path");
                    $pixbuf->save($png_path, "png");
                    $self->app->log_message('info', "Screenshot saved as PNG successfully");
                    $self->ui->show_notification("Success", "Screenshot saved as PNG to: $png_path");
                    
                    # Generate thumbnail for the PNG version
                    $self->generate_thumbnail($pixbuf, $png_path);
                    
                    if ($self->config->show_floating_thumbnail) {
                        $self->ui->show_floating_thumbnail($pixbuf, $png_path);
                    }
                };
                if ($@) {
                    $self->app->log_message('error', "Critical error: Could not save screenshot: $@");
                    $self->ui->show_error_dialog("Save Error", 
                        "Failed to save the screenshot. Please check disk space and permissions.");
                }
            } else {
                $self->app->log_message('error', "Critical error: Could not save screenshot: $@");
                $self->ui->show_error_dialog("Save Error", 
                    "Failed to save the screenshot. Please check disk space and permissions.");
            }
        }
    }
}


sub generate_thumbnail {
    my ($self, $pixbuf, $filepath) = @_;
    
    # Early validation to avoid unnecessary processing
    return unless defined $pixbuf && defined $filepath && -f $filepath;
    
    # Use a try/catch block to handle errors
    eval {
        # Get absolute path and convert to URI
        my $abs_path = File::Spec->rel2abs($filepath);
        my $file_uri = URI::file->new($abs_path)->as_string;
        
        # Generate MD5 hash of the URI
        my $md5_hash = md5_hex($file_uri);
        
        # Create thumbnail directory if needed (with error checking)
        my $thumbnail_dir = "$ENV{HOME}/.cache/thumbnails/normal";
        if (!-d $thumbnail_dir && !$self->ensure_directory($thumbnail_dir)) {
            $self->app->log_message('warning', "Failed to create thumbnail directory: $thumbnail_dir");
            return;
        }
        
        # Path for the thumbnail
        my $thumbnail_path = "$thumbnail_dir/$md5_hash.png";
        
        # Get file modification time
        my $mtime = (stat($filepath))[9] || time();
        
        # Calculate scaled dimensions more efficiently
        my $width = $pixbuf->get_width();
        my $height = $pixbuf->get_height();
        
        return if $width <= 0 || $height <= 0;
        
        my $scale_factor = ($width > $height) ? 128.0 / $width : 128.0 / $height;
        
        my $thumb_width = int($width * $scale_factor) || 1;
        my $thumb_height = int($height * $scale_factor) || 1;
        
        # Create scaled thumbnail in one step
        my $thumb_pixbuf = $pixbuf->scale_simple($thumb_width, $thumb_height, 'bilinear');
        
        if (!$thumb_pixbuf) {
            $self->app->log_message('warning', "Failed to create scaled thumbnail");
            return;
        }
        
        # Set metadata in a single operation if possible
        $thumb_pixbuf->set_option('tEXt::Thumb::URI', $file_uri);
        $thumb_pixbuf->set_option('tEXt::Thumb::MTime', $mtime);
        $thumb_pixbuf->set_option('tEXt::Software', $self->app->app_name() . ' ' . $self->app->app_version());
        
        # Save the thumbnail
        $thumb_pixbuf->save($thumbnail_path, 'png');
        
        $self->app->log_message('info', "Generated thumbnail for system cache: $thumbnail_path");
    };
    
    if ($@) {
        $self->app->log_message('warning', "Failed to generate thumbnail: $@");
    }
}

sub cancel_timeouts {
    my ($self) = @_;
    
    if ($self->{timeouts}) {
        foreach my $timeout_id (@{$self->{timeouts}}) {
            if (defined $timeout_id && $timeout_id > 0) {
                # Check if the source ID is still valid before removing it
                if (Glib::Source->get_current_source($timeout_id)) {
                    eval {
                        Glib::Source->remove($timeout_id);
                    };
                    if ($@) {
                        $self->app->log_message('debug', "Error removing timeout source ID $timeout_id: $@");
                    }
                }
            }
        }
        $self->{timeouts} = [];
    }
}

# Cleanup resources
sub cleanup {
    my ($self) = @_;
    
    $self->cancel_timeouts();
    
    # Clean up region selector if it exists
    if ($self->{region_selector}) {
        $self->{region_selector}->destroy_overlay();
    }
    
    # Reset preview pixbuf
    $self->{preview_pixbuf} = undef;
    
    # Reset state
    $self->{active_capture} = 0;
    $self->{in_region_selection} = 0;
}

1;