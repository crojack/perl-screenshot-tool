package ScreenshotTool::Logger;

use strict;
use warnings;
use POSIX qw(strftime);
use File::Path qw(make_path);
use Fcntl qw(:flock);

sub new {
    my ($class, %args) = @_;
    
    my $self = bless {
        verbose => $args{verbose} || 0,
        log_to_file => $args{log_to_file} || 0,
        log_file => $args{log_file} || "$ENV{HOME}/.local/share/perl-screenshot-tool/logs/screenshot-tool.log",
        log_fh => undef,
        log_level => $args{log_level} || 'info', # default log level
        rotation_size => $args{rotation_size} || 5 * 1024 * 1024, # 5MB default rotation size
        max_log_files => $args{max_log_files} || 3, # Keep 3 rotated log files by default
    }, $class;
    
    # Set log level priority
    $self->{_level_priority} = {
        'debug' => 0,
        'info' => 1,
        'warning' => 2,
        'error' => 3,
        'none' => 999
    };
    
    if ($self->{log_to_file}) {
        $self->_init_log_file();
    }
    
    return $self;
}

sub _init_log_file {
    my ($self) = @_;
    
    # Ensure log directory exists
    my $log_dir = $self->{log_file};
    $log_dir =~ s|/[^/]+$||;
    
    if (!-d $log_dir) {
        eval { make_path($log_dir); };
        if ($@) {
            warn "Could not create log directory $log_dir: $!";
            $self->{log_to_file} = 0;
            return;
        }
    }
    
    # Check if log rotation is needed
    if (-f $self->{log_file} && -s $self->{log_file} > $self->{rotation_size}) {
        $self->rotate_logs();
    }
    
    # Open log file with error handling
    eval {
        open($self->{log_fh}, '>>', $self->{log_file}) or die "Cannot open log file: $!";
        
        # Set autoflush for log file
        my $old_fh = select($self->{log_fh});
        $| = 1;
        select($old_fh);
        
        # Try to get an exclusive lock for writing
        flock($self->{log_fh}, LOCK_EX | LOCK_NB) or die "Cannot lock log file: $!";
    };
    
    if ($@) {
        warn "Could not open log file $self->{log_file}: $@";
        $self->{log_to_file} = 0;
        $self->{log_fh} = undef;
    }
}

sub rotate_logs {
    my ($self) = @_;
    
    # Close the current log file if open
    if ($self->{log_fh}) {
        close($self->{log_fh});
        $self->{log_fh} = undef;
    }
    
    # Rotate existing log files
    for (my $i = $self->{max_log_files} - 1; $i >= 0; $i--) {
        my $old_file = $i == 0 ? $self->{log_file} : "$self->{log_file}.$i";
        my $new_file = "$self->{log_file}.".($i + 1);
        
        if (-f $old_file) {
            rename($old_file, $new_file);
        }
    }
    
    # Remove the oldest log file if it exceeds max_log_files
    my $oldest_file = "$self->{log_file}.".$self->{max_log_files};
    unlink($oldest_file) if -f $oldest_file;
}

sub log {
    my ($self, $level, $message) = @_;
    
    # Check if this log level should be logged
    return if $self->{_level_priority}{$level} < $self->{_level_priority}{$self->{log_level}};
    
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    my $log_message = "[$timestamp] [$level] $message\n";
    
    # Print to console if verbose mode or level is higher than debug
    if ($self->{verbose} || $level ne 'debug') {
        print $log_message;
    }
    
    # Log to file if enabled
    if ($self->{log_to_file} && $self->{log_fh}) {
        eval {
            print {$self->{log_fh}} $log_message;
            
            # Check if log rotation is needed after writing
            if (-s $self->{log_file} > $self->{rotation_size}) {
                $self->rotate_logs();
                $self->_init_log_file(); # Reopen the log file
            }
        };
        
        # If writing to log file fails, try to reopen it
        if ($@) {
            warn "Error writing to log file: $@";
            $self->_init_log_file();
        }
    }
}

sub debug {
    my ($self, $message) = @_;
    $self->log('debug', $message);
}

sub info {
    my ($self, $message) = @_;
    $self->log('info', $message);
}

sub warning {
    my ($self, $message) = @_;
    $self->log('warning', $message);
}

sub error {
    my ($self, $message) = @_;
    $self->log('error', $message);
}

sub set_log_level {
    my ($self, $level) = @_;
    
    if (exists $self->{_level_priority}{$level}) {
        $self->{log_level} = $level;
        return 1;
    }
    return 0;
}

sub close {
    my ($self) = @_;
    
    if ($self->{log_fh}) {
        close($self->{log_fh});
        $self->{log_fh} = undef;
    }
}

1;