# PonyHolding

PonyHolding replaces PPM/2's clipped world-weapon display with a clientside
held-item renderer.

- Non-horned ponies carry the active item sideways in their mouth.
- Horned ponies float it beside their head with damped movement, bobbing, and
  a silent MLP Magic Auras effect.
- The supplied PAC transforms provide exact support for the standard Half-Life
  2 weapons, physgun, toolgun, and camera.
- Ordinary single-model SWEPs fall back to a hidden Valve-biped hand pose.
- MLP Magic Auras and the local PPM/2 Magic Auras patch are soft dependencies;
  PonyHolding still renders weapons when the aura renderer is unavailable.

## Client settings

- `ponyholding_enabled 1`
- `ponyholding_draw_distance 3000` (`0` disables distance culling)
- `ponyholding_magic_bob 1`
- `ponyholding_magic_aura 1`

`ponyholding_reload` destroys and lazily recreates all clientside render models.

### Mouth-hold fallback

Placement for weapons with no profile in `sh_core.lua`. Offsets are in
`LrigScull`'s local axes, in source units at pony size 1.0, and are scaled by
the pony's size at use.

- `ponyholding_mouth_x 4` — forward, along the muzzle
- `ponyholding_mouth_y 4.8` — vertical, **positive is down**
- `ponyholding_mouth_z -1.68` — lateral

A weapon with its own profile ignores all three; give it a
`RegisterMouthProfile` entry instead of bending the fallback around it.

## Profile API

Profiles are keyed by weapon class and take precedence over model profiles:

```lua
PonyHolding.RegisterMouthProfile("weapon_example", {
    bone = "LrigScull",
    pos = Vector(4, 4.5, -1.68),
    ang = Angle(0, 0, 90),
    -- Optional absolute model orientation relative to magic forward.
    magicAng = Angle(0, 0, 0),
    scale = 1
})
```

Shared world-model profiles are also supported:

```lua
PonyHolding.RegisterModelProfile("models/weapons/w_example.mdl", profile)
```

TFA and ArcCW multipart rendering are intentionally deferred to later adapters.

## Compatibility notes

SWEP Construction Kit `WElements` weapons are not adapted; every weapon is
rendered from its ordinary world model. A SWEP which sets `ShowWorldModel`
false is treated as having no drawable world model and is skipped entirely,
so its placeholder is never shown.

Combat states such as blocking are not represented. Guard poses need a
pony-specific indicator or animation and belong in the server's combat
presentation layer.
