package ScreenshotTool::KeyboardShortcuts;

use strict;
use warnings;
use Moo;
use Gtk3 qw(-init);
use Glib qw(TRUE FALSE);
use namespace::clean;
use File::Path qw(make_path);

# Required application reference
has 'app' => (
    is       => 'ro',
    required => 1,
);

# State tracking
has 'enabled' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'accel_group' => (
    is      => 'rw',
    default => sub { undef },
);

has 'registered_shortcuts' => (
    is      => 'rw',
    default => sub { [] },
);

has 'key_press_handler_id' => (
    is      => 'rw',
    default => sub { undef },
);

# Helper methods to get references to other components
sub ui {
    my ($self) = @_;
    return $self->app->ui;
}

sub capture_manager {
    my ($self) = @_;
    return $self->app->capture_manager;
}


# Initialize the class and connect it to the main window
sub initialize {
    my ($self) = @_;
    
    # Skip if already initialized
    return if $self->enabled;
    
    # Set enabled flag
    $self->enabled(1);
    
    # Create acceleration group for shortcuts if it doesn't exist
    if (!$self->accel_group) {
        $self->accel_group(Gtk3::AccelGroup->new());
    }
    
    # Connect to main window if it exists
    if ($self->app->ui && $self->app->ui->{main_window}) {
        # Add the accel group to the window - only if not already attached
        $self->app->ui->{main_window}->add_accel_group($self->accel_group);
        
        # Register only the three shortcuts we care about
        $self->register_standard_shortcuts();
        
        $self->app->log_message('info', "Keyboard shortcuts initialized");
    } else {
        $self->app->log_message('warning', "Cannot initialize keyboard shortcuts - main window not available");
    }
}

# Register standard shortcuts
sub register_standard_shortcuts {
    my ($self) = @_;
    
    # Only register the three main shortcuts you want
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
}

# Register a keyboard shortcut
sub register_shortcut {
    my ($self, $key, $modifiers, $callback) = @_;
    
    if (!$self->accel_group) {
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
        $id = $self->accel_group->connect(
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
    push @{$self->registered_shortcuts}, $id if $id;
    
    $self->app->log_message('debug', "Registered keyboard shortcut for '$key'");
    return 1;
}

sub trigger_capture {
    my ($self, $mode) = @_;
    
    # Validate mode
    if (!defined $mode || $mode < 0 || $mode > 2) {
        $self->app->log_message('error', "Invalid capture mode: " . (defined $mode ? $mode : "undefined"));
        return;
    }
    
    # Set the selection mode
    $self->app->config->selection_mode($mode);
    $self->app->log_message('debug', "Setting capture mode to $mode");
    
    # Hide the main window with extra care
    eval {
        $self->ui->hide_main_window_completely();
    };
    if ($@) {
        $self->app->log_message('warning', "Error hiding main window: $@");
        # Continue anyway as the capture might still work
    }
    
    # Process events to ensure UI is hidden
    while (Gtk3::events_pending()) {
        Gtk3::main_iteration();
    }
    
    # Add a small delay before capture to ensure UI is properly hidden
    my $delay = 300; # 300ms delay
    $self->app->log_message('debug', "Adding $delay ms delay before capture");
    
    # Start the capture after a short delay
    eval {
        Glib::Timeout->add($delay, sub {
            eval {
                $self->app->log_message('debug', "Initiating capture with mode $mode");
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
    if ($self->key_press_handler_id && $self->ui->{main_window}) {
        eval {
            $self->ui->{main_window}->signal_handler_disconnect($self->key_press_handler_id);
        };
        $self->key_press_handler_id(undef);
    }
    
    # Remove accel group from window
    if ($self->accel_group && $self->ui->{main_window}) {
        eval {
            $self->ui->{main_window}->remove_accel_group($self->accel_group);
        };
    }
    
    $self->registered_shortcuts([]);
    $self->accel_group(undef);
    $self->enabled(0);
    
    $self->app->log_message('debug', "Keyboard shortcuts cleaned up");
}

1;
