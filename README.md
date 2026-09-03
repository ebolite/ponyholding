# PonyHolding

PonyHolding allows ponies to visually carry held weapons.

- Ponies with horns carry weapons with a magical aura from MLP Magic Auras. Weapon movement is damped with bobbing.
- Ponies without horns carry weapons sideways in their mouths.
- Has authored support for HL2 weapons, with limited custom SWEP support.
- Supports authored `RegisterMouthProfile` entries for authored placements.

## Client settings

- `ponyholding_enabled 1`
- `ponyholding_draw_distance 3000` (`0` disables distance culling)
- `ponyholding_magic_bob 1`
- `ponyholding_magic_aura 1`

`ponyholding_reload` reloads ponyholding rendering.

## Profile API

Profiles are keyed by weapon class and take precedence over model profiles:

```lua
PonyHolding.RegisterMouthProfile("weapon_example", {
    bone = "LrigScull",
    pos = Vector(4, 4.5, -1.68),
    ang = Angle(0, 0, 90), -- Orientation of the model relative to forward
    magicAng = Angle(0, 0, 0), -- Orientation of the magic model relative to forward
    magicYaw = 0, -- Optional yaw correction for a sideways model
    magicOffset = Vector(0, 0, 0), -- Optional nudge for a model whose geometry is off-origin
    scale = 1
})
```

E.g. `weapon_crossbow` is `magicYaw = 90` (yawed left) because the automatic detection assumes it's pointed sideways.

The magic hold centres a weapon on its render bounds, so a model whose geometry sits off
to one side of its own origin hangs away from the aura. `magicOffset` moves it back, in
the weapon's own axes.

Shared world-model profiles are also supported:

```lua
PonyHolding.RegisterModelProfile("models/weapons/w_example.mdl", profile)
```

TFA and ArcCW multipart rendering might be supported later.
