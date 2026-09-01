--[[
PonyHolding diagnostics -- client side.

The weapon flicking to the chest is the *real* weapon becoming visible for a
frame, not the display model going astray: the display model is created with
SetNoDraw(true) and only ever appears through an explicit DrawModel, so it
cannot render itself anywhere. Something is clearing NoDraw on the weapon.

Only two things can. PPM/2's ModelChecks timer (client/hooks.moon:36) at 1 Hz,
which only touches weapons it flagged itself and only when something says the
weapon should draw -- nothing here implements those hooks. And our own
destroyState, via releaseHiddenWeapon, on any frame ensureState gives up.

So this watches both ends at once: what ensureState decided, and what actually
happened to NoDraw. Prints on transitions only, with the gap since the last
one -- a steady ~1.0s says PPM/2, anything faster says the bail.

    ponyholding_watch [partial name]   start (no name: everypony but you)
    ponyholding_watch_stop             stop, and print the tally
]]

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
        -- Entity index, so a weapon that keeps reading invalid can be told
        -- apart from one being destroyed and recreated. Same index either
        -- side of a gap is a networking hiccup on one entity; a changing
        -- index means something is handing the pony a new weapon.
        index = valid and weapon:EntIndex() or -1,
        -- The usual reason a remote entity reads invalid while its owner
        -- is plainly standing there.
        dormant = ply:IsDormant(),
        -- The two that matter together: NoDraw false while we still believe
        -- the weapon is hidden is precisely the visible frame.
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

    -- "visible" is the whole point: tracked as hidden by us, yet NoDraw is
    -- off, so the engine is drawing the real weapon on the pony this frame.
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
