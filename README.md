# Barloom

A sleek Windows 11–style taskbar for macOS that replaces the Dock.

- Full-width translucent bar pinned to the bottom of every display
- Centered Start button + pinned and running apps, with Fluent-style hover plates and running/active indicators
- Click the focused app to hide it (like minimising), click anything else to bring it forward or launch it
- Right-click an icon to pin/unpin, show in Finder or quit; drag icons to reorder pins
- Start menu: instant app search (Return launches the top hit), pinned apps, all apps, power and settings menus
- Four taskbar sizes, from compact to extra large
- Clock/date with a calendar flyout, battery indicator on laptops, and a show-desktop sliver at the far right

## Build & run

```sh
./scripts/build.sh --run
```

Produces `build/Barloom.app` (copy it to `/Applications` to keep it). Requires macOS 14+ and the Swift toolchain.

macOS only keeps windows clear of its own Dock, so while Barloom runs it shrinks the real Dock to exactly the bar's height and covers it. Zoomed, tiled and newly opened windows then stop at the top of the taskbar. The bar uses an opaque Mica-style background (blurred wallpaper) so the Dock never shows through. Quitting Barloom (Start menu → gear → Quit Barloom) restores your previous Dock settings; "Keep Windows Above Taskbar" in the same menu turns this off, and "Taskbar Size" (Small, Medium, Large, Extra Large) resizes the bar and the Dock beneath it together.

If Barloom ever crashes, relaunching and quitting it restores the Dock, or reset it by hand:

```sh
defaults delete com.apple.dock tilesize; defaults write com.apple.dock autohide -bool true; killall Dock
```

## Windows key

Bind any hotkey tool (skhd, Raycast, Shortcuts, BetterTouchTool) to post the distributed notification `com.qwelpl.barloom.toggleStart` to open or close the Start menu.

## Limitations

The Dock reserves space on one display at a time, so on secondary displays windows can still extend under the bar.
