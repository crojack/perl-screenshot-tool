package ScreenshotTool::UI;

use strict;
use warnings;
use Moo;
use Gtk3 qw(-init);
use Glib qw(TRUE FALSE);
use Cairo;
use POSIX qw(strftime);
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
        'background' => '#184752', 
        'foreground' => '#ffffff',  
        'accent'     => '#145867'   
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


sub show_main_window {
    my ($self) = @_;
    

    $self->is_quitting(0);
    

    $self->{main_window} = Gtk3::Window->new('toplevel');
    $self->{main_window}->set_title($self->app->app_name);
    $self->{main_window}->set_resizable(FALSE);
    if ($self->app->window_system =~ /^wayland/) {
     
        $self->{main_window}->set_gravity('south');
    } else {
        $self->{main_window}->set_position('center');
    }
    
    $self->{main_window}->set_border_width(10);

    $self->app->log_message('debug', "Initializing keyboard shortcuts manager");
    require ScreenshotTool::KeyboardShortcuts;
    my $shortcuts = ScreenshotTool::KeyboardShortcuts->new(app => $self->app);
    $shortcuts->initialize();
    $self->{shortcuts_manager} = $shortcuts;

    $self->{main_window}->signal_connect('delete-event' => sub {
        my ($widget, $event) = @_;
        $self->app->log_message('debug', "Delete event received on main window");
        
        $self->is_quitting(1);

        $self->cancel_all_timeouts();
        
        Gtk3::main_iteration() while Gtk3::events_pending();
        
        $self->app->log_message('debug', "Calling Gtk3->main_quit()");
        Gtk3->main_quit();
        
        return FALSE;
    });
    
    if ($self->app->window_system =~ /^wayland/) {
        $self->{main_window}->set_type_hint('dock');
    }

    if ($self->app->window_system ne 'wayland') {
        $self->{main_window}->signal_connect('button-press-event' => sub {
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
    }
    
    my $main_box = Gtk3::Box->new('horizontal', 10);
    $self->{main_window}->add($main_box);

    my $window_button = $self->create_button('window', 'Window', sub { 
        $self->config->selection_mode(0);
        $self->hide_main_window_completely();
        
        my $capture_manager = $self->app->capture_manager;
        
        Glib::Timeout->add(200, sub {
            $capture_manager->start_capture();
            return FALSE; 
        });
    });
    $main_box->pack_start($window_button, FALSE, FALSE, 0);
    
    my $region_button = $self->create_button('region', 'Region', sub { 
        $self->config->selection_mode(1);
        $self->hide_main_window_completely();
        
        my $capture_manager = $self->app->capture_manager;
        
        Glib::Timeout->add(200, sub {
            $capture_manager->start_capture();
            return FALSE; 
        });
    });
    $main_box->pack_start($region_button, FALSE, FALSE, 0);
    
    my $fullscreen_button = $self->create_button('desktop', 'Desktop', sub { 
        $self->config->selection_mode(2);
        $self->hide_main_window_completely();
        
        my $capture_manager = $self->app->capture_manager;
        
        Glib::Timeout->add(200, sub {
            $capture_manager->start_capture();
            return FALSE;
        });
    });
    $main_box->pack_start($fullscreen_button, FALSE, FALSE, 0);
    
    my $options_button = $self->create_button('settings', 'Options', undef);
    $options_button->signal_connect('clicked' => sub {
        $self->show_options_menu($options_button);
    });
    $main_box->pack_start($options_button, FALSE, FALSE, 0);

    my $appearance_button = $self->create_button('appearance', 'Interface', undef);
    $appearance_button->signal_connect('clicked' => sub {
        $self->show_appearance_menu($appearance_button);
    });
    $main_box->pack_start($appearance_button, FALSE, FALSE, 0);
    
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
    $button->set_size_request(60, 60); 
    
    my $button_box = Gtk3::Box->new('vertical', 5);
    $button_box->set_homogeneous(FALSE);
    $button->add($button_box);
    
    my $icon = $self->get_button_icon($icon_name);
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
  
    $button->set_size_request(40, 40);
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
    
    $icon->set_pixel_size(40); 
    $button->add($icon);
    
    return $button;
}

sub get_button_icon {
    my ($self, $icon_name) = @_;
    
    my $cache_key = "${icon_name}_" . $self->current_icon_size;
    
    if (exists $self->{icon_cache}{$cache_key}) {
        return $self->{icon_cache}{$cache_key};
    }
    
    my $icon;
    
    my $icon_path = $self->get_icon_path($icon_name);
    if ($icon_path && -f $icon_path) {
        $icon = Gtk3::Image->new_from_file($icon_path);
        
        $self->{icon_cache}{$cache_key} = $icon;
        return $icon;
    }
    
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
    }
    
    if (!$icon) {
        $icon = Gtk3::Image->new_from_icon_name($icon_name, 'dialog');
    }
    
    if (!$icon) {
        $icon = Gtk3::Image->new_from_icon_name('image-missing', 'dialog');
    }
    
    $self->{icon_cache}{$cache_key} = $icon;
    return $icon;
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
            
            # Make sure the position is correctly applied
            while (Gtk3::events_pending()) {
                Gtk3::main_iteration();
            }
            
            # Apply position a second time to ensure it sticks
            $self->{main_window}->move($self->last_window_x, $self->last_window_y);
        } else {
            # Fall back to the old centering method if we don't have a saved position
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
                $window_width = 350;  
                $window_height = 80; 
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
                
                my $window_width = 350; 
                my $window_height = 80; 
                
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
    
    $self->app->log_message('info', "Changing icon size to ${size}x${size}");
    
    $self->current_icon_size($size);
    
    $self->{icon_cache} = {};
    
    if ($self->{main_window}) {
        
        my ($current_x, $current_y) = $self->{main_window}->get_position();
        
        my $window_system = $self->app->window_system;
        
        my $old_window = $self->{main_window};
        $self->{main_window} = undef;
        $self->show_main_window();
        
        if ($window_system eq 'xorg') {
          
            $self->{main_window}->move($current_x, $current_y);
            
            while (Gtk3::events_pending()) {
                Gtk3::main_iteration();
            }
        }
        
        $old_window->destroy() if $old_window;
    }
}


sub get_icon_path {
    my ($self, $icon_name) = @_;
    
    my $size = $self->current_icon_size;
    my $size_dir = "${size}x${size}";
    
    my $base_dir = $self->config->custom_icons_dir;
    $base_dir =~ s|/share/icons$|/share|;
    
    my $icon_path = "$base_dir/icons/$size_dir/$icon_name.svg";
    if (-f $icon_path) {
        return $icon_path;
    }
    
    $icon_path = "$base_dir/icons/$icon_name.svg";
    if (-f $icon_path) {
        return $icon_path;
    }
    
    return undef;
}


sub show_color_picker {
    my ($self) = @_;
    
    $self->app->log_message('info', "Opening color theme picker");
    
    my $dialog = Gtk3::Dialog->new(
        "Custom Color Theme",
        $self->{main_window},
        'modal',
        'Close' => 'close'
    );
    
    $dialog->set_default_size(400, 250);
    
    my $content_area = $dialog->get_content_area();
    $content_area->set_border_width(15);
    
    my $grid = Gtk3::Grid->new();
    $grid->set_row_spacing(12);
    $grid->set_column_spacing(10);
    $content_area->add($grid);
    
    my $bg_label = Gtk3::Label->new("Background:");
    $bg_label->set_halign('start');
    $grid->attach($bg_label, 0, 0, 1, 1);
    
    my $bg_button = Gtk3::ColorButton->new();
    $bg_button->set_size_request(40, 40); 
    
    eval {
        my $rgba = Gtk3::Gdk::RGBA->new();
        $rgba->parse($self->theme_colors->{background} || '#f0f0f0');
        $bg_button->set_rgba($rgba);
    };
    if ($@) {
        $self->app->log_message('warning', "Failed to set background color: $@");
    }
    
    $grid->attach($bg_button, 1, 0, 1, 1);
    
    my $bg_apply = Gtk3::Button->new_with_label("Apply");
    $grid->attach($bg_apply, 2, 0, 1, 1);
    
    $bg_apply->signal_connect('clicked' => sub {
        my $color = $self->get_color_from_button($bg_button);
        my $colors = $self->theme_colors;
        $colors->{background} = $color;
        $self->theme_colors($colors);
        $self->apply_color_theme('custom');
    });
    
    my $fg_label = Gtk3::Label->new("Text:");
    $fg_label->set_halign('start');
    $grid->attach($fg_label, 0, 1, 1, 1);
    
    my $fg_button = Gtk3::ColorButton->new();
    $fg_button->set_size_request(40, 40);
    
    eval {
        my $rgba = Gtk3::Gdk::RGBA->new();
        $rgba->parse($self->theme_colors->{foreground} || '#333333');
        $fg_button->set_rgba($rgba);
    };
    if ($@) {
        $self->app->log_message('warning', "Failed to set text color: $@");
    }
    
    $grid->attach($fg_button, 1, 1, 1, 1);
    
    my $fg_apply = Gtk3::Button->new_with_label("Apply");
    $grid->attach($fg_apply, 2, 1, 1, 1);
    
    $fg_apply->signal_connect('clicked' => sub {
        my $color = $self->get_color_from_button($fg_button);
        my $colors = $self->theme_colors;
        $colors->{foreground} = $color;
        $self->theme_colors($colors);
        $self->apply_color_theme('custom');
    });
    
    my $accent_label = Gtk3::Label->new("Accent:");
    $accent_label->set_halign('start');
    $grid->attach($accent_label, 0, 2, 1, 1);
    
    my $accent_button = Gtk3::ColorButton->new();
    $accent_button->set_size_request(40, 40);
    
    eval {
        my $rgba = Gtk3::Gdk::RGBA->new();
        $rgba->parse($self->theme_colors->{accent} || '#0066cc');
        $accent_button->set_rgba($rgba);
    };
    if ($@) {
        $self->app->log_message('warning', "Failed to set accent color: $@");
    }
    
    $grid->attach($accent_button, 1, 2, 1, 1);
    
    my $accent_apply = Gtk3::Button->new_with_label("Apply");
    $grid->attach($accent_apply, 2, 2, 1, 1);
    
    $accent_apply->signal_connect('clicked' => sub {
        my $color = $self->get_color_from_button($accent_button);
        my $colors = $self->theme_colors;
        $colors->{accent} = $color;
        $self->theme_colors($colors);
        $self->apply_color_theme('custom');
    });
    
    my $preview_label = Gtk3::Label->new("Preview:");
    $preview_label->set_halign('start');
    $grid->attach($preview_label, 0, 3, 1, 1);
    
    my $preview_button = Gtk3::Button->new_with_label("Button Preview");
    $grid->attach($preview_button, 1, 3, 2, 1);
    
    my $apply_all = Gtk3::Button->new_with_label("Apply All");
    $apply_all->set_margin_top(15);
    $grid->attach($apply_all, 0, 4, 3, 1);
    
    $apply_all->signal_connect('clicked' => sub {
        my $bg_color = $self->get_color_from_button($bg_button);
        my $fg_color = $self->get_color_from_button($fg_button);
        my $accent_color = $self->get_color_from_button($accent_button);
        
        my $colors = {
            background => $bg_color,
            foreground => $fg_color,
            accent => $accent_color
        };
        
        $self->theme_colors($colors);
        $self->apply_color_theme('custom');
    });
    
    my $reset_button = Gtk3::Button->new_with_label("Reset to System Theme");
    $reset_button->set_margin_top(5);
    $grid->attach($reset_button, 0, 5, 3, 1);

    $reset_button->signal_connect('clicked' => sub {

        my $default_colors = {
            'background' => '#21444c',
            'foreground' => '#ffffff',
            'accent'     => '#3a6570'
        };
        
        $self->theme_colors($default_colors);
        
        my $bg_rgba = Gtk3::Gdk::RGBA->new();
        $bg_rgba->parse($default_colors->{background});
        $bg_button->set_rgba($bg_rgba);
        
        my $fg_rgba = Gtk3::Gdk::RGBA->new();
        $fg_rgba->parse($default_colors->{foreground});
        $fg_button->set_rgba($fg_rgba);
        
        my $accent_rgba = Gtk3::Gdk::RGBA->new();
        $accent_rgba->parse($default_colors->{accent});
        $accent_button->set_rgba($accent_rgba);
        
        $self->apply_color_theme('default');
        
        $self->update_color_preview($preview_button, $bg_button, $fg_button, $accent_button);
    });
    
    my $update_preview = sub {
        $self->update_color_preview($preview_button, $bg_button, $fg_button, $accent_button);
    };
    
    $bg_button->signal_connect('color-set' => $update_preview);
    $fg_button->signal_connect('color-set' => $update_preview);
    $accent_button->signal_connect('color-set' => $update_preview);
    
    $dialog->show_all();
    
    $update_preview->();
    
    $dialog->run();
    $dialog->destroy();
}


sub get_system_theme_colors {
    my ($self) = @_;
    
    my $colors = {
        'background' => '#21444c',
        'foreground' => '#ffffff',
        'accent'     => '#3a6570'
    };
    
    eval {

        my $temp_window = Gtk3::Window->new('toplevel');
        
        my $temp_button = Gtk3::Button->new_with_label("Test");
        $temp_window->add($temp_button);
        
        $temp_window->set_opacity(0);
        $temp_window->set_position('center');
        $temp_window->set_decorated(FALSE);
        $temp_window->set_default_size(1, 1);
        $temp_window->show_all();
        
        my $button_context = $temp_button->get_style_context();
        
        while (Gtk3::events_pending()) {
            Gtk3::main_iteration();
        }
        
        my $bg_color = $button_context->get_background_color('normal');
        if ($bg_color) {
            $colors->{background} = $self->rgba_to_hex($bg_color);
        }
        
        my $fg_color = $button_context->get_color('normal');
        if ($fg_color) {
            $colors->{foreground} = $self->rgba_to_hex($fg_color);
        }
        
        $temp_window->remove($temp_button);
        my $temp_label = Gtk3::Label->new("Link");
        $temp_label->set_markup("<a href='#'>Link</a>");
        $temp_window->add($temp_label);
        $temp_window->show_all();
        
        while (Gtk3::events_pending()) {
            Gtk3::main_iteration();
        }
        
        my $label_context = $temp_label->get_style_context();
        my $accent_color = $label_context->get_color('link');
        
        if ($accent_color) {
            $colors->{accent} = $self->rgba_to_hex($accent_color);
        }
        
        $temp_window->destroy();
    };
    
    if ($@) {
        $self->app->log_message('warning', "Error getting system theme colors: $@");
    }
    
    return $colors;
}


sub update_color_preview {
    my ($self, $preview_button, $bg_button, $fg_button, $accent_button) = @_;
    
    my $bg = $self->get_color_from_button($bg_button);
    my $fg = $self->get_color_from_button($fg_button);
    my $accent = $self->get_color_from_button($accent_button);
    
    my $bg_hex = $bg;
    $bg_hex =~ s/^#//;
    my $r = hex(substr($bg_hex, 0, 2));
    my $g = hex(substr($bg_hex, 2, 2));
    my $b = hex(substr($bg_hex, 4, 2));
    
    $r = ($r + 20 > 255) ? 255 : $r + 20;
    $g = ($g + 20 > 255) ? 255 : $g + 20;
    $b = ($b + 20 > 255) ? 255 : $b + 20;
    
    my $lighter_bg = sprintf("#%02x%02x%02x", $r, $g, $b);
    
    my $provider = Gtk3::CssProvider->new();
    my $css = qq{
        button {
            background-color: $lighter_bg;
            color: $fg;
            border-color: $accent;
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
    
    my $bg_hex = $self->theme_colors->{background};
    $bg_hex =~ s/^#//;
    my $r = hex(substr($bg_hex, 0, 2));
    my $g = hex(substr($bg_hex, 2, 2));
    my $b = hex(substr($bg_hex, 4, 2));
    
    $r = ($r + 20 > 255) ? 255 : $r + 20;
    $g = ($g + 20 > 255) ? 255 : $g + 20;
    $b = ($b + 20 > 255) ? 255 : $b + 20;
    
    my $lighter_bg = sprintf("#%02x%02x%02x", $r, $g, $b);
    
    my $css = qq{
        window.background, dialog.background {
            background-color: ${\$self->theme_colors->{background}};
        }
        
        label {
            color: ${\$self->theme_colors->{foreground}};
        }
        
        button {
            background-color: $lighter_bg;
            color: ${\$self->theme_colors->{foreground}};
            border-color: ${\$self->theme_colors->{accent}};
        }
        
        button:hover {
            background-color: ${\$self->theme_colors->{accent}};
            color: white;
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
    
    # Calculate thumbnail dimensions (keeping aspect ratio)
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


