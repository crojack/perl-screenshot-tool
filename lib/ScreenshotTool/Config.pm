package ScreenshotTool::Config;

use strict;
use warnings;
use File::Path qw(make_path);
use File::Spec;
use POSIX qw(strftime);

# List of configuration keys and their default values
my %DEFAULT_CONFIG = (
    # Selection mode (0 = window, 1 = region, 2 = fullscreen)
    selection_mode => 0,
    
    # Timer in seconds (0 = disabled, 3 = 3s, 5 = 5s, 10 = 10s)
    timer_value => 0,
    
    # Image format (png, jpg, webp, or avif if supported)
    image_format => "jpg",
    
    # Show floating thumbnail after capture
    show_floating_thumbnail => 1,
    
    # Remember the last selection region
    remember_last_selection => 1,
    
    # Include mouse pointer in screenshots
    show_mouse_pointer => 0,
    
    # Include window decorations when capturing a window
    capture_window_decoration => 1,
    
    # Option to allow capturing the main application window
    allow_self_capture => 0,
    
    # Delay before capture in milliseconds
    hide_delay => 300,
    
    # Save location (path or 'clipboard')
    save_location => undef, # Will be set to default in constructor
    
    # Last directory used for saving
    last_saved_dir => undef, # Will be set to default in constructor
);

# Constructor
sub new {
    my ($class, %args) = @_;
    
    my $app = $args{app} || die "App reference is required";
    
    my $self = bless {
        app => $app,
        
        # UI constants
        HANDLE_SIZE => 8,
        BORDER_WIDTH => 1,
        SELECTION_OPACITY => 0.3,
        DEFAULT_WIDTH => 800,
        DEFAULT_HEIGHT => 600,
        
        # Paths
        custom_icons_dir => "$ENV{HOME}/.local/share/perl-screenshot-tool/share/icons",
        
        # Format support
        avif_supported => 0,      # Will be checked later
    }, $class;
    
    # Initialize with default values
    foreach my $key (keys %DEFAULT_CONFIG) {
        $self->{$key} = $DEFAULT_CONFIG{$key};
    }
    
    # Set default save location
    $self->{save_location} = $self->get_default_save_location();
    $self->{last_saved_dir} = $self->{save_location};
    
    # Ensure custom icons directory exists
    $self->ensure_custom_icons_dir();
    
    # Check for AVIF support
    $self->{avif_supported} = $self->check_avif_support();
    if ($self->{avif_supported}) {
        $self->app->log_message('info', "AVIF format is supported on this system");
    } else {
        $self->app->log_message('info', "AVIF format is not supported on this system");
    }
    
    # Load saved configuration if available
    $self->load_config();
    
    return $self;
}

# Load configuration from file
sub load_config {
    my ($self) = @_;
    
    my $config_dir = "$ENV{HOME}/.config/perl-screenshot-tool";
    my $config_file = "$config_dir/config";
    
    $self->app->log_message('info', "Attempting to load config from: $config_file");
    
    # Return if config file doesn't exist
    if (!-f $config_file) {
        $self->app->log_message('info', "No config file found, using defaults");
        return;
    }
    
    # Open and read the config file
    open(my $fh, '<', $config_file) or do {
        $self->app->log_message('warning', "Could not open config file for reading: $!");
        return;
    };
    
    while (my $line = <$fh>) {
        chomp $line;
        
        # Skip empty lines and comments
        next if $line =~ /^\s*$/;
        next if $line =~ /^\s*#/;
        
        # Parse key=value pairs
        if ($line =~ /^\s*(\w+)\s*=\s*(.+?)\s*$/) {
            my ($key, $value) = ($1, $2);
            
            # Only set known configuration values
            if (exists $DEFAULT_CONFIG{$key}) {
                # Convert string "0" and "1" to actual 0 and 1 for boolean values
                if ($key =~ /^(show_floating_thumbnail|show_mouse_pointer|capture_window_decoration|allow_self_capture|remember_last_selection)$/) {
                    $value = ($value eq "1" || $value eq "true" || $value eq "yes") ? 1 : 0;
                }
                
                # Convert numeric values
                if ($key =~ /^(selection_mode|timer_value|hide_delay)$/) {
                    $value = int($value);
                }
                
                # Special handling for save_location
                if ($key eq "save_location" && $value ne "clipboard") {
                    # Ensure the directory exists
                    if (!-d $value) {
                        # If directory doesn't exist, try to create it or fall back to default
                        eval { make_path($value) };
                        if ($@ || !-d $value) {
                            $self->app->log_message('warning', "Save location '$value' doesn't exist and couldn't be created, using default");
                            $value = $self->get_default_save_location();
                        }
                    }
                }
                
                # Set the value in our config object
                $self->{$key} = $value;
                $self->app->log_message('debug', "Config: Set $key = $value");
            }
        }
    }
    
    close($fh);
    $self->app->log_message('info', "Configuration loaded successfully");
}

# Save configuration to file
sub save_config {
    my ($self) = @_;
    
    my $config_dir = "$ENV{HOME}/.config/perl-screenshot-tool";
    my $config_file = "$config_dir/config";
    
    $self->app->log_message('info', "Saving config to: $config_file");
    
    # Create config directory if it doesn't exist
    if (!-d $config_dir) {
        eval { make_path($config_dir) };
        if ($@ || !-d $config_dir) {
            $self->app->log_message('error', "Could not create config directory: $config_dir - $@");
            return 0;
        }
    }
    
    # Open the config file for writing
    open(my $fh, '>', $config_file) or do {
        $self->app->log_message('error', "Could not open config file for writing: $!");
        return 0;
    };
    
    # Write header with timestamp
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    print $fh "# Perl Screenshot Tool configuration\n";
    print $fh "# Last saved: $timestamp\n";
    print $fh "# Auto-generated file - edit at your own risk\n\n";
    
    # Write settings
    print $fh "# Capture mode (0 = window, 1 = region, 2 = fullscreen)\n";
    print $fh "selection_mode=$self->{selection_mode}\n\n";
    
    print $fh "# Timer in seconds (0 = disabled)\n";
    print $fh "timer_value=$self->{timer_value}\n\n";
    
    print $fh "# Image format (png, jpg, webp, avif)\n";
    print $fh "image_format=$self->{image_format}\n\n";
    
    print $fh "# Save location (path or 'clipboard')\n";
    print $fh "save_location=$self->{save_location}\n\n";
    
    print $fh "# Show floating thumbnail after capture (1 = yes, 0 = no)\n";
    print $fh "show_floating_thumbnail=$self->{show_floating_thumbnail}\n\n";
    
    print $fh "# Show mouse pointer in screenshots (1 = yes, 0 = no)\n";
    print $fh "show_mouse_pointer=$self->{show_mouse_pointer}\n\n";
    
    print $fh "# Capture window decorations (1 = yes, 0 = no)\n";
    print $fh "capture_window_decoration=$self->{capture_window_decoration}\n\n";
    
    print $fh "# Allow capturing the main application window (1 = yes, 0 = no)\n";
    print $fh "allow_self_capture=$self->{allow_self_capture}\n\n";
    
    print $fh "# Remember last selection (1 = yes, 0 = no)\n";
    print $fh "remember_last_selection=$self->{remember_last_selection}\n\n";
    
    print $fh "# Delay before capture in milliseconds\n";
    print $fh "hide_delay=$self->{hide_delay}\n";
    
    close($fh);
    $self->app->log_message('info', "Configuration saved successfully");
    
    return 1;
}

# Check if AVIF is supported
sub check_avif_support {
    my ($self) = @_;
    
    # Get the list of supported formats
    my @formats = Gtk3::Gdk::Pixbuf::get_formats(); 
    
    # Check if AVIF is in the list
    foreach my $format (@formats) {
        if ($format->get_name() eq 'avif') {
            return 1;
        }
    }
    
    return 0;
}

# NEW GENERIC CONFIG GETTER/SETTER
sub config_value {
    my ($self, $key, $new_value) = @_;
    
    # Check if the key is valid
    unless (exists $DEFAULT_CONFIG{$key} || $key =~ /^(custom_icons_dir|avif_supported)$/) {
        $self->app->log_message('warning', "Invalid configuration key: $key");
        return undef;
    }
    
    # Set new value if provided
    if (defined $new_value) {
        # Special handling for save_location
        if ($key eq 'save_location' && $new_value ne 'clipboard') {
            # Ensure directory exists
            if (!-d $new_value) {
                eval { make_path($new_value) };
                if ($@ || !-d $new_value) {
                    $self->app->log_message('warning', "Cannot create save location directory: $new_value");
                    return undef;
                }
            }
        }
        
        $self->{$key} = $new_value;
    }
    
    return $self->{$key};
}

# Getter for AVIF support
sub avif_supported {
    my ($self) = @_;
    return $self->{avif_supported};
}

# Get default save location
sub get_default_save_location {
    my ($self) = @_;
    
    my $desktop_dir = `xdg-user-dir DESKTOP`;
    chomp($desktop_dir);
    
    if (!$desktop_dir || !-d $desktop_dir) {
        $desktop_dir = $ENV{HOME} . '/Desktop';
        
        # Try to create Desktop directory if it doesn't exist
        if (!-d $desktop_dir) {
            eval { make_path($desktop_dir) };
            
            # Fall back to home directory if Desktop can't be created
            if ($@ || !-d $desktop_dir) {
                $self->app->log_message('warning', "Could not find or create Desktop directory, using home directory");
                $desktop_dir = $ENV{HOME};
            }
        }
    }
    
    return $desktop_dir;
}

# Ensure custom icons directory exists
sub ensure_custom_icons_dir {
    my ($self) = @_;
    
    if (!-d $self->{custom_icons_dir}) {
        $self->app->log_message('info', "Creating custom icons directory: $self->{custom_icons_dir}");
        eval { make_path($self->{custom_icons_dir}) };
        if ($@ || !-d $self->{custom_icons_dir}) {
            $self->app->log_message('warning', "Could not create custom icons directory: $@");
            return 0;
        }
    }
    
    # Check if we have custom icons
    if (opendir(my $dh, $self->{custom_icons_dir})) {
        my @icons = grep { /\.(png|svg)$/ } readdir($dh);
        closedir($dh);
        
        # Only print if no icons are found
        if (!@icons) {
            $self->app->log_message('warning', "No custom icons found in $self->{custom_icons_dir}");
        }
    } else {
        # Print if we can't open the directory
        $self->app->log_message('warning', "Cannot open custom icons directory: $self->{custom_icons_dir}");
    }
    
    return 1;
}

# Get app reference
sub app {
    my ($self) = @_;
    return $self->{app};
}

# The following accessors are kept for backward compatibility
# They use the new generic config_value method internally

# Get handle size
sub handle_size {
    my ($self) = @_;
    return $self->{HANDLE_SIZE};
}

# Get border width
sub border_width {
    my ($self) = @_;
    return $self->{BORDER_WIDTH};
}

# Get selection opacity
sub selection_opacity {
    my ($self) = @_;
    return $self->{SELECTION_OPACITY};
}

# Get default width for selection
sub default_width {
    my ($self) = @_;
    return $self->{DEFAULT_WIDTH};
}

# Get default height for selection
sub default_height {
    my ($self) = @_;
    return $self->{DEFAULT_HEIGHT};
}

# Get/set selection mode
sub selection_mode {
    my ($self, $new_value) = @_;
    return $self->config_value('selection_mode', $new_value);
}

# Get/set timer value
sub timer_value {
    my ($self, $new_value) = @_;
    return $self->config_value('timer_value', $new_value);
}

# Get/set image format
sub image_format {
    my ($self, $new_value) = @_;
    return $self->config_value('image_format', $new_value);
}

# Get/set show floating thumbnail
sub show_floating_thumbnail {
    my ($self, $new_value) = @_;
    return $self->config_value('show_floating_thumbnail', $new_value);
}

# Getter/setter for self capture option
sub allow_self_capture {
    my ($self, $new_value) = @_;
    return $self->config_value('allow_self_capture', $new_value);
}

# Getter/setter for hide delay
sub hide_delay {
    my ($self, $new_value) = @_;
    return $self->config_value('hide_delay', $new_value);
}

# Get/set remember last selection
sub remember_last_selection {
    my ($self, $new_value) = @_;
    return $self->config_value('remember_last_selection', $new_value);
}

# Get/set show mouse pointer
sub show_mouse_pointer {
    my ($self, $new_value) = @_;
    return $self->config_value('show_mouse_pointer', $new_value);
}

# Get/set capture window decoration
sub capture_window_decoration {
    my ($self, $new_value) = @_;
    return $self->config_value('capture_window_decoration', $new_value);
}

# Get/set save location
sub save_location {
    my ($self, $new_value) = @_;
    return $self->config_value('save_location', $new_value);
}

# Get/set last saved directory
sub last_saved_dir {
    my ($self, $new_value) = @_;
    return $self->config_value('last_saved_dir', $new_value);
}

# Get custom icons directory
sub custom_icons_dir {
    my ($self) = @_;
    return $self->{custom_icons_dir};
}

1;