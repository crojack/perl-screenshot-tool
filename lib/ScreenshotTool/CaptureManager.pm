package ScreenshotTool::CaptureManager;

use strict;
use warnings;
use Moo;
use Gtk3 qw(-init);
use Glib qw(TRUE FALSE);
use File::Path qw(make_path);
use Digest::MD5 qw(md5_hex);
use URI::file;
use File::Basename qw(basename dirname);
use File::Spec;
use POSIX qw(strftime);
use File::Temp qw(tempfile);
use namespace::clean;


BEGIN {
    eval {
        require X11::Protocol;
        X11::Protocol->import();
    };
}


use ScreenshotTool::RegionSelector;


has 'app' => (
    is       => 'ro',
    required => 1,
);

has 'region_selector' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_region_selector',
);

has 'preview_pixbuf' => (
    is      => 'rw',
    default => sub { undef },
);

has 'selection_start_x' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'selection_start_y' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'selection_width' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'selection_height' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'has_x11_protocol' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'has_xfixes' => (
    is      => 'rw',
    default => sub { 0 },
);

sub BUILD {
    my ($self) = @_;
    
    eval {
        require X11::Protocol;
        $self->has_x11_protocol(1);
        
        if ($self->app->window_system ne 'wayland' && $self->app->window_system ne 'wayland-limited') {
            my $x11 = X11::Protocol->new($ENV{'DISPLAY'});
            if ($x11->init_extension('XFIXES')) {
                $self->has_xfixes(1);
                $self->app->log_message('info', "XFIXES extension available for cursor capture");
            } else {
                $self->app->log_message('info', "XFIXES extension not available, will use fallback cursor capture method");
            }
        }
    };
    
    if ($@) {
        $self->app->log_message('warning', "X11::Protocol module not available: $@");
        $self->app->log_message('warning', "Advanced cursor capture will be limited");
    }
}

sub _build_region_selector {
    my ($self) = @_;
    return ScreenshotTool::RegionSelector->new(
        app => $self->app,
        capture_manager => $self
    );
}

sub config {
    my ($self) = @_;
    return $self->app->config;
}

sub ui {
    my ($self) = @_;
    return $self->app->ui;
}

sub get_wayland_backend {
    my ($self) = @_;
    
    my $tools = $self->app->wayland_tools;
    
    if ($tools && $tools->{'gnome-screenshot'}) {
        $self->app->log_message('info', "Using gnome-screenshot for Wayland");
        return 'gnome-screenshot';
    } else {
        $self->app->log_message('warning', "No supported Wayland screenshot tools found");
        return 'none';
    }
}

sub capture_wayland_region {
    my ($self) = @_;
    
    my $backend = $self->get_wayland_backend();
    
    if ($backend eq 'gnome-screenshot') {
        return $self->capture_wayland_region_gnome();
    } else {
        $self->app->log_message('error', "No supported Wayland screenshot tools available");
        return 0;
    }
}

sub capture_wayland_region_gnome {
    my ($self) = @_;
    
    $self->app->log_message('info', "Using gnome-screenshot for Wayland capture...");
    
    my $timestamp = strftime("%Y-%m-%d-%H%M%S", localtime);
    my $file_path = $self->config->save_location . "/Screenshot-$timestamp." . $self->config->image_format;
    
    if (!-d $self->config->save_location) {
        make_path($self->config->save_location);
    }
    
    $self->ui->{main_window}->hide();

    Gtk3::main_iteration() while Gtk3::events_pending();
    sleep(0.3);
    
    my $cursor_option = $self->config->show_mouse_pointer ? "--include-pointer" : "";
    
    if ($self->config->selection_mode == 1) {
        $self->app->log_message('info', "Using gnome-screenshot for area selection (Wayland)...");
        my $cmd = "gnome-screenshot --area $cursor_option --file=\"$file_path\"";
        $self->app->log_message('info', "Executing: $cmd");
        system($cmd);
    }

    elsif ($self->config->selection_mode == 2) {
        $self->app->log_message('info', "Capturing fullscreen...");
        my $cmd = "gnome-screenshot $cursor_option --file=\"$file_path\"";
        $self->app->log_message('info', "Executing: $cmd");
        system($cmd);
    }

    elsif ($self->config->selection_mode == 0) {
        $self->app->log_message('info', "Capturing window...");
        my $cmd = "gnome-screenshot --window $cursor_option --file=\"$file_path\"";
        $self->app->log_message('info', "Executing: $cmd");
        system($cmd);
    }

    if (-f $file_path && -s $file_path > 0) {
        $self->app->log_message('info', "Screenshot captured successfully");
        
        if ($self->config->show_floating_thumbnail) {
            my $pixbuf = eval { Gtk3::Gdk::Pixbuf->new_from_file($file_path); };
            if ($pixbuf) {
                $self->ui->show_floating_thumbnail($pixbuf, $file_path);
            }
        }
        
        if ($self->config->save_location eq "clipboard") {
            my $pixbuf = eval { Gtk3::Gdk::Pixbuf->new_from_file($file_path); };
            if ($pixbuf) {
                my $clipboard = Gtk3::Clipboard::get(Gtk3::Gdk::Atom::intern('CLIPBOARD', FALSE));
                $clipboard->set_image($pixbuf);
                $self->app->log_message('info', "Screenshot copied to clipboard");
                unlink($file_path); 
            }
        }
    } else {
        $self->app->log_message('warning', "Screenshot capture failed or was canceled");
    }
    
    $self->ui->restore_main_window();
    
    return 1; 
}

sub start_capture {
    my ($self) = @_;
    
    $self->preview_pixbuf(undef);
    
    if (!$self->config->remember_last_selection) {
        $self->selection_width(0);
        $self->selection_height(0);
    }
    
    if ($self->config->selection_mode == 1) {

        $self->perform_capture();
        return;
    }
    
    if ($self->config->timer_value > 0) {

        $self->start_timer();
    } else {

        if (!$self->config->allow_self_capture) {
            Glib::Timeout->add(
                $self->config->hide_delay,
                sub {
                    $self->perform_capture();
                    return FALSE; 
                }
            );
        } else {
          
            $self->perform_capture();
        }
    }
}

sub start_timer {
    my ($self) = @_;
    
    $self->app->log_message('info', "Starting " . $self->config->timer_value . "-second timer (silent)");
    
    Glib::Timeout->add(
        $self->config->timer_value * 1000,  
        sub {
            $self->perform_capture();
            return FALSE; 
        }
    );
}

sub perform_capture {
    my ($self) = @_;
    
    Gtk3::main_iteration() while Gtk3::events_pending();
    
    sleep(0.3);
    
    if ($self->app->window_system =~ /^wayland/) {
      
        $self->capture_wayland_region();
    } else {
      
        if ($self->config->selection_mode == 0) {
    
            $self->select_window();
        } elsif ($self->config->selection_mode == 1) {
         
            $self->region_selector->interactive_region_selection();
        } elsif ($self->config->selection_mode == 2) {
        
            $self->capture_fullscreen();
        }
    }
}

sub capture_fullscreen {
    my ($self) = @_;
    
    my $screen = Gtk3::Gdk::Screen::get_default();
    my $root_window = $screen->get_root_window();
    my $root_width = $screen->get_width();
    my $root_height = $screen->get_height();
    

    $self->ui->{main_window}->move(-9000, -9000); 
    $self->ui->{main_window}->hide();
    $self->ui->{main_window}->set_opacity(0.0);
    
    Gtk3::main_iteration() while Gtk3::events_pending();
    
    sleep(0.2);
    
    Gtk3::main_iteration() while Gtk3::events_pending();
    
    my $screenshot = Gtk3::Gdk::pixbuf_get_from_window($root_window, 0, 0, $root_width, $root_height);
    
    if ($self->config->show_mouse_pointer) {
        $self->app->log_message('debug', "Adding cursor to fullscreen capture");
        $self->add_cursor($screenshot, 0, 0);
    }
    
    $self->save_screenshot($screenshot);
    
    $self->ui->restore_main_window();
}

sub select_window {
    my ($self) = @_;
    
    my $screen = Gtk3::Gdk::Screen::get_default();
    my $root_window = $screen->get_root_window();
    
    $self->ui->{main_window}->move(-9000, -9000);  
    $self->ui->{main_window}->hide();
    $self->ui->{main_window}->set_opacity(0.0); 
    
    Gtk3::main_iteration() while Gtk3::events_pending();
    sleep(0.5); 
    
    if ($self->app->window_system eq 'xorg') {
        my $cmd = "xdotool getactivewindow";
        my $window_id = `$cmd`;
        chomp($window_id);
        
        if ($window_id) {
            $self->capture_specific_window($window_id);
        } else {
 
            my $root_width = $screen->get_width();
            my $root_height = $screen->get_height();
            my $screenshot = Gtk3::Gdk::pixbuf_get_from_window($root_window, 0, 0, $root_width, $root_height);
            $self->save_screenshot($screenshot);
        }
    } elsif ($self->app->window_system eq 'wayland') {

        $self->region_selector->select_region();
    }
    
    Glib::Timeout->add(500, sub {
        $self->ui->restore_main_window();
        return FALSE;
    });
}

sub get_window_at_position {
    my ($self, $x, $y) = @_;
    
    if ($self->app->window_system eq 'xorg') {

        my $cmd = "xdotool getmouselocation --shell";
        my $output = `$cmd`;
        my ($window_id) = $output =~ /WINDOW=(\d+)/;

        return $window_id;

    } elsif ($self->app->window_system eq 'wayland') {

        $self->region_selector->destroy_overlay();
        $self->region_selector->select_region();

        return undef;
    }
}

sub capture_specific_window {
    my ($self, $window_id) = @_;
    
    if (!$window_id) {
        $self->app->log_message('warning', "No window ID provided");
        $self->ui->restore_main_window();

        return;
    }
    
    $self->app->log_message('info', "Capturing window...");
    
    if ($self->app->window_system eq 'xorg') {
        eval {
       
            my $cmd = "xwininfo -id $window_id";
            my $output = `$cmd`;

            my ($x, $y, $width, $height);
            
            if ($self->config->capture_window_decoration) {
            
                ($x) = $output =~ /Absolute upper-left X:\s+(\d+)/;
                ($y) = $output =~ /Absolute upper-left Y:\s+(\d+)/;
                ($width) = $output =~ /Width:\s+(\d+)/;
                ($height) = $output =~ /Height:\s+(\d+)/;
                
                my $xprop_cmd = "xprop -id $window_id _NET_FRAME_EXTENTS";
                my $xprop_output = `$xprop_cmd`;
                
                if ($xprop_output =~ /_NET_FRAME_EXTENTS.*?(\d+),\s*(\d+),\s*(\d+),\s*(\d+)/) {
                    my ($left, $right, $top, $bottom) = ($1, $2, $3, $4);
                    
                    $x -= $left;
                    $y -= $top;
                    $width += $left + $right;
                    $height += $top + $bottom;
                }
            } else {

                ($x) = $output =~ /Absolute upper-left X:\s+(\d+)/;
                ($y) = $output =~ /Absolute upper-left Y:\s+(\d+)/;
                
                my ($client_x) = $output =~ /Relative upper-left X:\s+(\d+)/;
                my ($client_y) = $output =~ /Relative upper-left Y:\s+(\d+)/;
                
                if (defined $client_x && defined $client_y) {
                    $x += $client_x;
                    $y += $client_y;
                }
                
                my ($client_width) = $output =~ /Width:\s+(\d+)/;
                my ($client_height) = $output =~ /Height:\s+(\d+)/;
                
                $width = $client_width;
                $height = $client_height;
            }

            if (!defined $x || !defined $y || !defined $width || !defined $height) {
                die "Could not get window geometry";
            }
            
            my $screen = Gtk3::Gdk::Screen::get_default();
            my $screen_width = $screen->get_width();
            my $screen_height = $screen->get_height();
            
            if ($x < 0) {
                $width += $x;  
                $x = 0;
            }
            if ($y < 0) {
                $height += $y; 
                $y = 0;
            }
            if ($x + $width > $screen_width) {
                $width = $screen_width - $x;
            }
            if ($y + $height > $screen_height) {
                $height = $screen_height - $y;
            }
            
            my $screenshot = undef;
            my $root_window = Gtk3::Gdk::get_default_root_window();
            
            $screenshot = Gtk3::Gdk::pixbuf_get_from_window($root_window, $x, $y, $width, $height);
            
            if (!$screenshot) {
                die "Failed to capture window";
            }
            
            if ($self->config->show_mouse_pointer) {
                $self->app->log_message('debug', "Adding cursor to window capture");
                $self->add_cursor($screenshot, $x, $y);
            }
            
            $self->save_screenshot($screenshot);
        };
        
        if ($@) {
            if ($@ =~ /Could not get window geometry/) {
                $self->app->log_message('error', "Could not determine window size. Please try another capture method.");
            } elsif ($@ =~ /Failed to capture window/) {
                $self->app->log_message('error', "Failed to capture window. Please try again or use region capture.");
            } else {
                $self->app->log_message('error', "Error capturing window: $@");
            }
        }
    } elsif ($self->app->window_system eq 'wayland') {
       
        if ($self->config->capture_window_decoration) {
            $self->capture_wayland_window(1); 
        } else {
            $self->capture_wayland_window(0);  
        }
    }
}

sub capture_wayland_window {
    my ($self, $with_decorations) = @_;
    
    my $timestamp = strftime("%Y-%m-%d-%H%M%S", localtime);
    my $file_path = $self->config->save_location . "/Screenshot-$timestamp." . $self->config->image_format;
    
    if (!-d $self->config->save_location) {
        make_path($self->config->save_location);
    }
    
    my $cmd;
    if ($with_decorations) {
        $cmd = "gnome-screenshot --window --include-border --file=\"$file_path\"";
    } else {
        $cmd = "gnome-screenshot --window --file=\"$file_path\"";
    }
    
    $self->app->log_message('info', "Executing: $cmd");
    system($cmd);
    
    if (-f $file_path && -s $file_path > 0) {
        $self->app->log_message('info', "Screenshot captured successfully");
        
        if ($self->config->show_floating_thumbnail) {
            my $pixbuf = eval { Gtk3::Gdk::Pixbuf->new_from_file($file_path); };
            if ($pixbuf) {
                $self->ui->show_floating_thumbnail($pixbuf, $file_path);
            }
        }
    } else {
        $self->app->log_message('warning', "Screenshot capture failed or was canceled");
    }
}

sub add_cursor {
    my ($self, $screenshot, $region_x, $region_y) = @_;
    
    require ScreenshotTool::CursorUtils;
    my $cursor_utils = ScreenshotTool::CursorUtils->new(app => $self->app);
    return $cursor_utils->add_cursor_to_screenshot($screenshot, $region_x, $region_y);
}

sub set_pixel {
    my ($self, $pixbuf, $x, $y, $r, $g, $b, $a) = @_;
    
    return if $x < 0 || $y < 0 || $x >= $pixbuf->get_width() || $y >= $pixbuf->get_height();
    
    my $surface = Cairo::ImageSurface->create('argb32', 1, 1);
    my $cr = Cairo::Context->create($surface);
    
    $cr->set_source_rgba($r/255, $g/255, $b/255, $a/255);
    $cr->rectangle(0, 0, 1, 1);
    $cr->fill();
    
    my $temp_pixbuf = Gtk3::Gdk::pixbuf_get_from_surface($surface, 0, 0, 1, 1);
    
    $temp_pixbuf->copy_area(0, 0, 1, 1, $pixbuf, $x, $y);
}

sub save_screenshot {
    my ($self, $pixbuf) = @_;
    
    if (!defined $pixbuf) {
        $self->app->log_message('error', "Undefined pixbuf in save_screenshot()");
        return;
    }
    
    if ($self->config->save_location eq 'clipboard') {
       
        my $clipboard = Gtk3::Clipboard::get(Gtk3::Gdk::Atom::intern('CLIPBOARD', FALSE));
        $clipboard->set_image($pixbuf);
        $self->app->log_message('info', "Screenshot copied to clipboard");
    } else {
      
        if ($self->config->show_floating_thumbnail) {
            $self->ui->show_floating_thumbnail($pixbuf, undef);
        } else {
       
            my $timestamp = strftime("%Y-%m-%d-%H%M%S", localtime);
            my $filename = "Screenshot-$timestamp";
            $self->ui->save_screenshot_from_preview($pixbuf, $filename, $self->config->save_location);
        }
    }
}

sub generate_thumbnail {
    my ($self, $pixbuf, $filepath) = @_;
    
    eval {
      
        my $abs_path = File::Spec->rel2abs($filepath);
        my $file_uri = URI::file->new($abs_path)->as_string;
        
        my $md5_hash = md5_hex($file_uri);
        
        my $thumbnail_dir = "$ENV{HOME}/.cache/thumbnails/normal";
        if (!-d $thumbnail_dir) {
            make_path($thumbnail_dir, { mode => 0755 });
        }
        
        my $thumbnail_path = "$thumbnail_dir/$md5_hash.png";
        
        my $mtime = (stat($filepath))[9];
        
        my $width = $pixbuf->get_width();
        my $height = $pixbuf->get_height();
        my $scale_factor;
        
        if ($width > $height) {
            $scale_factor = 128.0 / $width;
        } else {
            $scale_factor = 128.0 / $height;
        }
        
        my $thumb_width = int($width * $scale_factor);
        my $thumb_height = int($height * $scale_factor);
        
        my $thumb_pixbuf = $pixbuf->scale_simple($thumb_width, $thumb_height, 'bilinear');

        $thumb_pixbuf->set_option('tEXt::Thumb::URI', $file_uri);
        $thumb_pixbuf->set_option('tEXt::Thumb::MTime', $mtime);
        $thumb_pixbuf->set_option('tEXt::Software', $self->app->app_name . ' ' . $self->app->app_version);
        
        $thumb_pixbuf->save($thumbnail_path, 'png');
        
        $self->app->log_message('info', "Generated thumbnail for system cache: $thumbnail_path");
    };
    
    if ($@) {
        $self->app->log_message('warning', "Failed to generate thumbnail: $@");
    }
}

1;





