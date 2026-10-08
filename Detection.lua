-- Social Forever
-- Nearby players for questing groups, and a memory of who you liked grouping with.
-- Built for World of Warcraft: Forever 1.60.1 (Interface 16001).

SocialForever = SocialForever or {}
local SF = SocialForever

local C = SF.Const
local S = SF.State
local Util = SF.Util
local Memory = SF.Memory
local Group = SF.Group
local Detection = SF.Detection
local Sharing = SF.Sharing
local UI = SF.UI

function Detection.ClearSightings()
    wipe(S.sightings)
    wipe(S.zoneSeen)
    wipe(S.zoneRoster)
    wipe(S.inZone)
    wipe(S.inviteState)
    wipe(S.groupedBefore)
    wipe(S.P.nameplateByUnit)
    S.sortHold.at = 0
    S.combatLogSeen = 0
    S.P.publishSig = nil
end

function Detection.IsVisibleMobName(key)
    if type(key) ~= "string" then
        return false
    end
    local wanted = key:lower():gsub("%s+", "-")
    for i = 1, #C.MOB_UNITS do
        local unit = C.MOB_UNITS[i]
        local ok, exists = pcall(UnitExists, unit)
        if ok and Util.PlainBool(exists) == true then
            local playerOk, isPlayer = pcall(UnitIsPlayer, unit)
            if playerOk and Util.PlainBool(isPlayer) == false then
                local nameOk, name = pcall(UnitName, unit)
                name = nameOk and Util.PlainString(name) or nil
                if name and name:lower():gsub("%s+", "-") == wanted then
                    return true
                end
            end
        end
    end
    return false
end

function Detection.Remember(key, bucket, classFile, ttl, yards, level, raceFile, faction, source)
    key = Util.SafeKey(key)
    if not key or Util.IsMe(key) or Detection.IsVisibleMobName(key) then
        if key then
            S.sightings[key] = nil
        end
        return
    end
    local prev = S.sightings[key]
    if yards == nil and prev then
        yards = prev.yards
    end
    classFile = Util.PlainString(classFile) or (prev and prev.class)
    raceFile = Util.NormRaceFile(raceFile) or (prev and prev.race)
    faction = Util.NormFaction(faction) or (prev and prev.faction)
    if not faction and raceFile then
        faction = C.FACTION_BY_RACE[raceFile]
    end
    level = tonumber(level)
    if level and level >= 1 then
        level = math.floor(level)
        local rec = Memory.EnsurePlayer(key)
        rec.level = level
    else
        level = prev and tonumber(prev.level) or nil
        if not level then
            local rec = SF.db and SF.db.players and SF.db.players[key]
            level = type(rec) == "table" and tonumber(rec.level) or nil
        end
        if level then
            level = math.floor(level)
        end
    end
    if classFile or raceFile or faction then
        local rec = Memory.EnsurePlayer(key)
        if classFile then
            rec.class = classFile
        end
        if raceFile then
            rec.race = raceFile
        end
        if faction then
            rec.faction = faction
        end
    end
    local area = Memory.NoteNearbyPlace(key, not prev) or (prev and prev.area)
    local zone = Memory.CurrentZone() or (prev and prev.zone)
    local now = GetTime()
    source = Util.PlainString(source) or (prev and prev.source) or "interaction"
    local trackable = source == "trackable" or source == "nameplate" or (prev and prev.trackable)
    S.sightings[key] = {
        key = key,
        bucket = bucket or 3,
        class = classFile or (prev and prev.class),
        race = raceFile or (prev and prev.race),
        faction = faction or (prev and prev.faction),
        yards = yards,
        level = level,
        area = area,
        zone = zone,
        at = now,
        ttl = ttl or C.CHAT_TTL,
        lastConfirmedAt = now,
        unconfirmedSince = nil,
        source = source,
        trackable = trackable and true or nil,
    }
    Memory.NoteHistory(key)
end

function Detection.WatchZone()
    local zone = Memory.CurrentZone()
    if not zone or zone == S.trackedZone then
        return
    end
    local previous = S.trackedZone
    S.trackedZone = zone
    if previous then
        S.zonePurgeAt = GetTime() + C.ZONE_PURGE_DELAY
    end
end


function Detection.WatchArea()
    if Memory.InCity() then
        S.trackedArea = Memory.CurrentArea()
        S.areaPurgeAt = nil
        return
    end
    local area = Memory.CurrentArea()
    if not area or area == S.trackedArea then
        return
    end
    local previous = S.trackedArea
    S.trackedArea = area
    if previous then
        -- Keep prior-area people visible at least AREA_PURGE_DELAY after a move.
        S.areaPurgeAt = GetTime() + C.AREA_PURGE_DELAY
    end
end

function Detection.PurgeOtherSubzones()
    if Memory.InCity() then
        return
    end
    Detection.WatchArea()
    if not S.areaPurgeAt or GetTime() < S.areaPurgeAt then
        return
    end
    S.areaPurgeAt = nil
    local area = Memory.CurrentArea()
    if not area then
        return
    end
    for key, seen in pairs(S.sightings) do
        local grouped = Group.InMyGroup and Group.InMyGroup(key)
        if not grouped and seen.area and seen.area ~= area then
            S.sightings[key] = nil
            S.inviteState[key] = nil
        end
    end
end

function Detection.PurgeOtherZones()
    Detection.WatchZone()
    if not S.zonePurgeAt or GetTime() < S.zonePurgeAt then
        return
    end
    S.zonePurgeAt = nil
    local zone = Memory.CurrentZone()
    if not zone then
        return
    end
    for key, seen in pairs(S.sightings) do
        local grouped = Group.InMyGroup and Group.InMyGroup(key)
        if not grouped and seen.zone ~= zone then
            S.sightings[key] = nil
            S.inviteState[key] = nil
        end
    end
    for key, seen in pairs(S.zoneSeen) do
        if seen.zone ~= zone then
            S.zoneSeen[key] = nil
        end
    end
    for key, seen in pairs(S.zoneRoster) do
        if seen.zone ~= zone then
            S.zoneRoster[key] = nil
        end
    end
end

function Detection.Publish()
    Detection.DropOfflineGroupSightings()
    Detection.PurgeOtherZones()
    Detection.PurgeOtherSubzones()
    local now = GetTime()
    local found = {}
    local function AddFound(key, seen)
        found[key] = {
            key = key,
            bucket = seen.bucket or 3,
            class = seen.class,
            race = seen.race,
            faction = seen.faction,
            yards = seen.yards,
            level = seen.level,
            area = seen.area,
            zone = seen.zone,
            at = seen.at,
            ttl = seen.ttl,
        }
    end
    for key, seen in pairs(S.sightings) do
        if Util.IsMe(key) or Detection.IsVisibleMobName(key) then
            S.sightings[key] = nil
            S.inviteState[key] = nil
        elseif Group.InMyGroup and Group.InMyGroup(key) then
            seen.at = now
            seen.lastConfirmedAt = now
            seen.unconfirmedSince = nil
            seen.area = Memory.NoteNearbyPlace(key, false) or seen.area
            seen.zone = Memory.CurrentZone() or seen.zone
            Memory.NoteHistory(key)
            AddFound(key, seen)
            Sharing.MaybeHello(key)
            if UI.TryAutoInvite then
                UI.TryAutoInvite(key)
            end
        elseif seen.unconfirmedSince
            and (now - seen.unconfirmedSince) >= (seen.trackable and S.P.staleTrackable or S.P.staleInteraction)
        then
            S.sightings[key] = nil
            S.inviteState[key] = nil
        elseif now - (seen.at or 0) > (seen.ttl or C.SEEN_TTL) then
            S.sightings[key] = nil
            S.inviteState[key] = nil
        else
            AddFound(key, seen)
            Sharing.MaybeHello(key)
            if UI.TryAutoInvite then
                UI.TryAutoInvite(key)
            end
        end
    end
    local zoneFound = {}
    for key, seen in pairs(S.zoneSeen) do
        if Util.IsMe(key) or now - (seen.at or 0) > C.ZONE_TTL or Detection.IsVisibleMobName(key) then
            S.zoneSeen[key] = nil
        elseif not found[key] then
            zoneFound[key] = {
                key = key,
                class = seen.class,
                race = seen.race,
                faction = seen.faction,
                zone = seen.zone,
                at = seen.at,
                ttl = C.ZONE_TTL,
            }
        end
    end
    for key, seen in pairs(S.zoneRoster) do
        if Util.IsMe(key) or now - (seen.at or 0) > C.ZONE_TTL or Detection.IsVisibleMobName(key) then
            S.zoneRoster[key] = nil
        elseif not found[key] and not zoneFound[key] then
            zoneFound[key] = {
                key = key,
                class = seen.class,
                race = seen.race,
                faction = seen.faction,
                zone = seen.zone,
                at = seen.at,
                ttl = C.ZONE_TTL,
                roster = true,
            }
        end
    end
    local targetKey = Util.UnitIdentity("target")
    local sig = Detection.DisplayMapSig(found)
        .. "\29"
        .. Detection.DisplayMapSig(zoneFound)
        .. "\28"
        .. (targetKey or "")
        .. "\27"
        .. (S.P.zoneRosterFull and "+" or "")
    local changed = sig ~= S.P.publishSig
    S.nearby = found
    S.inZone = zoneFound
    S.P.publishSig = sig
    if changed and UI.RefreshList then
        if UI.EnsureListFreezeHonest then
            UI.EnsureListFreezeHonest()
        end
        UI.RefreshList()
    end
end

function Detection.DisplayMapSig(map)
    if type(map) ~= "table" then
        return ""
    end
    local keys = {}
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local entry = map[keys[i]]
        local grouped = Group.InMyGroup and Group.InMyGroup(keys[i])
        parts[i] = table.concat({
            keys[i],
            tostring(entry and entry.bucket or ""),
            (entry and entry.class) or "",
            (entry and entry.race) or "",
            (entry and entry.faction) or "",
            tostring(entry and entry.level or ""),
            (entry and entry.area) or "",
            (entry and entry.zone) or "",
            entry and entry.roster and "r" or "",
            grouped and "g" or "",
        }, "\31")
    end
    return table.concat(parts, "\30")
end

function Detection.UnitIsVisiblePlain(unit)
    local ok, visible = pcall(UnitIsVisible, unit)
    if not ok then
        return nil
    end
    return Util.PlainBool(visible)
end

function Detection.UnitConnectedPlain(unit)
    unit = Util.PlainString(unit) or unit
    if not unit then
        return nil
    end
    if type(UnitIsConnected) ~= "function" then
        return true
    end
    local ok, connected = pcall(UnitIsConnected, unit)
    if not ok then
        return nil
    end
    return Util.PlainBool(connected)
end

-- GUID lookup works for offline characters. Only trust a GUID when the client
-- still has a live, connected unit token for that player.
function Detection.LiveIdentityFromGuid(guid)
    guid = Util.PlainString(guid)
    if not guid or guid == "" then
        return nil
    end
    if type(UnitTokenFromGUID) ~= "function" then
        return nil
    end
    local ok, unit = pcall(UnitTokenFromGUID, guid)
    unit = ok and Util.PlainString(unit) or nil
    if not unit then
        return nil
    end
    if Detection.UnitConnectedPlain(unit) == false then
        return nil
    end
    local playerOk, isPlayer = pcall(UnitIsPlayer, unit)
    if not playerOk or Util.PlainBool(isPlayer) ~= true then
        return nil
    end
    return Util.UnitIdentity(unit)
end

function Detection.DropOfflineGroupSightings()
    local function dropUnit(unit)
        local ok, exists = pcall(UnitExists, unit)
        if not ok or Util.PlainBool(exists) ~= true then
            return
        end
        if Detection.UnitConnectedPlain(unit) ~= false then
            return
        end
        local key = Util.UnitIdentity(unit)
        if key then
            S.sightings[key] = nil
            S.inviteState[key] = nil
        end
    end
    for i = 1, 4 do
        dropUnit("party" .. i)
    end
    if type(IsInRaid) == "function" then
        local raidOk, inRaid = pcall(IsInRaid)
        if raidOk and Util.PlainBool(inRaid) == true then
            for i = 1, 40 do
                dropUnit("raid" .. i)
            end
        end
    end
end

function Detection.UnitLevelPlain(unit)
    if type(UnitLevel) ~= "function" then
        return nil
    end
    local ok, level = pcall(UnitLevel, unit)
    level = ok and Util.PlainNumber(level) or nil
    if not level or level < 1 or level > 80 then
        return nil
    end
    return math.floor(level)
end

function Detection.ConsiderUnit(unit, loose)
    local ok, exists = pcall(UnitExists, unit)
    if not ok or Util.PlainBool(exists) ~= true then
        return
    end
    if Detection.UnitConnectedPlain(unit) == false then
        return
    end
    local playerOk, isPlayer = pcall(UnitIsPlayer, unit)
    if not playerOk or Util.PlainBool(isPlayer) ~= true then
        return
    end
    local selfOk, isSelf = pcall(UnitIsUnit, unit, "player")
    if selfOk and Util.PlainBool(isSelf) == true then
        return
    end
    local key, classFile, raceFile, faction = Util.UnitIdentity(unit)
    if not key or Util.IsMe(key) then
        return
    end

    local yards = Util.DistanceYards(unit)
    local bucket
    if yards then
        if yards > C.MAX_YARDS then
            S.sightings[key] = nil
            return
        end
        if yards <= 12 then
            bucket = 1
        elseif yards <= 30 then
            bucket = 2
        else
            bucket = 3
        end
    elseif Util.Interact(unit, 2) == true then
        bucket = 1
    elseif Util.Interact(unit, 1) == true then
        bucket = 2
    elseif loose and Detection.UnitIsVisiblePlain(unit) == true then
        bucket = 3
    else
        return
    end
    Detection.Remember(key, bucket, classFile, C.UNIT_TTL, yards, Detection.UnitLevelPlain(unit), raceFile, faction, "trackable")
end

function Detection.Scan()
    for i = 1, #C.LOOK_UNITS do
        pcall(Detection.ConsiderUnit, C.LOOK_UNITS[i], true)
    end
    for i = 1, 4 do
        pcall(Detection.ConsiderUnit, "party" .. i, false)
    end
    Detection.Publish()
end

function Detection.ScanRaid()
    local raidOk, inRaid = pcall(IsInRaid)
    if not (raidOk and Util.PlainBool(inRaid) == true) then
        return
    end
    for i = 1, 40 do
        pcall(Detection.ConsiderUnit, "raid" .. i, false)
        pcall(Detection.ConsiderUnit, "raid" .. i .. "target", true)
    end
    Detection.Publish()
end

function Detection.SyncRaidTicker()
    local raidOk, inRaid = pcall(IsInRaid)
    inRaid = raidOk and Util.PlainBool(inRaid) == true
    if inRaid then
        if not S.P.raidTicker then
            S.P.raidTicker = C_Timer.NewTicker(3, Detection.ScanRaid)
            Detection.ScanRaid()
        end
    elseif S.P.raidTicker then
        S.P.raidTicker:Cancel()
        S.P.raidTicker = nil
    end
end

function Detection.NormPresenceKey(key)
    if type(key) ~= "string" then
        return nil
    end
    return key:gsub("[%s%-]+", ""):lower()
end

function Detection.BuildLiveUnitMap()
    local map = {}
    local function take(unit)
        unit = Util.PlainString(unit) or unit
        if not unit then
            return
        end
        local ok, exists = pcall(UnitExists, unit)
        if not ok or Util.PlainBool(exists) ~= true then
            return
        end
        if Detection.UnitConnectedPlain(unit) == false then
            return
        end
        local playerOk, isPlayer = pcall(UnitIsPlayer, unit)
        if not playerOk or Util.PlainBool(isPlayer) ~= true then
            return
        end
        local key = Util.UnitIdentity(unit)
        if not key or Util.IsMe(key) then
            return
        end
        map[key] = unit
        local norm = Detection.NormPresenceKey(key)
        if norm then
            map[norm] = unit
        end
    end
    for i = 1, #C.LOOK_UNITS do
        take(C.LOOK_UNITS[i])
    end
    for i = 1, 4 do
        take("party" .. i)
        take("party" .. i .. "target")
    end
    local raidOk, inRaid = pcall(IsInRaid)
    if raidOk and Util.PlainBool(inRaid) == true then
        for i = 1, 40 do
            take("raid" .. i)
            take("raid" .. i .. "target")
        end
    end
    for unit in pairs(S.P.nameplateByUnit) do
        take(unit)
    end
    return map
end

function Detection.UnitStillNearby(unit)
    local yards = Util.DistanceYards(unit)
    if yards then
        if yards > C.MAX_YARDS then
            return false, yards
        end
        return true, yards
    end
    if Util.Interact(unit, 2) == true or Util.Interact(unit, 1) == true then
        return true, nil
    end
    if Detection.UnitIsVisiblePlain(unit) == true then
        return true, nil
    end
    return nil, nil
end

function Detection.ValidatePresence()
    local any = false
    for _ in pairs(S.sightings) do
        any = true
        break
    end
    if not any then
        return
    end
    local now = GetTime()
    local live = Detection.BuildLiveUnitMap()
    local dirty = false
    for key, seen in pairs(S.sightings) do
        if Group.InMyGroup and Group.InMyGroup(key) then
            seen.lastConfirmedAt = now
            seen.unconfirmedSince = nil
            local unit = live[key] or live[Detection.NormPresenceKey(key)]
            if unit then
                local okNear, yards = Detection.UnitStillNearby(unit)
                if yards then
                    seen.yards = yards
                end
                if okNear == true then
                    seen.at = now
                end
            end
        else
            local unit = live[key] or live[Detection.NormPresenceKey(key)]
            if unit then
                local okNear, yards = Detection.UnitStillNearby(unit)
                if okNear == false then
                    S.sightings[key] = nil
                    S.inviteState[key] = nil
                    dirty = true
                elseif okNear == true then
                    seen.lastConfirmedAt = now
                    seen.unconfirmedSince = nil
                    seen.at = now
                    if yards then
                        seen.yards = yards
                    end
                else
                    -- Token exists but no distance/visible proof: still a positive match.
                    seen.lastConfirmedAt = now
                    seen.unconfirmedSince = nil
                    seen.at = now
                end
            else
                if not seen.unconfirmedSince then
                    seen.unconfirmedSince = now
                end
                local grace = seen.trackable and S.P.staleTrackable or S.P.staleInteraction
                if (now - seen.unconfirmedSince) >= grace then
                    S.sightings[key] = nil
                    S.inviteState[key] = nil
                    dirty = true
                end
            end
        end
    end
    if dirty then
        Detection.Publish()
    end
end

function Detection.MarkPresenceStale(key, accelerate)
    key = Util.SafeKey(key)
    local seen = key and S.sightings[key]
    if not seen or (Group.InMyGroup and Group.InMyGroup(key)) then
        return
    end
    local now = GetTime()
    if not seen.unconfirmedSince then
        seen.unconfirmedSince = now
    elseif accelerate then
        -- Nameplate lost: do not wait a full fresh grace if already stale.
        local grace = seen.trackable and S.P.staleTrackable or S.P.staleInteraction
        local elapsed = now - seen.unconfirmedSince
        if elapsed < (grace * 0.5) then
            seen.unconfirmedSince = now - (grace * 0.5)
        end
    end
end

function Detection.NoteNamed(sender, bucket, ttl)
    sender = Util.PlainString(sender)
    if not sender then
        return
    end
    local name, realm = strsplit("-", sender, 2)
    Detection.Remember(Util.MakeKey(name, realm), bucket, nil, ttl, nil, nil, nil, nil, "interaction")
    Detection.Publish()
end

function Detection.NoteChat(sender, guid)
    guid = Util.PlainString(guid)
    if guid and guid:sub(1, 6) ~= "Player" then
        return
    end
    Detection.NoteNamed(sender, 2, C.CHAT_TTL)
end

function Detection.KeyFromSender(sender)
    sender = Util.PlainString(sender)
    if not sender or sender == "" then
        return nil
    end
    local namePart, realm = strsplit("-", sender, 2)
    if namePart and namePart:find("%s") then
        local first, second = namePart:match("^(%S+)%s+(%S+)$")
        if first and second then
            namePart = first .. "-" .. second
        end
    end
    return Util.MakeKey(namePart, realm)
end

function Detection.IsGeneralChannel(channelString, channelBase)
    local function lead(text)
        text = Util.PlainString(text)
        if not text then
            return nil
        end
        text = text:lower():gsub("^%d+%.%s*", "")
        return text
    end
    local function general(text)
        return text == "general" or text:sub(1, 8) == "general " or text:sub(1, 10) == "general -"
    end
    local base = lead(channelBase)
    local full = lead(channelString)
    if base and general(base) then
        return true
    end
    if full and general(full) then
        return true
    end
    return false
end

function Detection.NoteZone(sender, channelString, channelBase, guid)
    if not Detection.IsGeneralChannel(channelString, channelBase) then
        return
    end
    guid = Util.PlainString(guid)
    if guid and guid ~= "" and guid:sub(1, 6) ~= "Player" then
        return
    end
    local key = Detection.KeyFromSender(sender)
    local classFile, raceFile, faction
    if guid then
        local liveKey, liveClass, liveRace, liveFaction = Detection.LiveIdentityFromGuid(guid)
        if liveKey then
            key = key or liveKey
            classFile = liveClass
            raceFile = liveRace
            faction = liveFaction
        elseif not key then
            return
        else
            -- Chat proves they are speaking now; class/race from GUID is optional.
            local _, guidClass, guidRace = Detection.KeyFromGuid(guid)
            classFile = guidClass
            raceFile = guidRace
        end
    end
    if not key or Util.IsMe(key) or Detection.IsVisibleMobName(key) then
        return
    end
    faction = Util.NormFaction(faction) or (raceFile and C.FACTION_BY_RACE[Util.NormRaceFile(raceFile)]) or nil
    local prev = S.zoneSeen[key]
    S.zoneSeen[key] = {
        key = key,
        class = classFile or (prev and prev.class),
        race = raceFile or (prev and prev.race),
        faction = faction or (prev and prev.faction),
        zone = Memory.CurrentZone() or (prev and prev.zone),
        at = GetTime(),
    }
    if classFile or raceFile or faction then
        local rec = Memory.EnsurePlayer(key)
        if classFile then
            rec.class = classFile
        end
        if raceFile then
            rec.race = raceFile
        end
        if faction then
            rec.faction = faction
        end
    end
    Detection.Publish()
end

--------------------------------------------------
-- Extra detection sources (kept on U to save chunk locals)
--------------------------------------------------

function Detection.KeyFromGuid(guid)
    guid = Util.PlainString(guid)
    if not guid or guid == "" then
        return nil
    end
    if guid:sub(1, 6) ~= "Player" then
        return nil
    end
    if type(GetPlayerInfoByGUID) ~= "function" then
        return nil
    end
    local ok, className, classFile, raceName, raceFile, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
    if not ok then
        return nil
    end
    name = Util.PlainString(name)
    realm = Util.PlainString(realm)
    classFile = Util.PlainString(classFile) or Util.PlainString(className)
    raceFile = Util.NormRaceFile(raceFile) or Util.NormRaceFile(raceName)
    local key = Util.MakeKey(name, realm)
    if not key or Util.IsMe(key) then
        return nil
    end
    return key, classFile, raceFile
end

function Detection.NoteZoneWeak(sender, guid)
    local key = Detection.KeyFromSender(sender)
    local classFile, raceFile, faction
    if guid then
        local liveKey, liveClass, liveRace, liveFaction = Detection.LiveIdentityFromGuid(guid)
        if liveKey then
            key = key or liveKey
            classFile = liveClass
            raceFile = liveRace
            faction = liveFaction
        elseif not key then
            -- GUID alone can name offline characters; skip those echoes.
            return
        end
    end
    if not key or Util.IsMe(key) or Detection.IsVisibleMobName(key) then
        return
    end
    faction = Util.NormFaction(faction) or (raceFile and C.FACTION_BY_RACE[Util.NormRaceFile(raceFile)]) or nil
    local prev = S.zoneSeen[key]
    S.zoneSeen[key] = {
        key = key,
        class = classFile or (prev and prev.class),
        race = raceFile or (prev and prev.race),
        faction = faction or (prev and prev.faction),
        zone = Memory.CurrentZone() or (prev and prev.zone),
        at = GetTime(),
        weak = true,
    }
    if classFile or raceFile or faction then
        local rec = Memory.EnsurePlayer(key)
        if classFile then
            rec.class = classFile
        end
        if raceFile then
            rec.race = raceFile
        end
        if faction then
            rec.faction = faction
        end
    end
    Detection.Publish()
end

function Detection.NoteNearbyNamed(sender, guid)
    local key = Detection.KeyFromSender(sender)
    local classFile, raceFile, faction
    if guid then
        local liveKey, liveClass, liveRace, liveFaction = Detection.LiveIdentityFromGuid(guid)
        if liveKey then
            key = key or liveKey
            classFile = liveClass
            raceFile = liveRace
            faction = liveFaction
        elseif not key then
            return
        end
    end
    if not key or Util.IsMe(key) or Detection.IsVisibleMobName(key) then
        return
    end
    Detection.Remember(key, 1, classFile, C.UNIT_TTL, nil, nil, raceFile, faction, "interaction")
    Detection.Publish()
end

function Detection.IsGeneralChannelName(name)
    name = Util.PlainString(name)
    if not name then
        return false
    end
    name = name:lower():gsub("^%d+%.%s*", "")
    return name == "general" or name:sub(1, 8) == "general " or name:sub(1, 10) == "general -"
end

-- Returns channelNumber, displayIndex, listedCount.
-- Roster APIs on modern clients want the ChannelFrame display index;
-- classic GetNumChannelMembers often wants the channel number.
function Detection.FindGeneralChannel()
    local channelNumber, displayIndex, listedCount

    if type(GetNumDisplayChannels) == "function" and type(GetChannelDisplayInfo) == "function" then
        local ok, count = pcall(GetNumDisplayChannels)
        count = ok and Util.PlainNumber(count) or nil
        if count and count >= 1 then
            for i = 1, count do
                local infoOk, name, header, _, chanNum, members = pcall(GetChannelDisplayInfo, i)
                if infoOk and Util.PlainBool(header) ~= true and Detection.IsGeneralChannelName(name) then
                    displayIndex = i
                    channelNumber = Util.PlainNumber(chanNum)
                    listedCount = Util.PlainNumber(members)
                    break
                end
            end
        end
    end

    if not channelNumber and type(GetChannelList) == "function" then
        local packed = { pcall(GetChannelList) }
        if packed[1] then
            for i = 2, #packed, 3 do
                local id = Util.PlainNumber(packed[i])
                local name = packed[i + 1]
                if id and Detection.IsGeneralChannelName(name) then
                    channelNumber = id
                    break
                end
            end
        end
    end

    if not channelNumber and not displayIndex then
        return nil
    end
    return channelNumber, displayIndex, listedCount
end

function Detection.RosterMemberCount(channelNumber, displayIndex, listedCount)
    local function tryCount(id)
        if not id then
            return nil
        end
        if type(GetNumChannelMembers) == "function" then
            local ok, n = pcall(GetNumChannelMembers, id)
            n = ok and Util.PlainNumber(n) or nil
            if n and n > 0 then
                return n
            end
        end
        if C_ChatInfo and type(C_ChatInfo.GetNumChannelMembers) == "function" then
            local ok, n = pcall(C_ChatInfo.GetNumChannelMembers, id)
            n = ok and Util.PlainNumber(n) or nil
            if n and n > 0 then
                return n
            end
        end
        return nil
    end

    return tryCount(displayIndex) or tryCount(channelNumber) or listedCount
end

function Detection.ReadRosterEntry(channelId, index)
    if not channelId or not index then
        return nil
    end
    -- Modern: name, owner, moderator, guid
    if C_ChatInfo and type(C_ChatInfo.GetChannelRosterInfo) == "function" then
        local ok, name, _, _, guid = pcall(C_ChatInfo.GetChannelRosterInfo, channelId, index)
        if ok then
            name = Util.PlainString(name)
            guid = Util.PlainString(guid)
            if name or guid then
                return name, guid
            end
        end
    end
    -- Legacy: name, owner, isModerator, isMuted (no guid)
    if type(GetChannelRosterInfo) == "function" then
        local ok, name = pcall(GetChannelRosterInfo, channelId, index)
        if ok then
            name = Util.PlainString(name)
            if name then
                return name, nil
            end
        end
    end
    return nil
end

function Detection.RequestGeneralRoster(immediate)
    if immediate then
        S.P.rosterPending = false
        Detection.RefreshGeneralRoster()
        return
    end
    if S.P.rosterPending then
        return
    end
    S.P.rosterPending = true
    C_Timer.After(0.75, function()
        S.P.rosterPending = false
        Detection.RefreshGeneralRoster()
    end)
end

function Detection.RefreshGeneralRoster()
    local channelNumber, displayIndex, listedCount = Detection.FindGeneralChannel()
    if not channelNumber and not displayIndex then
        wipe(S.zoneRoster)
        S.P.zoneRosterFull = false
        Detection.Publish()
        return
    end

    local memberCount = Detection.RosterMemberCount(channelNumber, displayIndex, listedCount)
    if (not memberCount or memberCount < 1) and displayIndex and type(SetSelectedDisplayChannel) == "function" then
        -- Some clients only fill the roster after General is the selected channel.
        pcall(SetSelectedDisplayChannel, displayIndex)
        memberCount = Detection.RosterMemberCount(channelNumber, displayIndex, listedCount)
    end
    if not memberCount or memberCount < 1 then
        return
    end
    -- Channel UI only exposes 200 roster slots; at that cap there are usually more.
    local rosterFull = memberCount >= 200
    if memberCount > 200 then
        memberCount = 200
    end

    local now = GetTime()
    local zone = Memory.CurrentZone()
    if not zone then
        return
    end
    local nextRoster = {}
    local function takeEntry(name, guid)
        local key = name and Detection.KeyFromSender(name) or nil
        local classFile, raceFile, faction
        if guid then
            local guidKey, guidClass, guidRace = Detection.KeyFromGuid(guid)
            if not key then
                key = guidKey
            end
            classFile = guidClass
            raceFile = guidRace
        end
        faction = raceFile and C.FACTION_BY_RACE[Util.NormRaceFile(raceFile)] or nil
        if not key or Util.IsMe(key) or Detection.IsVisibleMobName(key) then
            return
        end
        nextRoster[key] = {
            key = key,
            class = classFile,
            race = raceFile,
            faction = faction,
            zone = zone,
            at = now,
            roster = true,
        }
        if classFile or raceFile or faction then
            local rec = Memory.EnsurePlayer(key)
            if classFile then
                rec.class = classFile
            end
            if raceFile then
                rec.race = raceFile
            end
            if faction then
                rec.faction = faction
            end
        end
    end

    local function harvest(channelId)
        if not channelId then
            return false
        end
        local any = false
        for i = 1, memberCount do
            local name, guid = Detection.ReadRosterEntry(channelId, i)
            if name or guid then
                takeEntry(name, guid)
                any = true
            end
        end
        return any
    end

    local gotAny = harvest(displayIndex) or harvest(channelNumber)
    if not gotAny and displayIndex and type(SetSelectedDisplayChannel) == "function" then
        pcall(SetSelectedDisplayChannel, displayIndex)
        gotAny = harvest(displayIndex) or harvest(channelNumber)
    end

    if not gotAny then
        return
    end

    local rosterSize = 0
    for _ in pairs(nextRoster) do
        rosterSize = rosterSize + 1
    end
    if rosterSize >= 200 then
        rosterFull = true
    end
    S.P.zoneRosterFull = rosterFull == true

    wipe(S.zoneRoster)
    for key, seen in pairs(nextRoster) do
        S.zoneRoster[key] = seen
    end
    Detection.Publish()
end

function Detection.OnNameplateAdded(unit)
    unit = Util.PlainString(unit)
    if not unit then
        return
    end
    local key = Util.UnitIdentity(unit)
    if key and not Util.IsMe(key) then
        S.P.nameplateByUnit[unit] = key
    end
    pcall(Detection.ConsiderUnit, unit, true)
    local seen = key and S.sightings[key]
    if seen then
        seen.source = "nameplate"
        seen.trackable = true
        seen.lastConfirmedAt = GetTime()
        seen.unconfirmedSince = nil
    end
    Detection.Publish()
end

function Detection.OnNameplateRemoved(unit)
    unit = Util.PlainString(unit)
    if not unit then
        return
    end
    local key = S.P.nameplateByUnit[unit]
    S.P.nameplateByUnit[unit] = nil
    if not key then
        local id = Util.UnitIdentity(unit)
        key = id
    end
    if key then
        Detection.MarkPresenceStale(key, true)
    end
end

function Detection.OnPlayerAura(unit, updateInfo)
    unit = Util.PlainString(unit) or unit
    if unit ~= "player" then
        return
    end
    if type(updateInfo) ~= "table" or Util.Secret(updateInfo) then
        return
    end
    local added = updateInfo.addedAuras
    if type(added) ~= "table" or Util.Secret(added) then
        return
    end
    local found = false
    for i = 1, #added do
        local aura = added[i]
        if type(aura) == "table" and not Util.Secret(aura) then
            local helpful = aura.isHelpful
            if helpful == nil and type(aura.isHarmful) == "boolean" then
                helpful = not aura.isHarmful
            end
            if Util.PlainBool(helpful) == true or helpful == true then
                local key, classFile, raceFile, faction
                local source = Util.PlainString(aura.sourceUnit)
                if source then
                    local selfOk, isSelf = pcall(UnitIsUnit, source, "player")
                    if not (selfOk and Util.PlainBool(isSelf) == true) then
                        local playerOk, isPlayer = pcall(UnitIsPlayer, source)
                        if playerOk and Util.PlainBool(isPlayer) == true then
                            key, classFile, raceFile, faction = Util.UnitIdentity(source)
                            if key and Detection.UnitConnectedPlain(source) == false then
                                key, classFile, raceFile, faction = nil, nil, nil, nil
                            end
                        end
                    end
                end
                if not key and C_UnitAuras and type(C_UnitAuras.GetAuraCasterGUID) == "function" then
                    local instanceId = Util.PlainNumber(aura.auraInstanceID)
                    if instanceId then
                        local ok, casterGuid = pcall(C_UnitAuras.GetAuraCasterGUID, "player", instanceId)
                        casterGuid = ok and Util.PlainString(casterGuid) or nil
                        if casterGuid then
                            key, classFile, raceFile, faction = Detection.LiveIdentityFromGuid(casterGuid)
                        end
                    end
                end
                if key and not Util.IsMe(key) then
                    Detection.Remember(key, 1, classFile, C.UNIT_TTL, nil, nil, raceFile, faction, "interaction")
                    found = true
                end
            end
        end
    end
    if found then
        Detection.Publish()
    end
end

function Detection.HarvestDamageMeter(combatStamp)
    if not C_DamageMeter then
        return
    end
    if combatStamp ~= nil and S.P.harvestedGen == combatStamp then
        return
    end
    if type(C_DamageMeter.IsDamageMeterAvailable) == "function" then
        local ok, available = pcall(C_DamageMeter.IsDamageMeterAvailable)
        if ok and Util.PlainBool(available) == false then
            return
        end
    end
    local sessionTypes = {}
    if Enum and Enum.DamageMeterType then
        sessionTypes = {
            Enum.DamageMeterType.DamageDone,
            Enum.DamageMeterType.DamageTaken,
            Enum.DamageMeterType.HealingDone,
            Enum.DamageMeterType.Interrupts,
            Enum.DamageMeterType.Dispels,
        }
    else
        sessionTypes = { 0, 7, 2, 5, 6 }
    end
    local currentType = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
    local seen = {}
    local found = false
    local function takeSource(source)
        if type(source) ~= "table" or Util.Secret(source) then
            return
        end
        if Util.PlainBool(source.isLocalPlayer) == true then
            return
        end
        if source.sourceCreatureID and Util.PlainNumber(source.sourceCreatureID) then
            return
        end
        local guid = Util.PlainString(source.sourceGUID)
        local key, classFile, raceFile, faction
        if guid then
            if seen[guid] then
                return
            end
            seen[guid] = true
            key, classFile, raceFile, faction = Detection.LiveIdentityFromGuid(guid)
        end
        if not key then
            return
        end
        if Util.IsMe(key) or Detection.IsVisibleMobName(key) then
            return
        end
        Detection.Remember(key, 2, classFile, C.UNIT_TTL, nil, nil, raceFile, faction, "interaction")
        found = true
    end
    for _, meterType in ipairs(sessionTypes) do
        if meterType ~= nil and type(C_DamageMeter.GetCombatSessionFromType) == "function" then
            local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, currentType, meterType)
            if ok and type(session) == "table" and not Util.Secret(session) then
                local sources = session.combatSources
                if type(sources) == "table" and not Util.Secret(sources) then
                    for i = 1, #sources do
                        takeSource(sources[i])
                    end
                end
            end
        end
    end
    if combatStamp ~= nil then
        S.P.harvestedGen = combatStamp
    end
    if found then
        Detection.Publish()
    end
end

function Detection.QueueDamageMeterHarvest()
    if S.P.meterPending then
        return
    end
    S.P.meterPending = true
    local stamp = S.P.combatGen
    C_Timer.After(0.75, function()
        S.P.meterPending = false
        if InCombatLockdown() then
            return
        end
        Detection.HarvestDamageMeter(stamp)
        Detection.EvaluateSameMobGrouping(stamp)
    end)
end

function Detection.DamageMeterSessionType()
    return Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
end

function Detection.DamageMeterDamageDoneType()
    return Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
end

-- Mob names this source damaged in the just-finished DamageDone session.
function Detection.MobsDamagedBySource(sourceGUID)
    local mobs = {}
    if not sourceGUID or not C_DamageMeter or type(C_DamageMeter.GetCombatSessionSourceFromType) ~= "function" then
        return mobs
    end
    local ok, sessionSource = pcall(
        C_DamageMeter.GetCombatSessionSourceFromType,
        Detection.DamageMeterSessionType(),
        Detection.DamageMeterDamageDoneType(),
        sourceGUID,
        nil
    )
    if not ok or type(sessionSource) ~= "table" or Util.Secret(sessionSource) then
        return mobs
    end
    local spells = sessionSource.combatSpells
    if type(spells) ~= "table" or Util.Secret(spells) then
        return mobs
    end
    local function takeDetail(detail)
        if type(detail) ~= "table" or Util.Secret(detail) then
            return
        end
        if Util.PlainBool(detail.isMob) ~= true then
            return
        end
        local amount = Util.PlainNumber(detail.amount) or 0
        if amount <= 0 then
            return
        end
        local name = Util.PlainString(detail.unitName)
        if name and name ~= "" then
            mobs[name:lower()] = name
        end
    end
    for i = 1, #spells do
        local spell = spells[i]
        if type(spell) == "table" and not Util.Secret(spell) then
            local details = spell.combatSpellDetails
            if type(details) == "table" and not Util.Secret(details) then
                if details[1] ~= nil then
                    for j = 1, #details do
                        takeDetail(details[j])
                    end
                else
                    takeDetail(details)
                end
            end
        end
    end
    return mobs
end

function Detection.FirstSharedMob(myMobs, theirMobs)
    if type(myMobs) ~= "table" or type(theirMobs) ~= "table" then
        return nil
    end
    for lower, name in pairs(myMobs) do
        if theirMobs[lower] then
            return name
        end
    end
    return nil
end

function Detection.RecentlyNearby(key)
    if not key then
        return false
    end
    if S.nearby and S.nearby[key] then
        return true
    end
    local seen = S.sightings and S.sightings[key]
    if not seen then
        return false
    end
    local grace = C.SAME_MOB_NEARBY_GRACE or 60
    return (GetTime() - (seen.at or 0)) <= grace
end

function Detection.SameMobOnCooldown(key)
    local at = S.sameMobInviteAt and S.sameMobInviteAt[key]
    if not at then
        return false
    end
    return (GetTime() - at) < (C.SAME_MOB_COOLDOWN or 300)
end

function Detection.MarkSameMobCooldown(key)
    key = Util.SafeKey(key)
    if not key then
        return
    end
    S.sameMobInviteAt[key] = GetTime()
end

function Detection.SameMobEligible(key, entry)
    key = Util.SafeKey(key)
    if not key or Util.IsMe(key) then
        return false
    end
    if Group.InMyGroup(key) then
        return false
    end
    if Memory.IsBlocked(key) or Memory.FlaggedKos(key) then
        return false
    end
    if Util.IsOtherFaction(key, entry) then
        return false
    end
    if Detection.IsVisibleMobName(key) then
        return false
    end
    if not Detection.RecentlyNearby(key) then
        return false
    end
    if Detection.SameMobOnCooldown(key) then
        return false
    end
    return true
end

function Detection.CollectSameMobCandidates()
    local list = {}
    if not C_DamageMeter then
        return list
    end
    local myGuid = Util.PlainString(UnitGUID("player"))
    if not myGuid then
        return list
    end
    local myMobs = Detection.MobsDamagedBySource(myGuid)
    if not next(myMobs) then
        return list
    end
    local damageDone = Detection.DamageMeterDamageDoneType()
    local sessionType = Detection.DamageMeterSessionType()
    if type(C_DamageMeter.GetCombatSessionFromType) ~= "function" then
        return list
    end
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, damageDone)
    if not ok or type(session) ~= "table" or Util.Secret(session) then
        return list
    end
    local sources = session.combatSources
    if type(sources) ~= "table" or Util.Secret(sources) then
        return list
    end
    for i = 1, #sources do
        local source = sources[i]
        if type(source) == "table" and not Util.Secret(source) then
            if Util.PlainBool(source.isLocalPlayer) ~= true
                and not (source.sourceCreatureID and Util.PlainNumber(source.sourceCreatureID))
            then
                local amount = Util.PlainNumber(source.totalAmount) or 0
                local guid = Util.PlainString(source.sourceGUID)
                if amount > 0 and guid then
                    local key, classFile, raceFile, faction = Detection.LiveIdentityFromGuid(guid)
                    local entry = {
                        key = key,
                        class = classFile,
                        race = raceFile,
                        faction = faction,
                    }
                    if key and Detection.SameMobEligible(key, entry) then
                        local theirMobs = Detection.MobsDamagedBySource(guid)
                        local shared = Detection.FirstSharedMob(myMobs, theirMobs)
                        if shared then
                            local near = S.nearby and S.nearby[key]
                            local seen = S.sightings and S.sightings[key]
                            list[#list + 1] = {
                                key = key,
                                mob = shared,
                                yards = (near and near.yards) or (seen and seen.yards) or nil,
                                amount = amount,
                                class = classFile,
                                race = raceFile,
                                faction = faction,
                            }
                        end
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        local ya, yb = a.yards, b.yards
        if ya and yb and math.abs(ya - yb) > 0.5 then
            return ya < yb
        end
        if ya and not yb then
            return true
        end
        if yb and not ya then
            return false
        end
        local fa = Memory.Familiarity(a.key)
        local fb = Memory.Familiarity(b.key)
        if fa ~= fb then
            return fa > fb
        end
        return (a.amount or 0) > (b.amount or 0)
    end)
    return list
end

function Detection.EvaluateSameMobGrouping(combatStamp)
    if InCombatLockdown() then
        return
    end
    if not Group.SameMobAskOn() and not Group.SameMobAutoOn() then
        return
    end
    if combatStamp ~= nil and S.P.sameMobStamp == combatStamp then
        return
    end
    if combatStamp ~= nil then
        S.P.sameMobStamp = combatStamp
    end
    if not Group.PartyHasRoom() then
        return
    end
    local candidates = Detection.CollectSameMobCandidates()
    if #candidates == 0 then
        return
    end
    if Group.SameMobAutoOn() then
        local anyInvited = false
        local fallbackFrom = nil
        for i = 1, #candidates do
            if not Group.PartyHasRoom() then
                break
            end
            local cand = candidates[i]
            if Detection.SameMobEligible(cand.key, cand) then
                if Group.InviteByKey(cand.key) then
                    Detection.MarkSameMobCooldown(cand.key)
                    anyInvited = true
                elseif S.P.sameMobApiInvite == false then
                    fallbackFrom = i
                    break
                end
            end
        end
        if UI.RefreshList and anyInvited then
            UI.RefreshList()
        end
        if fallbackFrom then
            -- Forever blocked API invites — fall back to clickable secure Invite.
            wipe(S.sameMobQueue)
            for i = fallbackFrom, #candidates do
                S.sameMobQueue[#S.sameMobQueue + 1] = candidates[i]
            end
            if UI.ShowSameMobPrompt then
                UI.ShowSameMobPrompt()
            end
        end
        return
    end
    if Group.SameMobAskOn() then
        wipe(S.sameMobQueue)
        for i = 1, #candidates do
            S.sameMobQueue[#S.sameMobQueue + 1] = candidates[i]
        end
        if UI.ShowSameMobPrompt then
            UI.ShowSameMobPrompt()
        end
    end
end

function Detection.CleanToken(token)
    if not token then
        return nil
    end
    token = token:gsub("^%p+", ""):gsub("%p+$", ""):gsub("'s$", "")
    if token == "" then
        return nil
    end
    return token
end

function Detection.LeadingName(text)
    text = Util.PlainString(text)
    if not text then
        return nil
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local first, second, third = text:match("^(%S+)%s+(%S+)%s+(%S+)")
    if not first then
        first, second = text:match("^(%S+)%s+(%S+)")
    end
    if not first then
        first = text:match("^(%S+)")
    end
    first = Detection.CleanToken(first)
    second = Detection.CleanToken(second)
    third = Detection.CleanToken(third)
    if not first or C.SKIP_WORDS[first:lower()] then
        return nil
    end
    local thirdWord = third and third:lower()
    local secondWord = second and second:lower()
    if second and thirdWord and C.CRAFT_VERBS[thirdWord]
        and not C.SKIP_WORDS[secondWord]
        and second:find("^%a")
        and not second:find("%d")
    then
        return first .. "-" .. second
    end
    if secondWord and C.CRAFT_VERBS[secondWord] then
        return first
    end
    return nil
end

function Detection.NoteCraftSender(sender)
    sender = Util.PlainString(sender)
    if not sender or sender == "" or C.SKIP_WORDS[sender:lower()] then
        return
    end
    if not sender:find("%s") then
        Detection.NoteNamed(sender, 2, C.SEEN_TTL)
        return
    end
    local first, second = sender:match("^(%S+)%s+(%S+)$")
    first = Detection.CleanToken(first)
    second = Detection.CleanToken(second)
    if not first or not second or C.SKIP_WORDS[first:lower()] or C.SKIP_WORDS[second:lower()] then
        return
    end
    Detection.Remember(Util.SafeKey(first .. "-" .. second), 2, nil, C.SEEN_TTL, nil, nil, nil, nil, "interaction")
    Detection.Publish()
end

function Detection.NoteActivity(message, sender, craft)
    if craft then
        Detection.NoteCraftSender(sender)
    else
        sender = Util.PlainString(sender)
        if sender and sender ~= "" and not sender:find("%s") and not C.SKIP_WORDS[sender:lower()] then
            Detection.NoteNamed(sender, 2, C.SEEN_TTL)
        end
    end
    message = Util.PlainString(message)
    if not message then
        return
    end
    local sawLink = false
    for name in message:gmatch("|Hplayer:([^|:]+)") do
        if name ~= "" and not C.SKIP_WORDS[name:lower()] then
            sawLink = true
            Detection.NoteNamed(name, 2, C.SEEN_TTL)
        end
    end
    if sawLink or not craft then
        return
    end
    local lead = Detection.LeadingName(message)
    if lead then
        Detection.Remember(Util.SafeKey(lead), 2, nil, C.SEEN_TTL, nil, nil, nil, nil, "interaction")
        Detection.Publish()
    end
end

function Detection.CombatLogFrame()
    local windows = NUM_CHAT_WINDOWS or 10
    for i = 1, windows do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.isCombatLog then
            return frame
        end
    end
    return ChatFrame2
end

function Detection.ScanCombatLog()
    local frame = Detection.CombatLogFrame()
    if not frame or not frame.GetNumMessages or not frame.GetMessageInfo then
        return
    end
    local ok, count = pcall(frame.GetNumMessages, frame)
    count = ok and Util.PlainNumber(count) or nil
    if not count or count < 1 then
        return
    end
    if S.combatLogSeen > count then
        S.combatLogSeen = 0
    end
    local startAt = S.combatLogSeen + 1
    if S.combatLogSeen == 0 then
        startAt = math.max(1, count - 4)
    end
    local discovered = false
    for i = startAt, count do
        local textOk, text = pcall(frame.GetMessageInfo, frame, i)
        if textOk and Util.PlainString(text) then
            for name in text:gmatch("|Hplayer:([^|:]+)") do
                if name ~= "" and not C.SKIP_WORDS[name:lower()] then
                    local nameOnly, realm = strsplit("-", name, 2)
                    local key = Util.MakeKey(nameOnly, realm)
                    if key and not Util.IsMe(key) and not S.sightings[key] then
                        Detection.Remember(key, 3, nil, C.SEEN_TTL, nil, nil, nil, nil, "interaction")
                        discovered = true
                    end
                end
            end
        end
    end
    S.combatLogSeen = count
    if discovered then
        Detection.Publish()
    end
end
