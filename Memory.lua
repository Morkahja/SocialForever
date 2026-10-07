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

function Memory.EnsurePlayer(key)
    local rec = SF.db.players[key]
    if type(rec) ~= "table" then
        rec = {}
        SF.db.players[key] = rec
    end
    if type(rec.flags) ~= "table" then
        rec.flags = {}
    end
    return rec
end

function Memory.HasOpinion(rec)
    if type(rec) ~= "table" then
        return false
    end
    if Util.ValidColor(rec.color) or Util.ValidStars(rec.stars) then
        return true
    end
    if type(rec.flags) == "table" then
        for _, on in pairs(rec.flags) do
            if on then
                return true
            end
        end
    end
    return false
end

function Memory.SanitizeFlag(flag)
    if type(flag) ~= "string" then
        return nil
    end
    flag = Util.Trim(flag):gsub("[%c|,]", " "):gsub("%s+", " ")
    if #flag < 2 or #flag > 24 then
        return nil
    end
    return flag
end

function Memory.AllFlags()
    local list = {}
    local seen = {}
    for _, flag in ipairs(C.PRESET_FLAGS) do
        list[#list + 1] = flag
        seen[flag:lower()] = true
    end
    for _, flag in ipairs(SF.db.customFlags) do
        flag = Memory.SanitizeFlag(flag)
        if flag and not seen[flag:lower()] then
            list[#list + 1] = flag
            seen[flag:lower()] = true
        end
    end
    return list
end

--------------------------------------------------
-- One general color from every mark, mine and others'.
-- Green is +1, yellow is 0, red is -1.
-- One red alone stays red. A green and a red become yellow.
-- Three greens and one red become green.
--------------------------------------------------

function Memory.EachVote(key, visitor)
    local mine = SF.db.players[key]
    if type(mine) == "table" then
        local color = Util.ValidColor(mine.color)
        if color then
            visitor(color)
        end
    end
    local remote = SF.db.remote[key]
    if type(remote) ~= "table" then
        return
    end
    for _, note in pairs(remote) do
        if type(note) == "table" then
            local color = Util.ValidColor(note.color)
            if color then
                visitor(color)
            end
        end
    end
end

function Memory.Tally(key)
    local score, good, okay, bad = 0, 0, 0, 0
    Memory.EachVote(key, function(color)
        score = score + (C.COLOR_SCORE[color] or 0)
        if color == "green" then
            good = good + 1
        elseif color == "red" then
            bad = bad + 1
        else
            okay = okay + 1
        end
    end)
    local votes = good + okay + bad
    if votes == 0 then
        return nil, good, okay, bad
    end
    if score > 0 then
        return "green", good, okay, bad
    end
    if score < 0 then
        return "red", good, okay, bad
    end
    return "yellow", good, okay, bad
end

function Memory.GeneralColor(key)
    local color = Memory.Tally(key)
    return color
end

function Memory.BandFor(key)
    local color = Memory.GeneralColor(key)
    if color == "green" then
        return 1
    end
    if color == "red" then
        return 3
    end
    return 2
end

function Memory.FlagCounts(key)
    local counts = {}
    local function add(flags)
        if type(flags) ~= "table" then
            return
        end
        for flag, on in pairs(flags) do
            flag = Memory.SanitizeFlag(flag)
            if on and flag then
                counts[flag] = (counts[flag] or 0) + 1
            end
        end
    end
    local mine = SF.db.players[key]
    if type(mine) == "table" then
        add(mine.flags)
    end
    local remote = SF.db.remote[key]
    if type(remote) == "table" then
        for _, note in pairs(remote) do
            if type(note) == "table" then
                add(note.flags)
            end
        end
    end
    local list = {}
    local seen = {}
    for _, flag in ipairs(Memory.AllFlags()) do
        local count = counts[flag]
        if count then
            list[#list + 1] = { flag = flag, count = count }
            seen[flag] = true
        end
    end
    for flag, count in pairs(counts) do
        if not seen[flag] then
            list[#list + 1] = { flag = flag, count = count }
        end
    end
    return list
end

function Memory.IsBlocked(key)
    if not key then
        return true
    end
    if SF.db and type(SF.db.ignored) == "table" and SF.db.ignored[key] then
        return true
    end
    if C_FriendList and C_FriendList.IsIgnored then
        local ok, ignored = pcall(C_FriendList.IsIgnored, key)
        if ok and Util.PlainBool(ignored) then
            return true
        end
    elseif type(IsIgnored) == "function" then
        local ok, ignored = pcall(IsIgnored, key)
        if ok and Util.PlainBool(ignored) then
            return true
        end
    end
    return false
end

function Memory.BumpSeen(key, field)
    if not SF.db or not key then
        return
    end
    local rec = Memory.EnsurePlayer(key)
    rec[field] = (tonumber(rec[field]) or 0) + 1
    Memory.NoteFamiliarityMax(key)
end

function Memory.SeenCount(key, field)
    local rec = SF.db and SF.db.players and SF.db.players[key]
    if type(rec) ~= "table" then
        return 0
    end
    return tonumber(rec[field]) or 0
end

function Memory.Familiarity(key)
    return Memory.SeenCount(key, "nearbyTimes") + Memory.SeenCount(key, "zoneTimes")
end

function Memory.InvalidateMaxFamiliarity()
    S.P.maxFamiliarity = nil
end

function Memory.NoteFamiliarityMax(key)
    if S.P.maxFamiliarity == nil then
        return
    end
    local n = Memory.Familiarity(key)
    if n > S.P.maxFamiliarity then
        S.P.maxFamiliarity = n
    end
end

function Memory.MaxFamiliarity()
    if S.P.maxFamiliarity ~= nil then
        return S.P.maxFamiliarity
    end
    local maxCount = 0
    if SF.db and type(SF.db.players) == "table" then
        for _, rec in pairs(SF.db.players) do
            if type(rec) == "table" then
                local n = (tonumber(rec.nearbyTimes) or 0) + (tonumber(rec.zoneTimes) or 0)
                if n > maxCount then
                    maxCount = n
                end
            end
        end
    end
    S.P.maxFamiliarity = maxCount
    return maxCount
end


function Memory.CurrentZone()
    local zone = type(GetZoneText) == "function" and Util.PlainString(GetZoneText()) or nil
    if zone and zone ~= "" then
        return zone
    end
    return nil
end

function Memory.CurrentHistoryPlace()
    if type(IsInInstance) == "function" then
        local ok, inside, kind = pcall(IsInInstance)
        inside = ok and Util.PlainBool(inside) or nil
        kind = ok and Util.PlainString(kind) or nil
        if inside and kind and kind ~= "none" and kind ~= "" and type(GetInstanceInfo) == "function" then
            local infoOk, name = pcall(GetInstanceInfo)
            name = infoOk and Util.PlainString(name) or nil
            if name and name ~= "" then
                return name
            end
        end
    end
    return Memory.CurrentZone()
end

function Memory.NoteHistory(key)
    local place = Memory.CurrentHistoryPlace()
    if not place or not SF.db or not key then
        return
    end
    local rec = Memory.EnsurePlayer(key)
    if type(rec.places) ~= "table" then
        rec.places = {}
    end
    local lower = place:lower()
    for i = 1, #rec.places do
        if type(rec.places[i]) == "string" and rec.places[i]:lower() == lower then
            return
        end
    end
    rec.places[#rec.places + 1] = place
    while #rec.places > 12 do
        table.remove(rec.places, 1)
    end
end

function Memory.CurrentArea()
    local zone = Memory.CurrentZone()
    if zone and C.CITY_ZONES[zone:lower()] then
        return zone
    end
    local sub = type(GetSubZoneText) == "function" and Util.PlainString(GetSubZoneText()) or nil
    if sub and sub ~= "" then
        return sub
    end
    if zone and zone ~= "" then
        return zone
    end
    return nil
end

function Memory.NoteNearbyPlace(key, isNew)
    local area = Memory.CurrentArea()
    if not area or not SF.db then
        return area
    end
    local rec = Memory.EnsurePlayer(key)
    if isNew and rec.nearbyArea ~= area then
        rec.nearbyTimes = (tonumber(rec.nearbyTimes) or 0) + 1
        Memory.NoteFamiliarityMax(key)
    end
    rec.nearbyArea = area
    return area
end

function Memory.InCity()
    local zone = Memory.CurrentZone()
    if zone and C.CITY_ZONES[zone:lower()] then
        return true
    end
    return false
end


function Memory.SeenRGB(key, maxCount)
    local n = Memory.Familiarity(key)
    local band = "white"
    if n > 1 and maxCount and maxCount > 1 then
        local ratio = n / maxCount
        if ratio > 0.80 then
            band = "purple"
        elseif ratio > 0.30 then
            band = "blue"
        end
    end
    local rgb = C.SEEN_RGB[band]
    return rgb[1], rgb[2], rgb[3]
end

function Memory.NameRGB(key, entry, maxSeen)
    if Util.IsOtherFaction(key, entry) then
        return C.ENEMY_FACTION_RGB[1], C.ENEMY_FACTION_RGB[2], C.ENEMY_FACTION_RGB[3]
    end
    return Memory.SeenRGB(key, maxSeen)
end

function Memory.FlaggedKos(key)
    local rec = SF.db and SF.db.players and SF.db.players[key]
    return type(rec) == "table" and rec.kos == true
end

function Memory.Touch(rec)
    if type(rec) == "table" then
        rec.updated = Util.Now()
    end
end

function Memory.ToggleKos(key)
    key = Util.SafeKey(key)
    if not key or not SF.db then
        return
    end
    local rec = Memory.EnsurePlayer(key)
    if rec.kos then
        rec.kos = nil
    else
        rec.kos = true
    end
    Memory.Touch(rec)
    if UI.RefreshList then
        UI.RefreshList()
    end
end

--------------------------------------------------
-- Marks and flags
--------------------------------------------------

function Memory.SetColor(key, color)
    key = Util.SafeKey(key)
    if not key then
        return
    end
    local rec = Memory.EnsurePlayer(key)
    rec.color = Util.ValidColor(color)
    Memory.Touch(rec)
    if Sharing.ShareSubject then
        Sharing.ShareSubject(key)
    end
    if UI.RefreshList then
        UI.RefreshList()
    end
end

function Memory.PlayerHasFlag(key, flag)
    local rec = SF.db.players[key]
    return type(rec) == "table" and type(rec.flags) == "table" and rec.flags[flag] == true
end

function Memory.ToggleFlag(key, flag)
    key = Util.SafeKey(key)
    flag = Memory.SanitizeFlag(flag)
    if not key or not flag then
        return
    end
    local rec = Memory.EnsurePlayer(key)
    if rec.flags[flag] then
        rec.flags[flag] = nil
    else
        rec.flags[flag] = true
    end
    Memory.Touch(rec)
    if Sharing.ShareSubject then
        Sharing.ShareSubject(key)
    end
    if UI.RefreshList then
        UI.RefreshList()
    end
    if UI.OpenMenu and S.menu and S.menu:IsShown() and S.menu.key == key then
        UI.OpenMenu(key, true)
    end
end

function Memory.AddCustomFlag(key, text)
    local flag = Memory.SanitizeFlag(text)
    if not flag then
        return
    end
    local seen = {}
    for _, preset in ipairs(C.PRESET_FLAGS) do
        seen[preset:lower()] = true
    end
    local kept = {}
    for _, existing in ipairs(SF.db.customFlags) do
        existing = Memory.SanitizeFlag(existing)
        if existing and not seen[existing:lower()] then
            kept[#kept + 1] = existing
            seen[existing:lower()] = true
        end
    end
    if not seen[flag:lower()] then
        kept[#kept + 1] = flag
    end
    while #kept > 24 do
        table.remove(kept, 1)
    end
    SF.db.customFlags = kept
    local rec = Memory.EnsurePlayer(key)
    rec.flags[flag] = true
    Memory.Touch(rec)
    if Sharing.ShareSubject then
        Sharing.ShareSubject(key)
    end
    if UI.OpenMenu then
        UI.OpenMenu(key, true)
    end
end

function Memory.HistoryLine(key)
    local rec = SF.db.players[key]
    local groups = type(rec) == "table" and tonumber(rec.groups) or 0
    local text
    if groups <= 0 then
        text = "First group"
    elseif groups == 1 then
        text = "Grouped once"
    else
        text = "Grouped " .. groups .. " times"
    end
    local color = type(rec) == "table" and Util.ValidColor(rec.color)
    if color then
        text = text .. " · your mark is " .. color
    end
    return text
end
