package ScreenshotTool::KeyboardShortcuts;

use strict;
use warnings;
use Gtk3 qw(-init);
use Glib qw(TRUE FALSE);

# Constructor
sub new {
    my ($class, %args) = @_;
    
    my $app = $args{app} || die "App reference is required";
    
    my $self = bless {
        app => $app,
        enabled => 0,
        accel_group => undef,
        registered_shortcuts => [],
        key_press_handler_id => undef,
    }, $class;
    
    return $self;
}

# Get app reference
sub app {
    my ($self) = @_;
    return $self->{app};
}

# Get UI reference
sub ui {
    my ($self) = @_;
    return $self->app->{ui};
}

# Get capture manager reference
sub capture_manager {
    my ($self) = @_;
    return $self->app->{capture_manager};
}

# Improved initialize method with error handling
sub initialize {
    my ($self) = @_;
    
    $self->app->log_message('info', "Initializing keyboard shortcuts");
    
    # Add key press event handler to the main window
    my $window = $self->ui->{main_window};
    if (!$window) {
        $self->app->log_message('warning', "Cannot set up key bindings: Main window not initialized");
        return 0;  # Return failure status
    }
    
    # Create accel group
    $self->{accel_group} = Gtk3::AccelGroup->new();
    if (!$self->{accel_group}) {
        $self->app->log_message('error', "Failed to create acceleration group for keyboard shortcuts");
        return 0;
    }
    
    $window->add_accel_group($self->{accel_group});
    
    # Set up keyboard shortcuts using direct key bindings
    eval {
        $self->{key_press_handler_id} = $window->signal_connect('key-press-event' => sub {
            my ($widget, $event) = @_;
            return $self->handle_key_press($widget, $event);
        });
    };
    
    if ($@) {
        $self->app->log_message('error', "Failed to set up key-press-event handler: $@");
        # Continue anyway, as other shortcuts might still work
    }
    
    # Register standard keyboard shortcuts
    $self->register_standard_shortcuts();
    
    $self->app->log_message('info', "Keyboard shortcuts initialized successfully");
    $self->{enabled} = 1;
    return 1;  # Return success status
}

# Handle key press events
sub handle_key_press {
    my ($self, $widget, $event) = @_;
    
    # Get keyval and state
    my $keyval = $event->keyval;
    my $state = $event->state;
    
    # Check for PrintScreen key (may have different key codes)
    my $is_print_key = ($keyval == Gtk3::Gdk::keyval_from_name('Print') ||
                      $keyval == Gtk3::Gdk::keyval_from_name('3270_PrintScreen') ||
                      $keyval == Gtk3::Gdk::keyval_from_name('SunPrint_Screen'));
    
    if ($is_print_key) {
        # Check modifiers
        my $shift_mask = $state & 'shift-mask';
        my $alt_mask = $state & 'mod1-mask';
        
        if ($shift_mask && !$alt_mask) {
            # Shift+Print - Region capture
            $self->app->log_message('info', "Shift+PrintScreen pressed - Capturing region");
            $self->trigger_capture(1); # Region
            return TRUE;
        } elsif ($alt_mask && !$shift_mask) {
            # Alt+Print - Window capture
            $self->app->log_message('info', "Alt+PrintScreen pressed - Capturing window");
            $self->trigger_capture(0); # Window
            return TRUE;
        } elsif (!$shift_mask && !$alt_mask) {
            # Print - Desktop capture
            $self->app->log_message('info', "PrintScreen pressed - Capturing desktop");
            $self->trigger_capture(2); # Desktop
            return TRUE;
        }
    }
    
    # Log key press for debugging
    my $key_name = Gtk3::Gdk::keyval_name($keyval) || "unknown";
    $self->app->log_message('debug', "Key pressed: $key_name ($keyval) with state: $state");
    
    return FALSE; # Let other handlers process the event
}

# Register standard shortcuts
sub register_standard_shortcuts {
    my ($self) = @_;
    
    # Register number shortcuts (1, 2, 3)
    $self->register_shortcut('1', ['control-mask'], sub {
        $self->app->log_message('info', "Ctrl+1 pressed - Capturing window");
        $self->trigger_capture(0); # Window
        return TRUE;
    });
    
    $self->register_shortcut('2', ['control-mask'], sub {
        $self->app->log_message('info', "Ctrl+2 pressed - Capturing region");
        $self->trigger_capture(1); # Region
        return TRUE;
    });
    
    $self->register_shortcut('3', ['control-mask'], sub {
        $self->app->log_message('info', "Ctrl+3 pressed - Capturing desktop");
        $self->trigger_capture(2); # Desktop
        return TRUE;
    });
    
    # Register mnemonic shortcuts (W, R, D)
    $self->register_shortcut('w', ['control-mask'], sub {
        $self->app->log_message('info', "Ctrl+W pressed - Capturing window");
        $self->trigger_capture(0); # Window
        return TRUE;
    });
    
    $self->register_shortcut('r', ['control-mask'], sub {
        $self->app->log_message('info', "Ctrl+R pressed - Capturing region");
        $self->trigger_capture(1); # Region
        return TRUE;
    });
    
    $self->register_shortcut('d', ['control-mask'], sub {
        $self->app->log_message('info', "Ctrl+D pressed - Capturing desktop");
        $self->trigger_capture(2); # Desktop
        return TRUE;
    });
    
    # Register Escape to cancel
    $self->register_shortcut('Escape', [], sub {
        $self->app->log_message('info', "Escape pressed - Canceling operation");
        # Close any active selector windows
        if ($self->app->{capture_manager} && 
            $self->app->{capture_manager}->{region_selector}) {
            $self->app->{capture_manager}->{region_selector}->destroy_overlay();
        }
        return TRUE;
    });
}

# NEW FUNCTION: Register a keyboard shortcut
sub register_shortcut {
    my ($self, $key, $modifiers, $callback) = @_;
    
    if (!$self->{accel_group}) {
        $self->app->log_message('warning', "Cannot register shortcut - accel_group missing");
        return 0;
    }
    
    my $keyval;
    if ($key =~ /^\d+$/) {
        # Numeric key value provided
        $keyval = $key;
    } else {
        # Key name provided
        $keyval = Gtk3::Gdk::keyval_from_name($key);
    }
    
    # Register the shortcut
    my $id;
    eval {
        $id = $self->{accel_group}->connect(
            $keyval,
            $modifiers,
            'visible',
            $callback
        );
    };
    
    if ($@) {
        $self->app->log_message('warning', "Failed to register shortcut for '$key': $@");
        return 0;
    }
    
    # Store the ID for later reference/removal
    push @{$self->{registered_shortcuts}}, $id if $id;
    
    $self->app->log_message('debug', "Registered keyboard shortcut for '$key'");
    return 1;
}

# Improved trigger_capture with error handling
sub trigger_capture {
    my ($self, $mode) = @_;
    
    # Validate mode
    if (!defined $mode || $mode < 0 || $mode > 2) {
        $self->app->log_message('error', "Invalid capture mode: " . (defined $mode ? $mode : "undefined"));
        return;
    }
    
    # Set the selection mode
    $self->app->{config}->selection_mode($mode);
    
    # Hide the main window
    eval {
        $self->ui->hide_main_window_completely();
    };
    if ($@) {
        $self->app->log_message('warning', "Error hiding main window: $@");
        # Continue anyway as the capture might still work
    }
    
    # Start the capture after a short delay
    eval {
        Glib::Timeout->add(200, sub {
            eval {
                $self->capture_manager->start_capture();
            };
            if ($@) {
                $self->app->log_message('error', "Error in capture process: $@");
                # Restore main window if capture fails
                $self->ui->restore_main_window();
            }
            return FALSE; # Run once
        });
    };
    if ($@) {
        $self->app->log_message('error', "Failed to set up capture timeout: $@");
        # Restore main window if we can't even start the timeout
        $self->ui->restore_main_window();
    }
}

# Clean up resources when shutting down
sub cleanup {
    my ($self) = @_;
    
    # Disconnect key press handler if it exists
    if ($self->{key_press_handler_id} && $self->ui->{main_window}) {
        eval {
            $self->ui->{main_window}->signal_handler_disconnect($self->{key_press_handler_id});
        };
        $self->{key_press_handler_id} = undef;
    }
    
    # Remove accel group from window
    if ($self->{accel_group} && $self->ui->{main_window}) {
        eval {
            $self->ui->{main_window}->remove_accel_group($self->{accel_group});
        };
    }
    
    $self->{registered_shortcuts} = [];
    $self->{accel_group} = undef;
    $self->{enabled} = 0;
    
    $self->app->log_message('debug', "Keyboard shortcuts cleaned up");
}

1;