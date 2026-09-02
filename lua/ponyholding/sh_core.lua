PonyHolding = PonyHolding or {}
local Holding = PonyHolding

Holding.VERSION = 1
Holding.MouthProfiles = Holding.MouthProfiles or {}
Holding.ModelProfiles = Holding.ModelProfiles or {}

local function copyProfile(profile)
    return {
        bone = profile.bone or "LrigScull",
        pos = Vector(profile.pos or vector_origin),
        ang = Angle(profile.ang or angle_zero),
        magicAng = profile.magicAng and Angle(profile.magicAng) or nil,
        magicYaw = tonumber(profile.magicYaw) or nil,
        scale = tonumber(profile.scale) or 1
    }
end

function Holding.RegisterMouthProfile(className, profile)
    assert(isstring(className) and className ~= "", "PonyHolding: weapon class is required")
    assert(istable(profile), "PonyHolding: profile table is required")

    Holding.MouthProfiles[string.lower(className)] = copyProfile(profile)
end

function Holding.RegisterModelProfile(modelName, profile)
    assert(isstring(modelName) and modelName ~= "", "PonyHolding: model path is required")
    assert(istable(profile), "PonyHolding: profile table is required")

    Holding.ModelProfiles[string.lower(modelName)] = copyProfile(profile)
end

function Holding.GetMouthProfile(weapon, modelName)
    if not IsValid(weapon) then return nil end

    local byClass = Holding.MouthProfiles[string.lower(weapon:GetClass())]
    if byClass then return byClass end

    if isstring(modelName) and modelName ~= "" then
        return Holding.ModelProfiles[string.lower(modelName)]
    end
end

-- Confirmed transforms from the PAC outfit for the PPM2 new model. The normal
-- and no-jiggle variants share this skeleton
local BUILTIN_PROFILES = {
    weapon_pistol = {
        pos = Vector(9.244995, 2.356445, 3.647705),
        ang = Angle(6.622631, 177.099777, -0.333197)
    },
    gmod_tool = {
        pos = Vector(5.966309, 1.525513, 1.932251),
        ang = Angle(-0.870094, -4.309549, 6.130774)
    },
    weapon_shotgun = {
        pos = Vector(20.827698, 0.203857, 3.460938),
        ang = Angle(9.263848, 175.861221, -6.928986),
        scale = 0.9
    },
    weapon_physgun = {
        pos = Vector(0.11, 3.6454, -9.2129),
        ang = Angle(0.701253, 0.053163, 99.665985)
    },
    weapon_physcannon = {
        pos = Vector(0.11, 3.6454, -9.2129),
        ang = Angle(0.701253, 0.053163, 99.665985)
    },
    weapon_crossbow = {
        pos = Vector(3.783691, -0.315430, 0.050049),
        ang = Angle(-0.945081, -0.147470, -3.004356),
        -- The frame derived from this model lies across the bow rather than
        -- along the bolt, so the magic hold aims it a quarter turn right
        magicYaw = 90,
        scale = 0.7
    },
    weapon_smg1 = {
        pos = Vector(13.892090, 0.961914, 3.502441),
        ang = angle_zero
    },
    gmod_camera = {
        pos = Vector(3.726000, -10.474000, 1.518000),
        ang = Angle(-0.800000, -6.700000, 93.200000)
    },
    weapon_crowbar = {
        pos = Vector(7.476074, 2.001587, 0.276489),
        ang = Angle(85.397942, 179.996094, 153.988419)
    },
    weapon_ar2 = {
        pos = Vector(16.74, -0.1704, 1.6836),
        ang = Angle(2.294339, 169.182098, -5.599233),
        scale = 0.6
    },
    weapon_rpg = {
        pos = Vector(-0.240234, 3.827759, 1.219604),
        ang = angle_zero
    },
    weapon_357 = {
        pos = Vector(5.225586, 1.826416, 1.217865),
        ang = angle_zero
    },
    weapon_frag = {
        pos = Vector(6.747559, 2.560791, 1.041016),
        ang = angle_zero
    }
}

for className, profile in pairs(BUILTIN_PROFILES) do
    profile.bone = "LrigScull"
    Holding.RegisterMouthProfile(className, profile)
end
