# Phalanx Shared Boundary

This note defines the current split for the `phalanx` weapon system.

## Goal

Keep `shared/` for reusable weapon logic, and keep `tool/` / `vehicle/` for game-facing adapters.

## Current split

### `shared/phalanx_weapon/`

Put logic here when it can be reused by both hand-held and vehicle-mounted Phalanx:

- weapon config and tuning
- projectile creation and ticking
- common projectile FX
- spin/fire-rate state
- audio loading and playback helpers

Current modules:

- [phalanx_weapon_config.lua](/c:/Users/13723/Documents/Teardown/mods/Phalanx/shared/phalanx_weapon/phalanx_weapon_config.lua)
- [phalanx_weapon_projectile.lua](/c:/Users/13723/Documents/Teardown/mods/Phalanx/shared/phalanx_weapon/phalanx_weapon_projectile.lua)
- [phalanx_weapon_fx.lua](/c:/Users/13723/Documents/Teardown/mods/Phalanx/shared/phalanx_weapon/phalanx_weapon_fx.lua)
- [phalanx_weapon_spin.lua](/c:/Users/13723/Documents/Teardown/mods/Phalanx/shared/phalanx_weapon/phalanx_weapon_spin.lua)
- [phalanx_weapon_audio.lua](/c:/Users/13723/Documents/Teardown/mods/Phalanx/shared/phalanx_weapon/phalanx_weapon_audio.lua)

### `tool/phalanx/`

Keep hand-held specific logic here:

- `RegisterTool(...)`
- player input
- hand-held animation / pose
- muzzle lookup for tool prefab
- tool XML / VOX resources

Current files:

- [phalanx.lua](/c:/Users/13723/Documents/Teardown/mods/Phalanx/tool/phalanx/phalanx.lua)
- [phalanx.xml](/c:/Users/13723/Documents/Teardown/mods/Phalanx/tool/phalanx/phalanx.xml)
- [phalanx.vox](/c:/Users/13723/Documents/Teardown/mods/Phalanx/tool/phalanx/phalanx.vox)

### `vehicle/military/`

Keep vehicle-mounted specific logic here:

- custom vehicle camera
- turret aim / mount control
- barrel spin pivot and mounted muzzle lookup
- vehicle input and UI
- vehicle XML / VOX resources

Current files:

- [car_phalanx.lua](/c:/Users/13723/Documents/Teardown/mods/Phalanx/vehicle/military/car_phalanx.lua)
- [mil-car-phalanx.xml](/c:/Users/13723/Documents/Teardown/mods/Phalanx/vehicle/military/mil-car-phalanx.xml)

## Dependency rule

Allowed:

- `main.lua` -> `tool/phalanx/phalanx.lua`
- `tool/...` -> `shared/...`
- `vehicle/...` -> `shared/...`

Avoid:

- `shared/...` depending on `tool/...`
- `shared/...` depending on `vehicle/...`

## Practical rule

Share the weapon system, not the mounting method.

That means:

- tool and vehicle can share ballistics
- tool and vehicle can share FX/audio helpers
- tool and vehicle should still keep their own prefab structure and control code
