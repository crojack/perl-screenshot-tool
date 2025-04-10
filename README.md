# Perl Screenshot Tool

A screenshot utility for Linux that works best on X11. It also supports Gnome Wayland through the gnome-screenshot backend. For KDE Plasma Wayland sessions, please use the native screenshot tools.

![Selection_001](https://github.com/user-attachments/assets/2e921beb-981e-427a-b691-e2b76e854641)


![Screenshot-2025-04-09-233033](https://github.com/user-attachments/assets/8ab886d8-7215-44cf-9638-9d1fa4eea73c)


![Workspace 1_001](https://github.com/user-attachments/assets/d6fa0aa9-1962-418b-bf99-992006435a48)


![Workspace 1_001](https://github.com/user-attachments/assets/e1d4a3bf-2d80-4e6b-9f24-8767e5ac2f99)

## Features

- Capture windows, regions, or entire screen
- Easily drag and resize the area selector
- View preview window (floating thumbnail) of screenshots
- Save screenshots to files or copy directly to clipboard
- Support for multiple image formats: PNG, JPG, WebP, and AVIF (if supported on your system)
- Customize the UI with your own icons, colors, and sizes
- Set capture timers for perfect screenshots

  ![Workspace 1_001](https://github.com/user-attachments/assets/b1a31ebf-963d-4cd7-a4e1-caa64dab31b6)


  ![Workspace 1_002](https://github.com/user-attachments/assets/7b527702-5f8c-4702-9cfb-690b8f07fb41)



## Wayland Support

This tool offers Gnome Wayland support via the gnome-screenshot backend:

- **GNOME Wayland**: Uses the native `gnome-screenshot` utility for reliable captures in GNOME environments

### Wayland Considerations

- Window positioning on Wayland depends on your compositor
- Some features like precise window placement have limitations on Wayland due to security constraints
- For GNOME Wayland sessions, make sure `gnome-screenshot` is installed

## UI Customization

### Icon Size Adjustment

You can change the size of the application buttons to match your preferences:

- Click the "Interface" button
- Choose from sizes ranging from 40×40 to 88×88 pixels

### Color Themes

Customize the application's appearance:

- Change background, text, and accent colors
- Access through the "Interface" button → Color Theme
- Preview changes before applying
- Reset to system defaults if needed

## Dependencies

### Required Packages

- Perl 5.10 or newer
- GTK3 libraries and Perl bindings
- Cairo libraries and Perl bindings

### Perl Modules

- Gtk3
- Cairo
- Moo
- File::Path
- File::Spec
- File::Temp
- POSIX
- Digest::MD5
- namespace::clean

### Optional Dependencies

- **X11::Protocol**: For better cursor capture on X11 systems
- **X11::Protocol::XFixes**: For cursor capture support (highly recommended for X11)
- **libavif**: For AVIF image format support

**For Debian/Ubuntu/Mint:**
```
sudo apt install perl libgtk3-perl libcairo-perl libmoo-perl libnamespace-clean-perl libx11-protocol-perl libx11-protocol-other-perl libfile-path-perl libdigest-md5-perl
```

**For Fedora/RHEL:**
```
sudo dnf install perl perl-Gtk3 perl-Cairo perl-Moo perl-namespace-clean perl-X11-Protocol perl-File-Path perl-Digest-MD5
```

**For Arch Linux:**
```
sudo pacman -S perl gtk3-perl cairo-perl perl-moo perl-namespace-clean perl-x11-protocol
```

**For other distributions:**
Install the following Perl modules:
```
cpanm Gtk3 Cairo File::Path File::Spec File::Temp POSIX File::Copy::Recursive
```

For Gnome Wayland support, install this additional package:

**For Debian/Ubuntu/Mint:**
```
sudo apt-get install gnome-screenshot

```

**For Fedora/RHEL:**
```
sudo dnf install gnome-screenshot
```

**For Arch Linux:**
```
sudo pacman -S gnome-screenshot
```

## Installation

### Standard Installation

1. Download the source code:
   ```
   git clone https://github.com/crojack/perl-screenshot-tool.git
   cd perl-screenshot-tool
   ```
2. Run the installation script:
   ```
   perl install.pl
   ```
3. You can also download the source code zip manually:

![Screenshot-2025-04-09-135150](https://github.com/user-attachments/assets/8ac9c568-4c4a-4010-9856-dfd6d5a05221)

unzip it, open terminal inside the perl-screenshot-tool folder, and run:

```
   perl install.pl
   ```
## Manual Installation

If you prefer to install manually:

1. Copy `bin/screenshot-tool.pl` to `/usr/bin/screenshot-tool` or `~/.local/bin/screenshot-tool`
2. Copy `applications/screenshot-tool.desktop` to `/usr/share/applications/` or `~/.local/share/applications/`
3. Copy bin, lib and share directories to `~/.local/share/perl-screenshot-tool/`
4. Make sure the executable has the correct permissions: `chmod +x /usr/bin/screenshot-tool`

## Configuration

The configuration file is stored at:
```
~/.config/perl-screenshot-tool/config
```

Other files like modules and icons are stored at:
```
~/.local/share/perl-screenshot-tool
```

## Usage

- Launch from your application menu or run `screenshot-tool` in the terminal
- Use keyboard shortcuts:
  - **Ctrl+W**: Capture active window
  - **Ctrl+R**: Capture selected region
  - **Ctrl+D**: Capture entire desktop
- Use the UI buttons to select capture mode
- Configure options through the options menu

### Running in Background (to do!)

The application can run in the background, allowing you to use keyboard shortcuts without keeping the main window open:

- To start minimized: Use the `--start-minimized` or `-m` flag
- To run in system tray: Right-click the application window and select "Minimize to Tray"
- To restore from system tray: Click on the tray icon

### Save Options

- Save to Desktop
- Save to Pictures folder
- Save to clipboard
- Save to custom location

### Image Formats

- PNG 
- JPG 
- WebP 
- AVIF (if supported by your system)

### Capture Timer

You can set a delay before capturing:

- None (immediate capture)
- 3 seconds
- 5 seconds
- 10 seconds

## Technical Details

The application automatically detects your desktop environment and display server:

- X11 environments use native Gtk3 functionality for capturing
- GNOME Wayland uses gnome-screenshot

## Support

For issues or suggestions, please open an issue on GitHub.

## License

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
