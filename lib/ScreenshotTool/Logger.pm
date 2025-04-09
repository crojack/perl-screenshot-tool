package ScreenshotTool::Logger;

use strict;
use warnings;
use Moo;
use POSIX qw(strftime);
use File::Path qw(make_path);
use Fcntl qw(:flock);
use namespace::clean;

has 'verbose' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'log_to_file' => (
    is      => 'rw',
    default => sub { 0 },
);

has 'log_file' => (
    is      => 'rw',
    default => sub { "$ENV{HOME}/.local/share/perl-screenshot-tool/logs/screenshot-tool.log" },
);

has 'log_fh' => (
    is      => 'rw',
    default => sub { undef },
);

has 'log_level' => (
    is      => 'rw',
    default => sub { 'info' },  
);

has 'rotation_size' => (
    is      => 'rw',
    default => sub { 5 * 1024 * 1024 },  
);

has 'max_log_files' => (
    is      => 'rw',
    default => sub { 3 },  
);


has '_level_priority' => (
    is      => 'ro',
    default => sub {
        {
            'debug'   => 0,
            'info'    => 1,
            'warning' => 2,
            'error'   => 3,
            'none'    => 999
        }
    },
);

sub BUILD {
    my ($self) = @_;
    
    if ($self->log_to_file) {
        $self->_init_log_file();
    }
}

sub _init_log_file {
    my ($self) = @_;
    
    my $log_dir = $self->log_file;
    $log_dir =~ s|/[^/]+$||;
    
    if (!-d $log_dir) {
        eval { make_path($log_dir); };
        if ($@) {
            warn "Could not create log directory $log_dir: $!";
            $self->log_to_file(0);
            return;
        }
    }
    
    if (-f $self->log_file && -s $self->log_file > $self->rotation_size) {
        $self->rotate_logs();
    }
    
    eval {
        my $fh;
        open($fh, '>>', $self->log_file) or die "Cannot open log file: $!";
        
        my $old_fh = select($fh);
        $| = 1;
        select($old_fh);
        
        flock($fh, LOCK_EX | LOCK_NB) or die "Cannot lock log file: $!";
        
        $self->log_fh($fh);
    };
    
    if ($@) {
        warn "Could not open log file " . $self->log_file . ": $@";
        $self->log_to_file(0);
        $self->log_fh(undef);
    }
}

sub rotate_logs {
    my ($self) = @_;
    
    if ($self->log_fh) {
        close($self->log_fh);
        $self->log_fh(undef);
    }
    
    for (my $i = $self->max_log_files - 1; $i >= 0; $i--) {
        my $old_file = $i == 0 ? $self->log_file : $self->log_file . ".$i";
        my $new_file = $self->log_file . "." . ($i + 1);
        
        if (-f $old_file) {
            rename($old_file, $new_file);
        }
    }
    
    my $oldest_file = $self->log_file . "." . $self->max_log_files;
    unlink($oldest_file) if -f $oldest_file;
}

sub log {
    my ($self, $level, $message) = @_;
    
    return if $self->_level_priority->{$level} < $self->_level_priority->{$self->log_level};
    
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    my $log_message = "[$timestamp] [$level] $message\n";
    
    if ($self->verbose || $level ne 'debug') {
        print $log_message;
    }
    
    if ($self->log_to_file && $self->log_fh) {
        eval {
            my $fh = $self->log_fh;
            print {$fh} $log_message;
            
            if (-s $self->log_file > $self->rotation_size) {
                $self->rotate_logs();
                $self->_init_log_file();
            }
        };
        
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
    
    if (exists $self->_level_priority->{$level}) {
        $self->log_level($level);
        return 1;
    }
    return 0;
}

sub close {
    my ($self) = @_;
    
    if ($self->log_fh) {
        close($self->log_fh);
        $self->log_fh(undef);
    }
}

1;
