package ScreenshotTool::CursorUtils;

use strict;
use warnings;
use Moo;
use Gtk3 qw(-init);
use Glib qw(TRUE FALSE);
use namespace::clean;


has 'app' => (
    is       => 'ro',
    required => 1,
);


has 'cursor_cache' => (
    is      => 'rw',
    default => sub { {} },
);


sub get_cursor_position {
    my ($self) = @_;
    my ($found, $x, $y) = (0, 0, 0);
    
    eval {
        my $display = Gtk3::Gdk::Display::get_default();
        if ($display) {
            my $seat = $display->get_default_seat();
            if ($seat) {
                my $pointer = $seat->get_pointer();
                if ($pointer) {
                    my ($screen, $px, $py) = $pointer->get_position();
                    $x = $px;
                    $y = $py;
                    $found = 1;
                    $self->app->log_message('debug', "Got cursor position using seat->get_pointer: $x, $y");
                }
            }
        }
    };
    
    if (!$found) {
        eval {
            my $display = Gtk3::Gdk::Display::get_default();
            my $device_manager = $display->get_device_manager();
            my $devices = $device_manager->list_devices('physical');
            
            foreach my $device (@$devices) {
                if ($device->get_source() eq 'mouse' || $device->get_source() eq 'touchpad') {
                    my ($screen, $px, $py) = $device->get_position();
                    $x = $px;
                    $y = $py;
                    $found = 1;
                    $self->app->log_message('debug', "Got cursor position using device_manager: $x, $y");
                    last;
                }
            }
        };
    }
    
    if (!$found && $self->is_command_available("xdotool")) {
        eval {
            my $cmd = "xdotool getmouselocation";
            my $output = `$cmd 2>/dev/null`;
            
            if ($output =~ /x:(\d+)\s+y:(\d+)/) {
                $x = $1;
                $y = $2;
                $found = 1;
                $self->app->log_message('debug', "Got cursor position using xdotool: $x, $y");
            }
        };
    }
    
    if (!$found) {
        $self->app->log_message('warning', "Failed to determine cursor position using any method");
    }
    
    return ($found, $x, $y);
}


sub get_cursor_image {
    my ($self, $cursor_name) = @_;
    
    $cursor_name ||= 'default';
    
    if (exists $self->cursor_cache->{$cursor_name}) {
        return @{$self->cursor_cache->{$cursor_name}};
    }
    
    my ($cursor_pixbuf, $hotspot_x, $hotspot_y) = (undef, 0, 0);
    
    eval {
        my $display = Gtk3::Gdk::Display::get_default();
        my $cursor = Gtk3::Gdk::Cursor->new_from_name($display, $cursor_name);
        if ($cursor) {
            my $cursor_image = $cursor->get_image();
            
            if ($cursor_image) {
                $cursor_pixbuf = $cursor_image;
                $hotspot_x = $cursor_image->get_hotspot_x();
                $hotspot_y = $cursor_image->get_hotspot_y();
                $self->app->log_message('debug', "Got cursor image with hotspot at $hotspot_x, $hotspot_y");
            } else {
                my $cursor_surface = $cursor->get_surface();
                if ($cursor_surface) {
                 
                    $cursor_pixbuf = Gtk3::Gdk::pixbuf_get_from_surface(
                        $cursor_surface, 0, 0, 
                        $cursor_surface->get_width(), 
                        $cursor_surface->get_height()
                    );
            
                    $hotspot_x = int($cursor_pixbuf->get_width() / 2);
                    $hotspot_y = int($cursor_pixbuf->get_height() / 2);
                    $self->app->log_message('debug', "Got cursor from surface with estimated hotspot");
                }
            }
        }
    };
    
    if (!$cursor_pixbuf) {
        $self->app->log_message('info', "Using fallback cursor image");
        ($cursor_pixbuf, $hotspot_x, $hotspot_y) = $self->create_fallback_cursor();
    }
    
    if ($cursor_pixbuf) {
        $self->cursor_cache->{$cursor_name} = [$cursor_pixbuf, $hotspot_x, $hotspot_y];
    }
    
    return ($cursor_pixbuf, $hotspot_x, $hotspot_y);
}


sub create_fallback_cursor {
    my ($self) = @_;
    
    my $cursor_width = 24;
    my $cursor_height = 24;
    my $cursor_pixbuf = Gtk3::Gdk::Pixbuf->new('rgba', TRUE, 8, $cursor_width, $cursor_height);
    
    $cursor_pixbuf->fill(0);
    
    my $surface = Cairo::ImageSurface->create('argb32', $cursor_width, $cursor_height);
    my $cr = Cairo::Context->new($surface);
    
    $cr->set_source_rgba(0, 0, 0, 1);
    $cr->move_to(0, 0);
    $cr->line_to($cursor_width * 0.7, $cursor_height * 0.7);
    $cr->line_to($cursor_width * 0.5, $cursor_height * 0.5);
    $cr->line_to($cursor_width * 0.7, $cursor_height * 0.9);
    $cr->line_to($cursor_width * 0.5, $cursor_height);
    $cr->line_to($cursor_width * 0.3, $cursor_height * 0.7);
    $cr->close_path();
    $cr->fill();
    
    $cr->set_source_rgba(1, 1, 1, 1); 
    $cr->move_to(2, 2);
    $cr->line_to($cursor_width * 0.65, $cursor_height * 0.65);
    $cr->line_to($cursor_width * 0.5, $cursor_height * 0.5);
    $cr->line_to($cursor_width * 0.65, $cursor_height * 0.85);
    $cr->line_to($cursor_width * 0.5, $cursor_height * 0.95);
    $cr->line_to($cursor_width * 0.35, $cursor_height * 0.7);
    $cr->close_path();
    $cr->fill();
    
    $cursor_pixbuf = Gtk3::Gdk::pixbuf_get_from_surface(
        $surface, 0, 0, $cursor_width, $cursor_height
    );
    
    my $hotspot_x = 0;
    my $hotspot_y = 0;
    
    $self->app->log_message('debug', "Created fallback cursor image");
    
    return ($cursor_pixbuf, $hotspot_x, $hotspot_y);
}


sub is_command_available {
    my ($self, $command) = @_;
    
    my $result = system("which $command >/dev/null 2>&1") == 0;
    return $result;
}


sub add_cursor_to_screenshot {
    my ($self, $screenshot, $region_x, $region_y) = @_;
    
    if (!defined $screenshot) {
        $self->app->log_message('error', "Screenshot is undefined in add_cursor_to_screenshot");
        return 0;
    }
    
    if (!defined $region_x || !defined $region_y) {
        $self->app->log_message('warning', "Region coordinates are undefined, using defaults");
        $region_x = 0 if !defined $region_x;
        $region_y = 0 if !defined $region_y;
    }
    
    $self->app->log_message('info', "Adding cursor to screenshot (region at $region_x, $region_y)");
    
    eval {
   
        my ($found, $pointer_x, $pointer_y) = $self->get_cursor_position();
        
        if ($found) {
            $self->app->log_message('debug', "Cursor at $pointer_x, $pointer_y - Screenshot region at $region_x, $region_y");
            
            my $screenshot_width = $screenshot->get_width();
            my $screenshot_height = $screenshot->get_height();
            
            if ($screenshot_width <= 0 || $screenshot_height <= 0) {
                $self->app->log_message('warning', "Invalid screenshot dimensions: ${screenshot_width}x${screenshot_height}");
                return 0;
            }
            
            my $in_region = (
                $pointer_x >= $region_x && 
                $pointer_y >= $region_y && 
                $pointer_x < $region_x + $screenshot_width && 
                $pointer_y < $region_y + $screenshot_height
            );
            
            if ($in_region) {
                $self->app->log_message('info', "Cursor is within the capture region");

                my ($cursor_pixbuf, $hotspot_x, $hotspot_y) = $self->get_cursor_image();
                
                if (!$cursor_pixbuf) {
                    $self->app->log_message('error', "Failed to get cursor image");
                    return 0;
                }

                my $cursor_x = $pointer_x - $region_x - $hotspot_x;
                my $cursor_y = $pointer_y - $region_y - $hotspot_y;
                
                $cursor_x = 0 if $cursor_x < 0;
                $cursor_y = 0 if $cursor_y < 0;
                
                my $cursor_width = $cursor_pixbuf->get_width();
                my $cursor_height = $cursor_pixbuf->get_height();
                
                if ($cursor_width <= 0 || $cursor_height <= 0) {
                    $self->app->log_message('warning', "Invalid cursor dimensions: ${cursor_width}x${cursor_height}");
                    return 0;
                }
                
                $cursor_x = $screenshot->get_width() - $cursor_width 
                    if $cursor_x + $cursor_width > $screenshot->get_width();
                $cursor_y = $screenshot->get_height() - $cursor_height 
                    if $cursor_y + $cursor_height > $screenshot->get_height();
                
                eval {
                    $cursor_pixbuf->composite(
                        $screenshot,           
                        $cursor_x, $cursor_y,  
                        $cursor_pixbuf->get_width(), $cursor_pixbuf->get_height(),  
                        $cursor_x, $cursor_y,  
                        1.0, 1.0,            
                        'bilinear',          
                        255                  
                    );
                };
                
                if ($@) {
                    $self->app->log_message('error', "Failed to composite cursor onto screenshot: $@");
                    return 0;
                }
                
                $self->app->log_message('info', "Added cursor to screenshot at $cursor_x, $cursor_y");
                return 1;
            } else {
                $self->app->log_message('info', "Cursor is outside the capture region");
            }
        } else {
            $self->app->log_message('warning', "Could not determine cursor position");
        }
    };
    
    if ($@) {
        $self->app->log_message('warning', "Error adding cursor: $@");
    }
    
    return 0;
}


sub clear_cache {
    my ($self) = @_;
    
    foreach my $key (keys %{$self->cursor_cache}) {
        $self->cursor_cache->{$key} = undef;
    }
    
    $self->cursor_cache({});
    
    $self->app->log_message('debug', "Cursor cache cleared");
}

1;
