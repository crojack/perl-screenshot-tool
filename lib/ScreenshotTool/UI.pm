package ScreenshotTool::UI;

use strict;
use warnings;
use Moo;
use Gtk3 qw(-init);
use Glib qw(TRUE FALSE);
use Cairo;
use POSIX qw(strftime);
use File::Path qw(make_path);
use namespace::clean;


has 'app' => (
    is       => 'ro',
    required => 1,
);


has 'main_window' => (
    is      => 'rw',
    default => sub { undef },
);


has 'icon_cache' => (
    is      => 'ro',
    default => sub { {} },
);


has 'is_quitting' => (
    is      => 'rw',
    default => sub { 0 },
);


has 'active_timeouts' => (
    is      => 'rw',
    default => sub { [] },
);


has 'current_icon_size' => (
    is      => 'rw',
    default => sub { 64 },
);


has 'last_window_x' => (
    is      => 'rw',
    default => sub { -1 },  # -1 means position not saved yet
);

has 'last_window_y' => (
    is      => 'rw',
    default => sub { -1 },
);


has 'theme_colors' => (
    is      => 'rw',
    default => sub { {
        'background' => '#262626', # Dark gray background
        'foreground' => '#ffffff',  
        'accent'     => '#25a56a'   # Green accent
    } },
);


sub config {
    my ($self) = @_;
    return $self->app->config;
}

sub capture_manager {
    my ($self) = @_;
    return $self->app->capture_manager;
}


sub hex_to_rgb {
    my ($self, $hex) = @_;
    $hex =~ s/^#//;  # Remove leading # if present
    my @rgb = ();
    push @rgb, hex(substr($hex, 0, 2)) / 255;
    push @rgb, hex(substr($hex, 2, 2)) / 255;
    push @rgb, hex(substr($hex, 4, 2)) / 255;
    return @rgb;
}


sub apply_button_styling {
    my ($self, $button) = @_;
    
    $button->signal_connect('enter-notify-event' => sub {
        my ($widget, $event) = @_;
        my $context = $widget->get_style_context();
        $context->add_class('hover');
        return FALSE;
    });
    
    $button->signal_connect('leave-notify-event' => sub {
        my ($widget, $event) = @_;
        my $context = $widget->get_style_context();
        $context->remove_class('hover');
        return FALSE;
    });
    
    $button->set_relief('none');
    $button->set_can_focus(FALSE);
    
    $button->add_events(['enter-notify-mask', 'leave-notify-mask']);
}

sub show_main_window {
    my ($self) = @_;
    
    # Reset quit flag
    $self->is_quitting(0);
    
    # Remember current icon size before loading config
    my $current_size = $self->current_icon_size;
    
    # Load configuration if it exists
    $self->load_config();
    
    # IMPORTANT: If we're changing icon size, restore the size
    if ($self->{changing_icon_size} && defined $current_size) {
        $self->current_icon_size($current_size);
    }
    
    $self->app->log_message('info', "show_main_window using icon size: " . $self->current_icon_size);
    
    $self->{main_window} = Gtk3::Window->new('toplevel');
    $self->{main_window}->set_title($self->app->app_name);
    $self->{main_window}->set_resizable(FALSE);
    $self->{main_window}->set_default_size(500, 100);
    $self->{main_window}->set_size_request(500, 100);

    $self->{main_window}->set_resizable(FALSE);
    $self->{main_window}->set_default_size(500, 100);
    $self->{main_window}->set_size_request(500, 100);

    $self->{main_window}->set_resizable(TRUE);
    $self->{main_window}->set_default_size(500, 100);
    $self->{main_window}->set_size_request(300, 80);

    $self->{main_window}->signal_connect('configure-event' => sub {
        my ($widget, $event) = @_;
        my $width = $event->width;
        my $height = $event->height;
        
        if ($width > 800 || $height > 600) {
            my $new_width = $width > 800 ? 800 : $width;
            my $new_height = $height > 600 ? 600 : $height;
            $widget->resize($new_width, $new_height);
        }
        
        return FALSE;
    });
    
    $self->{main_window}->set_app_paintable(1);
    
    $self->{main_window}->set_decorated(FALSE);
    
    if ($self->app->window_system =~ /^wayland/) {
        $self->{main_window}->set_gravity('south');
    } else {
        $self->{main_window}->set_position('center');
    }
    
    my $css_provider = Gtk3::CssProvider->new();
    
    $css_provider->load_from_data(qq{
        window {
            background-color: #262626;
            color: #ffffff;
        }
        
        .header-bar {
            background-color: transparent;
            color: #ffffff;
            border: none;
            padding: 8px;
        }
        
        button {
            background-color: rgba(0, 0, 0, 0);
            color: #ffffff;
            border: none;
            border-radius: 0px;
            margin: 3px;
            font-size: 15px;
            font-weight: normal;
            text-shadow: none;
        }
        
        button.hover {
            border: 1px solid ${\$self->theme_colors->{accent}};
            background-color: rgba(0, 0, 0, 0);
        }
        
        button:active {
            background-color: rgba(
                ${\ (hex(substr($self->theme_colors->{accent}, 1, 2)) / 255) },
                ${\ (hex(substr($self->theme_colors->{accent}, 3, 2)) / 255) },
                ${\ (hex(substr($self->theme_colors->{accent}, 5, 2)) / 255) },
                0.3
            );
        }
        
        /* Header buttons get different hover effect */
        .header-button.hover {
            background-color: rgba(
                ${\ (hex(substr($self->theme_colors->{accent}, 1, 2)) / 255) },
                ${\ (hex(substr($self->theme_colors->{accent}, 3, 2)) / 255) },
                ${\ (hex(substr($self->theme_colors->{accent}, 5, 2)) / 255) },
                0.3
            );
            border: none;
        }
        
        .header-button:active {
            background-color: rgba(
                ${\ (hex(substr($self->theme_colors->{accent}, 1, 2)) / 255) },
                ${\ (hex(substr($self->theme_colors->{accent}, 3, 2)) / 255) },
                ${\ (hex(substr($self->theme_colors->{accent}, 5, 2)) / 255) },
                0.5
            );
        }
        
        /* Menu styling based on calculator app with explicit blue-green color */
        menu, 
        .menu, 
        popover, 
        .popover,
        menu.background, 
        popover.background,
        popover contents {
            background-color: rgba(0, 0, 0, 0.9);
            color: #ffffff;
            border-radius: 8px;
            border: 1px solid #2a7a9b;  /* Blue-green accent color from calculator */
            padding: 4px;
        }
        
        menuitem,
        .menuitem,
        menu menuitem,
        popover menuitem {
            background-color: transparent;
            color: #ffffff;
            padding: 8px 12px;
            border: none;
        }
        
        menuitem:hover,
        .menuitem:hover,
        menu menuitem:hover,
        popover menuitem:hover {
            background-color: #2a7a9b;  /* Blue-green accent color from calculator */
            color: #ffffff;
        }
        
        menuitem separator,
        menu separator,
        popover separator {
            background-color: rgba(255, 255, 255, 0.2);
            margin: 4px 0;
        }
    });
    
    Gtk3::StyleContext::add_provider_for_screen(
        Gtk3::Gdk::Screen::get_default(),
        $css_provider,
        Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION
    );
    
    my $main_box = Gtk3::Box->new('vertical', 0);
    $self->{main_window}->add($main_box);
    
    my $header_event_box = Gtk3::EventBox->new();
    $header_event_box->add_events(['button-press-mask', 'button-release-mask', 'pointer-motion-mask']);
    $main_box->pack_start($header_event_box, FALSE, FALSE, 0);
    
    my $header_bar = Gtk3::Box->new('horizontal', 2);
    $header_bar->get_style_context()->add_class('header-bar');
    $header_event_box->add($header_bar);
    
    my $menu_button = Gtk3::MenuButton->new();
    my $menu_icon = Gtk3::Image->new_from_icon_name('open-menu-symbolic', 1);
    $menu_button->set_image($menu_icon);
    $menu_button->set_always_show_image(TRUE);
    $menu_button->set_label("");
    $menu_button->set_relief('none');
    $menu_button->set_tooltip_text("Menu");
    $menu_button->get_style_context()->add_class('header-button');
    $self->apply_button_styling($menu_button);
    $header_bar->pack_start($menu_button, FALSE, FALSE, 2);
    
    my $title_label = Gtk3::Label->new($self->app->app_name);
    $title_label->override_color('normal', Gtk3::Gdk::RGBA->new(1, 1, 1, 1));
    $header_bar->pack_start($title_label, TRUE, TRUE, 0);
    
    my $minimize_button = Gtk3::Button->new();
    my $minimize_icon = Gtk3::Image->new_from_icon_name('window-minimize-symbolic', 1);
    $minimize_button->set_image($minimize_icon);
    $minimize_button->set_tooltip_text("Minimize");
    $minimize_button->get_style_context()->add_class('header-button');
    $self->apply_button_styling($minimize_button);
    $minimize_button->signal_connect(clicked => sub { $self->{main_window}->iconify(); });
    
    my $close_button = Gtk3::Button->new();
    my $close_icon = Gtk3::Image->new_from_icon_name('window-close-symbolic', 1);
    $close_button->set_image($close_icon);
    $close_button->set_tooltip_text("Close");
    $close_button->get_style_context()->add_class('header-button');
    $self->apply_button_styling($close_button);
    $close_button->signal_connect(clicked => sub { 
        $self->app->log_message('info', "Close button clicked, shutting down gracefully");
        $self->is_quitting(1);
        $self->cancel_all_timeouts();
        
        while (Gtk3::events_pending()) {
            Gtk3::main_iteration();
        }
        
        $self->app->log_message('info', "Application exiting cleanly");
        Gtk3->main_quit();
    });
    
    $header_bar->pack_end($close_button, FALSE, FALSE, 0);
    $header_bar->pack_end($minimize_button, FALSE, FALSE, 0);
    
    $header_event_box->signal_connect('button-press-event' => sub {
        my ($widget, $event) = @_;
        
        if ($event->button == 1) {

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
    
    my $menu = Gtk3::Menu->new();
    
    my $capture_window_item = Gtk3::MenuItem->new_with_label("Capture Window");
    my $capture_region_item = Gtk3::MenuItem->new_with_label("Capture Region");
    my $capture_desktop_item = Gtk3::MenuItem->new_with_label("Capture Desktop");
    my $separator1 = Gtk3::SeparatorMenuItem->new();
    my $options_item = Gtk3::MenuItem->new_with_label("Options");
    my $separator2 = Gtk3::SeparatorMenuItem->new();
    my $exit_item = Gtk3::MenuItem->new_with_label("Exit");
    
    $capture_window_item->signal_connect(activate => sub {
        $self->config->selection_mode(0);
        $self->hide_main_window_completely();
        
        my $capture_manager = $self->app->capture_manager;
        
        Glib::Timeout->add(200, sub {
            $capture_manager->start_capture();
            return FALSE; 
        });
    });
    
    $capture_region_item->signal_connect(activate => sub {
        $self->config->selection_mode(1);
        $self->hide_main_window_completely();
        
        my $capture_manager = $self->app->capture_manager;
        
        Glib::Timeout->add(200, sub {
            $capture_manager->start_capture();
            return FALSE; 
        });
    });
    
    $capture_desktop_item->signal_connect(activate => sub {
        $self->config->selection_mode(2);
        $self->hide_main_window_completely();
        
        my $capture_manager = $self->app->capture_manager;
        
        Glib::Timeout->add(200, sub {
            $capture_manager->start_capture();
            return FALSE;
        });
    });
    
    $options_item->signal_connect(activate => sub {
        $self->show_options_menu($menu_button);
    });
    
    $exit_item->signal_connect(activate => sub { 
        $self->app->log_message('info', "Exit menu item clicked, shutting down gracefully");
        $self->is_quitting(1);
        $self->cancel_all_timeouts();
        
        while (Gtk3::events_pending()) {
            Gtk3::main_iteration();
        }
        
        $self->app->log_message('info', "Application exiting cleanly");
        Gtk3->main_quit();
    });

    $menu->append($capture_window_item);
    $menu->append($capture_region_item);
    $menu->append($capture_desktop_item);
    $menu->append($separator1);
    $menu->append($options_item);
    $menu->append($separator2);
    $menu->append($exit_item);

    $menu->show_all();
    $menu_button->set_popup($menu);
    
    my $content_box = Gtk3::Box->new('horizontal', 5);
    $content_box->set_border_width(5);
    $main_box->pack_start($content_box, TRUE, TRUE, 0);
    
    my $window_button = $self->create_button('window', 'Window', sub { 
        $self->config->selection_mode(0);
        $self->hide_main_window_completely();
        
        my $capture_manager = $self->app->capture_manager;
        
        Glib::Timeout->add(200, sub {
            $capture_manager->start_capture();
            return FALSE; 
        });
    });
    $content_box->pack_start($window_button, FALSE, FALSE, 0);
    
    my $region_button = $self->create_button('region', 'Region', sub { 
        $self->config->selection_mode(1);
        $self->hide_main_window_completely();
        
        my $capture_manager = $self->app->capture_manager;
        
        Glib::Timeout->add(200, sub {
            $capture_manager->start_capture();
            return FALSE; 
        });
    });
    $content_box->pack_start($region_button, FALSE, FALSE, 0);
    
    my $fullscreen_button = $self->create_button('desktop', 'Desktop', sub { 
        $self->config->selection_mode(2);
        $self->hide_main_window_completely();
        
        my $capture_manager = $self->app->capture_manager;
        
        Glib::Timeout->add(200, sub {
            $capture_manager->start_capture();
            return FALSE;
        });
    });
    $content_box->pack_start($fullscreen_button, FALSE, FALSE, 0);
    
    my $options_button = $self->create_button('settings', 'Options', undef);
    $options_button->signal_connect('clicked' => sub {
        $self->show_options_menu($options_button);
    });
    $content_box->pack_start($options_button, FALSE, FALSE, 0);

    my $appearance_button = $self->create_button('appearance', 'Interface', undef);
    $appearance_button->signal_connect('clicked' => sub {
        $self->show_appearance_menu($appearance_button);
    });
    $content_box->pack_start($appearance_button, FALSE, FALSE, 0);
    
    $self->{main_window}->signal_connect('draw' => sub {
        my ($widget, $cr) = @_;
        my $width = $widget->get_allocated_width();
        my $height = $widget->get_allocated_height();
        
        # Fill with solid dark background #262626
        $cr->set_source_rgb(0.15, 0.15, 0.15);  # #262626
        $cr->paint();
        
        # Get accent color components
        my $accent = $self->theme_colors->{accent};
        $accent =~ s/^#//;
        my $r = hex(substr($accent, 0, 2)) / 255;
        my $g = hex(substr($accent, 2, 2)) / 255;
        my $b = hex(substr($accent, 4, 2)) / 255;
        
        # Draw VERY subtle accent in top-right corner
        my $pattern1 = Cairo::RadialGradient->create(
            $width, 0,          # x,y of center point
            0,                  # radius of inner circle
            $width, 0,          # x,y of center point (same)
            $width * 0.8        # radius of outer circle
        );
        
        # Use the theme accent color with low alpha
        $pattern1->add_color_stop_rgba(0.0, $r, $g, $b, 0.0);  # More opaque at center but still subtle
        $pattern1->add_color_stop_rgba(0.0, $r, $g, $b, 0.0);   # Transparent at edge
        
        $cr->set_source($pattern1);
        $cr->paint();
        
        # Draw VERY subtle accent in bottom-left corner
        my $pattern2 = Cairo::RadialGradient->create(
            0, $height,         # x,y of center point
            0,                  # radius of inner circle 
            0, $height,         # x,y of center point (same)
            $width * 0.8        # radius of outer circle
        );
        
        # Use the theme accent color with low alpha
        $pattern2->add_color_stop_rgba(0.0, $r, $g, $b, 1.0);  # More opaque at center but still subtle
        $pattern2->add_color_stop_rgba(0.0, $r, $g, $b, 0.0);   # Transparent at edge
        
        $cr->set_source($pattern2);
        $cr->paint();
        
        # Draw the border with accent color
        $cr->set_source_rgba($r, $g, $b, 1.0);  # Accent color
        $cr->set_line_width(1);
        $cr->rectangle(0.5, 0.5, $width - 1, $height - 1);
        $cr->stroke();
        
        return FALSE;
    });

    $self->{main_window}->signal_connect('delete-event' => sub {
        my ($widget, $event) = @_;
        $self->app->log_message('info', "Delete event received on main window");
        
        $self->is_quitting(1);
        $self->cancel_all_timeouts();
        
        while (Gtk3::events_pending()) {
            Gtk3::main_iteration();
        }
        
        $self->app->log_message('info', "Application exiting cleanly");
        Gtk3->main_quit();
        
        return FALSE; 
    });
    

    $self->app->log_message('debug', "Initializing keyboard shortcuts manager");
    require ScreenshotTool::KeyboardShortcuts;
    my $shortcuts = ScreenshotTool::KeyboardShortcuts->new(app => $self->app);
    $shortcuts->initialize();
    $self->{shortcuts_manager} = $shortcuts;
    
    $self->{main_window}->set_can_focus(TRUE);
    $self->{main_window}->show_all();
    
    if ($self->app->{keyboard_shortcuts}) {
        $self->app->{keyboard_shortcuts}->initialize();
    } else {
        $self->app->{keyboard_shortcuts} = ScreenshotTool::KeyboardShortcuts->new(app => $self->app);
        $self->app->{keyboard_shortcuts}->initialize();
    }
    
    $self->{main_window}->grab_focus();
}

sub create_button {
    my ($self, $icon_name, $label_text, $callback) = @_;
    
    my $button = Gtk3::Button->new();
    
    # Get current icon size and explicitly use it - don't rely on any cached value
    my $size = $self->current_icon_size;
    $self->app->log_message('info', "Creating button with icon '$icon_name' at size: $size pixels");
    
    # Set button size to accommodate icon plus some padding
    $button->set_size_request(80, $size + 30);
    
    my $button_box = Gtk3::Box->new('vertical', 5);
    $button_box->set_homogeneous(FALSE);
    $button->add($button_box);
    
    # Create a fresh icon every time, avoiding cache
    my $icon;
    
    # First try custom icon path
    my $icon_path = $self->get_icon_path($icon_name);
    if ($icon_path && -f $icon_path) {
        $self->app->log_message('info', "Loading custom icon from file: $icon_path");
        $icon = Gtk3::Image->new_from_file($icon_path);
    } else {
        # Use standard icon names
        my %icons = (
            'close' => 'window-close',
            'window' => 'window',
            'region' => 'select-rectangular',
            'desktop' => 'desktop',
            'settings' => 'preferences-system',
            'capture' => 'camera-photo',
            'appearance' => 'preferences-desktop-theme',
        );
        
        if (exists $icons{$icon_name}) {
            $icon = Gtk3::Image->new_from_icon_name($icons{$icon_name}, 'dialog');
        } else {
            $icon = Gtk3::Image->new_from_icon_name($icon_name, 'dialog');
        }
        
        if (!$icon) {
            $icon = Gtk3::Image->new_from_icon_name('image-missing', 'dialog');
        }
    }
    
    # IMPORTANT: Make absolutely sure we set the pixel size correctly
    $self->app->log_message('info', "Setting SVG icon pixel size to: $size");
    $icon->set_pixel_size($size);
    
    $button_box->pack_start($icon, TRUE, TRUE, 0);
    
    my $label = Gtk3::Label->new($label_text);
    $button_box->pack_start($label, FALSE, FALSE, 0);
    
    if (defined $callback) {
        $button->signal_connect('clicked' => $callback);
    }
    
    return $button;
}


sub create_icon_button {
    my ($self, $icon_name, $tooltip) = @_;
    
    my $button = Gtk3::Button->new();
    
    my $size = $self->current_icon_size * 0.6; 
    $size = 40 if $size < 40; 
    
    $button->set_size_request($size, $size);
    $button->set_tooltip_text($tooltip);
    
    my $custom_icon_path = $self->config->custom_icons_dir . "/$icon_name.svg";
    my $icon;
    
    if (-f $custom_icon_path) {
        $icon = Gtk3::Image->new_from_file($custom_icon_path);
    } else {
        my %icons = (
            'close' => 'window-close',
            'window' => 'window',
            'region' => 'select-rectangular',
            'desktop' => 'desktop',
            'settings' => 'preferences-system',
            'capture' => 'camera-photo',
        );
        
        if (exists $icons{$icon_name}) {
            $icon = Gtk3::Image->new_from_icon_name($icons{$icon_name}, 'button');
        } else {
            $icon = Gtk3::Image->new_from_icon_name($icon_name, 'button');
        }
        
        if (!$icon) {
            $icon = Gtk3::Image->new_from_icon_name('image-missing', 'button');
        }
    }
    

    $icon->set_pixel_size($size);

    $button->add($icon);
    
    return $button;
}

sub get_button_icon {
    my ($self, $icon_name) = @_;
    
    my $size = $self->current_icon_size;
    $self->app->log_message('debug', "Getting button icon for $icon_name at size $size");
    
    my $icon;
    
    my $icon_path = $self->get_icon_path($icon_name);
    if ($icon_path && -f $icon_path) {
        $self->app->log_message('debug', "Creating image from file: $icon_path");
        $icon = Gtk3::Image->new_from_file($icon_path);
    } else {

        my %icons = (
            'close' => 'window-close',
            'window' => 'window',
            'region' => 'select-rectangular',
            'desktop' => 'desktop',
            'settings' => 'preferences-system',
            'capture' => 'camera-photo',
            'appearance' => 'preferences-desktop-theme',
        );
        
        my $icon_id = exists $icons{$icon_name} ? $icons{$icon_name} : $icon_name;
        $self->app->log_message('debug', "Using system icon: $icon_id");
        
        $icon = Gtk3::Image->new_from_icon_name($icon_id, 'dialog');
        
        if (!$icon) {
            $self->app->log_message('warning', "Failed to find icon, using fallback");
            $icon = Gtk3::Image->new_from_icon_name('image-missing', 'dialog');
        }
    }
    

    $self->app->log_message('debug', "Setting icon pixel size to: $size");

    $icon->set_pixel_size($size);
    
    return $icon;
}

sub get_icon_path {
    my ($self, $icon_name) = @_;
    
    my $size = $self->current_icon_size;
    my $size_dir = "${size}x${size}";
    
    my $base_dir = $self->config->custom_icons_dir;
    $base_dir =~ s|/share/icons$|/share|;
    
    $self->app->log_message('info', "Base icon directory: $base_dir");
    $self->app->log_message('info', "Looking for icon in size directory: $size_dir");
    
    my $icon_path = "$base_dir/icons/$size_dir/$icon_name.svg";
    $self->app->log_message('info', "Checking for icon at: $icon_path");
    
    if (-f $icon_path) {
        $self->app->log_message('info', "Found size-specific icon: $icon_path");
        return $icon_path;
    } else {
        $self->app->log_message('info', "Size-specific icon not found at: $icon_path");
    }
    
    $icon_path = "$base_dir/icons/$icon_name.svg";
    $self->app->log_message('info', "Checking for generic icon at: $icon_path");
    
    if (-f $icon_path) {
        $self->app->log_message('info', "Found generic icon: $icon_path");
        return $icon_path;
    } else {
        $self->app->log_message('info', "Generic icon not found at: $icon_path");
    }
    
    $self->app->log_message('info', "No custom icon found for $icon_name, will use system icon");
    return undef;
}


sub hide_main_window_completely {
    my ($self) = @_;
    
    if ($self->config->allow_self_capture) {
        return; 
    }
    
    my ($x, $y) = $self->{main_window}->get_position();
    $self->last_window_x($x);
    $self->last_window_y($y);
    
    $self->app->log_message('debug', "Saving window position: $x, $y");
    
    $self->{main_window}->iconify();
    $self->{main_window}->hide();
    $self->{main_window}->set_opacity(0.0);
    
    Gtk3::main_iteration() while Gtk3::events_pending();
}


sub restore_main_window {
    my ($self) = @_;
    
    if ($self->is_quitting) {
        $self->app->log_message('debug', "Skipping window restore because application is quitting");
        return;
    }
    
    if (defined $self->{main_window}) {
        return if $self->is_quitting;
        
        $self->{main_window}->set_opacity(1.0);
        
        if ($self->last_window_x >= 0 && $self->last_window_y >= 0) {
            $self->app->log_message('debug', "Restoring window to saved position: " . 
                                   $self->last_window_x . ", " . $self->last_window_y);
            
            $self->{main_window}->move($self->last_window_x, $self->last_window_y);
            $self->{main_window}->deiconify();
            $self->{main_window}->show_all();
            $self->{main_window}->present();
            
            while (Gtk3::events_pending()) {
                Gtk3::main_iteration();
            }
            
            $self->{main_window}->move($self->last_window_x, $self->last_window_y);
        } else {
            
            my $screen = Gtk3::Gdk::Screen::get_default();
            my $screen_width = $screen->get_width();
            my $screen_height = $screen->get_height();
            
            $self->{main_window}->set_resizable(TRUE);
            $self->{main_window}->resize(1, 1);  
            $self->{main_window}->set_resizable(FALSE);
            
            Gtk3::main_iteration() while Gtk3::events_pending();
            
            my $window_width = $self->{main_window}->get_allocated_width();
            my $window_height = $self->{main_window}->get_allocated_height();
            
            if (!$window_width || !$window_height || $window_width < 10 || $window_height < 10) {
                $window_width = 600;  
                $window_height = 150; 
            }
            
            my $x_position = int(($screen_width - $window_width) / 2);
            my $y_position = $screen_height - $window_height - 50; 
            
            $self->app->log_message('debug', "Positioning main window at: $x_position, $y_position " . 
                                   "(screen: $screen_width x $screen_height, window: $window_width x $window_height)");
            
            if ($self->app->window_system =~ /^wayland/) {
                $self->{main_window}->set_resizable(TRUE);
                
                my $screen = Gtk3::Gdk::Screen::get_default();
                my $screen_height = $screen->get_height();
                
                $self->{main_window}->resize(1, 1);
                
                my $window_width = 600; 
                my $window_height = 150; 
                
                $self->{main_window}->set_gravity('south');
                $self->{main_window}->move(0, $screen_height - $window_height - 50);
                $self->{main_window}->deiconify();
                $self->{main_window}->show_all();
                $self->{main_window}->resize($window_width, $window_height);
                $self->{main_window}->present();
                $self->{main_window}->set_resizable(FALSE);
            } else {
                $self->{main_window}->move($x_position, $y_position);
                $self->{main_window}->deiconify();
                $self->{main_window}->show_all();
                $self->{main_window}->present();
                
                Gtk3::main_iteration() while Gtk3::events_pending();
                $self->{main_window}->move($x_position, $y_position);
            }
        }
        
        Gtk3::main_iteration() while Gtk3::events_pending();
    }
}

sub show_options_menu {
    my ($self, $button) = @_;
    
    my $menu = Gtk3::Menu->new();
    
    my $location_item = Gtk3::MenuItem->new_with_label("Save to");
    $location_item->set_sensitive(FALSE);
    $menu->append($location_item);
    
    my $desktop_item = Gtk3::RadioMenuItem->new_with_label(undef, "Desktop");
    $desktop_item->set_active($self->config->save_location eq "$ENV{HOME}/Desktop");
    $desktop_item->signal_connect('toggled' => sub {
        $self->config->save_location("$ENV{HOME}/Desktop") if $desktop_item->get_active();
    });
    $menu->append($desktop_item);
    
    my $pictures_item = Gtk3::RadioMenuItem->new_with_label($desktop_item->get_group(), "Pictures");
    $pictures_item->set_active($self->config->save_location eq "$ENV{HOME}/Pictures");
    $pictures_item->signal_connect('toggled' => sub {
        $self->config->save_location("$ENV{HOME}/Pictures") if $pictures_item->get_active();
    });
    $menu->append($pictures_item);
    
    my $clipboard_item = Gtk3::RadioMenuItem->new_with_label($desktop_item->get_group(), "Clipboard");
    $clipboard_item->set_active($self->config->save_location eq "clipboard");
    $clipboard_item->signal_connect('toggled' => sub {
        $self->config->save_location("clipboard") if $clipboard_item->get_active();
    });
    $menu->append($clipboard_item);
    
    my $other_item = Gtk3::MenuItem->new_with_label("Other Location...");
    $other_item->signal_connect('activate' => sub {
        $self->select_other_location();
    });
    $menu->append($other_item);
    
    $menu->append(Gtk3::SeparatorMenuItem->new());
    
    my $timer_item = Gtk3::MenuItem->new_with_label("Timer");
    $timer_item->set_sensitive(FALSE);
    $menu->append($timer_item);
    
    my $none_item = Gtk3::RadioMenuItem->new_with_label(undef, "None");
    $none_item->set_active($self->config->timer_value == 0);
    $none_item->signal_connect('toggled' => sub {
        $self->config->timer_value(0) if $none_item->get_active();
    });
    $menu->append($none_item);
    
    my $three_item = Gtk3::RadioMenuItem->new_with_label($none_item->get_group(), "3 Seconds");
    $three_item->set_active($self->config->timer_value == 3);
    $three_item->signal_connect('toggled' => sub {
        $self->config->timer_value(3) if $three_item->get_active();
    });
    $menu->append($three_item);
    
    my $five_item = Gtk3::RadioMenuItem->new_with_label($none_item->get_group(), "5 Seconds");
    $five_item->set_active($self->config->timer_value == 5);
    $five_item->signal_connect('toggled' => sub {
        $self->config->timer_value(5) if $five_item->get_active();
    });
    $menu->append($five_item);
    
    my $ten_item = Gtk3::RadioMenuItem->new_with_label($none_item->get_group(), "10 Seconds");
    $ten_item->set_active($self->config->timer_value == 10);
    $ten_item->signal_connect('toggled' => sub {
        $self->config->timer_value(10) if $ten_item->get_active();
    });
    $menu->append($ten_item);

    $menu->append(Gtk3::SeparatorMenuItem->new());
    
    my $format_item = Gtk3::MenuItem->new_with_label("Image Format");
    $format_item->set_sensitive(FALSE);
    $menu->append($format_item);
    
    my $png_item = Gtk3::RadioMenuItem->new_with_label(undef, "PNG");
    $png_item->set_active($self->config->image_format eq "png" || !defined $self->config->image_format);
    $png_item->signal_connect('toggled' => sub {
        $self->config->image_format("png") if $png_item->get_active();
    });
    $menu->append($png_item);
    
    my $jpg_item = Gtk3::RadioMenuItem->new_with_label($png_item->get_group(), "JPG");
    $jpg_item->set_active($self->config->image_format eq "jpg");
    $jpg_item->signal_connect('toggled' => sub {
        $self->config->image_format("jpg") if $jpg_item->get_active();
    });
    $menu->append($jpg_item);
    
    my $webp_item = Gtk3::RadioMenuItem->new_with_label($png_item->get_group(), "WebP");
    $webp_item->set_active($self->config->image_format eq "webp");
    $webp_item->signal_connect('toggled' => sub {
        $self->config->image_format("webp") if $webp_item->get_active();
    });
    $menu->append($webp_item);
    
    my $avif_item = Gtk3::RadioMenuItem->new_with_label($png_item->get_group(), "AVIF");
    $avif_item->set_active($self->config->image_format eq "avif");
    
    $avif_item->set_sensitive($self->config->avif_supported);
    
    if ($self->config->avif_supported) {
        $avif_item->signal_connect('toggled' => sub {
            $self->config->image_format("avif") if $avif_item->get_active();
        });
    } else {
      
        $avif_item->set_tooltip_text("AVIF format is not supported on this system");
    }
    $menu->append($avif_item);

    $menu->append(Gtk3::SeparatorMenuItem->new());
    
    my $remember_item = Gtk3::CheckMenuItem->new_with_label("Remember Last Selection");
    $remember_item->set_active($self->config->remember_last_selection);
    $remember_item->signal_connect('toggled' => sub {
        $self->config->remember_last_selection($remember_item->get_active());
    });
    $menu->append($remember_item);
    
    my $pointer_item = Gtk3::CheckMenuItem->new_with_label("Show Mouse Pointer");
    $pointer_item->set_active($self->config->show_mouse_pointer);
    $pointer_item->signal_connect('toggled' => sub {
        $self->config->show_mouse_pointer($pointer_item->get_active());
    });
    $menu->append($pointer_item);
    
    my $decoration_item = Gtk3::CheckMenuItem->new_with_label("Capture Window Decoration");
    $decoration_item->set_active($self->config->capture_window_decoration);
    $decoration_item->signal_connect('toggled' => sub {
        $self->config->capture_window_decoration($decoration_item->get_active());
    });
    $menu->append($decoration_item);

    my $self_capture_item = Gtk3::CheckMenuItem->new_with_label("Allow Capturing Main Window");
    $self_capture_item->set_active($self->config->allow_self_capture);
    $self_capture_item->signal_connect('toggled' => sub {
        $self->config->allow_self_capture($self_capture_item->get_active());
    });
    $menu->append($self_capture_item);
    
    # Show the menu
    $menu->show_all();
    if ($self->app->window_system eq 'wayland') {
        $menu->popup_at_widget($button, 'bottom', 0, 0);
    } else {
        $menu->popup(undef, undef, undef, undef, 0, 0);
    }
}

sub show_appearance_menu {
    my ($self, $button) = @_;
    
    my $menu = Gtk3::Menu->new();
    
    my $size_item = Gtk3::MenuItem->new_with_label("Icon Size");
    $size_item->set_sensitive(FALSE);
    $menu->append($size_item);
    
    foreach my $size (40, 48, 56, 64, 72, 80, 88) {
        my $size_option = Gtk3::MenuItem->new_with_label("${size}x${size}");
        $size_option->signal_connect('activate' => sub {
            $self->change_icon_size($size);
        });
        $menu->append($size_option);
    }
    
    $menu->append(Gtk3::SeparatorMenuItem->new());
    
    my $theme_item = Gtk3::MenuItem->new_with_label("Color Theme");
    $theme_item->set_sensitive(FALSE);
    $menu->append($theme_item);
    
    my $custom_color = Gtk3::MenuItem->new_with_label("Custom Colors...");
    $custom_color->signal_connect('activate' => sub {
        $self->show_color_picker();
    });
    $menu->append($custom_color);
    
    $menu->show_all();
    if ($self->app->window_system eq 'wayland') {
        $menu->popup_at_widget($button, 'bottom', 0, 0);
    } else {
        $menu->popup(undef, undef, undef, undef, 0, 0);
    }
}


sub change_icon_size {
    my ($self, $size) = @_;
    
    # Skip if already at this size
    return if $size == $self->current_icon_size;
    
    $self->app->log_message('info', "Changing icon size to ${size}x${size}");
    
    # IMPORTANT: Store this as a temporary variable to ensure it persists through config loading
    my $new_size = $size;
    
    # Update the icon size
    $self->current_icon_size($new_size);
    
    # Completely clear the icon cache
    $self->{icon_cache} = {};
    
    if ($self->{main_window}) {
        # Remember current position and accent color
        my ($current_x, $current_y) = $self->{main_window}->get_position();
        my $current_accent = $self->theme_colors->{accent};
        
        # Store window system info
        my $window_system = $self->app->window_system;
        
        # Destroy the old window completely
        my $old_window = $self->{main_window};
        $old_window->destroy() if $old_window;
        $self->{main_window} = undef;
        
        # Process any pending events
        while (Gtk3::events_pending()) {
            Gtk3::main_iteration();
        }
        
        # IMPORTANT: Set a flag to prevent config loading from overriding our size
        $self->{changing_icon_size} = 1;
        
        # Show new main window - this will create new buttons with correct icon sizes
        $self->show_main_window();
        
        # Ensure the window has a reasonable size based on icon size
        my $window_width = 500 + ($new_size - 64) * 2.5;
        my $window_height = 100 + ($new_size - 64) * 0.8;
        
        # Keep window size within reasonable limits
        $window_width = 400 if $window_width < 400;
        $window_width = 800 if $window_width > 800;
        $window_height = 100 if $window_height < 100;
        $window_height = 300 if $window_height > 300;
        
        $self->{main_window}->resize($window_width, $window_height);
        
        # Restore position for Xorg
        if ($window_system eq 'xorg') {
            $self->{main_window}->move($current_x, $current_y);
            
            while (Gtk3::events_pending()) {
                Gtk3::main_iteration();
            }
        }
        
        # Apply stored accent color
        $self->apply_accent_color($current_accent);
        
        # Force a redraw and show all widgets to ensure visibility
        $self->{main_window}->queue_draw();
        $self->{main_window}->show_all();
        
        # IMPORTANT: Remove the flag after window is completely set up
        $self->{changing_icon_size} = 0;
    }
    
    # Save the configuration
    $self->save_config();
}

sub show_color_picker {
    my ($self) = @_;
    
    $self->app->log_message('info', "Opening accent color picker");
    
    my $dialog = Gtk3::Dialog->new(
        "Accent Color",
        $self->{main_window},
        'modal',
        'Cancel' => 'cancel',
        'Apply' => 'ok'
    );
    
    $dialog->set_default_size(300, 150);
    
    my $content_area = $dialog->get_content_area();
    $content_area->set_border_width(15);
    
    my $vbox = Gtk3::Box->new('vertical', 12);
    $content_area->add($vbox);
    
    my $label = Gtk3::Label->new("Select accent color:");
    $label->set_halign('start');
    $vbox->pack_start($label, FALSE, FALSE, 0);
    
    my $color_button = Gtk3::ColorButton->new();
    $color_button->set_size_request(60, 40); 
    
    eval {
        my $rgba = Gtk3::Gdk::RGBA->new();
        $rgba->parse($self->theme_colors->{accent} || '#25a56a');
        $color_button->set_rgba($rgba);
    };
    if ($@) {
        $self->app->log_message('warning', "Failed to set accent color: $@");
    }
    
    $vbox->pack_start($color_button, FALSE, FALSE, 10);
    
    my $preview_box = Gtk3::Box->new('horizontal', 10);
    $vbox->pack_start($preview_box, FALSE, FALSE, 10);
    
    my $preview_label = Gtk3::Label->new("Preview:");
    $preview_box->pack_start($preview_label, FALSE, FALSE, 0);
    
    my $preview_frame = Gtk3::Frame->new();
    $preview_frame->set_size_request(200, 30);
    $preview_box->pack_start($preview_frame, TRUE, TRUE, 0);
    
    my $preview_area = Gtk3::DrawingArea->new();
    $preview_frame->add($preview_area);
    
    $preview_area->signal_connect('draw' => sub {
        my ($widget, $cr) = @_;
        my $width = $widget->get_allocated_width();
        my $height = $widget->get_allocated_height();
        
        $cr->set_source_rgb(0.15, 0.15, 0.15);  # #262626
        $cr->paint();
        
        # Get the color from the button
        my $rgba = $color_button->get_rgba();
        my $r = $rgba->red;
        my $g = $rgba->green;
        my $b = $rgba->blue;
        
        # Create a radial gradient
        my $pattern = Cairo::RadialGradient->create(
            $width, 0, 0, $width, 0, $width * 0.8
        );
        
        $pattern->add_color_stop_rgba(0.0, $r, $g, $b, 0.15);
        $pattern->add_color_stop_rgba(1.0, $r, $g, $b, 0.0);
        
        $cr->set_source($pattern);
        $cr->paint();
        
        # Draw the border in accent color
        $cr->set_source_rgba($r, $g, $b, 1.0);
        $cr->set_line_width(1);
        $cr->rectangle(0.5, 0.5, $width - 1, $height - 1);
        $cr->stroke();
        
        return FALSE;
    });
    
    $color_button->signal_connect('color-set' => sub {
        $preview_area->queue_draw();
    });
    
    my $css_provider = Gtk3::CssProvider->new();
    $css_provider->load_from_data(qq{
        dialog {
            background-color: #262626;
            color: #ffffff;
        }
        
        dialog label {
            color: #ffffff;
        }
        
        #color-dialog-buttons button {
            background-color: rgba(0, 0, 0, 0.2);
            color: #ffffff;
            border: none;
        }
        
        #color-dialog-buttons button:hover {
            background-color: rgba(37, 165, 106, 0.3);
        }
    });
    
    my $style_context = $dialog->get_style_context();
    $style_context->add_provider($css_provider, Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION);
    
    my $action_area = $dialog->get_action_area();
    $action_area->set_name("color-dialog-buttons");
    
    $dialog->show_all();
    
    my $response = $dialog->run();
    if ($response eq 'ok') {

        my $rgba = $color_button->get_rgba();
        my $r = int($rgba->red * 255);
        my $g = int($rgba->green * 255);
        my $b = int($rgba->blue * 255);
        
        my $hex_color = sprintf("#%02x%02x%02x", $r, $g, $b);
        
        my $colors = $self->theme_colors;
        $colors->{accent} = $hex_color;
        $self->theme_colors($colors);
        
        $self->apply_accent_color($hex_color);
        
        $self->app->log_message('info', "Accent color changed to $hex_color");
    }
    
    $self->save_config();
    
    $dialog->destroy();
}

sub apply_accent_color {
    my ($self, $accent_color) = @_;
    
    my $colors = $self->theme_colors;
    $colors->{accent} = $accent_color;
    $self->theme_colors($colors);
    
    if ($self->{main_window}) {
        $self->{main_window}->queue_draw();
    }
    
    my $provider = Gtk3::CssProvider->new();
    
    # Parse the accent color for rgba calculations
    my $r = 0;
    my $g = 0;
    my $b = 0;
    
    if ($accent_color =~ /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i) {
        $r = hex($1) / 255;
        $g = hex($2) / 255;
        $b = hex($3) / 255;
    }
    
    # Use the new accent color everywhere, not the default green
    my $css = qq{
        button {
            background-color: rgba(0, 0, 0, 0);
            color: #ffffff;
            border: none;
            border-radius: 0px;
        }
        
        button.hover {
            border: 1px solid $accent_color;
            background-color: rgba(0, 0, 0, 0);
        }
        
        button:active {
            background-color: rgba($r, $g, $b, 0.3);
        }
        
        /* Header buttons get different hover effect */
        .header-button.hover {
            background-color: rgba($r, $g, $b, 0.3);
            border: none;
        }
        
        .header-button:active {
            background-color: rgba($r, $g, $b, 0.5);
        }
    };
    
    my $screen = Gtk3::Gdk::Screen::get_default();
    
    if (defined $self->{accent_provider}) {
        eval {
            Gtk3::StyleContext::remove_provider_for_screen($screen, $self->{accent_provider});
        };
    }
    
    eval {
        $provider->load_from_data($css);
        
        Gtk3::StyleContext::add_provider_for_screen(
            $screen,
            $provider,
            Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION
        );
        
        $self->{accent_provider} = $provider;
    };
    
    if ($@) {
        $self->app->log_message('error', "Failed to apply accent color: $@");
    }
}


sub get_color_from_button {
    my ($self, $button) = @_;
    
    my $rgba = $button->get_rgba();
    my $r = int($rgba->red * 255);
    my $g = int($rgba->green * 255);
    my $b = int($rgba->blue * 255);
    
    return sprintf("#%02x%02x%02x", $r, $g, $b);
}


sub hex_to_rgba {
    my ($self, $hex) = @_;
    
    $hex = '#f0f0f0' unless defined $hex && $hex =~ /^#[0-9A-Fa-f]{6}$/;
    
    $hex =~ s/^#//;
    
    my $r = hex(substr($hex, 0, 2)) / 255;
    my $g = hex(substr($hex, 2, 2)) / 255;
    my $b = hex(substr($hex, 4, 2)) / 255;
    
    my $rgba = Gtk3::Gdk::RGBA->new();
    $rgba->parse("rgb($r,$g,$b)");
    
    return $rgba;
}


sub rgba_to_hex {
    my ($self, $rgba) = @_;
    
    my $r = int($rgba->red * 255);
    my $g = int($rgba->green * 255);
    my $b = int($rgba->blue * 255);
    
    return sprintf("#%02x%02x%02x", $r, $g, $b);
}


sub update_color_preview {
    my ($self, $preview_button, $bg_button, $fg_button, $accent_button) = @_;
    
    my $bg = $self->get_color_from_button($bg_button);
    my $fg = $self->get_color_from_button($fg_button);
    my $accent = $self->get_color_from_button($accent_button);
    
    my $provider = Gtk3::CssProvider->new();
    my $css = qq{
        button {
            background-color: $bg;
            color: $fg;
            border: 1px solid $accent;
        }
        
        button:hover {
            background-color: $accent;
            color: white;
        }
    };
    
    eval {
        $provider->load_from_data($css);
        my $style_context = $preview_button->get_style_context();
        
        if ($preview_button->{css_provider}) {
            $style_context->remove_provider($preview_button->{css_provider});
        }
        
        $style_context->add_provider($provider, 600);
        $preview_button->{css_provider} = $provider;
    };
    
    if ($@) {
        $self->app->log_message('error', "Failed to update preview: $@");
    }
}


sub apply_color_theme {
    my ($self, $theme_name) = @_;
    
    $theme_name = 'system' if !defined $theme_name;
    
    $self->{current_theme} = 'system' if !defined $self->{current_theme};
    
    if ($theme_name eq 'default' || $theme_name eq 'system') {
       
        if ($self->{current_theme} eq 'system') {
            return;
        }
        
        my $screen = Gtk3::Gdk::Screen::get_default();
        Gtk3::StyleContext::remove_provider_for_screen($screen, $self->{css_provider})
            if defined $self->{css_provider};
        
        $self->{css_provider} = undef;
        $self->{current_theme} = 'system';
        $self->app->log_message('info', "Reset to system theme");
        return;
    }
    
    $self->app->log_message('info', "Applying color theme");
    
    my $provider = Gtk3::CssProvider->new();
    
    my $css = qq{
        window.background, dialog.background {
            background-color: ${\$self->theme_colors->{background}};
        }
        
        label {
            color: ${\$self->theme_colors->{foreground}};
        }
        
        button {
            background-color: rgba(0, 0, 0, 0);
            color: ${\$self->theme_colors->{foreground}};
            border: none;
        }
        
        button.hover {
            border: 1px solid ${\$self->theme_colors->{accent}};
        }
        
        /* Header buttons get different hover effect */
        .header-button.hover {
            background-color: rgba(37, 165, 106, 0.3);
            border: none;
        }
    };
    
    my $screen = Gtk3::Gdk::Screen::get_default();
    if (defined $self->{css_provider}) {
        Gtk3::StyleContext::remove_provider_for_screen($screen, $self->{css_provider});
    }
    
    eval {
        $provider->load_from_data($css);
        
        Gtk3::StyleContext::add_provider_for_screen(
            $screen,
            $provider,
            600 
        );
        
        $self->{css_provider} = $provider;
    };
    
    if ($@) {
        $self->app->log_message('error', "Failed to apply CSS theme: $@");
    }
    
    $self->{current_theme} = $theme_name;
}


sub select_other_location {
    my ($self) = @_;
    
    my $dialog = Gtk3::FileChooserDialog->new(
        "Select Save Location",
        $self->{main_window},
        'select-folder',
        'Cancel' => 'cancel',
        'Select' => 'ok'
    );
    
    $dialog->set_current_folder($self->config->last_saved_dir);
    
    if ($dialog->run() eq 'ok') {
        my $location = $dialog->get_filename();
        $self->config->save_location($location);
        $self->config->last_saved_dir($location);
    }
    
    $dialog->destroy();
}


sub show_floating_thumbnail {
    my ($self, $pixbuf, $temp_filepath) = @_;
    
    my ($thumb_w, $thumb_h) = (800, 600);
    
    my $orig_w = $pixbuf->get_width();
    my $orig_h = $pixbuf->get_height();
    my $ratio = $orig_w / $orig_h;
    
    if ($ratio > 1) {
        # Landscape
        $thumb_w = 800;
        $thumb_h = int(800 / $ratio);
    } else {
        # Portrait
        $thumb_h = 600;
        $thumb_w = int(600 * $ratio);
    }
    
    my $thumbnail = $pixbuf->scale_simple($thumb_w, $thumb_h, 'bilinear');
    
    my $thumb_window = Gtk3::Window->new('toplevel');
    $thumb_window->set_position('center');
    $thumb_window->set_title("Screenshot Preview");
    $thumb_window->set_decorated(TRUE);
    $thumb_window->set_border_width(10);
    $thumb_window->set_resizable(FALSE);

    my $vbox = Gtk3::Box->new('vertical', 10);
    $thumb_window->add($vbox);
    
    my $button_box = Gtk3::Box->new('horizontal', 10);
    $vbox->pack_start($button_box, FALSE, FALSE, 0);
    
    my $cancel_button = Gtk3::Button->new_with_label("Cancel");
    $cancel_button->signal_connect('clicked' => sub {
        $thumb_window->destroy();
    });
    $button_box->pack_start($cancel_button, FALSE, FALSE, 0);
    
    my $spacer = Gtk3::Box->new('horizontal', 0);
    $button_box->pack_start($spacer, TRUE, TRUE, 0);
    
    my @time = localtime();
    my $timestamp = sprintf(
        "%04d-%02d-%02d-%02d-%02d-%02d",
        $time[5] + 1900,  # year
        $time[4] + 1,     # month
        $time[3],         # day
        $time[2],         # hour
        $time[1],         # minute
        $time[0]          # second
    );

    my $format = $self->app->config->image_format || "jpg";
    my $default_filename = "Screenshot from $timestamp.$format";
    
    my $filename_entry = Gtk3::Entry->new();
    $filename_entry->set_text($default_filename);
    $filename_entry->set_editable(TRUE);
    
    my $location_combo = Gtk3::ComboBoxText->new();
    
    my $pictures_dir = "$ENV{HOME}/Pictures";
    my $desktop_dir = "$ENV{HOME}/Desktop";
    
    eval {
        my $xdg_pictures = `xdg-user-dir PICTURES`;
        chomp($xdg_pictures);
        $pictures_dir = $xdg_pictures if $xdg_pictures && -d $xdg_pictures;
        
        my $xdg_desktop = `xdg-user-dir DESKTOP`;
        chomp($xdg_desktop);
        $desktop_dir = $xdg_desktop if $xdg_desktop && -d $xdg_desktop;
    };
    
    $location_combo->append_text($pictures_dir);
    $location_combo->append_text($desktop_dir);
    $location_combo->append_text("Other...");
    
    if ($self->app->config->save_location ne "clipboard" &&
        $self->app->config->save_location ne $pictures_dir &&
        $self->app->config->save_location ne $desktop_dir) {
        $location_combo->append_text($self->app->config->save_location);
    }
    
    my $active_index = 0; 
    if ($self->app->config->save_location eq $desktop_dir) {
        $active_index = 1;
    } elsif ($self->app->config->save_location ne "clipboard" &&
             $self->app->config->save_location ne $pictures_dir &&
             $self->app->config->save_location ne $desktop_dir) {
        $active_index = 3;
    }
    $location_combo->set_active($active_index);
    
    $location_combo->signal_connect('changed' => sub {
        my $selected = $location_combo->get_active_text();
        if ($selected eq "Other...") {
            my $dialog = Gtk3::FileChooserDialog->new(
                "Select Folder",
                $thumb_window,
                'select-folder',
                'Cancel' => 'cancel',
                'Select' => 'ok'
            );
            
            if ($self->app->config->save_location ne "clipboard") {
                $dialog->set_current_folder($self->app->config->save_location);
            } else {
                $dialog->set_current_folder($pictures_dir);
            }
            
            if ($dialog->run() eq 'ok') {
                my $chosen_dir = $dialog->get_filename();
                
                $location_combo->remove(2);
                
                my $found = 0;
                for (my $i = 0; $i < $location_combo->get_model()->iter_n_children(undef); $i++) {
                    if ($location_combo->get_active_text() eq $chosen_dir) {
                        $found = 1;
                        $location_combo->set_active($i);
                        last;
                    }
                }
                
                if (!$found) {
                    $location_combo->append_text($chosen_dir);
                    $location_combo->set_active($location_combo->get_model()->iter_n_children(undef) - 1);
                }
                
                $location_combo->append_text("Other...");
            } else {
               
                $location_combo->set_active($active_index);
            }
            
            $dialog->destroy();
        }
    });
    
    my $copy_button = Gtk3::Button->new_with_label("Copy to Clipboard");
    $copy_button->signal_connect('clicked' => sub {
        my $clipboard = Gtk3::Clipboard::get(Gtk3::Gdk::Atom::intern('CLIPBOARD', FALSE));
        $clipboard->set_image($pixbuf);
        $self->app->log_message('info', "Screenshot copied to clipboard");
        $thumb_window->destroy();
    });
    $button_box->pack_start($copy_button, FALSE, FALSE, 0);
    
    my $open_button = Gtk3::Button->new_with_label("Open/Edit");
    $open_button->signal_connect('clicked' => sub {
    
        my $temp_dir = $ENV{TMPDIR} || $ENV{TMP} || '/tmp';
        my $format = $self->app->config->image_format || 'jpg';
        my $temp_file = "$temp_dir/screenshot-temp-$timestamp.$format";
        
        eval {
         
            my $format_string = ($format eq 'jpg') ? 'jpeg' : $format;
            if ($format_string eq 'jpeg' || $format_string eq 'webp') {
                $pixbuf->savev($temp_file, $format_string, ['quality'], ['100']);
            } elsif ($format_string eq 'avif' && $self->app->config->avif_supported) {
                $pixbuf->savev($temp_file, $format_string, ['quality'], ['100']);
            } else {
                $pixbuf->savev($temp_file, $format_string, [], []);
            }

            $self->app->log_message('info', "Saved temporary file for editing: $temp_file");
            
            $thumb_window->set_keep_above(FALSE);
            
            system("xdg-open", $temp_file);
        };
        
        if ($@) {
            $self->app->log_message('error', "Error opening image for editing: $@");
        }
    });
    $button_box->pack_start($open_button, FALSE, FALSE, 0);
    
    my $save_button = Gtk3::Button->new_with_label("Save");
    $save_button->signal_connect('clicked' => sub {
        my $selected_filename = $filename_entry->get_text();
        my $selected_location = $location_combo->get_active_text();
        
        if ($selected_location eq "Other...") {
       
            my $dialog = Gtk3::FileChooserDialog->new(
                "Save Screenshot",
                $thumb_window,
                'select-folder',
                'Cancel' => 'cancel',
                'Save' => 'ok'
            );
            
            $dialog->set_current_folder($pictures_dir);
            
            if ($dialog->run() eq 'ok') {
                $selected_location = $dialog->get_filename();
                $self->save_screenshot_from_preview($pixbuf, $selected_filename, $selected_location);
                $thumb_window->destroy();
            }
            
            $dialog->destroy();
        } else {
            $self->save_screenshot_from_preview($pixbuf, $selected_filename, $selected_location);
            $thumb_window->destroy();
        }
    });
    $button_box->pack_end($save_button, FALSE, FALSE, 0);
    
    my $image = Gtk3::Image->new_from_pixbuf($thumbnail);
    $vbox->pack_start($image, TRUE, TRUE, 0);

    my $bottom_box = Gtk3::Box->new('vertical', 10);
    $vbox->pack_start($bottom_box, FALSE, FALSE, 0);
    
    my $filename_box = Gtk3::Box->new('horizontal', 5);
    $bottom_box->pack_start($filename_box, FALSE, FALSE, 0);
    
    my $filename_label = Gtk3::Label->new("Name:");
    $filename_box->pack_start($filename_label, FALSE, FALSE, 0);
    
    $filename_box->pack_start($filename_entry, TRUE, TRUE, 0);
    
    my $folder_box = Gtk3::Box->new('horizontal', 5);
    $bottom_box->pack_start($folder_box, FALSE, FALSE, 0);
    
    my $folder_label = Gtk3::Label->new("Folder:");
    $folder_box->pack_start($folder_label, FALSE, FALSE, 0);
    
    $folder_box->pack_start($location_combo, TRUE, TRUE, 0);
    
    $thumb_window->show_all();
}

# Save screenshot from preview
sub save_screenshot_from_preview {
    my ($self, $pixbuf, $filename, $location) = @_;
    
    my $format = $self->app->config->image_format || 'jpg';
    
    if ($filename =~ /\.(\w+)$/) {
        $format = lc($1);
    } else {
        $filename .= ".$format";
    }
    
    if (!-d $location) {
        make_path($location);
    }
    
    my $filepath = File::Spec->catfile($location, $filename);
    
    $self->app->log_message('info', "Saving screenshot to: $filepath");
    
    eval {
        my $format_string;
        if ($format eq "jpg") {
            $format_string = "jpeg";
        } elsif ($format eq "webp") {
            $format_string = "webp";
        } elsif ($format eq "avif" && $self->app->config->avif_supported) {
            $format_string = "avif";
        } else {
            $format_string = $format;
        }
        
        if ($format_string eq "jpeg") {
            $pixbuf->savev($filepath, $format_string, ['quality'], ['100']);
        } elsif ($format_string eq "webp") {
            $pixbuf->savev($filepath, $format_string, ['quality'], ['100']);
        } elsif ($format_string eq "avif") {
            $pixbuf->savev($filepath, $format_string, ['quality'], ['100']);
        } else {
            $pixbuf->savev($filepath, $format_string, [], []);
        }
        
        $self->app->log_message('info', "Screenshot saved successfully to $filepath");
        
        $self->app->config->save_location($location);
        
        $self->app->capture_manager->generate_thumbnail($pixbuf, $filepath);
    };
    
    if ($@) {
        $self->app->log_message('error', "Error saving screenshot: $@");
        
        if ($format ne "png") {
            eval {
                my $png_path = $filepath;
                $png_path =~ s/\.\w+$/.png/;
                $self->app->log_message('info', "Attempting to save as PNG instead: $png_path");
                $pixbuf->save($png_path, "png");
                $self->app->log_message('info', "Screenshot saved as PNG successfully");
                
                $self->app->capture_manager->generate_thumbnail($pixbuf, $png_path);
            };
            if ($@) {
                $self->app->log_message('error', "Critical error: Could not save screenshot: $@");
            }
        } else {
            $self->app->log_message('error', "Critical error: Could not save screenshot: $@");
        }
    }
}

sub load_config {
    my ($self) = @_;
    
    # Define config file path
    my $config_dir = "$ENV{HOME}/.local/share/perl-screenshot-tool/config";
    my $config_file = "$config_dir/settings.json";
    
    # Remember current icon size if we're in the middle of resizing
    my $override_icon_size;
    if ($self->{changing_icon_size}) {
        $override_icon_size = $self->current_icon_size;
        $self->app->log_message('info', "Preserving current icon size during resize: $override_icon_size");
    }
    
    # If the config file doesn't exist yet, return
    if (!-f $config_file) {
        $self->app->log_message('info', "Config file doesn't exist yet");
        return 0;
    }
    
    # Load the config file
    eval {
        require JSON;
        
        open my $fh, '<', $config_file or die "Cannot open config file: $!";
        my $json_data = do { local $/; <$fh> };
        close $fh;
        
        # Make sure we have data
        if (!$json_data || $json_data =~ /^\s*$/) {
            $self->app->log_message('warning', "Config file is empty");
            return 0;
        }
        
        my $config = JSON::decode_json($json_data);
        
        # Update settings from the loaded config
        if (defined $config->{theme_colors} && ref $config->{theme_colors} eq 'HASH') {
            $self->theme_colors($config->{theme_colors});
        }
        
        # Only load icon size if we're not in the middle of changing it
        if (!$self->{changing_icon_size}) {
            if (defined $config->{current_icon_size} && $config->{current_icon_size} =~ /^\d+$/) {
                $self->app->log_message('info', "Loading saved icon size: $config->{current_icon_size}");
                $self->current_icon_size($config->{current_icon_size});
            }
        } elsif (defined $override_icon_size) {
            # Restore the override size we saved earlier
            $self->app->log_message('info', "Restoring current icon size after config load: $override_icon_size");
            $self->current_icon_size($override_icon_size);
        }
        
        # Load app configuration if available
        if (defined $config->{app_config} && ref $config->{app_config} eq 'HASH') {
            my $app_config = $self->app->config;
            
            # Update each available config option
            foreach my $key (keys %{$config->{app_config}}) {
                if ($app_config->can($key)) {
                    $app_config->$key($config->{app_config}->{$key});
                }
            }
        }
        
        $self->app->log_message('info', "Configuration loaded successfully");
    };
    
    if ($@) {
        $self->app->log_message('error', "Failed to load configuration: $@");
        return 0;
    }
    
    return 1;
}

sub save_config {
    my ($self) = @_;
    
    # Define config file path
    my $config_dir = "$ENV{HOME}/.local/share/perl-screenshot-tool/config";
    my $config_file = "$config_dir/settings.json";
    
    # Ensure the config directory exists
    if (!-d $config_dir) {
        $self->app->log_message('info', "Creating config directory: $config_dir");
        eval {
            require File::Path;
            File::Path::make_path($config_dir, {
                mode => 0755
            });
        };
        if ($@) {
            $self->app->log_message('error', "Failed to create config directory: $@");
            return 0;
        }
    }
    
    # Gather current settings into a configuration hash
    my $config = {
        theme_colors => $self->theme_colors,
        current_icon_size => $self->current_icon_size,  # Make sure this is included
        app_config => {}
    };
    
    # Add app configuration options
    my $app_config = $self->app->config;
    foreach my $method (qw(
        selection_mode timer_value image_format show_floating_thumbnail
        remember_last_selection show_mouse_pointer capture_window_decoration
        allow_self_capture 
    )) {
        if ($app_config->can($method)) {
            $config->{app_config}->{$method} = $app_config->$method();
        }
    }
    
    # Add save_location separately to handle potential special values
    if ($app_config->can('save_location')) {
        my $save_location = $app_config->save_location();
        if (defined $save_location) {
            $config->{app_config}->{save_location} = $save_location;
        }
    }
    
    # Save the configuration to file
    eval {
        require JSON;
        
        # Create JSON with clean formatting
        my $json_data = JSON::encode_json($config);
        
        open my $fh, '>', $config_file or die "Cannot open config file for writing: $!";
        print $fh $json_data;
        close $fh;
        
        $self->app->log_message('info', "Configuration saved to $config_file");
    };
    
    if ($@) {
        $self->app->log_message('error', "Failed to save configuration: $@");
        return 0;
    }
    
    return 1;
}

# Cancel all timeouts
sub cancel_all_timeouts {
    my ($self) = @_;
    
    if ($self->active_timeouts && @{$self->active_timeouts}) {
      
        my $old_handler = $SIG{__WARN__};
        local $SIG{__WARN__} = sub {
           
            unless ($_[0] =~ /GLib-CRITICAL.*Source ID.*not found/) {
                $old_handler->(@_) if $old_handler;
            }
        };
        
        foreach my $source_id (@{$self->active_timeouts}) {
         
            if ($source_id) {
                eval {
                    Glib::Source->remove($source_id);
                };
            }
        }
        
        $self->active_timeouts([]);
    }
}

1;
