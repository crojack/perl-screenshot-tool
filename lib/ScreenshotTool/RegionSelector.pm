package ScreenshotTool::RegionSelector;

use strict;
use warnings;
use Gtk3 qw(-init);
use Glib qw(TRUE FALSE);
use Cairo;

# Constructor
sub new {
    my ($class, %args) = @_;
    
    my $app = $args{app} || die "App reference is required";
    my $capture_manager = $args{capture_manager} || die "Capture manager reference is required";
    
    my $self = bless {
        app => $app,
        capture_manager => $capture_manager,
        
        # UI elements
        overlay_window => undef,
        fixed => undef,
        capture_button => undef,
        escape_button => undef,
        
        # Selection state
        preview_pixbuf => undef,
        is_dragging => 0,
        drag_handle => 0, # 0 = none, 1-8 = corner/edge handles, 9 = whole selection
        drag_start_x => 0,
        drag_start_y => 0,
        orig_sel_x => 0,
        orig_sel_y => 0,
        orig_sel_width => 0,
        orig_sel_height => 0,
        
        # Timeout tracking
        timeouts => [],
        
        # Status tracking
        selection_active => 0,
    }, $class;
    
    return $self;
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

sub capture_manager {
    my ($self) = @_;
    return $self->{capture_manager};
}

# Destroy overlay window if exists
sub destroy_overlay {
    my ($self) = @_;
    
    # Cancel any timeouts
    $self->cancel_timeouts();
    
    if (defined $self->{overlay_window}) {
        $self->{overlay_window}->destroy();
        $self->{overlay_window} = undef;
    }
    
    # Reset state
    $self->{selection_active} = 0;
    
    # Free preview pixbuf to reduce memory usage
    $self->{preview_pixbuf} = undef;
}


sub cancel_timeouts {
    my ($self) = @_;
    
    if ($self->{timeouts}) {
        foreach my $timeout_id (@{$self->{timeouts}}) {
            if (defined $timeout_id && $timeout_id > 0) {
                # Remove directly without checking if it exists
                eval {
                    Glib::Source->remove($timeout_id);
                };
                if ($@) {
                    $self->app->log_message('debug', "Error removing timeout source ID $timeout_id: $@");
                }
            }
        }
        $self->{timeouts} = [];
    }
}

# Initialize region selection
sub select_region {
    my ($self) = @_;
    $self->interactive_region_selection();
}

# Interactive region selection mode
sub interactive_region_selection {
    my ($self) = @_;
    
    # Prevent multiple selection windows
    if ($self->{selection_active}) {
        $self->app->log_message('warning', "Region selection already active, ignoring request");
        return;
    }
    
    $self->{selection_active} = 1;
    $self->app->log_message('info', "Starting interactive region selection...");
    
    # Create the overlay window
    $self->{overlay_window} = Gtk3::Window->new('popup');
    $self->{overlay_window}->set_app_paintable(TRUE);
    $self->{overlay_window}->set_decorated(FALSE);
    $self->{overlay_window}->set_skip_taskbar_hint(TRUE);
    $self->{overlay_window}->set_skip_pager_hint(TRUE);
    $self->{overlay_window}->set_keep_above(TRUE);

    # Explicit settings for keyboard focus
    $self->{overlay_window}->set_can_focus(TRUE);
    $self->{overlay_window}->set_accept_focus(TRUE);
    $self->{overlay_window}->set_focus_on_map(TRUE);
    
    # Get screen dimensions
    my $screen = Gtk3::Gdk::Screen::get_default();
    my $root_window = $screen->get_root_window();
    my $root_width = $screen->get_width();
    my $root_height = $screen->get_height();
    
    # Make overlay cover the entire screen
    $self->{overlay_window}->set_default_size($root_width, $root_height);
    $self->{overlay_window}->move(0, 0);
    
    # Take a screenshot of the entire screen to use as background
    eval {
        $self->{preview_pixbuf} = Gtk3::Gdk::pixbuf_get_from_window(
            $root_window, 0, 0, $root_width, $root_height
        );
    };
    
    if (!$self->{preview_pixbuf} || $@) {
        $self->app->log_message('error', "Failed to capture screen for region selection: $@");
        $self->ui->show_error_dialog("Region Selection Error", 
            "Failed to create screen preview for region selection. Please try again.");
        $self->destroy_overlay();
        $self->ui->restore_main_window();
        return;
    }
    
    # Set default selection if nothing exists yet or remember_last_selection is disabled
    if ($self->capture_manager->selection_width == 0 || 
        $self->capture_manager->selection_height == 0 || 
        !$self->config->remember_last_selection) {
        # Center a default selection in the screen
        $self->capture_manager->selection_start_x(($root_width - $self->config->default_width) / 2);
        $self->capture_manager->selection_start_y(($root_height - $self->config->default_height) / 2);
        $self->capture_manager->selection_width($self->config->default_width);
        $self->capture_manager->selection_height($self->config->default_height);
    }
    
    # Create a proper container hierarchy
    $self->{fixed} = Gtk3::Fixed->new();
    $self->{overlay_window}->add($self->{fixed});
    
    # Create selection drawing area (this will cover the entire window)
    my $overlay_area = Gtk3::DrawingArea->new();
    $self->{fixed}->put($overlay_area, 0, 0);
    $overlay_area->set_size_request($root_width, $root_height);
    
    # Create styled buttons with icons
    $self->{capture_button} = $self->ui->create_icon_button('capture', "Capture");
    $self->{fixed}->put($self->{capture_button}, 10, 10); # Initial position, will be updated in draw
    
    $self->{escape_button} = $self->ui->create_icon_button('close', "Cancel");
    $self->{fixed}->put($self->{escape_button}, 60, 10); # Initial position, will be updated in draw
    
    # Initially hide buttons until selection is made
    $self->{capture_button}->hide();
    $self->{escape_button}->hide();

    # Add all necessary events for proper interaction
    $self->{overlay_window}->add_events([
        'pointer-motion-mask',
        'button-press-mask',
        'button-release-mask',
        'key-press-mask',
        'key-release-mask',
        'focus-change-mask'
    ]);
    
    $overlay_area->signal_connect('draw' => sub { $self->draw_selection_overlay(@_); });
    
    # Set up event handlers
    $self->{overlay_window}->signal_connect('button-press-event' => sub {
        my ($widget, $event) = @_;
        
        if (!$self->{is_dragging}) {
            # Check if we're clicking on a handle of an existing selection
            $self->{drag_handle} = $self->check_handle($event->x, $event->y);
            
            if ($self->{drag_handle}) {
                # Start resizing the selection
                $self->{drag_start_x} = $event->x;
                $self->{drag_start_y} = $event->y;
                $self->{orig_sel_x} = $self->capture_manager->selection_start_x;
                $self->{orig_sel_y} = $self->capture_manager->selection_start_y;
                $self->{orig_sel_width} = $self->capture_manager->selection_width;
                $self->{orig_sel_height} = $self->capture_manager->selection_height;
            } else {
                # Start a new selection
                $self->capture_manager->selection_start_x($event->x);
                $self->capture_manager->selection_start_y($event->y);
                $self->capture_manager->selection_width(0);
                $self->capture_manager->selection_height(0);
            }
            
            $self->{is_dragging} = 1;
            
            # Explicitly hide buttons when dragging starts
            $self->{capture_button}->hide();
            $self->{escape_button}->hide();
            
            $overlay_area->queue_draw();
        }
        
        return TRUE;
    });
    
    # In button-release-event handler, make sure is_dragging is reset:
    $self->{overlay_window}->signal_connect('button-release-event' => sub {
        my ($widget, $event) = @_;
        
        if ($self->{is_dragging}) {
            $self->{is_dragging} = 0;
            $self->{drag_handle} = 0;
            
            # Make sure we have a valid selection
            $self->normalize_selection();
            $overlay_area->queue_draw();
            
            # Delay showing buttons slightly to ensure proper positioning
            my $timeout_id = Glib::Timeout->add(50, sub {
                if (!$self->{is_dragging}) {
                    $overlay_area->queue_draw(); # Force redraw which will show buttons
                }
                return FALSE; # Don't repeat
            });
            push @{$self->{timeouts}}, $timeout_id;
        }
        
        return TRUE;
    });
    
    $self->{overlay_window}->signal_connect('motion-notify-event' => sub {
        my ($widget, $event) = @_;
        
        if ($self->{is_dragging}) {
            if ($self->{drag_handle}) {
                # Resize selection based on which handle is being dragged
                $self->resize_selection($self->{drag_handle}, $event->x, $event->y);
            } else {
                # Update selection dimensions
                $self->capture_manager->selection_width($event->x - $self->capture_manager->selection_start_x);
                $self->capture_manager->selection_height($event->y - $self->capture_manager->selection_start_y);
            }
            
            $overlay_area->queue_draw();
        } else {
            # Always update cursor with current mouse position
            $self->update_cursor($event->x, $event->y);
        }
        
        return TRUE;
    });
    
    # Key press handler for Enter, Escape, Space
    $self->{overlay_window}->signal_connect('key-press-event' => sub {
        my ($widget, $event) = @_;
        
        # Debug output with key name and key value
        my $keyval = $event->keyval;
        my $key_name = Gtk3::Gdk::keyval_name($keyval) || "unknown";
        $self->app->log_message('debug', "Key press detected: $keyval ($key_name)");
        
        # Handle Enter and Return keys
        if ($keyval == 65293 || $keyval == 65421) {  # Direct keycode values for Return and KP_Enter
            $self->app->log_message('debug', "Enter key pressed!");
            
            # Only proceed if we have a valid selection
            if ($self->capture_manager->selection_width != 0 && 
                $self->capture_manager->selection_height != 0) {
                $self->app->log_message('debug', "Valid selection found, capturing region...");
                $self->capture_selected_region();
                return TRUE;
            }
        }
        
        # Handle Escape key
        if ($keyval == 65307) {  # Direct keycode for Escape
            $self->app->log_message('debug', "Escape pressed, closing overlay");
            $self->destroy_overlay();
            $self->ui->restore_main_window();
            return TRUE;
        }
        
        # Handle Space for capture
        if ($keyval == 32) {  # Direct keycode for Space
            $self->app->log_message('debug', "Space pressed, capturing region");
            if ($self->capture_manager->selection_width != 0 && 
                $self->capture_manager->selection_height != 0) {
                $self->capture_selected_region();
                return TRUE;
            }
        }
        
        return FALSE;
    });

    $self->{overlay_window}->signal_connect('destroy' => sub {
        $self->{selection_active} = 0;
        $self->capture_manager->{active_capture} = 0;
        $self->app->log_message('debug', "Region selection overlay destroyed, reset flags");
    });
    

    # Connect button handlers
    $self->{capture_button}->signal_connect('clicked' => sub {
        $self->app->log_message('debug', "Capture button clicked");
        $self->capture_selected_region();
    });
    
    $self->{escape_button}->signal_connect('clicked' => sub {
        $self->app->log_message('debug', "Escape button clicked");
        $self->destroy_overlay();
        $self->ui->restore_main_window();
    });

    # Safety timeout - auto-close the selection window after 5 minutes
    my $safety_timeout_id = Glib::Timeout->add(300000, sub {  # 5 minutes
        if ($self->{selection_active} && defined $self->{overlay_window}) {
            $self->app->log_message('warning', "Safety timeout triggered - closing overlay");
            $self->destroy_overlay();
            $self->ui->restore_main_window();
        }
        return FALSE; # Don't repeat
    });
    push @{$self->{timeouts}}, $safety_timeout_id;
    
    # Ensure focus and visibility
    $self->{overlay_window}->show_all();
    $self->{overlay_window}->set_can_focus(TRUE);
    $self->{overlay_window}->present();  # Raises window and gives it focus
    $self->{overlay_window}->grab_focus();
    
    # Grab keyboard focus
    eval {
        Gtk3::Gdk::keyboard_grab($self->{overlay_window}->get_window(), TRUE, Gtk3::get_current_event_time());
    };
    if ($@) {
        $self->app->log_message('warning', "Could not grab keyboard focus: $@");
    }
    
    # Force update of UI
    while (Gtk3::events_pending()) {
        Gtk3::main_iteration();
    }
}

# Get the normalized selection coordinates
sub normalize_selection_coords {
    my ($self) = @_;
    
    my $x = $self->capture_manager->selection_start_x;
    my $y = $self->capture_manager->selection_start_y;
    my $w = $self->capture_manager->selection_width;
    my $h = $self->capture_manager->selection_height;
    
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

# Make sure selection has positive width and height
sub normalize_selection {
    my ($self) = @_;
    
    if ($self->capture_manager->selection_width < 0) {
        $self->capture_manager->selection_start_x(
            $self->capture_manager->selection_start_x + $self->capture_manager->selection_width
        );
        $self->capture_manager->selection_width(abs($self->capture_manager->selection_width));
    }
    
    if ($self->capture_manager->selection_height < 0) {
        $self->capture_manager->selection_start_y(
            $self->capture_manager->selection_start_y + $self->capture_manager->selection_height
        );
        $self->capture_manager->selection_height(abs($self->capture_manager->selection_height));
    }
}

# Improved region selection capture with better error handling
sub capture_selected_region {
    my ($self) = @_;
    
    # Ensure we have valid selection
    $self->normalize_selection();
    my ($x, $y, $w, $h) = $self->normalize_selection_coords();
    
    # Ensure minimal dimensions
    if ($w < 5 || $h < 5) {
        $self->app->log_message('warning', "Selection too small, aborting capture");
        $self->ui->show_error_dialog("Selection Error", 
            "The selected region is too small. Please make a larger selection.");
        return;
    }
    
    # Make sure coordinates stay within the bounds of the screen
    my $screen = Gtk3::Gdk::Screen::get_default();
    my $screen_width = $screen->get_width();
    my $screen_height = $screen->get_height();
    
    # Constrain coordinates to screen size
    if ($x < 0) {
        $w += $x;  # Reduce width
        $x = 0;
    }
    if ($y < 0) {
        $h += $y;  # Reduce height
        $y = 0;
    }
    if ($x + $w > $screen_width) {
        $w = $screen_width - $x;
    }
    if ($y + $h > $screen_height) {
        $h = $screen_height - $y;
    }
    
    # Ensure we still have a valid selection after constraints
    if ($w <= 0 || $h <= 0) {
        $self->app->log_message('warning', "Invalid selection size after constraints, aborting capture");
        $self->ui->show_error_dialog("Selection Error", 
            "The selection coordinates are invalid. Please try again.");
        return;
    }
    
    # Check if timer is enabled
    if ($self->app->{config}->timer_value > 0) {
        # Use silent timer
        $self->app->log_message('info', "Starting " . $self->app->{config}->timer_value . "-second timer for region capture (silent)");
        
        # Hide the overlay window during countdown
        if ($self->{overlay_window}) {
            $self->{overlay_window}->hide();
            
            # Process events to ensure overlay is hidden
            while (Gtk3::events_pending()) {
                Gtk3::main_iteration();
            }
        }
        
        # Use a silent timer
        my $timeout_id = Glib::Timeout->add(
            $self->app->{config}->timer_value * 1000,  # Convert seconds to milliseconds
            sub {
                $self->perform_region_capture($x, $y, $w, $h);
                return FALSE; # Run once
            }
        );
        push @{$self->{timeouts}}, $timeout_id;
    } else {
        # No timer, capture immediately
        $self->perform_region_capture($x, $y, $w, $h);
    }
}

# In ScreenshotTool::RegionSelector

sub perform_region_capture {
    my ($self, $x, $y, $w, $h) = @_;
    
    # Validate parameters
    if (!defined $x || !defined $y || !defined $w || !defined $h ||
        $w <= 0 || $h <= 0) {
        $self->app->log_message('error', "Invalid region parameters: x=$x, y=$y, w=$w, h=$h");
        $self->ui->show_error_dialog("Capture Error", "Invalid region parameters. Please try again.");
        
        # Close the selection window if it exists
        $self->destroy_overlay();
        
        # Show the main window again
        $self->ui->restore_main_window();
        return;
    }
    
    # Make sure we have a valid preview pixbuf
    if (!$self->{preview_pixbuf}) {
        $self->app->log_message('error', "No preview pixbuf available for region capture");
        $self->ui->show_error_dialog("Capture Error", 
            "Failed to prepare screenshot data. Please try again.");
            
        # Close the selection window
        $self->destroy_overlay();
        
        # Show the main window again
        $self->ui->restore_main_window();
        return;
    }
    
    # Debug logging to identify bounds issues
    $self->app->log_message('debug', "Copying area: x=$x, y=$y, w=$w, h=$h from pixbuf with dimensions: " . 
                             $self->{preview_pixbuf}->get_width() . "x" . 
                             $self->{preview_pixbuf}->get_height());
    
    # Verify that the region is within the bounds of the preview pixbuf
    my $px_width = $self->{preview_pixbuf}->get_width();
    my $px_height = $self->{preview_pixbuf}->get_height();
    
    if ($x < 0 || $y < 0 || $x + $w > $px_width || $y + $h > $px_height) {
        $self->app->log_message('error', "Region out of bounds: ($x,$y,$w,$h) exceeds ($px_width,$px_height)");
        
        # Adjust region to fit within the pixbuf
        if ($x < 0) {
            $w += $x; # reduce width
            $x = 0;
        }
        if ($y < 0) {
            $h += $y; # reduce height
            $y = 0;
        }
        if ($x + $w > $px_width) {
            $w = $px_width - $x;
        }
        if ($y + $h > $px_height) {
            $h = $px_height - $y;
        }
        
        # Check if we still have a valid region
        if ($w <= 0 || $h <= 0) {
            $self->app->log_message('error', "No valid region after adjustment");
            $self->ui->show_error_dialog("Capture Error", 
                "The selected region is outside the screen bounds. Please try again.");
                
            # Close the selection window
            $self->destroy_overlay();
            
            # Show the main window again
            $self->ui->restore_main_window();
            return;
        }
        
        $self->app->log_message('info', "Adjusted region to: x=$x, y=$y, w=$w, h=$h");
    }
    
    # Capture the selection from the screenshot
    my $screenshot = eval {
        Gtk3::Gdk::Pixbuf->new(
            $self->{preview_pixbuf}->get_colorspace(),
            $self->{preview_pixbuf}->get_has_alpha(),
            $self->{preview_pixbuf}->get_bits_per_sample(),
            $w, $h
        );
    };
    
    if (!$screenshot || $@) {
        $self->app->log_message('error', "Failed to create pixbuf for region: $@");
        $self->ui->show_error_dialog("Capture Error", 
            "Failed to create image for selected region. Please try again.");
            
        # Close the selection window
        $self->destroy_overlay();
        
        # Show the main window again
        $self->ui->restore_main_window();
        return;
    }
    
    # Safely copy the area
    eval {
        $self->{preview_pixbuf}->copy_area($x, $y, $w, $h, $screenshot, 0, 0);
    };
    
    if ($@) {
        $self->app->log_message('error', "Error copying area: $@");
        $self->ui->show_error_dialog("Capture Error", 
            "Failed to capture the selected region. Please try again.");
            
        # Close the selection window
        $self->destroy_overlay();
        
        # Show the main window again
        $self->ui->restore_main_window();
        return;
    }
    
    # If cursor is visible and within the region, add it to the screenshot
    if ($self->config->show_mouse_pointer) {
        $self->app->log_message('debug', "Adding cursor to region capture");
        $self->capture_manager->add_cursor($screenshot, $x, $y);
    }
    
    # Close the selection window
    $self->destroy_overlay();
    
    # Save the screenshot
    $self->capture_manager->save_screenshot($screenshot);
    
    # Reset the active_capture flag in capture_manager
    $self->capture_manager->{active_capture} = 0;
    
    # Show the main window again
    $self->ui->restore_main_window();
}

sub draw_selection_overlay {
    my ($self, $widget, $cr) = @_;
    
    my $width = $widget->get_allocated_width();
    my $height = $widget->get_allocated_height();
    
    # Draw screen preview as background
    if ($self->{preview_pixbuf}) {
        Gtk3::Gdk::cairo_set_source_pixbuf($cr, $self->{preview_pixbuf}, 0, 0);
        $cr->paint();
    }
    
    # Draw semi-transparent overlay
    $cr->set_source_rgba(0, 0, 0, 0.4);
    $cr->rectangle(0, 0, $width, $height);
    $cr->fill();
    
    # If we have a selection, clear the selected area and draw its border
    if ($self->capture_manager->selection_width != 0 && $self->capture_manager->selection_height != 0) {
        my ($x, $y, $w, $h) = $self->normalize_selection_coords();
        
        # Clear the selected area
        $cr->set_operator('clear');
        $cr->rectangle($x, $y, $w, $h);
        $cr->fill();
        $cr->set_operator('over');
        
        # Draw the image in the selected area
        if ($self->{preview_pixbuf}) {
            Gtk3::Gdk::cairo_set_source_pixbuf($cr, $self->{preview_pixbuf}, 0, 0);
            $cr->rectangle($x, $y, $w, $h);
            $cr->fill();
        }
        
        # Draw white border
        $cr->set_source_rgb(1, 1, 1);
        $cr->set_line_width($self->config->border_width);
        $cr->rectangle($x, $y, $w, $h);
        $cr->stroke();
        
        # Draw corner handles
        $self->draw_handles($cr, $x, $y, $w, $h);
        
        # Draw dimensions text
        $cr->set_source_rgba(1, 1, 1, 1.0);
        $cr->select_font_face("Sans", "normal", "normal");
        $cr->set_font_size(14);

        my $text = int($w) . " x " . int($h);
        my $extents = $cr->text_extents($text);
        my $text_x = $x + ($w - $extents->{width}) / 2;
        my $text_y = $y + $h + 20;

        # Ensure text is visible
        if ($text_y > $height - 5) {
            $text_y = $y - 10;
        }

        # Draw text background
        $cr->set_source_rgba(0, 0, 0, 0.7);
        $cr->rectangle(
            $text_x - 5,
            $text_y - $extents->{height},
            $extents->{width} + 10,
            $extents->{height} + 5
        );
        $cr->fill();

        # Draw text
        $cr->set_source_rgb(1, 1, 1);
        $cr->move_to($text_x, $text_y);
        $cr->show_text($text);

        # Update button positions
        if (!$self->{is_dragging}) {
            my $button_y = $y + $h + 10;
            
            # Ensure buttons remain visible
            if ($button_y > $height - 50) {
                $button_y = $y - 50;
                if ($button_y < 10) {
                    $button_y = 10;
                }
            }
            
            # Get actual button sizes
            my $capture_width = $self->{capture_button}->get_allocated_width();
            my $escape_width = $self->{escape_button}->get_allocated_width();
            
            # Use default sizes if not yet allocated
            $capture_width = 40 if !$capture_width || $capture_width < 10;
            $escape_width = 40 if !$escape_width || $escape_width < 10;
            
            # Calculate positions with spacing
            my $spacing = 10; # Increased spacing between buttons
            my $escape_button_x = $x + $w - $escape_width;
            my $capture_button_x = $escape_button_x - $capture_width - $spacing;
            
            # Ensure buttons don't go off-screen to the left
            if ($capture_button_x < 10) {
                $capture_button_x = 10;
                $escape_button_x = $capture_button_x + $capture_width + $spacing;
            }
            
            # Move buttons
            $self->{fixed}->move($self->{capture_button}, $capture_button_x, $button_y);
            $self->{fixed}->move($self->{escape_button}, $escape_button_x, $button_y);
            
            $self->{capture_button}->show();
            $self->{escape_button}->show();
        } else {
            # Explicitly hide buttons during dragging
            $self->{capture_button}->hide();
            $self->{escape_button}->hide();
        }
    } else {
        # Draw instruction text
        $cr->set_source_rgb(1, 1, 1);
        $cr->select_font_face("Sans", "normal", "bold");
        $cr->set_font_size(24);
        
        my $text = "Drag to select a region to capture";
        my $extents = $cr->text_extents($text);
        $cr->move_to(
            ($width - $extents->{width}) / 2,
            ($height - $extents->{height}) / 2
        );
        $cr->show_text($text);
        
        # Hide buttons when no selection
        if (defined $self->{capture_button} && defined $self->{escape_button}) {
            $self->{capture_button}->hide();
            $self->{escape_button}->hide();
        }
    }
    
    return FALSE;
}

# Draw handles for resizing the selection
sub draw_handles {
    my ($self, $cr, $x, $y, $w, $h) = @_;
    
    my $half_handle = $self->config->handle_size / 2;
    
    # Draw the 8 handles
    # Corners
    $self->draw_handle($cr, $x - $half_handle, $y - $half_handle);               # Top-left (1)
    $self->draw_handle($cr, $x + $w - $half_handle, $y - $half_handle);          # Top-right (2)
    $self->draw_handle($cr, $x + $w - $half_handle, $y + $h - $half_handle);     # Bottom-right (3)
    $self->draw_handle($cr, $x - $half_handle, $y + $h - $half_handle);          # Bottom-left (4)
    
    # Edges
    $self->draw_handle($cr, $x + $w/2 - $half_handle, $y - $half_handle);        # Top (5)
    $self->draw_handle($cr, $x + $w - $half_handle, $y + $h/2 - $half_handle);   # Right (6)
    $self->draw_handle($cr, $x + $w/2 - $half_handle, $y + $h - $half_handle);   # Bottom (7)
    $self->draw_handle($cr, $x - $half_handle, $y + $h/2 - $half_handle);        # Left (8)
}

# Draw a single handle
sub draw_handle {
    my ($self, $cr, $x, $y) = @_;
    
    $cr->set_source_rgb(1, 1, 1);
    $cr->rectangle($x, $y, $self->config->handle_size, $self->config->handle_size);
    $cr->fill();
    
    # Draw border
    $cr->set_source_rgb(0, 0, 0);
    $cr->set_line_width(1);
    $cr->rectangle($x, $y, $self->config->handle_size, $self->config->handle_size);
    $cr->stroke();
}

# Check if point is in handle
sub is_in_handle {
    my ($self, $x, $y, $handle_x, $handle_y) = @_;
    
    return $x >= $handle_x && 
           $x <= $handle_x + $self->config->handle_size && 
           $y >= $handle_y && 
           $y <= $handle_y + $self->config->handle_size;
}

# Check if mouse is over a handle
sub check_handle {
    my ($self, $mouse_x, $mouse_y) = @_;
    
    # If no selection, no handles to check
    if ($self->capture_manager->selection_width == 0 || 
        $self->capture_manager->selection_height == 0) {
        return 0;
    }
    
    my ($x, $y, $w, $h) = $self->normalize_selection_coords();
    my $half_handle = $self->config->handle_size / 2;
    
    # Check each handle
    # Top-left (1)
    if ($self->is_in_handle($mouse_x, $mouse_y, $x - $half_handle, $y - $half_handle)) {
        return 1;
    }
    # Top-right (2)
    if ($self->is_in_handle($mouse_x, $mouse_y, $x + $w - $half_handle, $y - $half_handle)) {
        return 2;
    }
    # Bottom-right (3)
    if ($self->is_in_handle($mouse_x, $mouse_y, $x + $w - $half_handle, $y + $h - $half_handle)) {
        return 3;
    }
    # Bottom-left (4)
    if ($self->is_in_handle($mouse_x, $mouse_y, $x - $half_handle, $y + $h - $half_handle)) {
        return 4;
    }
    # Top (5)
    if ($self->is_in_handle($mouse_x, $mouse_y, $x + $w/2 - $half_handle, $y - $half_handle)) {
        return 5;
    }
    # Right (6)
    if ($self->is_in_handle($mouse_x, $mouse_y, $x + $w - $half_handle, $y + $h/2 - $half_handle)) {
        return 6;
    }
    # Bottom (7)
    if ($self->is_in_handle($mouse_x, $mouse_y, $x + $w/2 - $half_handle, $y + $h - $half_handle)) {
        return 7;
    }
    # Left (8)
    if ($self->is_in_handle($mouse_x, $mouse_y, $x - $half_handle, $y + $h/2 - $half_handle)) {
        return 8;
    }
    
    # Check if inside selection (for moving)
    if ($mouse_x >= $x && $mouse_x <= $x + $w && $mouse_y >= $y && $mouse_y <= $y + $h) {
        return 9; # 9 means inside selection
    }
    
    return 0;
}

# Update cursor based on mouse position 
sub update_cursor {
    my ($self, $mouse_x, $mouse_y) = @_;
    
    if (!$self->{overlay_window}) {
        return;
    }
    
    # First, determine where the mouse is relative to the selection
    my $handle = 0;
    my $is_inside_selection = 0;
    
    if ($self->capture_manager->selection_width != 0 && 
        $self->capture_manager->selection_height != 0) {
        my ($sel_x, $sel_y, $sel_w, $sel_h) = $self->normalize_selection_coords();
        
        # Check if mouse is inside the selection area
        $is_inside_selection = 
            $mouse_x >= $sel_x && 
            $mouse_x <= ($sel_x + $sel_w) && 
            $mouse_y >= $sel_y && 
            $mouse_y <= ($sel_y + $sel_h);
            
        # Only check handles if we have a selection
        $handle = $self->check_handle($mouse_x, $mouse_y);
    }
    
    # Determine which cursor to show
    my $cursor;
    
    if ($handle == 1 || $handle == 3) { # Top-left or Bottom-right
        $cursor = Gtk3::Gdk::Cursor->new('bottom-right-corner');
    } elsif ($handle == 2 || $handle == 4) { # Top-right or Bottom-left
        $cursor = Gtk3::Gdk::Cursor->new('bottom-left-corner');
    } elsif ($handle == 5 || $handle == 7) { # Top or Bottom
        $cursor = Gtk3::Gdk::Cursor->new('sb-v-double-arrow');
    } elsif ($handle == 6 || $handle == 8) { # Right or Left
        $cursor = Gtk3::Gdk::Cursor->new('sb-h-double-arrow');
    } elsif ($handle == 9) { # Inside selection
        $cursor = Gtk3::Gdk::Cursor->new('fleur');
    } elsif ($self->capture_manager->selection_width == 0 && 
             $self->capture_manager->selection_height == 0) {
        # No selection yet - use crosshair for drawing
        $cursor = Gtk3::Gdk::Cursor->new('crosshair');
    } else {
        # Default (outside selection) - use left-ptr instead of 'default'
        $cursor = Gtk3::Gdk::Cursor->new('left-ptr');
    }
    
    # Apply the cursor
    if ($cursor) {
        eval {
            $self->{overlay_window}->get_window()->set_cursor($cursor);
        };
        if ($@) {
            $self->app->log_message('warning', "Failed to set cursor: $@");
        }
    }
}

# Resize selection based on handle being dragged
sub resize_selection {
    my ($self, $handle, $x, $y) = @_;
    
    my $dx = $x - $self->{drag_start_x};
    my $dy = $y - $self->{drag_start_y};
    
    if ($handle == 1) { # Top-left
        $self->capture_manager->selection_start_x($self->{orig_sel_x} + $dx);
        $self->capture_manager->selection_start_y($self->{orig_sel_y} + $dy);
        $self->capture_manager->selection_width($self->{orig_sel_width} - $dx);
        $self->capture_manager->selection_height($self->{orig_sel_height} - $dy);
    } elsif ($handle == 2) { # Top-right
        $self->capture_manager->selection_start_y($self->{orig_sel_y} + $dy);
        $self->capture_manager->selection_width($self->{orig_sel_width} + $dx);
        $self->capture_manager->selection_height($self->{orig_sel_height} - $dy);
    } elsif ($handle == 3) { # Bottom-right
        $self->capture_manager->selection_width($self->{orig_sel_width} + $dx);
        $self->capture_manager->selection_height($self->{orig_sel_height} + $dy);
    } elsif ($handle == 4) { # Bottom-left
        $self->capture_manager->selection_start_x($self->{orig_sel_x} + $dx);
        $self->capture_manager->selection_width($self->{orig_sel_width} - $dx);
        $self->capture_manager->selection_height($self->{orig_sel_height} + $dy);
    } elsif ($handle == 5) { # Top
        $self->capture_manager->selection_start_y($self->{orig_sel_y} + $dy);
        $self->capture_manager->selection_height($self->{orig_sel_height} - $dy);
    } elsif ($handle == 6) { # Right
        $self->capture_manager->selection_width($self->{orig_sel_width} + $dx);
    } elsif ($handle == 7) { # Bottom
        $self->capture_manager->selection_height($self->{orig_sel_height} + $dy);
    } elsif ($handle == 8) { # Left
        $self->capture_manager->selection_start_x($self->{orig_sel_x} + $dx);
        $self->capture_manager->selection_width($self->{orig_sel_width} - $dx);
    } elsif ($handle == 9) { # Move entire selection
        $self->capture_manager->selection_start_x($self->{orig_sel_x} + $dx);
        $self->capture_manager->selection_start_y($self->{orig_sel_y} + $dy);
    }
}

1;