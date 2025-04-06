package ScreenshotTool::UI;

use strict;
use warnings;
use Gtk3 qw(-init);
use Glib qw(TRUE FALSE);
use Cairo;

# Constructor
sub new {
    my ($class, %args) = @_;
    
    my $app = $args{app} || die "App reference is required";
    
    my $self = bless {
        app => $app,
        
        # UI elements
        main_window => undef,
        
        # Icon cache
        icon_cache => {},
        
        # Timeout tracking
        active_timeouts => [],
        
        # Floating window tracking
        floating_windows => [],
        
        # State tracking
        is_quitting => 0,
    }, $class;
    
    return $self;
}

# Get app reference
sub app {
    my ($self) = @_;
    return $self->{app};
}

# Get config reference
sub config {
    my ($self) = @_;
    return $self->app->{config};
}

# Get capture manager reference
sub capture_manager {
    my ($self) = @_;
    return $self->app->{capture_manager};
}

# Create and show the main application window
sub show_main_window {
    my ($self) = @_;
    
    # Initialize flag to track application quitting state
    $self->{is_quitting} = 0;
    
    # Create main window as a standard Gtk3::Window
    $self->{main_window} = Gtk3::Window->new('toplevel');
    $self->{main_window}->set_title($self->app->app_name);
    $self->{main_window}->set_resizable(FALSE);
    $self->{main_window}->set_position('center');
    $self->{main_window}->set_border_width(10);
    
    # Set the application for the window if not already set
    if ($self->app->{gtk_app} && !$self->{main_window}->get_application()) {
        $self->{main_window}->set_application($self->app->{gtk_app});
    }
    
    # Enhanced delete-event handler with detailed logging
    $self->{main_window}->signal_connect('delete-event' => sub {
        my ($widget, $event) = @_;
        $self->app->log_message('debug', "Delete event received on main window");
        
        # Set quitting flag immediately
        $self->{is_quitting} = 1;

        # Cancel any pending timeouts
        $self->cancel_all_timeouts();
        
        # Force immediate processing of any pending events
        Gtk3::main_iteration() while Gtk3::events_pending();
        
        # Exit the application immediately
        $self->app->log_message('debug', "Calling Gtk3->main_quit()");
        Gtk3->main_quit();
        
        # Return FALSE to allow the default handler to continue
        return FALSE;
    });
    
    # Make window draggable without titlebar, only for X11
    if ($self->app->{window_system} ne 'wayland' && $self->app->{window_system} ne 'wayland-limited') {
        $self->{main_window}->signal_connect('button-press-event' => sub {
            my ($widget, $event) = @_;
            if ($event->button == 1) {  # Left mouse button
                $self->{main_window}->begin_move_drag(
                    $event->button,
                    $event->x_root,
                    $event->y_root,
                    $event->time
                );
                return TRUE;
            }
            return FALSE;
        });
    }
    
    # Main buttons container
    my $main_box = Gtk3::Box->new('horizontal', 10);
    $self->{main_window}->add($main_box);
    
    # Create buttons
    my $window_button = $self->create_button('window', 'Window', sub { 
        $self->config->selection_mode(0);
        $self->hide_main_window_completely();
        
        # Store capture_manager reference to avoid scope issues in the closure
        my $capture_manager = $self->app->{capture_manager};
        
        my $timeout_id = Glib::Timeout->add(200, sub {
            $capture_manager->start_capture();
            return FALSE; # Run once
        });
        push @{$self->{active_timeouts}}, $timeout_id;
    });
    $main_box->pack_start($window_button, FALSE, FALSE, 0);
    
    # Region capture button
    my $region_button = $self->create_button('region', 'Region', sub { 
        $self->config->selection_mode(1);
        $self->hide_main_window_completely();
        
        # Store capture_manager reference to avoid scope issues in the closure
        my $capture_manager = $self->app->{capture_manager};
        
        my $timeout_id = Glib::Timeout->add(200, sub {
            $capture_manager->start_capture();
            return FALSE; # Run once
        });
        push @{$self->{active_timeouts}}, $timeout_id;
    });
    $main_box->pack_start($region_button, FALSE, FALSE, 0);
    
    # Fullscreen capture button
    my $fullscreen_button = $self->create_button('desktop', 'Desktop', sub { 
        $self->config->selection_mode(2);
        $self->hide_main_window_completely();
        
        # Store capture_manager reference to avoid scope issues in the closure
        my $capture_manager = $self->app->{capture_manager};
        
        my $timeout_id = Glib::Timeout->add(200, sub {
            $capture_manager->start_capture();
            return FALSE; # Run once
        });
        push @{$self->{active_timeouts}}, $timeout_id;
    });
    $main_box->pack_start($fullscreen_button, FALSE, FALSE, 0);
    
    # Options button and menu
    my $options_button = $self->create_button('settings', 'Options', undef);
    $options_button->signal_connect('clicked' => sub {
        $self->show_options_menu($options_button);
    });
    $main_box->pack_start($options_button, FALSE, FALSE, 0);
    
    $self->{main_window}->show_all();
}

# Create a styled button with icon and label
sub create_button {
    my ($self, $icon_name, $label_text, $callback) = @_;
    
    my $button = Gtk3::Button->new();
    $button->set_size_request(100, 100); # Set both width and height to 100px
    
    my $button_box = Gtk3::Box->new('vertical', 5);
    $button_box->set_homogeneous(FALSE);
    $button->add($button_box);
    
    # Use appropriate icon
    my $icon = $self->get_button_icon($icon_name);
    $button_box->pack_start($icon, TRUE, TRUE, 0);
    
    my $label = Gtk3::Label->new($label_text);
    $button_box->pack_start($label, FALSE, FALSE, 0);
    
    # Only connect the signal if a callback is provided
    if (defined $callback) {
        $button->signal_connect('clicked' => $callback);
    }
    
    return $button;
}

# NEW FUNCTION: Create menu item with consistent styling and behavior
sub create_menu_item {
    my ($self, $type, $label, $callback, $group) = @_;
    
    my $item;
    
    if ($type eq 'radio') {
        $item = Gtk3::RadioMenuItem->new_with_label($group || undef, $label);
    } elsif ($type eq 'check') {
        $item = Gtk3::CheckMenuItem->new_with_label($label);
    } elsif ($type eq 'separator') {
        return Gtk3::SeparatorMenuItem->new();
    } elsif ($type eq 'header') {
        $item = Gtk3::MenuItem->new_with_label($label);
        $item->set_sensitive(FALSE);
    } else {
        $item = Gtk3::MenuItem->new_with_label($label);
    }
    
    # Set active state if provided
    $item->set_active($callback->{active}) if ref($callback) eq 'HASH' && exists $callback->{active};
    
    # Connect signal if provided
    if (ref($callback) eq 'CODE') {
        $item->signal_connect('activate' => $callback);
    } elsif (ref($callback) eq 'HASH' && exists $callback->{callback}) {
        if ($type eq 'radio' || $type eq 'check') {
            $item->signal_connect('toggled' => $callback->{callback});
        } else {
            $item->signal_connect('activate' => $callback->{callback});
        }
    }
    
    return $item;
}

# Create a compact icon button for overlay
sub create_icon_button {
    my ($self, $icon_name, $tooltip) = @_;
    
    my $button = Gtk3::Button->new();
    # Force exact dimensions to ensure consistency
    $button->set_size_request(50, 50);
    $button->set_tooltip_text($tooltip);
    
    # Check for custom icon
    my $custom_icon_path = $self->config->custom_icons_dir . "/$icon_name.svg";
    my $icon;
    
    if (-f $custom_icon_path) {
        # Use custom icon
        $icon = Gtk3::Image->new_from_file($custom_icon_path);
    } else {
        # Try system icons with more reliable mapping
        my %icons = (
            'close' => 'window-close',
            'window' => 'window',
            'region' => 'select-rectangular',
            'desktop' => 'desktop',
            'settings' => 'preferences-system',
            'capture' => 'camera-photo',
        );
        
        # Try the mapped icon name
        if (exists $icons{$icon_name}) {
            $icon = Gtk3::Image->new_from_icon_name($icons{$icon_name}, 'button');
        } else {
            # Try directly with provided name
            $icon = Gtk3::Image->new_from_icon_name($icon_name, 'button');
        }
        
        # Last resort fallback
        if (!$icon) {
            $icon = Gtk3::Image->new_from_icon_name('image-missing', 'button');
        }
    }
    
    $icon->set_pixel_size(24); # Force icon to be 24x24 pixels
    $button->add($icon);
    
    return $button;
}

# Get button icon from custom directory or system theme
sub get_button_icon {
    my ($self, $icon_name) = @_;
    
    # Check cache first
    if (exists $self->{icon_cache}{$icon_name}) {
        return $self->{icon_cache}{$icon_name};
    }
    
    my $icon;
    
    # Check for custom icons with different extensions
    foreach my $ext ('svg', 'png') {
        my $custom_icon_path = $self->config->custom_icons_dir . "/$icon_name.$ext";
        if (-f $custom_icon_path) {
            $icon = Gtk3::Image->new_from_file($custom_icon_path);
            # Cache and return
            $self->{icon_cache}{$icon_name} = $icon;
            return $icon;
        }
    }
    
    # Fallback to system icons with more reliable mapping
    my %icons = (
        'close' => 'window-close',
        'window' => 'window',
        'region' => 'select-rectangular',
        'desktop' => 'desktop',
        'settings' => 'preferences-system',
        'capture' => 'camera-photo',
    );
    
    # Try the mapped icon name
    if (exists $icons{$icon_name}) {
        $icon = Gtk3::Image->new_from_icon_name($icons{$icon_name}, 'dialog');
    }
    
    # If that fails, try the original name
    if (!$icon) {
        $icon = Gtk3::Image->new_from_icon_name($icon_name, 'dialog');
    }
    
    # Last resort fallback
    if (!$icon) {
        $icon = Gtk3::Image->new_from_icon_name('image-missing', 'dialog');
    }
    
    # Set icon size
    $icon->set_pixel_size(48);
    
    # Cache and return
    $self->{icon_cache}{$icon_name} = $icon;
    return $icon;
}

# Hide main window completely before capture
sub hide_main_window_completely {
    my ($self) = @_;
    
    # If self-capture is enabled, don't hide
    if ($self->config->allow_self_capture) {
        return;  # Skip hiding if self-capture is enabled
    }
    
    # Hide the window by iconifying (minimizing) it
    $self->{main_window}->iconify();
    
    # Also call hide() for extra certainty
    $self->{main_window}->hide();
    
    # Set opacity to 0 for good measure
    $self->{main_window}->set_opacity(0.0);
    
    # Process events to ensure changes take effect
    Gtk3::main_iteration() while Gtk3::events_pending();
}

sub restore_main_window {
    my ($self) = @_;
    
    # Cancel immediately if we're in the process of quitting
    if ($self->{is_quitting}) {
        $self->app->log_message('debug', "Skipping window restore because application is quitting");
        return;
    }
    
    if (defined $self->{main_window}) {
        # Check if the window is being closed
        return if $self->{is_quitting};
        
        # Reset opacity
        $self->{main_window}->set_opacity(1.0);
        
        # On Wayland, we need a different approach for window positioning
        if ($self->app->{window_system} =~ /^wayland/) {
            # For Wayland, set window to be centered by using GtkWindow property
            $self->{main_window}->set_position('center');
            
            # Make sure the window is visible and has focus
            $self->{main_window}->deiconify();
            $self->{main_window}->show_all();
            $self->{main_window}->present();
            
            # Force process events to ensure window appears
            Gtk3::main_iteration() while Gtk3::events_pending();
            return;
        }
        
        # For X11, we can position the window precisely (existing code)
        # Get screen dimensions
        my $screen = Gtk3::Gdk::Screen::get_default();
        my $screen_width = $screen->get_width();
        my $screen_height = $screen->get_height();
        
        # Force request geometry to ensure window size is calculated
        $self->{main_window}->set_resizable(TRUE);
        $self->{main_window}->resize(1, 1);  # Force resize to trigger size calculation
        $self->{main_window}->set_resizable(FALSE);
        
        # Process events to ensure sizes are updated
        Gtk3::main_iteration() while Gtk3::events_pending();
        
        # Get window dimensions - use default values if not available yet
        my $window_width = $self->{main_window}->get_allocated_width();
        my $window_height = $self->{main_window}->get_allocated_height();
        
        # If window dimensions are not yet available, use reasonable defaults
        if (!$window_width || !$window_height || $window_width < 10 || $window_height < 10) {
            $window_width = 500;  # Approximate width of our main window
            $window_height = 120;  # Approximate height of our main window
        }
        
        # Calculate position for bottom center
        my $x_position = int(($screen_width - $window_width) / 2);
        my $y_position = $screen_height - $window_height - 50;  # 50px from bottom
        
        $self->app->log_message('debug', "Positioning main window at: $x_position, $y_position (screen: $screen_width x $screen_height, window: $window_width x $window_height)");
        
        # Move to bottom center - do this before showing the window
        $self->{main_window}->move($x_position, $y_position);
        
        # Ensure the window is not iconified (minimized)
        $self->{main_window}->deiconify();
        
        # Show the window
        $self->{main_window}->show_all();
        $self->{main_window}->present();
        
        # Force update to ensure window appears
        Gtk3::main_iteration() while Gtk3::events_pending();
        
        # Ensure the window is positioned correctly after showing
        $self->{main_window}->move($x_position, $y_position);
        
        # Process events again to ensure all changes are applied
        Gtk3::main_iteration() while Gtk3::events_pending();
    }
}

# Show options menu - refactored to use the new create_menu_item function
sub show_options_menu {
    my ($self, $button) = @_;
    
    # Create menu
    my $menu = Gtk3::Menu->new();
    
    # Save location section
    $menu->append($self->create_menu_item('header', "Save to"));
    
    # Create a radio button group for save locations
    my $desktop_dir = "$ENV{HOME}/Desktop";
    my $pictures_dir = "$ENV{HOME}/Pictures";
    
    # Desktop option
    my $desktop_item = $self->create_menu_item('radio', "Desktop", {
        active => $self->config->save_location eq $desktop_dir,
        callback => sub {
            my $widget = shift;
            $self->config->save_location($desktop_dir) if $widget->get_active();
        }
    });
    $menu->append($desktop_item);
    
    # Pictures option
    my $pictures_item = $self->create_menu_item('radio', "Pictures", {
        active => $self->config->save_location eq $pictures_dir,
        callback => sub {
            my $widget = shift;
            $self->config->save_location($pictures_dir) if $widget->get_active();
        }
    }, $desktop_item->get_group());
    $menu->append($pictures_item);
    
    # Clipboard option
    my $clipboard_item = $self->create_menu_item('radio', "Clipboard", {
        active => $self->config->save_location eq "clipboard",
        callback => sub {
            my $widget = shift;
            $self->config->save_location("clipboard") if $widget->get_active();
        }
    }, $desktop_item->get_group());
    $menu->append($clipboard_item);
    
    # Other location option
    my $other_item = $self->create_menu_item('normal', "Other Location...", sub {
        $self->select_other_location();
    });
    $menu->append($other_item);
    
    # Separator
    $menu->append($self->create_menu_item('separator', ""));
    
    # Timer section
    $menu->append($self->create_menu_item('header', "Timer"));
    
    # Create a radio button group for timer values
    my $none_item = $self->create_menu_item('radio', "None", {
        active => $self->config->timer_value == 0,
        callback => sub {
            my $widget = shift;
            $self->config->timer_value(0) if $widget->get_active();
        }
    });
    $menu->append($none_item);
    
    my $three_item = $self->create_menu_item('radio', "3 Seconds", {
        active => $self->config->timer_value == 3,
        callback => sub {
            my $widget = shift;
            $self->config->timer_value(3) if $widget->get_active();
        }
    }, $none_item->get_group());
    $menu->append($three_item);
    
    my $five_item = $self->create_menu_item('radio', "5 Seconds", {
        active => $self->config->timer_value == 5,
        callback => sub {
            my $widget = shift;
            $self->config->timer_value(5) if $widget->get_active();
        }
    }, $none_item->get_group());
    $menu->append($five_item);
    
    my $ten_item = $self->create_menu_item('radio', "10 Seconds", {
        active => $self->config->timer_value == 10,
        callback => sub {
            my $widget = shift;
            $self->config->timer_value(10) if $widget->get_active();
        }
    }, $none_item->get_group());
    $menu->append($ten_item);
    
    # Separator
    $menu->append($self->create_menu_item('separator', ""));
    
    # Image Format section
    $menu->append($self->create_menu_item('header', "Image Format"));
    
    # Create a radio button group for image formats
    my $png_item = $self->create_menu_item('radio', "PNG", {
        active => $self->config->image_format eq "png",
        callback => sub {
            my $widget = shift;
            $self->config->image_format("png") if $widget->get_active();
        }
    });
    $menu->append($png_item);
    
    my $jpg_item = $self->create_menu_item('radio', "JPG", {
        active => $self->config->image_format eq "jpg",
        callback => sub {
            my $widget = shift;
            $self->config->image_format("jpg") if $widget->get_active();
        }
    }, $png_item->get_group());
    $menu->append($jpg_item);
    
    # Add WebP option
    my $webp_item = $self->create_menu_item('radio', "WebP", {
        active => $self->config->image_format eq "webp",
        callback => sub {
            my $widget = shift;
            $self->config->image_format("webp") if $widget->get_active();
        }
    }, $png_item->get_group());
    $menu->append($webp_item);
    
    # Add AVIF option if supported
    my $avif_item = $self->create_menu_item('radio', "AVIF", {
        active => $self->config->image_format eq "avif",
        callback => sub {
            my $widget = shift;
            $self->config->image_format("avif") if $widget->get_active();
        }
    }, $png_item->get_group());
    
    # Only enable AVIF option if supported
    $avif_item->set_sensitive($self->config->avif_supported());
    if (!$self->config->avif_supported()) {
        $avif_item->set_tooltip_text("AVIF format is not supported on this system");
    }
    $menu->append($avif_item);

    # Separator
    $menu->append($self->create_menu_item('separator', ""));
    
    # Checkboxes for additional options
    $menu->append($self->create_menu_item('check', "Remember Last Selection", {
        active => $self->config->remember_last_selection,
        callback => sub {
            my $widget = shift;
            $self->config->remember_last_selection($widget->get_active());
        }
    }));
    
    $menu->append($self->create_menu_item('check', "Show Mouse Pointer", {
        active => $self->config->show_mouse_pointer,
        callback => sub {
            my $widget = shift;
            $self->config->show_mouse_pointer($widget->get_active());
        }
    }));
    
    $menu->append($self->create_menu_item('check', "Capture Window Decoration", {
        active => $self->config->capture_window_decoration,
        callback => sub {
            my $widget = shift;
            $self->config->capture_window_decoration($widget->get_active());
        }
    }));
    
    $menu->append($self->create_menu_item('check', "Allow Capturing Main Window", {
        active => $self->config->allow_self_capture,
        callback => sub {
            my $widget = shift;
            $self->config->allow_self_capture($widget->get_active());
        }
    }));
    
    # Show the menu
    $menu->show_all();
    $menu->popup(undef, undef, undef, undef, 0, 0);
}

# Select other location
sub select_other_location {
    my ($self) = @_;
    
    # Create a file chooser dialog
    my $dialog = Gtk3::FileChooserDialog->new(
        "Select Save Location",
        $self->{main_window},
        'select-folder',
        'Cancel' => 'cancel',
        'Select' => 'ok'
    );
    
    # Set current folder to last saved directory
    $dialog->set_current_folder($self->config->last_saved_dir);
    
    if ($dialog->run() eq 'ok') {
        my $location = $dialog->get_filename();
        if ($location) {
            $self->config->save_location($location);
            $self->config->last_saved_dir($location);
        }
    }
    
    $dialog->destroy();
}

sub show_floating_thumbnail {
    my ($self, $pixbuf, $filepath) = @_;
    
    # Validate input parameters
    return unless defined $pixbuf && defined $filepath;
    
    # Create thumbnail (max 600x600 pixels)
    my ($thumb_w, $thumb_h) = (600, 600);
    
    # Calculate scaled dimensions maintaining aspect ratio
    my $orig_w = $pixbuf->get_width();
    my $orig_h = $pixbuf->get_height();
    
    # Ensure valid dimensions
    if ($orig_w <= 0 || $orig_h <= 0) {
        $self->app->log_message('warning', "Invalid image dimensions: ${orig_w}x${orig_h}");
        return;
    }
    
    my $ratio = $orig_w / $orig_h;
    
    # Adjust dimensions while maintaining aspect ratio and not exceeding max size
    if ($ratio > 1) {
        # Wider than tall
        $thumb_w = 600;
        $thumb_h = int(600 / $ratio);
    } else {
        # Taller than wide
        $thumb_h = 600;
        $thumb_w = int(600 * $ratio);
    }
    
    # Create the thumbnail
    my $thumbnail = $pixbuf->scale_simple($thumb_w, $thumb_h, 'bilinear');
    
    # Create a window with no padding
    my $thumb_window = Gtk3::Window->new('popup');
    
    # Always use center positioning - this works for both X11 and Wayland
    $thumb_window->set_position('center');
    
    $thumb_window->set_keep_above(TRUE);
    $thumb_window->set_decorated(FALSE);
    
    # Create a vertical box with minimal spacing
    my $vbox = Gtk3::Box->new('vertical', 0);
    $vbox->set_spacing(0);  # No spacing between elements
    $thumb_window->add($vbox);
    
    # Add the image directly to the vbox
    my $image = Gtk3::Image->new_from_pixbuf($thumbnail);
    $vbox->pack_start($image, FALSE, FALSE, 0);  # No padding
    
    # Add button bar with no spacing
    my $button_box = Gtk3::Box->new('horizontal', 0);
    $button_box->set_homogeneous(TRUE);  # Equal button sizes
    $vbox->pack_start($button_box, FALSE, FALSE, 0);  # No padding
    
    # Open button
    my $open_button = Gtk3::Button->new_with_label("Open");
    $open_button->signal_connect('clicked' => sub {
        # Use xdg-open to open the image with the default application
        system("xdg-open", $filepath);
        $thumb_window->destroy();
    });
    $button_box->pack_start($open_button, TRUE, TRUE, 0);
    
    # Close button
    my $close_button = Gtk3::Button->new_with_label("Close");
    $close_button->signal_connect('clicked' => sub {
        $thumb_window->destroy();
    });
    $button_box->pack_start($close_button, TRUE, TRUE, 0);
    
    # Set button height to be reasonable
    $open_button->set_size_request(-1, 30);  # Standard height
    $close_button->set_size_request(-1, 30);  # Standard height
    
    # Show everything
    $thumb_window->show_all();
    
    # Size the window to exactly fit its contents
    $thumb_window->resize(1, 1);
    
    # Store the window for tracking
    push @{$self->{floating_windows}}, $thumb_window;
    
    # Auto-close after 5 seconds
    my $timeout_id = Glib::Timeout->add(5000, sub {
        # Check if window still exists
        if ($thumb_window) {
            $thumb_window->destroy();
            # Remove from the floating windows array
            @{$self->{floating_windows}} = grep { $_ != $thumb_window } @{$self->{floating_windows}};
        }
        return FALSE; # Run once
    });
    
    # Track the timeout
    push @{$self->{active_timeouts}}, $timeout_id;
}

sub show_error_dialog {
    my ($self, $title, $message) = @_;
    
    # Validate parameters
    $title ||= "Error";
    $message ||= "An unknown error occurred";
    
    # Log the error
    $self->app->log_message('error', "$title: $message");
    
    # Create a dialog
    my $dialog = Gtk3::MessageDialog->new(
        $self->{main_window},
        'modal',
        'error',
        'ok',
        $message
    );
    
    $dialog->set_title($title);
    $dialog->run();
    $dialog->destroy();
}

sub show_notification {
    my ($self, $title, $message) = @_;
    
    # Log the notification
    $self->app->log_message('info', "Notification: $title - $message");
    
    # Check if we can create a Gtk3::Notification (available in newer Gtk3)
    eval {
        if ($self->app->{gtk_app}) {
            my $notification = Gtk3::Notification->new($title);
            $notification->set_body($message);
            $self->app->{gtk_app}->send_notification(undef, $notification);
            return;
        }
    };
    
    # Fallback to a temporary floating notification
    my $notification_window = Gtk3::Window->new('popup');
    $notification_window->set_position('center');
    $notification_window->set_keep_above(TRUE);
    $notification_window->set_decorated(FALSE);
    $notification_window->set_opacity(0.9);
    
    my $vbox = Gtk3::Box->new('vertical', 5);
    $vbox->set_border_width(10);
    $notification_window->add($vbox);
    
    my $label_title = Gtk3::Label->new();
    $label_title->set_markup("<b>$title</b>");
    $vbox->pack_start($label_title, FALSE, FALSE, 0);
    
    my $label_message = Gtk3::Label->new($message);
    $vbox->pack_start($label_message, FALSE, FALSE, 0);
    
    $notification_window->show_all();
    
    # Track the floating window
    push @{$self->{floating_windows}}, $notification_window;
    
    # Auto-close after 3 seconds
    my $timeout_id = Glib::Timeout->add(3000, sub {
        if ($notification_window) {
            $notification_window->destroy();
            # Remove from the floating windows array
            @{$self->{floating_windows}} = grep { $_ != $notification_window } @{$self->{floating_windows}};
        }
        return FALSE; # Run once
    });
    
    # Track the timeout
    push @{$self->{active_timeouts}}, $timeout_id;
}

sub cancel_all_timeouts {
    my ($self) = @_;
    
    # Cancel any active timeouts
    if ($self->{active_timeouts}) {
        foreach my $source_id (@{$self->{active_timeouts}}) {
            if (defined $source_id && $source_id > 0) {
                # Remove source directly without checking if it exists
                eval {
                    Glib::Source->remove($source_id);
                };
                if ($@) {
                    $self->app->log_message('debug', "Error removing timeout source ID $source_id: $@");
                }
            }
        }
        $self->{active_timeouts} = [];
    }
}

# NEW FUNCTION: Clean up resources
sub destroy_resources {
    my ($self) = @_;
    
    # Set quitting flag
    $self->{is_quitting} = 1;
    
    # Clean up icon cache
    foreach my $key (keys %{$self->{icon_cache}}) {
        $self->{icon_cache}{$key} = undef;
    }
    $self->{icon_cache} = {};
    
    # Cancel all timeouts
    $self->cancel_all_timeouts();
    
    # Destroy any floating windows
    if ($self->{floating_windows}) {
        foreach my $window (@{$self->{floating_windows}}) {
            $window->destroy() if $window;
        }
        $self->{floating_windows} = [];
    }
    
    $self->app->log_message('debug', "UI resources cleaned up");
}

1;

