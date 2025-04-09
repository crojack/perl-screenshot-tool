package ScreenshotTool::RegionSelector;

use strict;
use warnings;
use Moo;
use Gtk3 qw(-init);
use Glib qw(TRUE FALSE);
use Cairo;
use Time::HiRes qw(time);
use namespace::clean;


has 'app' => (
    is       => 'ro',
    required => 1,
);

has 'capture_manager' => (
    is       => 'ro',
    required => 1,
);


has 'overlay_window' => (
    is      => 'rw',
    default => sub { undef },
);

has 'fixed' => (
    is      => 'rw',
    default => sub { undef },
);

has 'capture_button' => (
    is      => 'rw',
    default => sub { undef },
);

has 'escape_button' => (
    is      => 'rw',
    default => sub { undef },
);


has 'preview_pixbuf' => (
    is      => 'rw',
    default => sub { undef },
);

has 'is_dragging' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'drag_handle' => (
    is      => 'rw',
    default => sub { 0 }, # 0 = none, 1-8 = corner/edge handles, 9 = whole selection
);

has 'drag_start_x' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'drag_start_y' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'orig_sel_x' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'orig_sel_y' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'orig_sel_width' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'orig_sel_height' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'last_redraw_time' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'redraw_throttle_ms' => (
    is      => 'ro',
    default => sub { 16 },
);


sub config {
    my ($self) = @_;
    return $self->app->config;
}

sub ui {
    my ($self) = @_;
    return $self->app->ui;
}


sub destroy_overlay {
    my ($self) = @_;
    
    if (defined $self->overlay_window) {
        $self->overlay_window->destroy();
        $self->overlay_window(undef);
    }
}


sub select_region {
    my ($self) = @_;
    $self->interactive_region_selection();
}


sub interactive_region_selection {
    my ($self) = @_;
    
    $self->app->log_message('info', "Starting interactive region selection...");
    
    $self->overlay_window(Gtk3::Window->new('popup'));
    $self->overlay_window->set_app_paintable(TRUE);
    $self->overlay_window->set_decorated(FALSE);
    $self->overlay_window->set_skip_taskbar_hint(TRUE);
    $self->overlay_window->set_skip_pager_hint(TRUE);
    $self->overlay_window->set_keep_above(TRUE);

    $self->overlay_window->set_can_focus(TRUE);
    $self->overlay_window->set_accept_focus(TRUE);
    $self->overlay_window->set_focus_on_map(TRUE);

    my $screen = Gtk3::Gdk::Screen::get_default();
    my $root_window = $screen->get_root_window();
    my $root_width = $screen->get_width();
    my $root_height = $screen->get_height();

    $self->overlay_window->set_default_size($root_width, $root_height);
    $self->overlay_window->move(0, 0);

    $self->preview_pixbuf(Gtk3::Gdk::pixbuf_get_from_window(
        $root_window, 0, 0, $root_width, $root_height
    ));

    if ($self->capture_manager->selection_width == 0 || 
        $self->capture_manager->selection_height == 0 || 
        !$self->config->remember_last_selection) {
 
        $self->capture_manager->selection_start_x(($root_width - $self->config->default_width) / 2);
        $self->capture_manager->selection_start_y(($root_height - $self->config->default_height) / 2);
        $self->capture_manager->selection_width($self->config->default_width);
        $self->capture_manager->selection_height($self->config->default_height);
    }
    
    $self->fixed(Gtk3::Fixed->new());
    $self->overlay_window->add($self->fixed);
    
    my $overlay_area = Gtk3::DrawingArea->new();
    $self->fixed->put($overlay_area, 0, 0);
    $overlay_area->set_size_request($root_width, $root_height);

    $self->capture_button($self->ui->create_icon_button('capture', "Capture"));
    $self->fixed->put($self->capture_button, 10, 10);
    
    $self->escape_button($self->ui->create_icon_button('close', "Cancel"));
    $self->fixed->put($self->escape_button, 60, 10); 
    
    $self->capture_button->hide();
    $self->escape_button->hide();
    
    $self->overlay_window->add_events([
        'pointer-motion-mask',
        'button-press-mask',
        'button-release-mask',
        'key-press-mask',
        'key-release-mask',
        'focus-change-mask'
    ]);
    
    $overlay_area->signal_connect('draw' => sub { $self->draw_selection_overlay(@_); });
    
    $self->overlay_window->signal_connect('button-press-event' => sub {
        my ($widget, $event) = @_;
        
        if (!$self->is_dragging) {
          
            $self->drag_handle($self->check_handle($event->x, $event->y));
            
            if ($self->drag_handle) {
            
                $self->drag_start_x($event->x);
                $self->drag_start_y($event->y);
                $self->orig_sel_x($self->capture_manager->selection_start_x);
                $self->orig_sel_y($self->capture_manager->selection_start_y);
                $self->orig_sel_width($self->capture_manager->selection_width);
                $self->orig_sel_height($self->capture_manager->selection_height);
            } else {
              
                $self->capture_manager->selection_start_x($event->x);
                $self->capture_manager->selection_start_y($event->y);
                $self->capture_manager->selection_width(0);
                $self->capture_manager->selection_height(0);
            }
            
            $self->is_dragging(1);
            
            $self->capture_button->hide();
            $self->escape_button->hide();
            
            $overlay_area->queue_draw();
        }
        
        return TRUE;
    });
    
    $self->overlay_window->signal_connect('button-release-event' => sub {
        my ($widget, $event) = @_;
        
        if ($self->is_dragging) {
            $self->is_dragging(0);
            $self->drag_handle(0);

            $self->normalize_selection();
            $overlay_area->queue_draw();

            Glib::Timeout->add(50, sub {
                if (!$self->is_dragging) {
                    $overlay_area->queue_draw(); 
                }
                return FALSE; 
            });
        }
        
        return TRUE;
    });

    $self->overlay_window->signal_connect('motion-notify-event' => sub {
        my ($widget, $event) = @_;
        
        if ($self->is_dragging) {
            if ($self->drag_handle) {
            
                $self->resize_selection($self->drag_handle, $event->x, $event->y);
            } else {
               
                $self->capture_manager->selection_width($event->x - $self->capture_manager->selection_start_x);
                $self->capture_manager->selection_height($event->y - $self->capture_manager->selection_start_y);
            }

            if (defined $overlay_area) {
                $overlay_area->queue_draw();
            }
        } else {
         
            $self->update_cursor($event->x, $event->y);
        }
        
        return TRUE;
    });
    
    $self->overlay_window->signal_connect('key-press-event' => sub {
        my ($widget, $event) = @_;
        
        my $keyval = $event->keyval;
        $self->app->log_message('debug', "Key press detected: $keyval (" . 
                  (defined Gtk3::Gdk::keyval_name($keyval) ? 
                   Gtk3::Gdk::keyval_name($keyval) : "unknown") . ")");
        
        if ($keyval == 65293 || $keyval == 65421) { 
            $self->app->log_message('debug', "Enter key pressed!");
            
            if ($self->capture_manager->selection_width != 0 && 
                $self->capture_manager->selection_height != 0) {
                $self->app->log_message('debug', "Valid selection found, capturing region...");
                $self->capture_selected_region();
                return TRUE;
            }
        }

        if ($keyval == 65307) {  
            $self->app->log_message('debug', "Escape pressed, closing overlay");
            $self->overlay_window->destroy();
            $self->overlay_window(undef);
            $self->ui->restore_main_window();
            return TRUE;
        }
        
        if ($keyval == 32) { 
            $self->app->log_message('debug', "Space pressed, capturing region");
            if ($self->capture_manager->selection_width != 0 && 
                $self->capture_manager->selection_height != 0) {
                $self->capture_selected_region();
                return TRUE;
            }
        }
        
        return FALSE;
    });

    $self->capture_button->signal_connect('clicked' => sub {
        $self->app->log_message('debug', "Capture button clicked");
        $self->capture_selected_region();
    });
    
    $self->escape_button->signal_connect('clicked' => sub {
        $self->app->log_message('debug', "Escape button clicked");
        $self->overlay_window->destroy();
        $self->overlay_window(undef);
        $self->ui->restore_main_window();
    });

    Glib::Timeout->add(300000, sub { 
        if (defined $self->overlay_window) {
            $self->app->log_message('warning', "Safety timeout triggered - closing overlay");
            $self->overlay_window->destroy();
            $self->overlay_window(undef);
            $self->ui->restore_main_window();
        }
        return FALSE; 
    });

    $self->overlay_window->show_all();
    $self->overlay_window->set_can_focus(TRUE);
    $self->overlay_window->present(); 
    $self->overlay_window->grab_focus();
    Gtk3::Gdk::keyboard_grab($self->overlay_window->get_window(), TRUE, Gtk3::get_current_event_time());
    
    while (Gtk3::events_pending()) {
        Gtk3::main_iteration();
    }
}


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

sub calculate_redraw_area {
    my ($self) = @_;
    
    my ($x, $y, $w, $h) = $self->normalize_selection_coords();
    
    my $padding = $self->config->handle_size * 2;
    
    return (
        $x - $padding,
        $y - $padding,
        $w + ($padding * 2),
        $h + ($padding * 2)
    );
}

sub capture_selected_region {
    my ($self) = @_;
    
    $self->normalize_selection();
    my ($x, $y, $w, $h) = $self->normalize_selection_coords();
    
    if ($w < 5 || $h < 5) {
        $self->app->log_message('warning', "Selection too small, aborting capture");
        return;
    }
    
    my $screen = Gtk3::Gdk::Screen::get_default();
    my $screen_width = $screen->get_width();
    my $screen_height = $screen->get_height();
    
    if ($x < 0) {
        $w += $x;  
        $x = 0;
    }
    if ($y < 0) {
        $h += $y;  
        $y = 0;
    }
    if ($x + $w > $screen_width) {
        $w = $screen_width - $x;
    }
    if ($y + $h > $screen_height) {
        $h = $screen_height - $y;
    }
    
    if ($w <= 0 || $h <= 0) {
        $self->app->log_message('warning', "Invalid selection size after constraints, aborting capture");
        return;
    }
    
    if ($self->app->config->timer_value > 0) {

        $self->app->log_message('info', "Starting " . $self->app->config->timer_value . "-second timer for region capture (silent)");
        
        if ($self->overlay_window) {
            $self->overlay_window->hide();
            
            while (Gtk3::events_pending()) {
                Gtk3::main_iteration();
            }
        }
        
        Glib::Timeout->add(
            $self->app->config->timer_value * 1000, 
            sub {
                $self->perform_region_capture($x, $y, $w, $h);
                return FALSE; 
            }
        );
    } else {
      
        $self->perform_region_capture($x, $y, $w, $h);
    }
}


sub perform_region_capture {
    my ($self, $x, $y, $w, $h) = @_;
    
    my $screenshot = Gtk3::Gdk::Pixbuf->new(
        $self->preview_pixbuf->get_colorspace(),
        $self->preview_pixbuf->get_has_alpha(),
        $self->preview_pixbuf->get_bits_per_sample(),
        $w, $h
    );
    
    $self->app->log_message('debug', "Copying area: x=$x, y=$y, w=$w, h=$h from pixbuf with dimensions: " . 
                             $self->preview_pixbuf->get_width() . "x" . 
                             $self->preview_pixbuf->get_height());
    
    eval {
        $self->preview_pixbuf->copy_area($x, $y, $w, $h, $screenshot, 0, 0);
    };
    
    if ($@) {
        $self->app->log_message('error', "Error copying area: $@");
        return;
    }

    if ($self->config->show_mouse_pointer) {
        $self->app->log_message('debug', "Adding cursor to region capture");
        $self->capture_manager->add_cursor($screenshot, $x, $y);
    }
    
    if ($self->overlay_window) {
        $self->overlay_window->destroy();
        $self->overlay_window(undef);
    }
    
    $self->capture_manager->save_screenshot($screenshot);
    
    $self->ui->restore_main_window();
}



sub draw_selection_overlay {
    my ($self, $widget, $cr) = @_;
    
    my $width = $widget->get_allocated_width();
    my $height = $widget->get_allocated_height();
    
    if ($self->preview_pixbuf) {
        Gtk3::Gdk::cairo_set_source_pixbuf($cr, $self->preview_pixbuf, 0, 0);
        $cr->paint();
    }
    
    $cr->set_source_rgba(0, 0, 0, 0.4);
    $cr->rectangle(0, 0, $width, $height);
    $cr->fill();
    
    if ($self->capture_manager->selection_width != 0 && $self->capture_manager->selection_height != 0) {
        my ($x, $y, $w, $h) = $self->normalize_selection_coords();
        
        $cr->set_operator('clear');
        $cr->rectangle($x, $y, $w, $h);
        $cr->fill();
        $cr->set_operator('over');
        
        if ($self->preview_pixbuf) {
            Gtk3::Gdk::cairo_set_source_pixbuf($cr, $self->preview_pixbuf, 0, 0);
            $cr->rectangle($x, $y, $w, $h);
            $cr->fill();
        }
        
        $cr->set_source_rgb(1, 1, 1);
        $cr->set_line_width($self->config->border_width);
        $cr->rectangle($x, $y, $w, $h);
        $cr->stroke();
        
        $self->draw_handles($cr, $x, $y, $w, $h);
        
        $cr->set_source_rgba(1, 1, 1, 1.0);
        $cr->select_font_face("Inter Display Light", "normal", "normal");
        $cr->set_font_size(14);

        my $text = int($w) . " x " . int($h); 
        my $extents = $cr->text_extents($text);
        my $text_x = $x + ($w - $extents->{width}) / 2;
        my $text_y = $y + $h + 20;

        if ($text_y > $height - 5) {
            $text_y = $y - 10;
        }

        $cr->set_source_rgba(0, 0, 0, 0.7);
        $cr->rectangle(
            $text_x - 5,
            $text_y - $extents->{height},
            $extents->{width} + 10,
            $extents->{height} + 5
        );
        $cr->fill();

        $cr->set_source_rgb(1, 1, 1);
        $cr->move_to($text_x, $text_y);
        $cr->show_text($text);

        if (!$self->is_dragging) {
            my $button_y = $y + $h + 10;
            
            if ($button_y > $height - 50) {
                $button_y = $y - 50;
                if ($button_y < 10) {
                    $button_y = 10;
                }
            }
            
            my $capture_width = $self->capture_button->get_allocated_width();
            my $escape_width = $self->escape_button->get_allocated_width();
            
            $capture_width = 40 if !$capture_width || $capture_width < 10;
            $escape_width = 40 if !$escape_width || $escape_width < 10;
            
            my $spacing = 10; 
            my $escape_button_x = $x + $w - $escape_width;
            my $capture_button_x = $escape_button_x - $capture_width - $spacing;
            
            if ($capture_button_x < 10) {
                $capture_button_x = 10;
                $escape_button_x = $capture_button_x + $capture_width + $spacing;
            }
            
            $self->fixed->move($self->capture_button, $capture_button_x, $button_y);
            $self->fixed->move($self->escape_button, $escape_button_x, $button_y);
            
            $self->capture_button->show();
            $self->escape_button->show();
        } else {
          
            $self->capture_button->hide();
            $self->escape_button->hide();
        }
    } else {
      
        $cr->set_source_rgb(1, 1, 1);
        $cr->select_font_face("Inter Display Light", "normal", "bold");
        $cr->set_font_size(24);
        
        my $text = "Drag to select a region to capture";
        my $extents = $cr->text_extents($text);
        $cr->move_to(
            ($width - $extents->{width}) / 2,
            ($height - $extents->{height}) / 2
        );
        $cr->show_text($text);
        
        if (defined $self->capture_button && defined $self->escape_button) {
            $self->capture_button->hide();
            $self->escape_button->hide();
        }
    }
    
    return FALSE;
}


sub draw_handles {
    my ($self, $cr, $x, $y, $w, $h) = @_;
    
    my $half_handle = $self->config->handle_size / 2;
    
    $self->draw_handle($cr, $x - $half_handle, $y - $half_handle);               # Top-left (1)
    $self->draw_handle($cr, $x + $w - $half_handle, $y - $half_handle);          # Top-right (2)
    $self->draw_handle($cr, $x + $w - $half_handle, $y + $h - $half_handle);     # Bottom-right (3)
    $self->draw_handle($cr, $x - $half_handle, $y + $h - $half_handle);          # Bottom-left (4)
    

    $self->draw_handle($cr, $x + $w/2 - $half_handle, $y - $half_handle);        # Top (5)
    $self->draw_handle($cr, $x + $w - $half_handle, $y + $h/2 - $half_handle);   # Right (6)
    $self->draw_handle($cr, $x + $w/2 - $half_handle, $y + $h - $half_handle);   # Bottom (7)
    $self->draw_handle($cr, $x - $half_handle, $y + $h/2 - $half_handle);        # Left (8)
}


sub draw_handle {
    my ($self, $cr, $x, $y) = @_;
    
    $cr->save();
    
    $cr->set_source_rgb(1, 1, 1);
    $cr->rectangle($x, $y, $self->config->handle_size, $self->config->handle_size);
    $cr->fill();
    
    $cr->set_source_rgb(0, 0, 0);
    $cr->set_line_width(1);
    $cr->rectangle($x, $y, $self->config->handle_size, $self->config->handle_size);
    $cr->stroke();
    
    $cr->restore();
}

sub is_in_handle {
    my ($self, $x, $y, $handle_x, $handle_y) = @_;
    
    return $x >= $handle_x && 
           $x <= $handle_x + $self->config->handle_size && 
           $y >= $handle_y && 
           $y <= $handle_y + $self->config->handle_size;
}

sub check_handle {
    my ($self, $mouse_x, $mouse_y) = @_;
    
    if ($self->capture_manager->selection_width == 0 || 
        $self->capture_manager->selection_height == 0) {
        return 0;
    }
    
    my ($x, $y, $w, $h) = $self->normalize_selection_coords();
    my $half_handle = $self->config->handle_size / 2;
    
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
    
    if ($mouse_x >= $x && $mouse_x <= $x + $w && $mouse_y >= $y && $mouse_y <= $y + $h) {
        return 9; # 9 means inside selection
    }
    
    return 0;
}


sub update_cursor {
    my ($self, $mouse_x, $mouse_y) = @_;
    
    if (!$self->overlay_window) {
        return;
    }
    
    my $handle = 0;
    my $is_inside_selection = 0;
    
    if ($self->capture_manager->selection_width != 0 && 
        $self->capture_manager->selection_height != 0) {
        my ($sel_x, $sel_y, $sel_w, $sel_h) = $self->normalize_selection_coords();
        
        $is_inside_selection = 
            $mouse_x >= $sel_x && 
            $mouse_x <= ($sel_x + $sel_w) && 
            $mouse_y >= $sel_y && 
            $mouse_y <= ($sel_y + $sel_h);
            
        $handle = $self->check_handle($mouse_x, $mouse_y);
    }
    
    my $cursor;
    
    if ($handle == 1 || $handle == 3) {
        $cursor = Gtk3::Gdk::Cursor->new('bottom-right-corner');
    } elsif ($handle == 2 || $handle == 4) { 
        $cursor = Gtk3::Gdk::Cursor->new('bottom-left-corner');
    } elsif ($handle == 5 || $handle == 7) { 
        $cursor = Gtk3::Gdk::Cursor->new('sb-v-double-arrow');
    } elsif ($handle == 6 || $handle == 8) { 
        $cursor = Gtk3::Gdk::Cursor->new('sb-h-double-arrow');
    } elsif ($handle == 9) { 
        $cursor = Gtk3::Gdk::Cursor->new('fleur');
    } elsif ($self->capture_manager->selection_width == 0 && 
             $self->capture_manager->selection_height == 0) {

        $cursor = Gtk3::Gdk::Cursor->new('crosshair');
    } else {
   
        $cursor = Gtk3::Gdk::Cursor->new('left-ptr');
    }
    
    $self->overlay_window->get_window()->set_cursor($cursor);
}

sub resize_selection {
    my ($self, $handle, $x, $y) = @_;
    
    my $dx = $x - $self->drag_start_x;
    my $dy = $y - $self->drag_start_y;
    
    if ($handle == 1) { # Top-left
        $self->capture_manager->selection_start_x($self->orig_sel_x + $dx);
        $self->capture_manager->selection_start_y($self->orig_sel_y + $dy);
        $self->capture_manager->selection_width($self->orig_sel_width - $dx);
        $self->capture_manager->selection_height($self->orig_sel_height - $dy);
    } elsif ($handle == 2) { # Top-right
        $self->capture_manager->selection_start_y($self->orig_sel_y + $dy);
        $self->capture_manager->selection_width($self->orig_sel_width + $dx);
        $self->capture_manager->selection_height($self->orig_sel_height - $dy);
    } elsif ($handle == 3) { # Bottom-right
        $self->capture_manager->selection_width($self->orig_sel_width + $dx);
        $self->capture_manager->selection_height($self->orig_sel_height + $dy);
    } elsif ($handle == 4) { # Bottom-left
        $self->capture_manager->selection_start_x($self->orig_sel_x + $dx);
        $self->capture_manager->selection_width($self->orig_sel_width - $dx);
        $self->capture_manager->selection_height($self->orig_sel_height + $dy);
    } elsif ($handle == 5) { # Top
        $self->capture_manager->selection_start_y($self->orig_sel_y + $dy);
        $self->capture_manager->selection_height($self->orig_sel_height - $dy);
    } elsif ($handle == 6) { # Right
        $self->capture_manager->selection_width($self->orig_sel_width + $dx);
    } elsif ($handle == 7) { # Bottom
        $self->capture_manager->selection_height($self->orig_sel_height + $dy);
    } elsif ($handle == 8) { # Left
        $self->capture_manager->selection_start_x($self->orig_sel_x + $dx);
        $self->capture_manager->selection_width($self->orig_sel_width - $dx);
    } elsif ($handle == 9) { # Move entire selection
        $self->capture_manager->selection_start_x($self->orig_sel_x + $dx);
        $self->capture_manager->selection_start_y($self->orig_sel_y + $dy);
    }
}

1;
