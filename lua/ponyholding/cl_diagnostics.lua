local Holding = PonyHolding

local watching = nil
local previous = {}
local tally = {}
local lastEventAt = {}
local startedAt = 0

local function label(ply)
    return IsValid(ply) and ply:Nick() or "<gone>"
end

local function snapshot(ply)
    local weapon = ply:GetActiveWeapon()
    local valid = IsValid(weapon)

    return {
        bail = Holding.LastBail and Holding.LastBail[ply] or nil,
        held = valid and weapon:GetClass() or "-",
        -- Entity index
        index = valid and weapon:EntIndex() or -1,
        -- The usual reason a remote entity reads invalid
        dormant = ply:IsDormant(),
        -- NoDraw false while we still believe the weapon is hidden means the weapon briefly shows in the default position
        noDraw = valid and weapon:GetNoDraw() or false,
        tracked = valid and Holding.HiddenWeapons[weapon] ~= nil or false,
        alive = ply:Alive(),
        model = string.lower(ply:GetModel() or "")
    }
end

local function differs(a, b)
    if not a then return true end

    return a.bail ~= b.bail
        or a.held ~= b.held
        or a.index ~= b.index
        or a.dormant ~= b.dormant
        or a.noDraw ~= b.noDraw
        or a.tracked ~= b.tracked
        or a.alive ~= b.alive
        or a.model ~= b.model
end

local function describe(shot)
    local reason = shot.bail or "ok"

    local visible = shot.tracked and not shot.noDraw

    return string.format("%-18s %-20s #%-4d noDraw %-5s tracked %-5s%s%s",
        reason,
        shot.held,
        shot.index,
        tostring(shot.noDraw),
        tostring(shot.tracked),
        shot.dormant and " DORMANT" or "",
        visible and "  <-- REAL WEAPON VISIBLE" or "")
end

local function watched()
    local out = {}

    for _, ply in ipairs(player.GetAll()) do
        if ply ~= LocalPlayer() or watching ~= "" then
            if watching == "" or string.find(string.lower(ply:Nick()), watching, 1, true) then
                table.insert(out, ply)
            end
        end
    end

    return out
end

hook.Add("Think", "PonyHolding.Diagnostics", function()
    if not watching then return end

    for _, ply in ipairs(watched()) do
        local shot = snapshot(ply)

        if differs(previous[ply], shot) then
            local now = CurTime()
            local gap = lastEventAt[ply] and (now - lastEventAt[ply]) or 0
            lastEventAt[ply] = now

            MsgC(Color(255, 220, 120), string.format("[ph %6d  +%5.2fs] ", FrameNumber(), gap))
            Msg(string.format("%-16s %s\n", label(ply), describe(shot)))

            local key = shot.bail or "ok"
            tally[key] = (tally[key] or 0) + 1

            previous[ply] = shot
        end
    end
end)

concommand.Add("ponyholding_watch", function(_, _, args)
    watching = string.lower(args[1] or "")
    previous = {}
    tally = {}
    lastEventAt = {}
    startedAt = CurTime()

    Msg(string.format("[ponyholding] watching %s -- transitions only.\n",
        watching == "" and "everypony" or ("names containing '" .. watching .. "'")))
end)

concommand.Add("ponyholding_watch_stop", function()
    if not watching then
        Msg("[ponyholding] not watching.\n")
        return
    end

    local elapsed = math.max(CurTime() - startedAt, 0.001)
    watching = nil

    MsgC(Color(255, 220, 120), string.format("[ponyholding] %.1fs watched\n", elapsed))

    for reason, count in SortedPairs(tally) do
        Msg(string.format("    %-18s %4d   (%.2f/sec)\n", reason, count, count / elapsed))
    end

    -- A bail rate near 1/sec would still point at PPM/2's timer rather than
    -- at us, so the rate is printed rather than just the count.
    Msg("    a rate near 1.00/sec is PPM/2's ModelChecks; faster is the bail.\n")
end)

-- What a weapon says about its world model, for the ones we draw something for
-- and should not. There is no single flag meaning "hidden": some declare an
-- empty WorldModel, some set ShowWorldModel false, some override DrawWorldModel
-- and paint their own, and a class with no Lua behind it answers with whatever
-- the engine left on the entity.
concommand.Add("ponyholding_weapon_dump", function()
    local ply = LocalPlayer()
    local weapon = IsValid(ply) and ply:GetActiveWeapon()

    if not IsValid(weapon) then
        Msg("[ponyholding] no active weapon\n")
        return
    end

    local class = weapon:GetClass()
    local stored = weapons.GetStored and weapons.GetStored(class)
    local base = stored and stored.Base and weapons.GetStored(stored.Base)

    local function show(value)
        if value == nil then return "<nil>" end
        if value == "" then return "<empty string>" end
        return tostring(value)
    end

    local drawWorld = "<nil>"

    if stored and stored.DrawWorldModel then
        drawWorld = (base and stored.DrawWorldModel == base.DrawWorldModel)
            and "inherited" or "overridden by this swep"
    end

    Msg(string.format("[ponyholding] %s\n", class))
    Msg(string.format("    lua swep            %s\n", stored and "yes" or "no"))
    Msg(string.format("    ShowWorldModel      inst %s  stored %s\n",
        show(weapon.ShowWorldModel), show(stored and stored.ShowWorldModel)))
    Msg(string.format("    WorldModel          inst %s  stored %s\n",
        show(weapon.WorldModel), show(stored and stored.WorldModel)))
    Msg(string.format("    GetWeaponWorldModel %s\n",
        show(isfunction(weapon.GetWeaponWorldModel) and weapon:GetWeaponWorldModel() or nil)))
    Msg(string.format("    GetModel            %s\n", show(weapon:GetModel())))
    Msg(string.format("    DrawWorldModel      %s\n", drawWorld))
    Msg(string.format("    we would draw       %s\n", show(Holding.WorldModelFor(weapon))))
end, nil, "Dump what the active weapon reports about its world model")
