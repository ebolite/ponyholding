-- PonyHolding client renderer.
--
-- PPM/2 continues to hide its real weapon entity. This file draws a quiet
-- clientside copy at the pony's mouth, or floating beside a horned pony.

local Holding = PonyHolding

local ENABLED = CreateClientConVar(
    "ponyholding_enabled", "1", true, false,
    "Draw held weapons on PPM/2 ponies")

local DRAW_DISTANCE = CreateClientConVar(
    "ponyholding_draw_distance", "3000", true, false,
    "Maximum PonyHolding draw distance; 0 disables distance culling", 0, 20000)

local MAGIC_BOB = CreateClientConVar(
    "ponyholding_magic_bob", "1", true, false,
    "Add a gentle floating motion to magically held weapons")

local MAGIC_AURA = CreateClientConVar(
    "ponyholding_magic_aura", "1", true, false,
    "Draw a silent MLP Magic Auras effect around magically held weapons")

local REFERENCE_MODEL = "models/player/kleiner.mdl"
local WORLD_UP = Vector(0, 0, 1)
local MAGIC_RESPONSE = 9
local TELEPORT_DISTANCE_SQR = 200 * 200
local AURA_MARGIN = 1.2

-- Placement calibration. These were console variables while the transforms
-- were being dialled in against the PAC outfit; the magic values are settled,
-- so they are named here instead of sitting on the addon's console surface.
-- Both pitch corrections landed on zero and are kept named to document where
-- a correction would go.
local MAGIC_FORWARD = 10
local MAGIC_RIGHT = 20
local MAGIC_UP = -10
local MAGIC_PITCH = 0
local MOUTH_PITCH = 0

--[[
The mouth fallback is back on convars, because it is not settled.

It only applies to weapons with no profile in sh_core.lua, so unlike the
magic offsets it is aimed at models nopony has measured -- there is no
single right answer to freeze, and dialling it in wants the game running
rather than a publish cycle per unit.

Axes are LrigScull's own, which is why the help text now says so: Y is
vertical and POSITIVE IS DOWN, X is roughly forward along the muzzle (the
long weapons in sh_core.lua carry the big X -- shotgun 20.8, AR2 16.7),
and Z is the lateral bias. Recorded here because the previous round of
tuning left the mapping in nopony's head but the tuner's.

Units are source units at pony size 1.0; every offset is multiplied by
ponySize() at use, so these stay true for a bigger or smaller pony.
]]
local MOUTH_X = CreateClientConVar(
    "ponyholding_mouth_x", "4", true, false,
    "Fallback mouth-hold offset along LrigScull's local X axis (forward)", -100, 100)

local MOUTH_Y = CreateClientConVar(
    "ponyholding_mouth_y", "4.8", true, false,
    "Fallback mouth-hold offset along LrigScull's local Y axis (vertical, + is down)", -100, 100)

local MOUTH_Z = CreateClientConVar(
    "ponyholding_mouth_z", "-1.68", true, false,
    "Fallback mouth-hold offset along LrigScull's local Z axis (lateral)", -100, 100)

local states = {}

-- Restore anything hidden by an older copy of this file before a Lua refresh.
if istable(Holding.HiddenWeapons) then
    for weapon, record in pairs(Holding.HiddenWeapons) do
        if IsValid(weapon) and record.forced then
            weapon:SetNoDraw(record.original)
        end
    end
end

local hiddenWeapons = {}
Holding.HiddenWeapons = hiddenWeapons

local HOLD_ACTIVITIES = {
    normal = ACT_HL2MP_IDLE,
    passive = ACT_HL2MP_IDLE_PASSIVE,
    pistol = ACT_HL2MP_IDLE_PISTOL,
    revolver = ACT_HL2MP_IDLE_REVOLVER,
    smg = ACT_HL2MP_IDLE_SMG1,
    ar2 = ACT_HL2MP_IDLE_AR2,
    shotgun = ACT_HL2MP_IDLE_SHOTGUN,
    rpg = ACT_HL2MP_IDLE_RPG,
    crossbow = ACT_HL2MP_IDLE_CROSSBOW,
    grenade = ACT_HL2MP_IDLE_GRENADE,
    melee = ACT_HL2MP_IDLE_MELEE,
    melee2 = ACT_HL2MP_IDLE_MELEE2,
    knife = ACT_HL2MP_IDLE_KNIFE,
    fist = ACT_HL2MP_IDLE_FIST,
    physgun = ACT_HL2MP_IDLE_PHYSGUN,
    camera = ACT_HL2MP_IDLE_CAMERA,
    magic = ACT_HL2MP_IDLE_MAGIC,
    slam = ACT_HL2MP_IDLE_SLAM
}

-- The biped pose supplies the grip location. This conversion turns the human
-- hand into a sideways mouth grip. It is intentionally small and hold-type
-- based; exact weapon profiles always win.
local function removeEntity(ent)
    if IsValid(ent) then ent:Remove() end
end

local function releaseHiddenWeapon(weapon)
    local record = hiddenWeapons[weapon]
    if not record then return end

    hiddenWeapons[weapon] = nil

    if not IsValid(weapon) or not record.forced then return end

    weapon:SetNoDraw(record.original)
end

--[[
Defuse PPM/2's un-hide before it fires, rather than mopping up after it.

Its ModelChecks timer (client/hooks.moon:36) un-hides, once a second, every
weapon carrying __ppm2_weapon_hit, whenever the pony's Hide Weapons option is
off. No hook is consulted on that branch -- it is unconditional.

And the flag is never cleared, because PPM/2 sets it on the weapon and clears
it on the player:

    wep.__ppm2_weapon_hit = true      -- set here
    ply.__ppm2_weapon_hit = false     -- cleared here

So a weapon PPM/2 hid even once is un-hidden every second for the rest of the
map. We re-forced NoDraw each Think, but the timer fires after that within a
frame, so one frame rendered the real weapon at its bonemerged position --
the chest -- before the next Think put it back. Exactly 1.00s apart, which is
what the diagnostics showed.

Clearing the flag is the surgical fix: the branch only touches weapons that
carry it. It cannot lose PPM/2 any state it actually keeps, since the flag it
believes it clears is the one on the player, which is not the one it reads.
]]
local function releaseFromPPM2(weapon)
    weapon.__ppm2_weapon_hit = nil
end

local function hideRealWeapon(weapon)
    if not IsValid(weapon) then return end

    releaseFromPPM2(weapon)

    local existing = hiddenWeapons[weapon]
    if existing then
        -- Still re-forced: the flag is cleared every Think, but PPM/2 sets it
        -- again whenever Hide Weapons is on, so a toggle can still land one
        -- un-hide between two of our passes.
        if not weapon:GetNoDraw() then
            existing.forced = true
            weapon:SetNoDraw(true)
        end
        return
    end

    local original = weapon:GetNoDraw()
    hiddenWeapons[weapon] = {
        original = original,
        forced = not original
    }

    if not original then weapon:SetNoDraw(true) end
end

local function destroyState(ply)
    local state = states[ply]
    if not state then return end

    releaseHiddenWeapon(state.weapon)
    removeEntity(state.model)
    removeEntity(state.reference)
    states[ply] = nil
end

local function cleanupAll()
    for ply in pairs(states) do
        destroyState(ply)
    end

    for weapon in pairs(hiddenWeapons) do
        releaseHiddenWeapon(weapon)
    end
end

-- Remove models left by a prior Lua refresh before replacing the table.
if istable(Holding.ClientModels) then
    for _, ent in pairs(Holding.ClientModels) do
        removeEntity(ent)
    end
end
Holding.ClientModels = {}

local function rememberModel(ent)
    Holding.ClientModels[#Holding.ClientModels + 1] = ent
    return ent
end

local function isPony(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false end

    if isfunction(ply.IsPony) then
        local ok, result = pcall(ply.IsPony, ply)
        if ok then return result == true end
    end

    local modelName = string.lower(ply:GetModel() or "")
    return string.StartWith(modelName, "models/ppm/")
end

local function hasHorn(ply)
    local patch = MLPAuraPatch
    if istable(patch) and isfunction(patch.HasHorn) then
        return patch.HasHorn(ply)
    end

    if not istable(PPM2) or not isnumber(PPM2.RACE_HAS_HORN) then return false end
    if not isfunction(ply.GetPonyData) then return false end

    local data = ply:GetPonyData()
    if not data or not isfunction(data.GetPonyRaceFlags) then return false end

    return bit.band(data:GetPonyRaceFlags() or 0, PPM2.RACE_HAS_HORN) ~= 0
end

local function magicColor(ply)
    local patch = MLPAuraPatch
    if istable(patch) and isfunction(patch.MagicColor) then
        return patch.MagicColor(ply)
    end

    return Color(150, 200, 255)
end

local function ponySize(ply)
    if not isfunction(ply.GetPonyData) then return 1 end

    local data = ply:GetPonyData()
    if not data or not isfunction(data.GetPonySize) then return 1 end

    return math.max(tonumber(data:GetPonySize()) or 1, 0.01)
end

local function storedWeaponFor(weapon)
    if not IsValid(weapon) or not weapons.GetStored then return nil end
    return weapons.GetStored(weapon:GetClass())
end

local function worldModelFor(weapon)
    if not IsValid(weapon) then return nil end

    local stored = storedWeaponFor(weapon)

    -- A SWEP which explicitly disables its world model is saying its WorldModel
    -- field is a placeholder rather than the thing players should see. Draw
    -- nothing instead of exposing that placeholder.
    local showWorldModel = weapon.ShowWorldModel
    if showWorldModel == nil and stored then showWorldModel = stored.ShowWorldModel end
    if showWorldModel == false then return nil end

    local modelName

    if isfunction(weapon.GetWeaponWorldModel) then
        modelName = weapon:GetWeaponWorldModel()
    end

    if not isstring(modelName) or modelName == "" then
        modelName = weapon:GetModel()
    end
    if not isstring(modelName) or modelName == "" then
        modelName = weapon.WorldModel
    end

    if not isstring(modelName) or modelName == "" then
        modelName = stored and stored.WorldModel
    end

    if not isstring(modelName) or modelName == "" or not util.IsValidModel(modelName) then
        return nil
    end

    return modelName
end

local function copyAppearance(source, target)
    if not IsValid(source) or not IsValid(target) then return end

    target:SetSkin(source:GetSkin() or 0)
    target:SetMaterial(source:GetMaterial() or "")
    target:SetColor(source:GetColor())
    target:SetRenderMode(source:GetRenderMode())

    for index = 0, source:GetNumBodyGroups() - 1 do
        target:SetBodygroup(index, source:GetBodygroup(index))
    end
end

local function createDisplayModel(modelName, weapon)
    local model = ClientsideModel(modelName, RENDERGROUP_BOTH)
    if not IsValid(model) then return nil end

    rememberModel(model)
    model:SetNoDraw(true)
    model:DrawShadow(false)
    copyAppearance(weapon, model)

    -- Cache the root bone's inverse bind transform before this model is
    -- parented and bonemerged. Later, currentRoot * inverseBind reconstructs
    -- the model-to-world matrix for its render bounds.
    model:SetPos(vector_origin)
    model:SetAngles(angle_zero)
    model:SetModelScale(1, 0)
    model:SetupBones()

    local rootBone = model:LookupBone("ValveBiped.weapon_bone") or 0
    local bindMatrix = model:GetBoneMatrix(rootBone)

    model.PonyHoldingRootBone = rootBone
    model.PonyHoldingInverseBind = bindMatrix and bindMatrix:GetInverse() or nil
    return model
end

local function createReference()
    local reference = ClientsideModel(REFERENCE_MODEL, RENDERGROUP_OTHER)
    if not IsValid(reference) then return nil end

    rememberModel(reference)
    reference:SetNoDraw(true)
    reference:DrawShadow(false)
    reference:SetIK(false)
    return reference
end

local function refreshState(ply, weapon, modelName)
    destroyState(ply)

    local model = createDisplayModel(modelName, weapon)
    if not IsValid(model) then return nil end

    local state = {
        weapon = weapon,
        modelName = modelName,
        model = model,
        profile = Holding.GetMouthProfile(weapon, modelName),
        mode = "mouth",
        lastFrame = -1,
        auraVisible = false
    }

    states[ply] = state
    hideRealWeapon(weapon)
    return state
end

-- Why ensureState last gave up on a player, for cl_diagnostics to read.
-- Cleared the moment it succeeds again, so a reason sitting here is a reason
-- that is live this frame.
Holding.LastBail = Holding.LastBail or {}

--[[
A bail is not free, so a brief one is not obeyed.

destroyState calls releaseHiddenWeapon, which puts the real weapon back on
the pony at its bonemerged position -- the chest, on a PPM/2 skeleton. On the
next frame the inputs recover, refreshState runs, hideRealWeapon hides it
again. Net effect: one frame of chest weapon per hiccup, and nothing on the
holder's own screen, because every input below is locally authoritative for
yourself and networked for everypony else. ply:GetActiveWeapon() is the
obvious one -- for a remote player that is a separate networked entity that
can read invalid while the pony itself is drawing perfectly.

So a bail suspends rather than tears down, and only destroys once the reason
has held for GRACE. Nothing extra is needed to stop drawing during that
window: updateAndDraw already declines when state.weapon is invalid, and a
brief stale world model beats a frame of the real one appearing.

Long enough to cover a network hiccup, short enough that a real holster
still clears the model faster than anypony can see.
]]
local BAIL_GRACE = 0.25

local function bail(ply, reason)
    Holding.LastBail[ply] = reason

    local state = states[ply]
    if state then
        state.bailedAt = state.bailedAt or CurTime()

        if CurTime() - state.bailedAt < BAIL_GRACE then return nil end
    end

    destroyState(ply)
    return nil
end

local function ensureState(ply)
    if not ENABLED:GetBool() then return bail(ply, "disabled") end
    if not ply:Alive() then return bail(ply, "not alive") end
    if not isPony(ply) then return bail(ply, "not a pony") end

    local weapon = ply:GetActiveWeapon()
    if not IsValid(weapon) then return bail(ply, "no active weapon") end

    local modelName = worldModelFor(weapon)
    if not modelName then return bail(ply, "no world model") end

    Holding.LastBail[ply] = nil

    local state = states[ply]
    if not state
        or state.weapon ~= weapon
        or state.modelName ~= modelName
        or not IsValid(state.model) then
        state = refreshState(ply, weapon, modelName)
    else
        hideRealWeapon(weapon)
    end

    if state then
        -- Recovered, so the next bail starts its own grace window rather
        -- than measuring against one from minutes ago.
        state.bailedAt = nil
        state.mode = hasHorn(ply) and "magic" or "mouth"
        state.auraVisible = false
    end

    return state
end

local function boneTransform(ply, boneName)
    local bone = ply:LookupBone(boneName or "LrigScull")
        or ply:LookupBone("LrigScull")
        or ply:LookupBone("lrigscull")

    if not bone then return nil end

    local matrix = ply:GetBoneMatrix(bone)
    if matrix then return matrix:GetTranslation(), matrix:GetAngles() end

    return ply:GetBonePosition(bone)
end

local function setReferenceActivity(reference, holdType)
    local activity = HOLD_ACTIVITIES[holdType] or ACT_HL2MP_IDLE
    local sequence = reference:SelectWeightedSequence(activity)

    if not isnumber(sequence) or sequence < 0 then
        sequence = reference:LookupSequence("idle_all")
    end

    if isnumber(sequence) and sequence >= 0 and reference:GetSequence() ~= sequence then
        reference:SetSequence(sequence)
        reference:SetCycle(0)
    end
end

local function referenceHoldType(state)
    if not IsValid(state.weapon) then return "normal" end

    local holdType = isfunction(state.weapon.GetHoldType)
        and state.weapon:GetHoldType() or "normal"
    return string.lower(holdType or "normal")
end

local function matrixAt(pos, ang)
    local matrix = Matrix()
    matrix:SetTranslation(pos)
    matrix:SetAngles(ang)
    return matrix
end

local function scaledRenderBounds(model)
    local mins, maxs = model:GetRenderBounds()
    if not mins or not maxs then return vector_origin, Vector(6, 6, 6) end

    return (mins + maxs) * 0.5, (maxs - mins) * 0.5
end

local function muzzleAttachment(model, weapon)
    local bestID
    local bestScore = 0

    for _, attachment in ipairs(model:GetAttachments() or {}) do
        local name = string.lower(attachment.name or "")
        local score = 0

        if name == "muzzle" then
            score = 100
        elseif string.find(name, "muzzle", 1, true) then
            score = 90
        elseif string.find(name, "barrel", 1, true) then
            score = 70
        elseif string.find(name, "shoot", 1, true) then
            score = 60
        end

        if score > bestScore and model:GetAttachment(attachment.id) then
            bestID = attachment.id
            bestScore = score
        end
    end

    if bestID then return bestID end

    -- Some SWEP bases expose the correct numbered world-model attachment even
    -- when its name is unconventional.
    if isfunction(weapon.GetMuzzleAttachment) then
        local ok, attachmentID = pcall(weapon.GetMuzzleAttachment, weapon)
        if ok and isnumber(attachmentID) and attachmentID > 0
            and model:GetAttachment(attachmentID) then
            return attachmentID
        end
    end
end

local function configureReference(state, targetPos, targetAng, scale, mouthGrip)
    if not IsValid(state.weapon) then return false end

    if not IsValid(state.reference) then
        state.reference = createReference()
        if not IsValid(state.reference) then return false end
    end

    local reference = state.reference
    local holdType = referenceHoldType(state)

    reference:SetParent(NULL)
    reference:SetPos(vector_origin)
    reference:SetAngles(angle_zero)
    reference:SetModelScale(scale, 0)
    setReferenceActivity(reference, holdType)
    reference:SetupBones()

    local handBone = reference:LookupBone("ValveBiped.Bip01_R_Hand")
    local handMatrix = handBone and reference:GetBoneMatrix(handBone)
    if not handMatrix then return false end

    local _, desiredAng = LocalToWorld(
        vector_origin,
        mouthGrip and Angle(MOUTH_PITCH, 0, 0) or angle_zero,
        vector_origin,
        targetAng)

    local inverseHand = Matrix(handMatrix)
    inverseHand:Invert()

    local rootMatrix = matrixAt(targetPos, desiredAng) * inverseHand
    reference:SetPos(rootMatrix:GetTranslation())
    reference:SetAngles(rootMatrix:GetAngles())
    reference:SetupBones()

    if state.model:GetParent() ~= reference then
        state.model:SetParent(reference)
        state.model:AddEffects(EF_BONEMERGE)
        state.model:AddEffects(EF_BONEMERGE_FASTCULL)
        state.model:AddEffects(EF_PARENT_ANIMATES)
    end

    state.model:SetModelScale(scale, 0)
    state.model:SetupBones()
    return true
end

-- A muzzle attachment only reliably encodes the barrel direction. Its roll
-- about that barrel is whatever bone the modeller hung it off, so it is
-- routinely a quarter turn away from the weapon's own up. Spin the frame
-- about the aim axis -- which leaves the aim itself untouched -- until the
-- model's up is as close to world up as it can get.
local function levelRollAboutAxis(ang, axis)
    local up = ang:Up()
    local upPerp = up - axis * up:Dot(axis)
    local worldPerp = WORLD_UP - axis * WORLD_UP:Dot(axis)

    -- Aiming straight up or down leaves the roll genuinely undefined.
    if upPerp:LengthSqr() < 1e-6 or worldPerp:LengthSqr() < 1e-6 then return ang end

    upPerp = upPerp:GetNormalized()
    worldPerp = worldPerp:GetNormalized()

    local cosine = math.Clamp(upPerp:Dot(worldPerp), -1, 1)
    local sine = axis:Dot(upPerp:Cross(worldPerp))

    local leveled = Angle(ang)
    leveled:RotateAroundAxis(axis, math.deg(math.atan2(sine, cosine)))
    return leveled
end

-- Magic uses the reference rig only to recover the weapon's authored
-- orientation. The visible clone is then detached and centered on one common
-- skull-relative target, so hold-type hand positions cannot move different
-- weapons to radically different places.
local function configureMagicReference(state, referenceAng, targetCenter, scale)
    if not IsValid(state.weapon) then return false end

    if not IsValid(state.reference) then
        state.reference = createReference()
        if not IsValid(state.reference) then return false end
    end

    local reference = state.reference
    local holdType = referenceHoldType(state)

    -- Resolve one canonical model frame per hold type. Muzzle-bearing weapons
    -- are normalized by the attachment's semantic forward direction; models
    -- without one retain their reference-biped orientation.
    state.magicOrientations = state.magicOrientations or {}
    local orientation = state.magicOrientations[holdType]

    if not orientation and state.profile and state.profile.magicAng then
        orientation = {
            kind = "profile",
            localAng = Angle(state.profile.magicAng)
        }
        state.magicOrientations[holdType] = orientation
    end

    if not orientation then
        reference:SetParent(NULL)
        reference:SetPos(vector_origin)
        reference:SetAngles(angle_zero)
        reference:SetModelScale(1, 0)
        setReferenceActivity(reference, holdType)
        reference:SetupBones()

        if state.model:GetParent() ~= reference then
            state.model:SetParent(reference)
            state.model:AddEffects(EF_BONEMERGE)
            state.model:AddEffects(EF_BONEMERGE_FASTCULL)
            state.model:AddEffects(EF_PARENT_ANIMATES)
        end

        state.model:SetModelScale(1, 0)
        state.model:SetupBones()

        local currentRoot = state.model:GetBoneMatrix(state.model.PonyHoldingRootBone or 0)
        local modelToWorld = currentRoot
            and state.model.PonyHoldingInverseBind
            and currentRoot * state.model.PonyHoldingInverseBind

        local attachmentID = muzzleAttachment(state.model, state.weapon)
        local attachment = attachmentID and state.model:GetAttachment(attachmentID)

        if modelToWorld and attachment then
            local worldToModel = Matrix(modelToWorld)
            worldToModel:Invert()

            local localMuzzle = worldToModel * matrixAt(attachment.Pos, attachment.Ang)
            local inverseLocalMuzzle = matrixAt(vector_origin, localMuzzle:GetAngles())
            inverseLocalMuzzle:Invert()

            orientation = {
                kind = "muzzle",
                inverseLocalMuzzle = inverseLocalMuzzle,
                attachmentID = attachmentID
            }
        else
            orientation = {
                kind = "reference",
                localAng = Angle(modelToWorld and modelToWorld:GetAngles() or angle_zero)
            }
        end

        state.magicOrientations[holdType] = orientation
    end

    local desiredFrame

    if orientation.kind == "muzzle" then
        -- The attachment's +X/Forward axis is the barrel direction. Mapping it
        -- onto this level world frame makes differently authored models agree.
        -- Only the direction is trustworthy, so the roll is re-derived rather
        -- than inherited from the attachment.
        local aimAng = Angle(0, referenceAng.y, 0)
        desiredFrame = matrixAt(vector_origin, aimAng)
            * orientation.inverseLocalMuzzle
        desiredFrame = matrixAt(
            vector_origin,
            levelRollAboutAxis(desiredFrame:GetAngles(), aimAng:Forward()))
    else
        local pitch = orientation.kind == "reference" and MAGIC_PITCH or 0
        desiredFrame = matrixAt(vector_origin, Angle(pitch, referenceAng.y, 0))
            * matrixAt(vector_origin, orientation.localAng)
    end

    local modelAng = desiredFrame:GetAngles()
    local localCenter, halfExtents = scaledRenderBounds(state.model)
    local centerOffset = Vector(localCenter) * scale
    centerOffset:Rotate(modelAng)

    state.model:SetParent(NULL)
    state.model:RemoveEffects(EF_BONEMERGE)
    state.model:RemoveEffects(EF_BONEMERGE_FASTCULL)
    state.model:RemoveEffects(EF_PARENT_ANIMATES)
    state.model:SetPos(targetCenter - centerOffset)
    state.model:SetAngles(modelAng)
    state.model:SetModelScale(scale, 0)
    state.model:SetupBones()

    return true, targetCenter, halfExtents:Length() * scale * AURA_MARGIN
end

local function clearReferenceParent(state)
    if state.model:GetParent() == state.reference then
        state.model:SetParent(NULL)
        state.model:RemoveEffects(EF_BONEMERGE)
        state.model:RemoveEffects(EF_BONEMERGE_FASTCULL)
        state.model:RemoveEffects(EF_PARENT_ANIMATES)
    end
end

local function exactTransform(ply, state, skullPos, skullAng, size)
    local profile = state.profile
    if not profile then return nil end

    local position = Vector(profile.pos) * size
    local pos, ang = LocalToWorld(position, profile.ang, skullPos, skullAng)
    return pos, ang, profile.scale * size
end

local function targetTransform(ply, state)
    local profile = state.profile
    local skullPos, skullAng = boneTransform(ply, profile and profile.bone or "LrigScull")
    if not skullPos then return nil end

    local size = ponySize(ply)
    local pos, ang, displayScale = exactTransform(ply, state, skullPos, skullAng, size)
    local mouthOffset = Vector(
        MOUTH_X:GetFloat(),
        MOUTH_Y:GetFloat(),
        MOUTH_Z:GetFloat())

    if not pos then
        pos = LocalToWorld(mouthOffset * size, angle_zero, skullPos, skullAng)
        ang, displayScale = skullAng, size
    end

    if state.mode == "magic" then
        --[[
        Offset one normalized weapon center from the skull. Mouth profiles
        and hold-type hand positions do not contribute to this position.

        Both the position and the orientation take their yaw from EyeAngles.
        They used to disagree -- the orientation came from GetAngles while
        only the offset used EyeAngles -- and that is a real difference, not
        two spellings of one thing. EyeAngles is networked for every player
        precisely so other clients can read an aim direction. A player's
        entity angles are not: the rendered facing of somepony else is
        reconstructed by the animation system from pose parameters, so
        GetAngles is only dependable for the local player.

        Which produced exactly the reported shape. The weapon orbited the
        holder's head correctly, because that half read EyeAngles, while
        pointing one fixed world direction, because the half that aimed it
        did not. Right on the holder's own screen, where the two agree.

        Levelled here rather than inside the consumers, because the yaw is
        all either one wants: configureMagicReference reads referenceAng.y,
        and the non-reference fallback would otherwise hand the model a
        pitch and roll that nothing intends it to have.
        ]]
        local levelAng = Angle(0, ply:EyeAngles().y, 0)

        ang = Angle(levelAng)
        displayScale = size
        pos = skullPos
            + levelAng:Forward() * MAGIC_FORWARD * size
            + levelAng:Right() * MAGIC_RIGHT * size
            + WORLD_UP * MAGIC_UP * size

        if MAGIC_BOB:GetBool() then
            pos = pos + WORLD_UP * math.sin(CurTime() * 2.2 + ply:EntIndex()) * 1.5 * size
        end

        if state.smoothedPos and state.smoothedPos:DistToSqr(pos) <= TELEPORT_DISTANCE_SQR then
            local fraction = 1 - math.exp(-MAGIC_RESPONSE * FrameTime())
            state.smoothedPos = LerpVector(fraction, state.smoothedPos, pos)
            state.smoothedAng = LerpAngle(fraction, state.smoothedAng, ang)
        else
            state.smoothedPos = Vector(pos)
            state.smoothedAng = Angle(ang)
        end

        pos, ang = state.smoothedPos, state.smoothedAng
    else
        state.smoothedPos = nil
        state.smoothedAng = nil
    end

    return pos, ang, displayScale, skullAng
end

local function shouldDraw(ply)
    if ply:IsDormant() or not ply:Alive() then return false end
    if ply == LocalPlayer() and not ply:ShouldDrawLocalPlayer() then return false end

    local maximum = DRAW_DISTANCE:GetFloat()
    if maximum <= 0 then return true end

    return EyePos():DistToSqr(ply:WorldSpaceCenter()) <= maximum * maximum
end

local function updateAndDraw(ply, state)
    -- PostPlayerDraw runs once per render pass, not once per frame: water
    -- reflections, RT monitors and the 3D skybox each re-draw the player. The
    -- transform below advances the magic damping by a FrameTime() step, so a
    -- second pass would step the smoothing again and leave its copy of the
    -- weapon trailing the first. Later passes redraw what the first one
    -- already positioned, which still puts the weapon in the reflection.
    local frame = FrameNumber()
    if state.lastFrame == frame then
        if IsValid(state.model) then state.model:DrawModel() end
        return
    end

    if not IsValid(state.weapon) or not shouldDraw(ply) or not IsValid(state.model) then
        state.auraVisible = false
        return
    end

    state.lastFrame = frame

    local pos, ang, scale, skullAng = targetTransform(ply, state)
    if not pos then
        state.auraVisible = false
        return
    end

    copyAppearance(state.weapon, state.model)

    local usedReference = false
    local referenceAnchor
    local referenceRadius

    if state.mode == "magic" then
        usedReference, referenceAnchor, referenceRadius = configureMagicReference(
            state,
            ang,
            pos,
            scale)
    elseif not state.profile then
        usedReference = configureReference(
            state,
            pos,
            skullAng or ang,
            scale,
            true)
    end

    if not usedReference then
        clearReferenceParent(state)
        state.model:SetPos(pos)
        state.model:SetAngles(ang)
        state.model:SetModelScale(scale, 0)
        state.model:SetupBones()
    end

    state.model:DrawModel()

    state.auraVisible = state.mode == "magic"

    if state.auraVisible then
        state.auraPos = Vector(referenceAnchor or pos)
        state.auraRadius = math.Clamp(
            referenceRadius or state.model:BoundingRadius() * scale * AURA_MARGIN,
            6,
            128)
    else
        state.auraPos = nil
        state.auraRadius = nil
    end
end

hook.Add("Think", "PonyHolding.Update", function()
    local present = {}

    for _, ply in ipairs(player.GetAll()) do
        present[ply] = true
        ensureState(ply)
    end

    for ply in pairs(states) do
        if not present[ply] or not IsValid(ply) then
            destroyState(ply)
        end
    end
end)

--[[
One last re-force immediately before anything is drawn.

hideRealWeapon runs from Think, early in the frame. PPM/2's timer clearing
NoDraw after that is the cause we know about, and clearing its flag stops it,
but the shape of the bug -- one rendered frame between somepony clearing
NoDraw and our next Think -- is available to anything that touches a weapon we
have hidden. This closes the window itself instead of one route into it.

PreDrawOpaqueRenderables rather than PrePlayerDraw: a weapon is its own
entity, bonemerged rather than drawn by the player, so player draw order
guarantees nothing about when it renders.

Cheap: one entry per armed pony in view, and SetNoDraw on an already-hidden
entity does nothing.
]]
hook.Add("PreDrawOpaqueRenderables", "PonyHolding.HoldNoDraw", function()
    for weapon, record in pairs(hiddenWeapons) do
        if not IsValid(weapon) then
            hiddenWeapons[weapon] = nil
        elseif record.forced and not weapon:GetNoDraw() then
            weapon:SetNoDraw(true)
        end
    end
end)

hook.Add("PostPlayerDraw", "PonyHolding.Draw", function(ply)
    local state = states[ply]
    if state then updateAndDraw(ply, state) end
end)

hook.Add("PostDrawTranslucentRenderables", "PonyHolding.DrawMagicAuras", function(drawingDepth, drawingSkybox)
    if drawingDepth or drawingSkybox or not MAGIC_AURA:GetBool() then return end
    if not isfunction(DrawAura) then return end

    local visibility = GetConVar("pma_visibility")
    local alpha = visibility and visibility:GetInt() or 200

    Holding.AuraPreviousTime = Holding.AuraPreviousTime or CurTime()
    Holding.AuraPreviousFrame = Holding.AuraPreviousFrame or -1

    local frame = FrameNumber()
    local deltaTime = 0

    if frame ~= Holding.AuraPreviousFrame then
        deltaTime = math.max(0, CurTime() - Holding.AuraPreviousTime)
        Holding.AuraPreviousTime = CurTime()
        Holding.AuraPreviousFrame = frame
    end

    local particleSpeed = GetConVar("pma_particle_speed")
    local particlesPerSecond = particleSpeed and particleSpeed:GetInt() or 200

    for ply, state in pairs(states) do
        if state.auraVisible and IsValid(ply) and state.auraPos then
            local color = magicColor(ply)
            DrawAura(
                state.auraPos,
                0,
                state.auraRadius or 12,
                100,
                color.r,
                color.g,
                color.b,
                alpha)

            if particlesPerSecond > 0 and isfunction(DrawParticles) then
                state.auraPhase = DrawParticles(
                    state.auraPos,
                    state.auraRadius or 12,
                    state.auraPhase or 0,
                    1 / particlesPerSecond,
                    deltaTime)
            end
        end
    end
end)

hook.Add("EntityRemoved", "PonyHolding.CleanupEntity", function(ent)
    if states[ent] then
        destroyState(ent)
        return
    end

    if hiddenWeapons[ent] then
        hiddenWeapons[ent] = nil
    end
end)

hook.Add("ShutDown", "PonyHolding.Cleanup", cleanupAll)

concommand.Add("ponyholding_reload", function()
    cleanupAll()
end)
