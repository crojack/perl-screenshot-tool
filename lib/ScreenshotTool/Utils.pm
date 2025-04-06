package ScreenshotTool::Utils;

use strict;
use warnings;
use File::Path qw(make_path);
use File::Spec;
use POSIX qw(strftime);
use IPC::Open3;
use Symbol qw(gensym);
use IO::Handle;

# Constructor
sub new {
    my ($class, %args) = @_;
    
    my $app = $args{app} || die "App reference is required";
    
    my $self = bless {
        app => $app,
    }, $class;
    
    return $self;
}

# Get app reference
sub app {
    my ($self) = @_;
    return $self->{app};
}

# Generate a timestamp-based filename
sub generate_filename {
    my ($self, $format) = @_;
    
    my $timestamp = strftime("%Y-%m-%d-%H%M%S", localtime);
    return "Screenshot-$timestamp.$format";
}

# Ensure directory exists
sub ensure_directory {
    my ($self, $dir) = @_;
    
    if (!-d $dir) {
        $self->app->log_message('info', "Creating directory: $dir");
        eval { make_path($dir); };
        if ($@ || !-d $dir) {
            $self->app->log_message('error', "Could not create directory: $dir - $@");
            return 0;
        }
        return 1;
    }
    
    # Check if directory is writable
    if (!-w $dir) {
        $self->app->log_message('warning', "Directory not writable: $dir");
        return 0;
    }
    
    return 1;
}

# Get min value (helper)
sub min {
    my ($self, $a, $b) = @_;
    return $a < $b ? $a : $b;
}

# Normalize rectangle (make sure width and height are positive)
sub normalize_rect {
    my ($self, $x, $y, $w, $h) = @_;
    
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

# Convert format string for Gtk
sub map_format_string {
    my ($self, $format) = @_;
    
    if ($format eq "jpg") {
        return "jpeg";
    } elsif ($format eq "webp") {
        return "webp";
    } else {
        return $format; # png or others
    }
}

# Get timestamp
sub get_timestamp {
    my ($self) = @_;
    return strftime("%Y-%m-%d %H:%M:%S", localtime);
}

# Get date-time string for filename
sub get_datetime_for_filename {
    my ($self) = @_;
    return strftime("%Y-%m-%d-%H%M%S", localtime);
}

# NEW FUNCTION: Get standard paths for application data
sub get_path_for_cache {
    my ($self, $type) = @_;
    
    my %paths = (
        'thumbnails' => "$ENV{HOME}/.cache/thumbnails/normal",
        'config' => "$ENV{HOME}/.config/perl-screenshot-tool",
        'data' => "$ENV{HOME}/.local/share/perl-screenshot-tool",
        'logs' => "$ENV{HOME}/.local/share/perl-screenshot-tool/logs",
        'icons' => "$ENV{HOME}/.local/share/perl-screenshot-tool/share/icons",
    );
    
    return $paths{$type} || '';
}

# NEW FUNCTION: Ensure path exists with proper error handling
sub ensure_path_exists {
    my ($self, $path, $mode) = @_;
    $mode ||= 0755;
    
    if (!-d $path) {
        eval { make_path($path, { mode => $mode }); };
        if ($@ || !-d $path) {
            $self->app->log_message('error', "Could not create directory: $path - $@");
            return 0;
        }
        $self->app->log_message('info', "Created directory: $path");
    }
    
    # Check if directory is writable
    if (!-w $path) {
        $self->app->log_message('warning', "Directory not writable: $path");
        return 0;
    }
    
    return 1;
}

# NEW FUNCTION: Handle errors consistently
sub handle_error {
    my ($self, $error_type, $message, $show_dialog) = @_;
    
    $self->app->log_message('error', $message);
    
    if ($show_dialog && $self->app->{ui}) {
        $self->app->{ui}->show_error_dialog($error_type, $message);
    }
    
    return 0; # Indicating error
}

# NEW FUNCTION: Check if a command is available
sub is_command_available {
    my ($self, $command) = @_;
    
    my $result = system("which $command >/dev/null 2>&1") == 0;
    $self->app->log_message('debug', "Command '$command' " . ($result ? "is" : "is not") . " available");
    return $result;
}

# NEW FUNCTION: Run command safely
sub run_command {
    my ($self, $command, $args) = @_;
    
    # Validate command exists
    if (!$self->is_command_available($command)) {
        $self->app->log_message('error', "Command not found: $command");
        return (1, "Command not found: $command");
    }
    
    # Build command safely using array for system
    my @cmd = ($command);
    
    # Add arguments safely
    if (defined $args) {
        if (ref($args) eq 'ARRAY') {
            push @cmd, @$args;
        } else {
            # Split string args, but prefer array form
            push @cmd, split(/\s+/, $args);
        }
    }
    
    # Log the command we're executing
    $self->app->log_message('debug', "Executing: " . join(' ', @cmd));
    
    # Capture output with proper error handling
    my $output = '';
    eval {
        my ($in, $out, $err);
        $err = gensym;
        
        my $pid = open3($in, $out, $err, @cmd);
        close $in;
        
        local $/ = undef;
        $output = <$out>;
        my $error = <$err>;
        
        waitpid($pid, 0);
        my $exit_code = $? >> 8;
        
        if ($exit_code != 0) {
            $self->app->log_message('warning', "Command exited with code $exit_code: $error");
            return ($exit_code, $error);
        }
    };
    
    if ($@) {
        $self->app->log_message('error', "Failed to execute command: $@");
        return (1, $@);
    }
    
    return (0, $output);
}

1;