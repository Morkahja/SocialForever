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
    -- Shared opinion is marks only. Flags are personal and do not count.
    if type(rec) ~= "table" then
        return false
    end
    if Util.ValidColor(rec.color) or Util.ValidStars(rec.stars) then
        return true
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
    -- Personal flags only. Shared remote notes never contribute.
    local counts = {}
    local mine = SF.db.players[key]
    if type(mine) == "table" and type(mine.flags) == "table" then
        for flag, on in pairs(mine.flags) do
            flag = Memory.SanitizeFlag(flag)
            if on and flag then
                counts[flag] = 1
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
    -- Only real Nearby encounters count toward familiarity / list sorting.
    return Memory.SeenCount(key, "nearbyTimes")
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
        for key, rec in pairs(SF.db.players) do
            if type(rec) == "table" then
                local n = Memory.Familiarity(key)
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

-- Places ("Seen before in …") only for people who have actually been Nearby.
function Memory.NoteHistory(key)
    local place = Memory.CurrentHistoryPlace()
    if not place or not SF.db or not key then
        return
    end
    local rec = Memory.EnsurePlayer(key)
    if (tonumber(rec.nearbyTimes) or 0) < 1 then
        return
    end
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

-- isNew: they just entered Nearby sightings (were not on the list).
-- Familiarity charges only when that re-entry is in a *different* place than
-- the last charged meeting. Same subzone/city after a drop, reload, or relog
-- does not farm nearbyTimes. lastFamiliarityPlace is saved in SocialForeverDB.
function Memory.NoteNearbyPlace(key, isNew)
    local area = Memory.CurrentArea()
    if not area or not SF.db then
        return area
    end
    local rec = Memory.EnsurePlayer(key)
    if isNew then
        local lastPlace = nil
        if type(rec.lastFamiliarityPlace) == "string" and rec.lastFamiliarityPlace ~= "" then
            lastPlace = rec.lastFamiliarityPlace
        elseif type(rec.nearbyArea) == "string" and rec.nearbyArea ~= "" then
            -- Older saves before lastFamiliarityPlace existed.
            lastPlace = rec.nearbyArea
        end
        local samePlace = lastPlace and lastPlace:lower() == area:lower()
        if not samePlace then
            rec.nearbyTimes = (tonumber(rec.nearbyTimes) or 0) + 1
            rec.lastFamiliarityPlace = area
            Memory.NoteFamiliarityMax(key)
        end
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


-- Same bands as SeenRGB: white / blue / purple from nearbyTimes vs max.
function Memory.FamiliarityBand(key)
    local n = Memory.Familiarity(key)
    local maxCount = Memory.MaxFamiliarity()
    if n > 1 and maxCount and maxCount > 1 then
        local ratio = n / maxCount
        if ratio > 0.80 then
            return "purple"
        end
        if ratio > 0.30 then
            return "blue"
        end
    end
    return "white"
end

function Memory.SeenRGB(key, maxCount)
    local band = "white"
    local n = Memory.Familiarity(key)
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

--------------------------------------------------
-- Familiar recognition (quiet chat thought)
--------------------------------------------------

function Memory.PlayerIdentityFiles(key)
    local seen = S.sightings and S.sightings[key]
    local near = S.nearby and S.nearby[key]
    local rec = SF.db and SF.db.players and SF.db.players[key]
    local classFile = (seen and seen.class) or (near and near.class) or (type(rec) == "table" and rec.class) or nil
    local raceFile = (seen and seen.race) or (near and near.race) or (type(rec) == "table" and rec.race) or nil
    return classFile, raceFile
end

function Memory.RecognitionPhrase(key)
    local classFile, raceFile = Memory.PlayerIdentityFiles(key)
    local race = UI.RaceLabel and UI.RaceLabel(raceFile) or nil
    local class = UI.ClassLabel and UI.ClassLabel(classFile) or nil
    if race and class then
        return "I've seen this " .. race .. " " .. class .. " before."
    end
    if class then
        return "I've seen this " .. class .. " before."
    end
    if race then
        return "I've seen this " .. race .. " before."
    end
    return "I've seen this player before."
end

function Memory.RecognitionOnCooldown(key)
    local rec = SF.db and SF.db.players and SF.db.players[key]
    local last = type(rec) == "table" and tonumber(rec.lastRecognitionAt) or nil
    if not last then
        return false
    end
    local now = Util.Now()
    if not now then
        return false
    end
    local gap = C.RECOGNITION_COOLDOWN or 1200
    return (now - last) < gap
end

function Memory.RecognitionEligible(key)
    key = Util.SafeKey(key)
    if not key or Util.IsMe(key) then
        return false
    end
    if Group.InMyGroup and Group.InMyGroup(key) then
        return false
    end
    local band = Memory.FamiliarityBand(key)
    if band ~= "blue" and band ~= "purple" then
        return false
    end
    if Memory.RecognitionOnCooldown(key) then
        return false
    end
    return true
end

function Memory.CancelRecognition(key)
    key = Util.SafeKey(key)
    if not key then
        return
    end
    S.P.recognitionToken[key] = (S.P.recognitionToken[key] or 0) + 1
end

function Memory.PrintRecognition(key)
    local text = Memory.RecognitionPhrase(key)
    local frame = DEFAULT_CHAT_FRAME or ChatFrame1
    if frame and frame.AddMessage then
        frame:AddMessage(text, 0.62, 0.62, 0.62)
    end
end

function Memory.FireRecognition(key)
    key = Util.SafeKey(key)
    if not key then
        return false
    end
    if not Memory.RecognitionEligible(key) then
        return false
    end
    local rec = Memory.EnsurePlayer(key)
    rec.lastRecognitionAt = Util.Now()
    Memory.PrintRecognition(key)
    return true
end

-- delaySeconds nil/0 = fire now (target). Nearby uses a random 2–5s half-second step.
function Memory.ScheduleRecognition(key, delaySeconds)
    key = Util.SafeKey(key)
    if not key then
        return false
    end
    if not Memory.RecognitionEligible(key) then
        return false
    end
    if not S.P.recognitionPending then
        S.P.recognitionPending = {}
    end
    if S.P.recognitionPending[key] then
        return false
    end
    local delay = tonumber(delaySeconds)
    if not delay or delay <= 0 then
        S.P.recognitionPending[key] = true
        Memory.FireRecognition(key)
        S.P.recognitionPending[key] = nil
        return true
    end
    local token = (S.P.recognitionToken[key] or 0) + 1
    S.P.recognitionToken[key] = token
    S.P.recognitionPending[key] = true
    C_Timer.After(delay, function()
        if S.P.recognitionToken[key] ~= token then
            return
        end
        S.P.recognitionPending[key] = nil
        Memory.FireRecognition(key)
    end)
    return true
end

function Memory.RecognitionDelay()
    -- Random 2.0 … 5.0 in half-second steps.
    local steps = 7
    local index = math.random(1, steps)
    return 1.5 + index * 0.5
end

function Memory.NoteNearbyRecognition(key)
    if not S.armed then
        return
    end
    key = Util.SafeKey(key)
    if not key then
        return
    end
    Memory.ScheduleRecognition(key, Memory.RecognitionDelay())
end

function Memory.NoteTargetRecognition()
    if not S.armed or not SF.db then
        return
    end
    local okPlayer, isPlayer = pcall(UnitIsPlayer, "target")
    if not okPlayer or Util.PlainBool(isPlayer) ~= true then
        return
    end
    local key = Util.UnitIdentity("target")
    if not key or Util.IsMe(key) then
        return
    end
    -- Deliberate target: quiet thought now (Nearby appearances stay delayed).
    Memory.ScheduleRecognition(key, nil)
end

function Memory.ResetPlayer(key)
    key = Util.SafeKey(key)
    if not key or not SF.db then
        return false
    end
    Memory.CancelRecognition(key)
    if S.P.recognitionPending then
        S.P.recognitionPending[key] = nil
    end
    if type(SF.db.players) == "table" then
        SF.db.players[key] = nil
    end
    if type(SF.db.remote) == "table" then
        SF.db.remote[key] = nil
    end
    if type(SF.db.ignored) == "table" then
        SF.db.ignored[key] = nil
    end
    S.inviteState[key] = nil
    if S.sameMobInviteAt then
        S.sameMobInviteAt[key] = nil
    end
    if S.helloAt then
        S.helloAt[key] = nil
    end
    if S.helloReplyAt then
        S.helloReplyAt[key] = nil
    end
    if S.pushedAt then
        S.pushedAt[key] = nil
    end
    if S.peers then
        S.peers[key] = nil
    end
    Memory.InvalidateMaxFamiliarity()
    if Detection.Publish then
        Detection.Publish()
    elseif UI.RefreshList then
        UI.RefreshList()
    end
    return true
end

function Memory.ResetAllPlayers()
    if not SF.db then
        return false
    end
    if type(S.P.recognitionToken) == "table" then
        wipe(S.P.recognitionToken)
    end
    if type(S.P.recognitionPending) == "table" then
        wipe(S.P.recognitionPending)
    else
        S.P.recognitionPending = {}
    end
    SF.db.players = {}
    SF.db.remote = {}
    if type(SF.db.ignored) == "table" then
        wipe(SF.db.ignored)
    end
    wipe(S.inviteState)
    if S.sameMobInviteAt then
        wipe(S.sameMobInviteAt)
    end
    if S.helloAt then
        wipe(S.helloAt)
    end
    if S.helloReplyAt then
        wipe(S.helloReplyAt)
    end
    if S.pushedAt then
        wipe(S.pushedAt)
    end
    if S.peers then
        wipe(S.peers)
    end
    Memory.InvalidateMaxFamiliarity()
    if Detection.Publish then
        Detection.Publish()
    elseif UI.RefreshList then
        UI.RefreshList()
    end
    return true
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
    if UI.InvalidateListSort then
        UI.InvalidateListSort()
    end
    if UI.RefreshList then
        UI.RefreshList()
    end
    if UI.PaintRowAppearance then
        UI.PaintRowAppearance(key)
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
    if UI.InvalidateListSort then
        UI.InvalidateListSort()
    end
    if UI.RefreshList then
        UI.RefreshList()
    end
    if UI.PaintRowAppearance then
        UI.PaintRowAppearance(key)
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
    -- Flags stay local; do not touch/share (marks alone go over the wire).
    if UI.RefreshList then
        UI.RefreshList()
    end
    if UI.PaintRowAppearance then
        UI.PaintRowAppearance(key)
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
    if UI.RefreshList then
        UI.RefreshList()
    end
    if UI.PaintRowAppearance then
        UI.PaintRowAppearance(key)
    end
    if UI.OpenMenu then
        UI.OpenMenu(key, true)
    end
end

function Memory.NoteDecline(key)
    key = Util.SafeKey(key)
    if not key or Util.IsMe(key) then
        return nil
    end
    local rec = Memory.EnsurePlayer(key)
    local n = tonumber(rec.declines) or 0
    if n < 0 then
        n = 0
    end
    rec.declines = n + 1
    return rec.declines
end

function Memory.DeclineCount(key)
    local rec = SF.db and SF.db.players and SF.db.players[key]
    local n = type(rec) == "table" and tonumber(rec.declines) or 0
    if not n or n < 0 then
        return 0
    end
    return n
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
    local declines = type(rec) == "table" and tonumber(rec.declines) or 0
    if declines and declines > 0 then
        if declines == 1 then
            text = text .. " · denied invite once"
        else
            text = text .. " · denied invite " .. declines .. " times"
        end
    end
    local color = type(rec) == "table" and Util.ValidColor(rec.color)
    if color then
        text = text .. " · your mark is " .. color
    end
    return text
end
