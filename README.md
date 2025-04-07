# Perl Screenshot Tool

A flexible screenshot utility for Linux that works on both X11 and Wayland.

## Features

- Window, region, and fullscreen captures
- Support for both X11 and Wayland
- Save screenshots to file or clipboard
- Various image formats: PNG, JPG, WebP, AVIF (if supported)
- Customizable options
- System tray support

## Installation

###  Standard Installation

1. Download the source code:
   ```
   git clone https://github.com/crojack/perl-screenshot-tool.git
   cd perl-screenshot-tool
   ```

2. Run the installation script:
   ```
   perl install.pl
   ```

3. Launch the application:
   - From the application menu: Look for "Perl Screenshot Tool"
   - From the command line: `screenshot-tool`

## Dependencies

### For Debian/Ubuntu:

All dependencies will be automatically installed when using the .deb package.

If installing manually, you'll need:
```
sudo apt-get install libgtk3-perl libcairo-perl libfile-copy-recursive-perl
```

### For other distributions:

Install the following Perl modules:
```
cpanm Gtk3 Cairo File::Path File::Spec File::Temp POSIX File::Copy::Recursive
```

## Manual Installation

If you prefer to install manually:

1. Copy `bin/screenshot-tool.pl` to `/usr/bin/screenshot-tool` or `~/.local/bin/screenshot-tool`
2. Copy `applications/screenshot-tool.desktop` to `/usr/share/applications/` or `~/.local/share/applications/`
3. Copy the entire project directory to `~/.local/share/perl-screenshot-tool/`
4. Ensure the executable has the correct permissions: `chmod +x /usr/bin/screenshot-tool`

## Configuration

The configuration file is stored at:
```
~/.config/perl-screenshot-tool/config
```

## Usage

### Keyboard Shortcuts

- `PrintScreen` - Capture entire desktop
- `Alt+PrintScreen` - Capture active window
- `Shift+PrintScreen` - Capture selected region
- `Ctrl+1` or `Ctrl+W` - Capture active window
- `Ctrl+2` or `Ctrl+R` - Capture selected region  
- `Ctrl+3` or `Ctrl+D` - Capture entire desktop

### Save Options

- Save to Desktop
- Save to Pictures folder
- Save to clipboard
- Save to custom location

### Image Formats

- PNG (lossless)
- JPG (compressed)
- WebP (modern compressed format)
- AVIF (if supported by your system)

## Support

For any issues or suggestions, please open an issue on GitHub.

