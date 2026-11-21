# Barloom

A sleek Windows 11–style taskbar for macOS that replaces the Dock.

- Full-width translucent bar pinned to the bottom of every display
- Centered Start button + pinned and running apps, with Fluent-style hover plates and running/active indicators
- Click the focused app to hide it (like minimising), click anything else to bring it forward or launch it
- Right-click an icon to pin/unpin, show in Finder or quit; drag icons to reorder pins
- Start menu: instant app search (Return launches the top hit), pinned apps, all apps, power and settings menus
- Clock/date with a calendar flyout, battery indicator on laptops, and a show-desktop sliver at the far right

## Build & run

```sh
./scripts/build.sh --run
```

Produces `build/Barloom.app` (copy it to `/Applications` to keep it). Requires macOS 14+ and the Swift toolchain.

While Barloom runs it auto-hides the macOS Dock with a very long reveal delay; quitting Barloom (Start menu → gear → Quit Barloom) restores your previous Dock settings. Turn this off with "Hide macOS Dock" in the same menu.

If Barloom ever crashes and leaves the Dock hidden:

```sh
defaults delete com.apple.dock autohide-delay; killall Dock
```

## Windows key

Bind any hotkey tool (skhd, Raycast, Shortcuts, BetterTouchTool) to post the distributed notification `com.qwelpl.barloom.toggleStart` to open or close the Start menu.

## Limitations

macOS has no API for reserving screen space, so zoomed windows can extend underneath the bar.
