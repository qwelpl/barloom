# Barloom

A sleek Windows 11–style taskbar for macOS that replaces the Dock.

- Full-width translucent bar pinned to the bottom of every display
- One button per window, with its title, for the windows on the current Space and display (or one icon per app)
- Click a window's button to switch to it, click the focused one to minimise it, middle-click to close it
- Hover a window's button for a live thumbnail with a close button
- Pinned apps keep their slot, showing their windows or a launcher icon; drag buttons to reorder
- Right-click for minimise/restore, close, new window, keep in taskbar and quit
- Left (Windows 10) or centered (Windows 11) layout, optional grouping of windows by app
- Start menu: instant app search (Return launches the top hit), pinned, recent and all apps, power and settings menus
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

## Permissions

- **Accessibility** lists and switches windows. Without it the bar falls back to one icon per app and shows an "Allow window buttons" button.
- **Screen Recording** (optional) is only used for hover thumbnails.

Run `./scripts/make-dev-cert.sh` once to create a self-signed "Barloom Dev" identity; `build.sh` then signs with it and macOS keeps both permissions across rebuilds (click "Always Allow" the first time codesign asks for the key). Without it builds are ad-hoc signed and the permissions reset every rebuild.

## Windows key

Bind any hotkey tool (skhd, Raycast, Shortcuts, BetterTouchTool) to post the distributed notification `com.qwelpl.barloom.toggleStart` to open or close the Start menu.

## Limitations

The Dock reserves space on one display at a time, so on secondary displays windows can still extend under the bar.
