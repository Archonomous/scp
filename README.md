# Studio Controller Pro

<img src="assets/logo-512.png" width="96" align="right" alt="Studio Controller Pro logo">

Fly the Roblox Studio edit camera with a gamepad. Rebind every button, build combos, and keep separate layouts as profiles.

- **Turn it on or off three ways:** the toolbar button, a keyboard shortcut you assign, or **View + Menu** on the controller (this works even while it's off).
- **Six-axis fly camera:** move, ascend and descend (triggers are pressure-sensitive), yaw, pitch and roll, with smoothing you can tune.
- **Camera tools:** step the speed from 1/16× to 32×, boost and precision modifiers, FOV zoom, reset roll / FOV / everything, level view, frame selection, and return to start.
- **Screenshots** of the viewport go to a Captures gallery, with the HUD hidden while it captures.
- **Custom bindings:** click a binding and press a button. Hold one button and press another to make a combo. If a binding is taken, the plugin unbinds it from the other action and tells you.
- **Profiles:** Default, Cinematic, Builder and Southpaw presets. You can create, duplicate, rename, reorder and delete profiles, export and import them as text, and switch between them from the pad.
- **Automatic controller detection:** glyphs and button names follow the connected controller (Xbox, PlayStation, generic). With more than one pad, the most recently used one is active, or you can pick a slot.
- **Native look:** Studio's theme colors (Light and Dark), Builder Sans, and Studio's own icons. The viewport HUD shows status, toasts and an optional on-screen button guide.

## Default layout (Xbox naming)

| Input | Action |
| --- | --- |
| Left stick | Move |
| Right stick | Look |
| RT / LT | Ascend / Descend |
| RB / LB | Roll right / left |
| LS click | Boost (hold) |
| B | Precision (hold) |
| D-Pad Up / Down | Speed up / down |
| D-Pad Left / Right | Widen / narrow FOV |
| RS click | Reset roll |
| Y | Reset camera (roll, FOV, speed) |
| A | Frame selection |
| X | Take screenshot |
| View | Toggle HUD |
| Menu | Toggle button guide |
| View + Menu | Toggle controller mode |
| View + D-Pad Left / Right | Previous / next profile |

## Install from source

Requires [Rokit](https://github.com/rojo-rbx/rokit). Then:

```bash
rokit install
```

```bash
rojo build default.project.json --plugin StudioControllerPro.rbxm
```

That writes the plugin to Studio's local Plugins folder. Studio loads new plugins on startup and hot-reloads ones it already has when the file changes.

## Development

- `src/init.server.luau` is the plugin entry point and per-frame loop.
- `src/Core` holds the logic: `Gamepad` (detection and sampling), `Resolver` (bindings to actions, combos), `CameraController`, `Store` (profiles and persistence), `Captures`, and the `Actions` / `Inputs` / `Tuning` catalogs.
- `src/UI` holds `App` (dock panel), `Hud` (viewport overlay), `Components`, `Glyphs` and `Theme`.

`rojo serve dev.project.json` (port 34800) syncs the source into `ServerStorage.StudioControllerPro` so you can browse it in a place. The plugin itself always runs from the built `.rbxm`. Format with `stylua src` and lint with `selene src`.

To add an action, add it to `Core/Actions.luau` and handle it in `pressHandlers` (or read it in the frame loop) in `init.server.luau`. Saved profiles pick up the new default automatically.

## Publishing checklist

1. Upload `assets/toolbar-64.png` as an Image on the Creator Dashboard and set `Theme.ToolbarIcon` in `src/UI/Theme.luau` to its `rbxassetid://` id. Until then the toolbar uses Studio's built-in gamepad glyph.
2. Build to a file: `rojo build default.project.json -o StudioControllerPro.rbxm`.
3. In Studio, insert the `.rbxm`, right-click the `StudioControllerPro` script, and choose **Publish as Plugin**. Use `assets/logo-512.png` as the listing icon.
4. Set the price to Free and publish to the Creator Store.

## Known limits

- Studio only receives controller input while its window is focused.
- Plugins can't write image files, so captures last for the Studio session. To keep one, open it in the Captures tab and use the Windows Snipping Tool.
- Plugins can't trigger most of Studio's built-in commands, so bindings map to the plugin's own actions.
- The plugin is inactive during Play tests, where the game owns the controller.
