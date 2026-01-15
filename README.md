# Shepherd

A macOS menu bar app for intelligent screen and audio monitoring with keyword detection.

![macOS 13.0+](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)

## Features

### Visual Monitoring
- **Screen Region Capture** - Select any screen region to monitor
- **OCR Keyword Detection** - Detect text keywords using Vision framework
- **Window Sticky Mode** - Watchers follow windows when moved
- **Smart Snap** - Magnetic UI element detection using Accessibility API

### Audio Monitoring
- **System Audio Capture** - Monitor audio from any application
- **Speech Recognition** - Real-time transcription with keyword detection
- **Audio Replay** - 30-second time rewind to replay what was said
- **Smart Defaults** - Auto-recommends Audio mode for meeting apps (Zoom, Teams, etc.)

### Performance
- **Dynamic Frame Rate** - Adaptive capture frequency (0.5s-5s) based on content changes
- **Low CPU Usage** - Reduces to ~0.2 FPS when screen is static

### Notifications
- **macOS Notifications** - Alert with evidence screenshots
- **Webhook Support** - POST alerts to custom endpoints with Base64 images

## Installation

1. Clone the repository
2. Open `Shepherd.xcodeproj` in Xcode
3. Build and run (Cmd+R)

## Requirements

- macOS 13.0 or later
- Screen Recording permission (for visual monitoring)
- Accessibility permission (for Smart Snap)
- Speech Recognition permission (for audio monitoring)

## Usage

1. Click the Shepherd icon in the menu bar
2. Click "New Watcher" or press `Cmd+Shift+S`
3. Select a screen region or click to snap to UI elements
4. Choose Visual or Audio mode
5. Enter a name and keyword to watch for
6. Click "Create"

### Watch Modes

| Mode | Icon | Use Case |
|------|------|----------|
| Visual | Eye | Monitor screen text (chat messages, notifications) |
| Audio | Ear | Monitor spoken words (meetings, calls) |

### Smart Defaults

Shepherd automatically recommends Audio mode for:
- Zoom, Microsoft Teams, Google Meet
- Slack, Discord, Skype
- FaceTime, Webex

## Architecture

```
Sources/
├── App/
│   └── ShepherdApp.swift       # Main app entry point
├── Managers/
│   ├── AccessibilityManager.swift  # Smart Snap (AXUIElement)
│   ├── AudioCaptureManager.swift   # System audio capture
│   ├── HotkeyManager.swift         # Global hotkey handling
│   ├── OverlayWindowController.swift
│   ├── WatcherManager.swift        # Core monitoring logic
│   └── WhisperManager.swift        # Speech recognition
├── Models/
│   └── AppState.swift          # App state, Watcher model
├── Utils/
│   └── Constants.swift         # Colors, animations, layout
└── Views/
    ├── InputPillView.swift     # Watcher creation UI
    ├── MenuBarView.swift       # Menu bar dropdown
    ├── SelectionOverlayView.swift  # Region selection overlay
    ├── SettingsView.swift      # Settings panel
    └── WatcherMarkView.swift   # On-screen watcher indicators
```

## Version History

### v3.1 (Current)
- Smart Snap: Magnetic UI element detection
- Audio Replay: 30-second buffer playback
- Dynamic Frame Rate: Adaptive capture frequency
- Model Loading Indicator: Speech recognition status
- Smart Defaults: Auto-recommend mode based on app
- Improved Audio UI text

### v3.0
- Audio monitoring with speech recognition
- Visual/Audio mode toggle
- System audio capture via ScreenCaptureKit

### v2.0
- Window sticky mode
- Watchers follow windows when moved

### v1.0
- Basic screen region monitoring
- OCR keyword detection
- macOS notifications

## License

MIT License

## Credits

Built with Claude Code by Anthropic.
