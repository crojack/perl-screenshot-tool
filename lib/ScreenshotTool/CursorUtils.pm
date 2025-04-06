package ScreenshotTool::CursorUtils;

use strict;
use warnings;
use Gtk3 qw(-init);
use Glib qw(TRUE FALSE);

sub new {
    my ($class, %args) = @_;
    
    my $app = $args{app} || die "App reference is required";
    
    my $self = bless {
        app => $app,
        cursor_cache => {}, # Cache for cursor images
    }, $class;
    
    return $self;
}

sub get_cursor_position {
    my ($self) = @_;
    my ($found, $x, $y) = (0, 0, 0);
    
    # Try multiple methods to get cursor position, starting with most reliable
    
    # Method 1: Using display->get_default_seat->get_pointer (newer Gtk3)
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
                    $self->{app}->log_message('debug', "Got cursor position using seat->get_pointer: $x, $y");
                }
            }
        }
    };
    
    # Method 2: Using device manager (older Gtk3)
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
                    $self->{app}->log_message('debug', "Got cursor position using device_manager: $x, $y");
                    last;
                }
            }
        };
    }
    
    # Method 3: Fallback - use xdotool if available
    if (!$found && $self->is_command_available("xdotool")) {
        eval {
            my $cmd = "xdotool getmouselocation";
            my $output = `$cmd 2>/dev/null`;
            
            if ($output =~ /x:(\d+)\s+y:(\d+)/) {
                $x = $1;
                $y = $2;
                $found = 1;
                $self->{app}->log_message('debug', "Got cursor position using xdotool: $x, $y");
            }
        };
    }
    
    # Log failure if we couldn't determine position
    if (!$found) {
        $self->{app}->log_message('warning', "Failed to determine cursor position using any method");
    }
    
    return ($found, $x, $y);
}

sub get_cursor_image {
    my ($self, $cursor_name) = @_;
    
    # Default to 'default' cursor if not specified
    $cursor_name ||= 'default';
    
    # Check cache first
    if (exists $self->{cursor_cache}{$cursor_name}) {
        return @{$self->{cursor_cache}{$cursor_name}};
    }
    
    my ($cursor_pixbuf, $hotspot_x, $hotspot_y) = (undef, 0, 0);
    
    # Try to get the actual cursor image
    eval {
        my $display = Gtk3::Gdk::Display::get_default();
        my $cursor = Gtk3::Gdk::Cursor->new_from_name($display, $cursor_name);
        if ($cursor) {
            my $cursor_image = $cursor->get_image();
            
            if ($cursor_image) {
                $cursor_pixbuf = $cursor_image;
                $hotspot_x = $cursor_image->get_hotspot_x();
                $hotspot_y = $cursor_image->get_hotspot_y();
                $self->{app}->log_message('debug', "Got cursor image with hotspot at $hotspot_x, $hotspot_y");
            } else {
                my $cursor_surface = $cursor->get_surface();
                if ($cursor_surface) {
                    # Try to create a pixbuf from the surface
                    $cursor_pixbuf = Gtk3::Gdk::pixbuf_get_from_surface(
                        $cursor_surface, 0, 0, 
                        $cursor_surface->get_width(), 
                        $cursor_surface->get_height()
                    );
                    # Default hotspot to center
                    $hotspot_x = int($cursor_pixbuf->get_width() / 2);
                    $hotspot_y = int($cursor_pixbuf->get_height() / 2);
                    $self->{app}->log_message('debug', "Got cursor from surface with estimated hotspot");
                }
            }
        }
    };
    
    # If we couldn't get a real cursor image, create a custom one
    if (!$cursor_pixbuf) {
        $self->{app}->log_message('info', "Using fallback cursor image");
        ($cursor_pixbuf, $hotspot_x, $hotspot_y) = $self->create_fallback_cursor();
    }
    
    # Cache the cursor for future use
    if ($cursor_pixbuf) {
        $self->{cursor_cache}{$cursor_name} = [$cursor_pixbuf, $hotspot_x, $hotspot_y];
    }
    
    return ($cursor_pixbuf, $hotspot_x, $hotspot_y);
}

# Create a fallback cursor when system cursor can't be retrieved
sub create_fallback_cursor {
    my ($self) = @_;
    
    # Create a better looking cursor
    my $cursor_width = 24;
    my $cursor_height = 24;
    my $cursor_pixbuf = Gtk3::Gdk::Pixbuf->new('rgba', TRUE, 8, $cursor_width, $cursor_height);
    
    # Clear with transparency
    $cursor_pixbuf->fill(0);
    
    # Create a surface and context for drawing
    my $surface = Cairo::ImageSurface->create('argb32', $cursor_width, $cursor_height);
    my $cr = Cairo::Context->new($surface);
    
    # Draw arrow cursor shape
    # First draw black outline/fill
    $cr->set_source_rgba(0, 0, 0, 1); # Black
    $cr->move_to(0, 0);
    $cr->line_to($cursor_width * 0.7, $cursor_height * 0.7);
    $cr->line_to($cursor_width * 0.5, $cursor_height * 0.5);
    $cr->line_to($cursor_width * 0.7, $cursor_height * 0.9);
    $cr->line_to($cursor_width * 0.5, $cursor_height);
    $cr->line_to($cursor_width * 0.3, $cursor_height * 0.7);
    $cr->close_path();
    $cr->fill();
    
    # Then draw white inner area
    $cr->set_source_rgba(1, 1, 1, 1); # White
    $cr->move_to(2, 2);
    $cr->line_to($cursor_width * 0.65, $cursor_height * 0.65);
    $cr->line_to($cursor_width * 0.5, $cursor_height * 0.5);
    $cr->line_to($cursor_width * 0.65, $cursor_height * 0.85);
    $cr->line_to($cursor_width * 0.5, $cursor_height * 0.95);
    $cr->line_to($cursor_width * 0.35, $cursor_height * 0.7);
    $cr->close_path();
    $cr->fill();
    
    # Convert Cairo surface to pixbuf
    $cursor_pixbuf = Gtk3::Gdk::pixbuf_get_from_surface(
        $surface, 0, 0, $cursor_width, $cursor_height
    );
    
    # Set hotspot at the top-left corner of the arrow
    my $hotspot_x = 0;
    my $hotspot_y = 0;
    
    $self->{app}->log_message('debug', "Created fallback cursor image");
    
    return ($cursor_pixbuf, $hotspot_x, $hotspot_y);
}

# Check if a command is available
sub is_command_available {
    my ($self, $command) = @_;
    
    my $result = system("which $command >/dev/null 2>&1") == 0;
    return $result;
}

# Add cursor to screenshot
sub add_cursor_to_screenshot {
    my ($self, $screenshot, $region_x, $region_y) = @_;
    
    # Safety check for parameters
    if (!defined $screenshot) {
        $self->{app}->log_message('error', "Screenshot is undefined in add_cursor_to_screenshot");
        return 0;
    }
    
    if (!defined $region_x || !defined $region_y) {
        $self->{app}->log_message('warning', "Region coordinates are undefined, using defaults");
        $region_x = 0 if !defined $region_x;
        $region_y = 0 if !defined $region_y;
    }
    
    $self->{app}->log_message('info', "Adding cursor to screenshot (region at $region_x, $region_y)");
    
    eval {
        # Get current cursor position
        my ($found, $pointer_x, $pointer_y) = $self->get_cursor_position();
        
        # Proceed if we found a pointer position
        if ($found) {
            $self->{app}->log_message('debug', "Cursor at $pointer_x, $pointer_y - Screenshot region at $region_x, $region_y");
            
            # Check if cursor is within the captured region
            my $screenshot_width = $screenshot->get_width();
            my $screenshot_height = $screenshot->get_height();
            
            # Check for valid dimensions
            if ($screenshot_width <= 0 || $screenshot_height <= 0) {
                $self->{app}->log_message('warning', "Invalid screenshot dimensions: ${screenshot_width}x${screenshot_height}");
                return 0;
            }
            
            my $in_region = (
                $pointer_x >= $region_x && 
                $pointer_y >= $region_y && 
                $pointer_x < $region_x + $screenshot_width && 
                $pointer_y < $region_y + $screenshot_height
            );
            
            if ($in_region) {
                $self->{app}->log_message('info', "Cursor is within the capture region");
                
                # Get the cursor image
                my ($cursor_pixbuf, $hotspot_x, $hotspot_y) = $self->get_cursor_image();
                
                if (!$cursor_pixbuf) {
                    $self->{app}->log_message('error', "Failed to get cursor image");
                    return 0;
                }
                
                # Calculate cursor position relative to the screenshot
                my $cursor_x = $pointer_x - $region_x - $hotspot_x;
                my $cursor_y = $pointer_y - $region_y - $hotspot_y;
                
                # Keep cursor within bounds
                $cursor_x = 0 if $cursor_x < 0;
                $cursor_y = 0 if $cursor_y < 0;
                
                my $cursor_width = $cursor_pixbuf->get_width();
                my $cursor_height = $cursor_pixbuf->get_height();
                
                if ($cursor_width <= 0 || $cursor_height <= 0) {
                    $self->{app}->log_message('warning', "Invalid cursor dimensions: ${cursor_width}x${cursor_height}");
                    return 0;
                }
                
                # Ensure cursor doesn't go out of bounds
                $cursor_x = $screenshot->get_width() - $cursor_width 
                    if $cursor_x + $cursor_width > $screenshot->get_width();
                $cursor_y = $screenshot->get_height() - $cursor_height 
                    if $cursor_y + $cursor_height > $screenshot->get_height();
                
                # Add cursor to the screenshot using composite for alpha blending
                eval {
                    $cursor_pixbuf->composite(
                        $screenshot,           # destination
                        $cursor_x, $cursor_y,  # destination x,y
                        $cursor_pixbuf->get_width(), $cursor_pixbuf->get_height(),  # width, height
                        $cursor_x, $cursor_y,  # offset x,y
                        1.0, 1.0,              # scale x,y
                        'bilinear',            # interpolation - better quality
                        255                    # overall alpha
                    );
                };
                
                if ($@) {
                    $self->{app}->log_message('error', "Failed to composite cursor onto screenshot: $@");
                    return 0;
                }
                
                $self->{app}->log_message('info', "Added cursor to screenshot at $cursor_x, $cursor_y");
                return 1;
            } else {
                $self->{app}->log_message('info', "Cursor is outside the capture region");
            }
        } else {
            $self->{app}->log_message('warning', "Could not determine cursor position");
        }
    };
    
    if ($@) {
        $self->{app}->log_message('warning', "Error adding cursor: $@");
    }
    
    return 0;
}

# Clear the cursor cache to free memory
sub clear_cache {
    my ($self) = @_;
    
    foreach my $key (keys %{$self->{cursor_cache}}) {
        $self->{cursor_cache}{$key} = undef;
    }
    
    $self->{cursor_cache} = {};
    
    $self->{app}->log_message('debug', "Cursor cache cleared");
}

1;