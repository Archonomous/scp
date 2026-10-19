<p align="center">
  <img src="assets/logo-512.png" width="128" alt="Studio Controller Pro">
</p>

<h1 align="center">Studio Controller Pro</h1>

<p align="center">Control Roblox Studio using a game controller in edit mode.</p>

## Features

- Toggle controller mode from the toolbar, a keyboard shortcut, or by clicking both sticks
- Smooth fly camera with roll, FOV zoom, speed steps, boost and precision
- Centre reticle: select, fly to, or frame whatever you're looking at with one button
- Level movement mode (like shift lock) so looking down never dives
- Screenshots from the controller, with one-click return to any shot's exact view
- Upload screenshots to keep them: they land on exportable planes in ServerStorage
- Vibration feedback with adjustable strength
- Rebind any button, including two-button combos
- Save layouts as profiles and switch between them from the pad
- Detects Xbox, PlayStation and generic controllers automatically
- Native Studio look in both Light and Dark themes

## Default controls

| Input | Action |
| --- | --- |
| Left stick / Right stick | Move / Look |
| RT / LT | Up / Down |
| RB / LB | Roll |
| D-Pad Up / Down | Speed |
| D-Pad Left / Right | FOV |
| LS click / B | Boost / Precision |
| A | Tap: select what the reticle is on · Double-tap: fly to it · Hold: select and frame it, then orbit with the right stick until you move (hold on empty space to deselect) |
| X | Screenshot |
| Y | Reset camera |
| View + Y | Toggle level movement |
| Menu | Button guide |
| Click both sticks | Toggle controller mode |

## Build

```bash
rokit install
rojo build default.project.json --plugin StudioControllerPro.rbxm
```