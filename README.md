<p align="center">
  <img src="assets/logo-512.png" width="128" alt="Studio Controller Pro">
</p>

<h1 align="center">Studio Controller Pro</h1>

<p align="center">Fly the Roblox Studio camera with a gamepad.</p>

## Features

- Toggle controller mode from the toolbar, a keyboard shortcut, or **View + Menu** on the pad
- Smooth fly camera with roll, FOV zoom, speed steps, boost and precision
- Screenshots straight from the controller
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
| A | Frame selection |
| X | Screenshot |
| Y | Reset camera |
| View + Menu | Toggle controller mode |

## Build

```bash
rokit install
rojo build default.project.json --plugin StudioControllerPro.rbxm
```
