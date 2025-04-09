package ScreenshotTool::Config;

use strict;
use warnings;
use Moo;
use File::Path qw(make_path);
use File::Spec;
use namespace::clean;


has 'app' => (
    is       => 'ro',
    required => 1,
);


has 'HANDLE_SIZE' => (
    is      => 'ro',
    default => sub { 8 },
);

has 'BORDER_WIDTH' => (
    is      => 'ro',
    default => sub { 1 },
);

has 'SELECTION_OPACITY' => (
    is      => 'ro',
    default => sub { 0.3 },
);

has 'DEFAULT_WIDTH' => (
    is      => 'ro',
    default => sub { 1100 },
);

has 'DEFAULT_HEIGHT' => (
    is      => 'ro',
    default => sub { 650 },
);


has 'selection_mode' => (
    is      => 'rw',
    default => sub { 0 },    # 0 = window, 1 = region, 2 = fullscreen
);

has 'timer_value' => (
    is      => 'rw',
    default => sub { 0 },    # 0 = none, 3 = 3 seconds, 5 = 5 seconds, 10 = 10 seconds
);

has 'image_format' => (
    is      => 'rw',
    default => sub { "jpg" },  # Default image format: png, jpg or webp
);

has 'show_floating_thumbnail' => (
    is      => 'rw',
    default => sub { 1 },
);

has 'remember_last_selection' => (
    is      => 'rw',
    default => sub { 1 },
);

has 'show_mouse_pointer' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'capture_window_decoration' => (
    is      => 'rw',
    default => sub { 1 },
);

has 'allow_self_capture' => (
    is      => 'rw',
    default => sub { 0 },  
);

has 'hide_delay' => (
    is      => 'rw',
    default => sub { 300 },  # 300ms delay before capturing (configurable)
);


has 'custom_icons_dir' => (
    is      => 'ro',
    default => sub { "$ENV{HOME}/.local/share/perl-screenshot-tool/share/icons" },
);

has 'save_location' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_save_location',
);

has 'last_saved_dir' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_last_saved_dir',
);


has 'avif_supported' => (
    is      => 'rw',
    default => sub { 0 },   # Will be checked during BUILD
);

sub BUILD {
    my ($self) = @_;
    
    $self->ensure_custom_icons_dir();
    
    my $avif_support = $self->check_avif_support();
    $self->avif_supported($avif_support);
    
    if ($avif_support) {
        $self->app->log_message('info', "AVIF format is supported on this system");
    } else {
        $self->app->log_message('info', "AVIF format is not supported on this system");
    }
}


sub _build_save_location {
    my ($self) = @_;
    return $self->get_default_save_location();
}

sub _build_last_saved_dir {
    my ($self) = @_;
    return $self->save_location;
}


sub check_avif_support {
    my ($self) = @_;
    
    my @formats = Gtk3::Gdk::Pixbuf::get_formats(); 
    
    foreach my $format (@formats) {
        if ($format->get_name() eq 'avif') {
            return 1;
        }
    }
    
    return 0;
}


sub get_default_save_location {
    my ($self) = @_;
    
    my $desktop_dir = `xdg-user-dir DESKTOP`;
    chomp($desktop_dir);
    
    if (!$desktop_dir || !-d $desktop_dir) {
        $desktop_dir = $ENV{HOME} . '/Desktop';
    }
    
    return $desktop_dir;
}


sub ensure_custom_icons_dir {
    my ($self) = @_;
    
    if (!-d $self->custom_icons_dir) {
        $self->app->log_message('info', "Creating custom icons directory: " . $self->custom_icons_dir);
        make_path($self->custom_icons_dir);
    }
    
    if (opendir(my $dh, $self->custom_icons_dir)) {
        my @icons = grep { /\.(png|svg)$/ } readdir($dh);
        closedir($dh);
        
        if (!@icons) {
            $self->app->log_message('warning', "No custom icons found in " . $self->custom_icons_dir);
        }
    } else {
     
        $self->app->log_message('warning', "Cannot open custom icons directory: " . $self->custom_icons_dir);
    }
}


sub config_value {
    my ($self, $key, $new_value) = @_;
    
    if (defined $key && $self->can($key)) {
        if (defined $new_value) {
            $self->$key($new_value);
        }
        return $self->$key;
    }
    return undef;
}


sub handle_size { return shift->HANDLE_SIZE; }
sub border_width { return shift->BORDER_WIDTH; }
sub selection_opacity { return shift->SELECTION_OPACITY; }
sub default_width { return shift->DEFAULT_WIDTH; }
sub default_height { return shift->DEFAULT_HEIGHT; }

1;
