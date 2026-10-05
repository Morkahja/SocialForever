-- Social Forever
-- Nearby players for questing groups, and a memory of who you liked grouping with.
-- Built for World of Warcraft: Forever 1.60.1 (Interface 16001).
--
-- Another player's quest log is not readable, so this cannot put people on the
-- same quest first. Nearby players come from speech, emotes, crafting lines,
-- the cursor, and other units the game already tracks. Creature names are left out.
-- Nameplates stay off. A nearby name stays for three minutes, and each new
-- sighting refreshes that timer. Out in the world, a different subzone drops
-- them immediately. A capital city counts as one place.
-- Group members stay until they leave the group.
-- People you have seen more often sit higher.
-- Ratings are account-wide. Other copies of this addon can whisper their marks
-- when you stand near them, and those marks are counted with yours.

local ADDON = "SocialForever"
local PREFIX = "SocialForever"
local VISIBLE_ROWS = 5
local ROW_HEIGHT = 24
local MAX_ROWS = 40
local FRAME_WIDTH = 280
local FRAME_HEIGHT = 196
local MAX_YARDS = 50
local SEEN_TTL = 180
local SORT_EVERY = 3
local ZONE_TTL = 600
local ZONE_PURGE_DELAY = 30
local CHAT_TTL = SEEN_TTL
local UNIT_TTL = SEEN_TTL
local EMPTY_TEXT = "No one nearby yet, and no one has spoken in General."
local MAX_ORIGINS = 12
local MAX_SHARE = 8
local HELLO_GAP = 300

local PRESET_FLAGS = {
    "Really friendly",
    "Generous",
    "Weird",
    "Bad behavior",
}

local COLOR_SCORE = { green = 1, yellow = 0, red = -1 }
local COLOR_RGB = {
    green = { 0.35, 1, 0.45 },
    yellow = { 1, 0.86, 0.25 },
    red = { 1, 0.35, 0.30 },
}
local COLOR_LABEL = {
    green = "Green - group again",
    yellow = "Yellow - neutral",
    red = "Red - unpleasant",
}
local WIRE_COLOR = { G = "green", Y = "yellow", R = "red" }
local COLOR_WIRE = { green = "G", yellow = "Y", red = "R" }

local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local PANEL_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local FLAT_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local db
local main, popup, menu, settingsMenu
local U = {}

local function NameSize()
    local size = db and tonumber(db.nameSize)
    if size == 18 or size == 20 then
        return size
    end
    return 16
end

local function RowHeight()
    return NameSize() + 8
end

local function NameFont()
    local font, _, flags = GameFontHighlight:GetFont()
    if type(font) ~= "string" or font == "" then
        font = "Fonts\\FRIZQT__.TTF"
    end
    return font, NameSize(), flags or ""
end

-- SetFont keeps only the Latin face. Chinese names then draw as empty boxes.
local function ApplyNameFont(fontString)
    if not fontString or not fontString.SetFontObject then
        return
    end
    fontString:SetFontObject(GameFontHighlight)
    local size = NameSize()
    if fontString.SetTextScale then
        local _, base = GameFontHighlight:GetFont()
        base = tonumber(base)
        if not base or base <= 0 then
            base = 16
        end
        pcall(fontString.SetTextScale, fontString, size / base)
    elseif fontString.SetFontHeight then
        pcall(fontString.SetFontHeight, fontString, size)
    end
end
local nearby = {}
local inZone = {}
local peers = {}
local lastMembers = {}
local wasParty = false
local armed = false
local queue = {}
local sendReady = false
local helloAt = {}
local helloReplyAt = {}
local pushedAt = {}
local lastPopupSig = ""
local lastPopupAt = 0
local tipToken = 0

local RefreshList
local ShareSubject
local OpenMenu
local PaintChoice

--------------------------------------------------
-- Values the client may seal in combat
--------------------------------------------------

local function Secret(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then
            return true
        end
    end
    if type(canaccessvalue) == "function" then
        local ok, allowed = pcall(canaccessvalue, value)
        if not ok or not allowed then
            return true
        end
    end
    return false
end

local function PlainString(value)
    if type(value) ~= "string" or Secret(value) then
        return nil
    end
    if value == "" then
        return nil
    end
    return value
end

local function PlainBool(value)
    if type(value) ~= "boolean" or Secret(value) then
        return nil
    end
    return value
end

local function PlainNumber(value)
    if type(value) ~= "number" or Secret(value) then
        return nil
    end
    local ok = pcall(function()
        return value + 0
    end)
    if not ok then
        return nil
    end
    return value
end

local function Now()
    if type(GetServerTime) == "function" then
        return GetServerTime()
    end
    return time()
end

local function Trim(text)
    if type(text) ~= "string" then
        return ""
    end
    if strtrim then
        return strtrim(text)
    end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function NormRealm(realm)
    realm = PlainString(realm)
    if not realm then
        return nil
    end
    realm = realm:gsub("%s+", "")
    if realm == "" then
        return nil
    end
    return realm
end

local function MyRealm()
    if type(GetNormalizedRealmName) == "function" then
        local realm = NormRealm(GetNormalizedRealmName())
        if realm then
            return realm
        end
    end
    return NormRealm(GetRealmName())
end

local function MakeKey(name, realm)
    name = PlainString(name)
    if not name or #name < 2 or #name > 24 then
        return nil
    end
    if name:find("[%c|%%%[%]]") then
        return nil
    end
    local theirs = NormRealm(realm)
    local mine = MyRealm()
    if theirs and mine and theirs:lower() ~= mine:lower() then
        return name .. "-" .. theirs
    end
    return name
end

local function SafeKey(key)
    if type(key) ~= "string" or #key < 2 or #key > 50 then
        return nil
    end
    if key:find("[%c|%%%[%]]") then
        return nil
    end
    return key
end

local function MyKey()
    local ok, name, realm = pcall(UnitName, "player")
    if not ok then
        return nil
    end
    return MakeKey(name, realm)
end

local function ValidColor(color)
    if color == "green" or color == "yellow" or color == "red" then
        return color
    end
    return nil
end

local function ValidStars(stars)
    stars = tonumber(stars)
    if not stars then
        return nil
    end
    stars = math.floor(stars)
    if stars < 1 or stars > 5 then
        return nil
    end
    return stars
end

--------------------------------------------------
-- Saved data. Account-wide, loaded with the addon.
--------------------------------------------------

local function EnsurePlayer(key)
    local rec = db.players[key]
    if type(rec) ~= "table" then
        rec = {}
        db.players[key] = rec
    end
    if type(rec.flags) ~= "table" then
        rec.flags = {}
    end
    return rec
end

local function InitDB()
    if type(SocialForeverDB) ~= "table" then
        SocialForeverDB = {}
    end
    db = SocialForeverDB
    if type(db.players) ~= "table" then
        db.players = {}
    end
    if type(db.remote) ~= "table" then
        db.remote = {}
    end
    if type(db.customFlags) ~= "table" then
        db.customFlags = {}
    end
    if db.partyId ~= nil and type(db.partyId) ~= "number" then
        db.partyId = nil
    end
    if type(db.partyCounted) ~= "table" then
        db.partyCounted = nil
    end
    if type(db.ignored) ~= "table" then
        db.ignored = {}
    end
    if not db.migratedIgnoreFlags then
        local hasIgnoredName = false
        for _, existing in ipairs(db.customFlags) do
            if type(existing) == "string" and existing:lower() == "ignored" then
                hasIgnoredName = true
                break
            end
        end
        for key in pairs(db.ignored) do
            if type(key) == "string" then
                local rec = EnsurePlayer(key)
                rec.color = "red"
                rec.flags["Ignored"] = true
                if not hasIgnoredName then
                    db.customFlags[#db.customFlags + 1] = "Ignored"
                    hasIgnoredName = true
                end
            end
        end
        db.migratedIgnoreFlags = true
    end
end

local function HasOpinion(rec)
    if type(rec) ~= "table" then
        return false
    end
    if ValidColor(rec.color) or ValidStars(rec.stars) then
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

local function SanitizeFlag(flag)
    if type(flag) ~= "string" then
        return nil
    end
    flag = Trim(flag):gsub("[%c|,]", " "):gsub("%s+", " ")
    if #flag < 2 or #flag > 24 then
        return nil
    end
    return flag
end

local function AllFlags()
    local list = {}
    local seen = {}
    for _, flag in ipairs(PRESET_FLAGS) do
        list[#list + 1] = flag
        seen[flag:lower()] = true
    end
    for _, flag in ipairs(db.customFlags) do
        flag = SanitizeFlag(flag)
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

local function EachVote(key, visitor)
    local mine = db.players[key]
    if type(mine) == "table" then
        local color = ValidColor(mine.color)
        if color then
            visitor(color)
        end
    end
    local remote = db.remote[key]
    if type(remote) ~= "table" then
        return
    end
    for _, note in pairs(remote) do
        if type(note) == "table" then
            local color = ValidColor(note.color)
            if color then
                visitor(color)
            end
        end
    end
end

local function Tally(key)
    local score, good, okay, bad = 0, 0, 0, 0
    EachVote(key, function(color)
        score = score + (COLOR_SCORE[color] or 0)
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

local function GeneralColor(key)
    local color = Tally(key)
    return color
end

local function BandFor(key)
    local color = GeneralColor(key)
    if color == "green" then
        return 1
    end
    if color == "red" then
        return 3
    end
    return 2
end

local function FlagCounts(key)
    local counts = {}
    local function add(flags)
        if type(flags) ~= "table" then
            return
        end
        for flag, on in pairs(flags) do
            flag = SanitizeFlag(flag)
            if on and flag then
                counts[flag] = (counts[flag] or 0) + 1
            end
        end
    end
    local mine = db.players[key]
    if type(mine) == "table" then
        add(mine.flags)
    end
    local remote = db.remote[key]
    if type(remote) == "table" then
        for _, note in pairs(remote) do
            if type(note) == "table" then
                add(note.flags)
            end
        end
    end
    local list = {}
    local seen = {}
    for _, flag in ipairs(AllFlags()) do
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

--------------------------------------------------
-- Nearby players. No nameplates.
-- Say and emotes are the short range around you. Mouseover, target, and the
-- person in front of you are units the game already has. Party members are
-- included only when a real distance puts them inside 50 yards.
-- COMBAT_LOG_EVENT_UNFILTERED is not registered: on this client it errors,
-- and the combat-log lines that do arrive are sealed, so names cannot be read.
--------------------------------------------------

local function DistanceYards(unit)
    if type(UnitDistanceSquared) ~= "function" then
        return nil
    end
    local ok, distSq, checked = pcall(UnitDistanceSquared, unit)
    if not ok or PlainBool(checked) ~= true then
        return nil
    end
    local sq = PlainNumber(distSq)
    if not sq or sq < 0 then
        return nil
    end
    return math.sqrt(sq)
end

local function Interact(unit, index)
    if type(CheckInteractDistance) ~= "function" then
        return nil
    end
    local ok, value = pcall(CheckInteractDistance, unit, index)
    if not ok then
        return nil
    end
    return PlainBool(value)
end

local function UnitIdentity(unit)
    local ok, name, realm = pcall(UnitName, unit)
    if not ok then
        return nil
    end
    local key = MakeKey(name, realm)
    if not key then
        return nil
    end
    local classFile
    local classOk, _, file = pcall(UnitClass, unit)
    if classOk then
        classFile = PlainString(file)
    end
    return key, classFile
end

local LOOK_UNITS = {
    "mouseover",
    "target",
    "focus",
    "softfriend",
    "softenemy",
    "softinteract",
    "targettarget",
    "mouseovertarget",
    "party1target",
    "party2target",
    "party3target",
    "party4target",
    "npc",
}

local sightings = {}
local zoneSeen = {}
local inviteState = {}
local groupedBefore = {}
local sortHold = { at = 0, near = {}, zone = {} }
local listedKeys = {}
local fadeInAt = {}
local fadeOutAt = {}
local fadeOutEntry = {}
local moveWave
local moveKeys = {}
local moveHeld
local lastShown
local RowFadeAlpha
local FADE_IN_TIME = 0.4
local FADE_OUT_TIME = 3
local MOVE_HALF = 0.8
local trackedZone
local zonePurgeAt
local friendNames = {}
local combatLogSeen = 0
local TryAutoInvite
local InMyParty

local SKIP_WORDS = {
    you = true,
    your = true,
    someone = true,
    unknown = true,
    creates = true,
    create = true,
    created = true,
    performs = true,
    perform = true,
    has = true,
    hits = true,
    hit = true,
    crits = true,
    casts = true,
    cast = true,
    gains = true,
    misses = true,
    resists = true,
    dies = true,
}

local function ClearSightings()
    wipe(sightings)
    wipe(zoneSeen)
    wipe(inZone)
    wipe(inviteState)
    wipe(groupedBefore)
    sortHold.at = 0
    combatLogSeen = 0
end

local function IsBlocked(key)
    if not key then
        return true
    end
    if db and type(db.ignored) == "table" and db.ignored[key] then
        return true
    end
    if C_FriendList and C_FriendList.IsIgnored then
        local ok, ignored = pcall(C_FriendList.IsIgnored, key)
        if ok and PlainBool(ignored) then
            return true
        end
    elseif type(IsIgnored) == "function" then
        local ok, ignored = pcall(IsIgnored, key)
        if ok and PlainBool(ignored) then
            return true
        end
    end
    return false
end

local function CanWhisperTarget(target)
    if type(target) ~= "string" or target == "" or Secret(target) then
        return false
    end
    if target:find("%s") then
        return false
    end
    local mine = MyRealm()
    local base = target
    if mine and #target > #mine + 1 and target:lower():sub(-(#mine + 1)) == "-" .. mine:lower() then
        base = target:sub(1, #(target) - #mine - 1)
    end
    -- Forever two-word names are stored as First-Second. Whispering that
    -- form makes the client look up "First Second" and print that nobody
    -- by that name is playing, even when they are standing next to you.
    if base:find("-") or base:find("%s") then
        return false
    end
    return true
end

local function MaybeHello(key)
    if not sendReady or not main:IsShown() then
        return
    end
    if not CanWhisperTarget(key) then
        return
    end
    local now = GetTime()
    if helloAt[key] and now - helloAt[key] < HELLO_GAP then
        return
    end
    helloAt[key] = now
    if #queue < 80 then
        queue[#queue + 1] = { target = key, msg = "H1" }
    end
end

local MOB_UNITS = {
    "target",
    "mouseover",
    "focus",
    "softenemy",
    "softinteract",
    "npc",
    "targettarget",
    "mouseovertarget",
    "party1target",
    "party2target",
    "party3target",
    "party4target",
}

local function IsVisibleMobName(key)
    if type(key) ~= "string" then
        return false
    end
    local wanted = key:lower():gsub("%s+", "-")
    for i = 1, #MOB_UNITS do
        local unit = MOB_UNITS[i]
        local ok, exists = pcall(UnitExists, unit)
        if ok and PlainBool(exists) == true then
            local playerOk, isPlayer = pcall(UnitIsPlayer, unit)
            if playerOk and PlainBool(isPlayer) == false then
                local nameOk, name = pcall(UnitName, unit)
                name = nameOk and PlainString(name) or nil
                if name and name:lower():gsub("%s+", "-") == wanted then
                    return true
                end
            end
        end
    end
    return false
end

local function BumpSeen(key, field)
    if not db or not key then
        return
    end
    local rec = EnsurePlayer(key)
    rec[field] = (tonumber(rec[field]) or 0) + 1
end

local function SeenCount(key, field)
    local rec = db and db.players and db.players[key]
    if type(rec) ~= "table" then
        return 0
    end
    return tonumber(rec[field]) or 0
end

local function Familiarity(key)
    return SeenCount(key, "nearbyTimes") + SeenCount(key, "zoneTimes")
end

local function MaxFamiliarity()
    local maxCount = 0
    if db and type(db.players) == "table" then
        for _, rec in pairs(db.players) do
            if type(rec) == "table" then
                local n = (tonumber(rec.nearbyTimes) or 0) + (tonumber(rec.zoneTimes) or 0)
                if n > maxCount then
                    maxCount = n
                end
            end
        end
    end
    return maxCount
end

local SEEN_RGB = {
    white = { 0.95, 0.95, 0.95 },
    blue = { 0.45, 0.7, 1 },
    purple = { 0.76, 0.45, 1 },
}

local function SeenRGB(key, maxCount)
    local n = Familiarity(key)
    local band = "white"
    if n > 1 and maxCount and maxCount > 1 then
        local ratio = n / maxCount
        if ratio > 0.80 then
            band = "purple"
        elseif ratio > 0.30 then
            band = "blue"
        end
    end
    local rgb = SEEN_RGB[band]
    return rgb[1], rgb[2], rgb[3]
end

local CITY_ZONES = {
    ironforge = true,
    ["stormwind city"] = true,
    stormwind = true,
    darnassus = true,
    orgrimmar = true,
    ["thunder bluff"] = true,
    undercity = true,
    ["the exodar"] = true,
    ["silvermoon city"] = true,
    ["shattrath city"] = true,
    dalaran = true,
}

local function CurrentZone()
    local zone = type(GetZoneText) == "function" and PlainString(GetZoneText()) or nil
    if zone and zone ~= "" then
        return zone
    end
    return nil
end

local function CurrentHistoryPlace()
    if type(IsInInstance) == "function" then
        local ok, inside, kind = pcall(IsInInstance)
        inside = ok and PlainBool(inside) or nil
        kind = ok and PlainString(kind) or nil
        if inside and kind and kind ~= "none" and kind ~= "" and type(GetInstanceInfo) == "function" then
            local infoOk, name = pcall(GetInstanceInfo)
            name = infoOk and PlainString(name) or nil
            if name and name ~= "" then
                return name
            end
        end
    end
    return CurrentZone()
end

local function NoteHistory(key)
    local place = CurrentHistoryPlace()
    if not place or not db or not key then
        return
    end
    local rec = EnsurePlayer(key)
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

local function CurrentArea()
    local zone = CurrentZone()
    if zone and CITY_ZONES[zone:lower()] then
        return zone
    end
    local sub = type(GetSubZoneText) == "function" and PlainString(GetSubZoneText()) or nil
    if sub and sub ~= "" then
        return sub
    end
    if zone and zone ~= "" then
        return zone
    end
    return nil
end

local function NoteNearbyPlace(key, isNew)
    local area = CurrentArea()
    if not area or not db then
        return area
    end
    local rec = EnsurePlayer(key)
    if isNew and rec.nearbyArea ~= area then
        rec.nearbyTimes = (tonumber(rec.nearbyTimes) or 0) + 1
    end
    rec.nearbyArea = area
    return area
end

local function Remember(key, bucket, classFile, ttl, yards, level)
    key = SafeKey(key)
    if not key or key == MyKey() or IsVisibleMobName(key) then
        if key then
            sightings[key] = nil
        end
        return
    end
    local prev = sightings[key]
    if yards == nil and prev then
        yards = prev.yards
    end
    level = tonumber(level)
    if level and level >= 1 then
        level = math.floor(level)
        local rec = EnsurePlayer(key)
        rec.level = level
    else
        level = prev and tonumber(prev.level) or nil
        if not level then
            local rec = db and db.players and db.players[key]
            level = type(rec) == "table" and tonumber(rec.level) or nil
        end
        if level then
            level = math.floor(level)
        end
    end
    local area = NoteNearbyPlace(key, not prev) or (prev and prev.area)
    local zone = CurrentZone() or (prev and prev.zone)
    sightings[key] = {
        key = key,
        bucket = bucket or 3,
        class = classFile or (prev and prev.class),
        yards = yards,
        level = level,
        area = area,
        zone = zone,
        at = GetTime(),
        ttl = ttl or CHAT_TTL,
    }
    NoteHistory(key)
end

local function WatchZone()
    local zone = CurrentZone()
    if not zone or zone == trackedZone then
        return
    end
    local previous = trackedZone
    trackedZone = zone
    if previous then
        zonePurgeAt = GetTime() + ZONE_PURGE_DELAY
    end
end

local function InCity()
    local zone = CurrentZone()
    if zone and CITY_ZONES[zone:lower()] then
        return true
    end
    return false
end

local function PurgeOtherSubzones()
    if InCity() then
        return
    end
    local area = CurrentArea()
    if not area then
        return
    end
    for key, seen in pairs(sightings) do
        local grouped = InMyParty and InMyParty(key)
        if not grouped and seen.area and seen.area ~= area then
            sightings[key] = nil
            inviteState[key] = nil
        end
    end
end

local function PurgeOtherZones()
    WatchZone()
    if not zonePurgeAt or GetTime() < zonePurgeAt then
        return
    end
    zonePurgeAt = nil
    local zone = CurrentZone()
    if not zone then
        return
    end
    for key, seen in pairs(sightings) do
        local grouped = InMyParty and InMyParty(key)
        if not grouped and seen.zone ~= zone then
            sightings[key] = nil
            inviteState[key] = nil
        end
    end
    for key, seen in pairs(zoneSeen) do
        if seen.zone ~= zone then
            zoneSeen[key] = nil
        end
    end
end

local function Publish()
    PurgeOtherZones()
    PurgeOtherSubzones()
    local now = GetTime()
    local found = {}
    local function AddFound(key, seen)
        found[key] = {
            key = key,
            bucket = seen.bucket or 3,
            class = seen.class,
            yards = seen.yards,
            level = seen.level,
            area = seen.area,
            zone = seen.zone,
            at = seen.at,
            ttl = seen.ttl,
        }
    end
    for key, seen in pairs(sightings) do
        if IsVisibleMobName(key) then
            sightings[key] = nil
            inviteState[key] = nil
        elseif InMyParty and InMyParty(key) then
            seen.at = now
            seen.area = NoteNearbyPlace(key, false) or seen.area
            seen.zone = CurrentZone() or seen.zone
            NoteHistory(key)
            AddFound(key, seen)
            MaybeHello(key)
            if TryAutoInvite then
                TryAutoInvite(key)
            end
        elseif now - (seen.at or 0) > (seen.ttl or SEEN_TTL) then
            sightings[key] = nil
            inviteState[key] = nil
        else
            AddFound(key, seen)
            MaybeHello(key)
            if TryAutoInvite then
                TryAutoInvite(key)
            end
        end
    end
    local zoneFound = {}
    for key, seen in pairs(zoneSeen) do
        if now - (seen.at or 0) > ZONE_TTL or IsVisibleMobName(key) then
            zoneSeen[key] = nil
        elseif not found[key] then
            zoneFound[key] = {
                key = key,
                class = seen.class,
                zone = seen.zone,
                at = seen.at,
                ttl = ZONE_TTL,
            }
        end
    end
    nearby = found
    inZone = zoneFound
    if RefreshList then
        RefreshList()
    end
end

local function UnitIsVisiblePlain(unit)
    local ok, visible = pcall(UnitIsVisible, unit)
    if not ok then
        return nil
    end
    return PlainBool(visible)
end

local function UnitLevelPlain(unit)
    if type(UnitLevel) ~= "function" then
        return nil
    end
    local ok, level = pcall(UnitLevel, unit)
    level = ok and PlainNumber(level) or nil
    if not level or level < 1 or level > 80 then
        return nil
    end
    return math.floor(level)
end

local function ConsiderUnit(unit, loose)
    local ok, exists = pcall(UnitExists, unit)
    if not ok or PlainBool(exists) ~= true then
        return
    end
    local playerOk, isPlayer = pcall(UnitIsPlayer, unit)
    if not playerOk or PlainBool(isPlayer) ~= true then
        return
    end
    local selfOk, isSelf = pcall(UnitIsUnit, unit, "player")
    if selfOk and PlainBool(isSelf) == true then
        return
    end
    local key, classFile = UnitIdentity(unit)
    if not key or key == MyKey() then
        return
    end

    local yards = DistanceYards(unit)
    local bucket
    if yards then
        if yards > MAX_YARDS then
            sightings[key] = nil
            return
        end
        if yards <= 12 then
            bucket = 1
        elseif yards <= 30 then
            bucket = 2
        else
            bucket = 3
        end
    elseif Interact(unit, 2) == true then
        bucket = 1
    elseif Interact(unit, 1) == true then
        bucket = 2
    elseif loose and UnitIsVisiblePlain(unit) == true then
        bucket = 3
    else
        return
    end
    Remember(key, bucket, classFile, UNIT_TTL, yards, UnitLevelPlain(unit))
end

local function Scan()
    for i = 1, #LOOK_UNITS do
        pcall(ConsiderUnit, LOOK_UNITS[i], true)
    end
    for i = 1, 4 do
        pcall(ConsiderUnit, "party" .. i, false)
    end
    Publish()
end

local function NoteNamed(sender, bucket, ttl)
    sender = PlainString(sender)
    if not sender then
        return
    end
    local name, realm = strsplit("-", sender, 2)
    Remember(MakeKey(name, realm), bucket, nil, ttl)
    Publish()
end

local function NoteChat(sender, guid)
    guid = PlainString(guid)
    if guid and guid:sub(1, 6) ~= "Player" then
        return
    end
    NoteNamed(sender, 2, CHAT_TTL)
end

local function KeyFromSender(sender)
    sender = PlainString(sender)
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
    return MakeKey(namePart, realm)
end

local function IsGeneralChannel(channelString, channelBase)
    local function lead(text)
        text = PlainString(text)
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

local function NoteZone(sender, channelString, channelBase, guid)
    if not IsGeneralChannel(channelString, channelBase) then
        return
    end
    guid = PlainString(guid)
    if guid and guid ~= "" and guid:sub(1, 6) ~= "Player" then
        return
    end
    local key = KeyFromSender(sender)
    if not key or key == MyKey() or IsVisibleMobName(key) then
        return
    end
    local prev = zoneSeen[key]
    if not prev then
        BumpSeen(key, "zoneTimes")
    end
    zoneSeen[key] = {
        key = key,
        class = prev and prev.class,
        zone = CurrentZone() or (prev and prev.zone),
        at = GetTime(),
    }
    NoteHistory(key)
    Publish()
end

local CRAFT_VERBS = {
    creates = true,
    create = true,
    created = true,
    performs = true,
    perform = true,
    performed = true,
}

local function CleanToken(token)
    if not token then
        return nil
    end
    token = token:gsub("^%p+", ""):gsub("%p+$", ""):gsub("'s$", "")
    if token == "" then
        return nil
    end
    return token
end

local function LeadingName(text)
    text = PlainString(text)
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
    first = CleanToken(first)
    second = CleanToken(second)
    third = CleanToken(third)
    if not first or SKIP_WORDS[first:lower()] then
        return nil
    end
    local thirdWord = third and third:lower()
    local secondWord = second and second:lower()
    if second and thirdWord and CRAFT_VERBS[thirdWord]
        and not SKIP_WORDS[secondWord]
        and second:find("^%a")
        and not second:find("%d")
    then
        return first .. "-" .. second
    end
    if secondWord and CRAFT_VERBS[secondWord] then
        return first
    end
    return nil
end

local function NoteCraftSender(sender)
    sender = PlainString(sender)
    if not sender or sender == "" or SKIP_WORDS[sender:lower()] then
        return
    end
    if not sender:find("%s") then
        NoteNamed(sender, 2, SEEN_TTL)
        return
    end
    local first, second = sender:match("^(%S+)%s+(%S+)$")
    first = CleanToken(first)
    second = CleanToken(second)
    if not first or not second or SKIP_WORDS[first:lower()] or SKIP_WORDS[second:lower()] then
        return
    end
    Remember(SafeKey(first .. "-" .. second), 2, nil, SEEN_TTL)
    Publish()
end

local function NoteActivity(message, sender, craft)
    if craft then
        NoteCraftSender(sender)
    else
        sender = PlainString(sender)
        if sender and sender ~= "" and not sender:find("%s") and not SKIP_WORDS[sender:lower()] then
            NoteNamed(sender, 2, SEEN_TTL)
        end
    end
    message = PlainString(message)
    if not message then
        return
    end
    local sawLink = false
    for name in message:gmatch("|Hplayer:([^|:]+)") do
        if name ~= "" and not SKIP_WORDS[name:lower()] then
            sawLink = true
            NoteNamed(name, 2, SEEN_TTL)
        end
    end
    if sawLink or not craft then
        return
    end
    local lead = LeadingName(message)
    if lead then
        Remember(SafeKey(lead), 2, nil, SEEN_TTL)
        Publish()
    end
end

local function CombatLogFrame()
    local windows = NUM_CHAT_WINDOWS or 10
    for i = 1, windows do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.isCombatLog then
            return frame
        end
    end
    return ChatFrame2
end

local function ScanCombatLog()
    local frame = CombatLogFrame()
    if not frame or not frame.GetNumMessages or not frame.GetMessageInfo then
        return
    end
    local ok, count = pcall(frame.GetNumMessages, frame)
    count = ok and PlainNumber(count) or nil
    if not count or count < 1 then
        return
    end
    if combatLogSeen > count then
        combatLogSeen = 0
    end
    local startAt = combatLogSeen + 1
    if combatLogSeen == 0 then
        startAt = math.max(1, count - 4)
    end
    for i = startAt, count do
        local textOk, text = pcall(frame.GetMessageInfo, frame, i)
        if textOk and PlainString(text) then
            for name in text:gmatch("|Hplayer:([^|:]+)") do
                if name ~= "" and not SKIP_WORDS[name:lower()] then
                    local nameOnly, realm = strsplit("-", name, 2)
                    Remember(MakeKey(nameOnly, realm), 3, nil, SEEN_TTL)
                end
            end
        end
    end
    combatLogSeen = count
    Publish()
end

local function PartyKeys()
    local list = {}
    local me = MyKey()
    for i = 1, 4 do
        local unit = "party" .. i
        local ok, exists = pcall(UnitExists, unit)
        if ok and PlainBool(exists) then
            local key = UnitIdentity(unit)
            if key and key ~= me then
                list[#list + 1] = key
            end
        end
    end
    return list
end

InMyParty = function(key)
    local members = PartyKeys()
    for _, member in ipairs(members) do
        if member == key then
            return true
        end
    end
    return false
end

local function RefreshFriends()
    wipe(friendNames)
    if not (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex) then
        return
    end
    local ok, count = pcall(C_FriendList.GetNumFriends)
    count = ok and PlainNumber(count) or nil
    if not count or count < 1 then
        return
    end
    if count > 200 then
        count = 200
    end
    for i = 1, count do
        local infoOk, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
        if infoOk then
            local name = type(info) == "table" and PlainString(info.name) or PlainString(info)
            if name then
                friendNames[name] = true
                local short = name:match("^([^%-]+)")
                if short and short ~= name then
                    friendNames[short] = true
                end
            end
        end
    end
end

local function FriendsAutoOn()
    return db and db.autoInviteFriends ~= false
end

local function FlaggedKos(key)
    local rec = db and db.players and db.players[key]
    return type(rec) == "table" and rec.kos == true
end

local function SpokenName(key)
    if type(key) ~= "string" then
        return key
    end
    return (key:gsub("-", " "))
end

local function ListName(key, level)
    local name = SpokenName(key) or ""
    level = tonumber(level)
    if not level or level < 1 then
        local rec = db and db.players and db.players[key]
        level = type(rec) == "table" and tonumber(rec.level) or nil
    end
    if level and level >= 1 and level <= 80 then
        return name .. "  " .. math.floor(level)
    end
    return name
end

local function TargetMacro(key)
    local spoken = SpokenName(key)
    if type(spoken) ~= "string" then
        return nil
    end
    local first = spoken:match("^(%S+)")
    if not first or first == "" then
        return nil
    end
    return "/target " .. first
end

local function ApplyMacro(button, macro, anyClick)
    if not button or InCombatLockdown() then
        return
    end
    macro = macro or ""
    local stamp = macro .. (anyClick and ":any" or ":left")
    if button.lastMacro == stamp then
        return
    end
    button.lastMacro = stamp
    button:SetAttribute("*type1", nil)
    button:SetAttribute("*macrotext1", nil)
    button:SetAttribute("type", nil)
    button:SetAttribute("macrotext", nil)
    button:SetAttribute("type1", nil)
    button:SetAttribute("macrotext1", nil)
    if macro == "" then
        return
    end
    button:SetAttribute("type1", "macro")
    button:SetAttribute("macrotext1", macro)
    if anyClick then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", macro)
    end
end

local function ApplyTarget(row, key)
    ApplyMacro(row, TargetMacro(key), false)
end

local function SlashName(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end
    local name = key
    local mine = MyRealm()
    if mine and #key > #mine + 1 and key:lower():sub(-(#mine + 1)) == "-" .. mine:lower() then
        local base = key:sub(1, #key - #mine - 1)
        name = base:gsub("-", " ") .. "-" .. key:sub(#key - #mine + 1)
    else
        name = key:gsub("-", " ")
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        return nil
    end
    return name
end

local function InviteMacro(key)
    local name = SlashName(key)
    if not name then
        return nil
    end
    return "/invite " .. name
end

local function MatchKnownKey(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local function same(key)
        return key == name or SpokenName(key) == name
    end
    if db and type(db.players) == "table" then
        for key in pairs(db.players) do
            if same(key) then
                return key
            end
        end
    end
    for key in pairs(sightings) do
        if same(key) then
            return key
        end
    end
    for key in pairs(zoneSeen) do
        if same(key) then
            return key
        end
    end
    return SafeKey(name:gsub(" ", "-"))
end

local function NoteDecline(message)
    message = PlainString(message)
    if type(message) ~= "string" then
        return
    end
    local name = message:match("^(.-) declines your group invitation%.?$")
        or message:match("^(.-) declines your invitation%.?$")
    if not name then
        return
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    local key = MatchKnownKey(name)
    if not key then
        return
    end
    inviteState[key] = "declined"
    if RefreshList then
        RefreshList()
    end
end

local function NoteGroupButtons(members)
    local nowIn = {}
    for _, key in ipairs(members) do
        nowIn[key] = true
        inviteState[key] = nil
    end
    for key in pairs(groupedBefore) do
        if not nowIn[key] and inviteState[key] ~= "declined" then
            inviteState[key] = nil
        end
    end
    wipe(groupedBefore)
    for key in pairs(nowIn) do
        groupedBefore[key] = true
    end
end

local function ApplyInvite(button, key)
    local blocked = (not key) or InMyParty(key) or IsBlocked(key) or FlaggedKos(key)
    local macro = (not blocked) and InviteMacro(key) or nil
    ApplyMacro(button, macro, true)
end

local function InviteKey(key)
    if not key or InMyParty(key) or IsBlocked(key) or FlaggedKos(key) then
        return
    end
    inviteState[key] = "invited"
    if RefreshList then
        RefreshList()
    end
end

local function PaintInvite(button)
    if not button then
        return
    end
    local state = button.key and inviteState[button.key]
    local label, br, bg, bb, fr, fg, fb, tr, tg, tb
    if state == "declined" then
        label = "Declined"
        br, bg, bb = 0.32, 0.08, 0.08
        fr, fg, fb = 1, 0.4, 0.35
        tr, tg, tb = 1, 0.75, 0.7
    elseif state == "invited" then
        label = "Invited"
        br, bg, bb = 0.08, 0.36, 0.14
        fr, fg, fb = 0.45, 1, 0.55
        tr, tg, tb = 0.85, 1, 0.88
    else
        label = "Invite"
        br, bg, bb = 0.1, 0.16, 0.1
        fr, fg, fb = 0.3, 0.7, 0.35
        tr, tg, tb = 0.55, 1, 0.62
    end
    button.label:SetText(label)
    button.label:SetTextColor(tr, tg, tb)
    button:SetBackdropColor(br, bg, bb, 1)
    button:SetBackdropBorderColor(fr, fg, fb, 1)
end

TryAutoInvite = function()
end

local function Touch(rec)
    if type(rec) == "table" then
        rec.updated = Now()
    end
end

local function ToggleKos(key)
    key = SafeKey(key)
    if not key or not db then
        return
    end
    local rec = EnsurePlayer(key)
    if rec.kos then
        rec.kos = nil
    else
        rec.kos = true
    end
    Touch(rec)
    if RefreshList then
        RefreshList()
    end
end

--------------------------------------------------
-- Marks and flags
--------------------------------------------------

local function SetColor(key, color)
    key = SafeKey(key)
    if not key then
        return
    end
    local rec = EnsurePlayer(key)
    rec.color = ValidColor(color)
    Touch(rec)
    if ShareSubject then
        ShareSubject(key)
    end
    if RefreshList then
        RefreshList()
    end
end

local function PlayerHasFlag(key, flag)
    local rec = db.players[key]
    return type(rec) == "table" and type(rec.flags) == "table" and rec.flags[flag] == true
end

local function ToggleFlag(key, flag)
    key = SafeKey(key)
    flag = SanitizeFlag(flag)
    if not key or not flag then
        return
    end
    local rec = EnsurePlayer(key)
    if rec.flags[flag] then
        rec.flags[flag] = nil
    else
        rec.flags[flag] = true
    end
    Touch(rec)
    if ShareSubject then
        ShareSubject(key)
    end
    if RefreshList then
        RefreshList()
    end
    if OpenMenu and menu and menu:IsShown() and menu.key == key then
        OpenMenu(key, true)
    end
end

local function AddCustomFlag(key, text)
    local flag = SanitizeFlag(text)
    if not flag then
        return
    end
    local seen = {}
    for _, preset in ipairs(PRESET_FLAGS) do
        seen[preset:lower()] = true
    end
    local kept = {}
    for _, existing in ipairs(db.customFlags) do
        existing = SanitizeFlag(existing)
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
    db.customFlags = kept
    local rec = EnsurePlayer(key)
    rec.flags[flag] = true
    Touch(rec)
    if ShareSubject then
        ShareSubject(key)
    end
    if OpenMenu then
        OpenMenu(key, true)
    end
end

--------------------------------------------------
-- Addon whispers. Only another Social Forever hears them.
--------------------------------------------------

local function NoteEmpty(note)
    if ValidColor(note.color) or ValidStars(note.stars) then
        return false
    end
    if type(note.flags) == "table" then
        for _, on in pairs(note.flags) do
            if on then
                return false
            end
        end
    end
    return true
end

local function Encode(subject, note, origin)
    local flags = {}
    if type(note.flags) == "table" then
        for flag, on in pairs(note.flags) do
            flag = SanitizeFlag(flag)
            if on and flag then
                flags[#flags + 1] = flag
            end
        end
    end
    table.sort(flags)
    while #flags > 8 do
        flags[#flags] = nil
    end
    local function pack(list)
        local color = COLOR_WIRE[ValidColor(note.color)] or "-"
        local stars = ValidStars(note.stars) or 0
        return string.format(
            "D\t%s\t%s\t%d\t%s\t%s",
            subject,
            color,
            stars,
            table.concat(list, ","),
            origin
        )
    end
    local msg = pack(flags)
    while #msg > 240 and #flags > 0 do
        flags[#flags] = nil
        msg = pack(flags)
    end
    if #msg > 240 then
        return nil
    end
    return msg
end

local function Enqueue(target, msg)
    if not sendReady or type(target) ~= "string" or type(msg) ~= "string" then
        return
    end
    if not CanWhisperTarget(target) then
        return
    end
    if #msg > 250 or #queue >= 80 then
        return
    end
    queue[#queue + 1] = { target = target, msg = msg }
end

local function NearbyPeerList()
    local list = {}
    for key in pairs(nearby) do
        if peers[key] then
            list[#list + 1] = key
        end
    end
    table.sort(list)
    return list
end

local function SubjectsToShare()
    local list = {}
    local seen = {}
    local function add(key)
        key = SafeKey(key)
        if not key or seen[key] or #list >= MAX_SHARE then
            return
        end
        local mine = db.players[key]
        local remote = db.remote[key]
        local anyRemote = false
        if type(remote) == "table" then
            for _, note in pairs(remote) do
                if type(note) == "table" and not NoteEmpty(note) then
                    anyRemote = true
                    break
                end
            end
        end
        local touched = type(mine) == "table" and tonumber(mine.updated)
        if HasOpinion(mine) or anyRemote or touched then
            seen[key] = true
            list[#list + 1] = key
        end
    end
    for key in pairs(nearby) do
        add(key)
    end
    local extra = {}
    for key, rec in pairs(db.players) do
        -- updated is set when a mark changes, including a clear, so a
        -- removed mark is still sent and other copies can drop it.
        if HasOpinion(rec) or tonumber(rec.updated) then
            extra[#extra + 1] = { key = key, at = tonumber(rec.updated) or 0 }
        end
    end
    table.sort(extra, function(a, b)
        return a.at > b.at
    end)
    for _, entry in ipairs(extra) do
        add(entry.key)
    end
    return list
end

local function MessagesFor(subject)
    local messages = {}
    local me = MyKey()
    local mine = db.players[subject]
    if type(mine) == "table" and me then
        local msg = Encode(subject, mine, me)
        if msg then
            messages[#messages + 1] = msg
        end
    end
    local remote = db.remote[subject]
    if type(remote) == "table" then
        local relayed = 0
        for origin, note in pairs(remote) do
            if relayed >= 2 then
                break
            end
            origin = SafeKey(origin)
            if origin and origin ~= me and type(note) == "table" and not NoteEmpty(note) then
                local msg = Encode(subject, note, origin)
                if msg then
                    messages[#messages + 1] = msg
                    relayed = relayed + 1
                end
            end
        end
    end
    return messages
end

local function PushRelevant(peer, force)
    peer = SafeKey(peer)
    if not peer then
        return
    end
    local now = GetTime()
    if not force and pushedAt[peer] and now - pushedAt[peer] < 15 then
        return
    end
    pushedAt[peer] = now
    local sent = 0
    for _, subject in ipairs(SubjectsToShare()) do
        for _, msg in ipairs(MessagesFor(subject)) do
            if sent >= 12 then
                return
            end
            Enqueue(peer, msg)
            sent = sent + 1
        end
    end
end

ShareSubject = function(key)
    local me = MyKey()
    local mine = db.players[key]
    if not me or type(mine) ~= "table" then
        return
    end
    local msg = Encode(key, mine, me)
    if not msg then
        return
    end
    for _, peer in ipairs(NearbyPeerList()) do
        Enqueue(peer, msg)
    end
end

local function CapOrigins(subject)
    local bucket = db.remote[subject]
    if type(bucket) ~= "table" then
        return
    end
    local list = {}
    for origin, note in pairs(bucket) do
        list[#list + 1] = {
            origin = origin,
            at = type(note) == "table" and tonumber(note.at) or 0,
        }
    end
    if #list <= MAX_ORIGINS then
        return
    end
    table.sort(list, function(a, b)
        return a.at < b.at
    end)
    for i = 1, #list - MAX_ORIGINS do
        bucket[list[i].origin] = nil
    end
end

local function StoreRemote(sender, msg)
    local _, subject, colorCode, stars, flagText, origin = strsplit("\t", msg)
    subject = SafeKey(subject)
    origin = SafeKey(origin) or sender
    local me = MyKey()
    if not subject or not origin or origin == me or subject == me or subject == origin then
        return
    end
    local note = {
        color = WIRE_COLOR[colorCode],
        stars = ValidStars(stars),
        flags = {},
        at = Now(),
    }
    if type(flagText) == "string" and flagText ~= "" then
        local flags = { strsplit(",", flagText) }
        local count = 0
        for _, flag in ipairs(flags) do
            flag = SanitizeFlag(flag)
            if flag then
                note.flags[flag] = true
                count = count + 1
                if count >= 8 then
                    break
                end
            end
        end
    end
    if type(db.remote[subject]) ~= "table" then
        db.remote[subject] = {}
    end
    if NoteEmpty(note) then
        db.remote[subject][origin] = nil
    else
        db.remote[subject][origin] = note
        CapOrigins(subject)
    end
    if RefreshList then
        RefreshList()
    end
end

local function OnAddon(prefix, msg, channel, sender)
    if prefix ~= PREFIX or channel ~= "WHISPER" or type(msg) ~= "string" then
        return
    end
    local name, realm = strsplit("-", sender or "", 2)
    local senderKey = MakeKey(name, realm)
    local me = MyKey()
    if not senderKey or senderKey == me then
        return
    end
    peers[senderKey] = GetTime()
    if msg == "H1" then
        local now = GetTime()
        if not helloReplyAt[senderKey] or now - helloReplyAt[senderKey] > 20 then
            helloReplyAt[senderKey] = now
            Enqueue(senderKey, "H1")
        end
        PushRelevant(senderKey, false)
        return
    end
    if msg:sub(1, 2) == "D\t" then
        StoreRemote(senderKey, msg)
    end
end

local function Pump()
    if not sendReady or #queue == 0 then
        return
    end
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
        wipe(queue)
        return
    end
    local item = table.remove(queue, 1)
    if not item or not CanWhisperTarget(item.target) or type(item.msg) ~= "string" then
        return
    end
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, "WHISPER", item.target)
end

local shareRotate = 1
local function ShareTick()
    if InCombatLockdown() or not main or not main:IsShown() then
        return
    end
    local list = NearbyPeerList()
    if #list == 0 then
        return
    end
    shareRotate = (shareRotate % #list) + 1
    PushRelevant(list[shareRotate], false)
end

--------------------------------------------------
-- Group memory. The rating window opens when the party ends.
--------------------------------------------------

local function GroupState()
    local okG, grouped = pcall(IsInGroup)
    local okR, raid = pcall(IsInRaid)
    if not okG or not okR then
        return nil
    end
    grouped = PlainBool(grouped)
    raid = PlainBool(raid)
    if grouped == nil or raid == nil then
        return nil
    end
    if raid then
        return "raid"
    end
    if grouped then
        return "party"
    end
    return "solo"
end

local function EndPartySession()
    db.partyId = nil
    db.partyCounted = nil
end

local function NoteMembers(members)
    if not db.partyId then
        db.nextPartyId = (tonumber(db.nextPartyId) or 0) + 1
        db.partyId = db.nextPartyId
        db.partyCounted = {}
    end
    if type(db.partyCounted) ~= "table" then
        db.partyCounted = {}
    end
    for _, key in ipairs(members) do
        if not db.partyCounted[key] then
            db.partyCounted[key] = true
            local rec = EnsurePlayer(key)
            rec.groups = (tonumber(rec.groups) or 0) + 1
        end
    end
    lastMembers = members
end

local function CopyMembers(members)
    local copy = {}
    for i = 1, math.min(4, #members) do
        copy[i] = members[i]
    end
    return copy
end

local function HistoryLine(key)
    local rec = db.players[key]
    local groups = type(rec) == "table" and tonumber(rec.groups) or 0
    local text
    if groups <= 0 then
        text = "First group"
    elseif groups == 1 then
        text = "Grouped once"
    else
        text = "Grouped " .. groups .. " times"
    end
    local color = type(rec) == "table" and ValidColor(rec.color)
    if color then
        text = text .. " · your mark is " .. color
    end
    return text
end

local function PlayTick()
    local kit = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
    if kit then
        pcall(PlaySound, kit)
    end
end

function U.ShowRatePopup(members)
    if not armed or not popup then
        return
    end
    local list = {}
    local seen = {}
    local me = MyKey()
    for _, key in ipairs(members) do
        key = SafeKey(key)
        if key and key ~= me and not seen[key] then
            seen[key] = true
            list[#list + 1] = key
            if #list == 4 then
                break
            end
        end
    end
    if #list == 0 then
        return
    end
    local sig = table.concat(list, "|")
    local now = GetTime()
    if sig == lastPopupSig and now - lastPopupAt < 3 then
        return
    end
    lastPopupSig = sig
    lastPopupAt = now

    popup.title:SetText(#list == 1 and "How was this player?" or "How was this group?")
    for i = 1, 4 do
        local row = popup.rows[i]
        local key = list[i]
        if key then
            row.key = key
            row.choice = nil
            row.name:SetText(SpokenName(key))
            row.sub:SetText(HistoryLine(key))
            if PaintChoice then
                PaintChoice(row)
            end
            row:Show()
        else
            row.key = nil
            row:Hide()
        end
    end
    popup:SetHeight(46 + #list * 44 + 34)
    popup:Show()
    popup:Raise()
    C_Timer.After(0, function()
        if popup:IsShown() and popup.Anchor then
            popup:Anchor()
        end
    end)
    PlayTick()
end

function U.RefreshRoster()
    if not db then
        return
    end
    local state = GroupState()
    if state == nil then
        return
    end
    if state == "party" then
        NoteGroupButtons(PartyKeys())
    elseif state == "solo" then
        NoteGroupButtons({})
    end
    if state == "party" then
        local members = PartyKeys()
        if wasParty then
            local still = {}
            for _, key in ipairs(members) do
                still[key] = true
            end
            local left = {}
            for _, key in ipairs(lastMembers) do
                if not still[key] then
                    left[#left + 1] = key
                end
            end
            if #left > 0 then
                U.ShowRatePopup(left)
            end
        end
        if #members > 0 then
            NoteMembers(members)
        end
        wasParty = true
        if RefreshList then
            RefreshList()
        end
        return
    end
    if not armed then
        return
    end
    if wasParty and state == "solo" then
        local members = CopyMembers(lastMembers)
        wasParty = false
        lastMembers = {}
        EndPartySession()
        U.ShowRatePopup(members)
    else
        wasParty = false
        lastMembers = {}
        EndPartySession()
    end
    if RefreshList then
        RefreshList()
    end
end

function U.Arm()
    armed = true
    if not wasParty then
        local state = GroupState()
        if state == "solo" or state == "raid" or state == nil then
            EndPartySession()
        end
    end
end

--------------------------------------------------
-- Window chrome
--------------------------------------------------

function U.BackgroundAlpha()
    local alpha = db and tonumber(db.bgAlpha)
    if not alpha or alpha ~= alpha then
        return 0.94
    end
    if alpha < 0.15 then
        return 0.15
    end
    if alpha > 1 then
        return 1
    end
    return alpha
end

function U.ApplyBackground()
    local alpha = U.BackgroundAlpha()
    if main then
        main:SetBackdropColor(0.04, 0.04, 0.04, alpha)
    end
    if popup then
        popup:SetBackdropColor(0.04, 0.04, 0.04, alpha)
    end
end

function U.Chrome(frame)
    frame:SetBackdrop(PANEL_BACKDROP)
    frame:SetBackdropColor(0.04, 0.04, 0.04, 0.94)
    frame:SetBackdropBorderColor(0.72, 0.58, 0.18, 0.95)
end

function U.FlatButton(parent, text, width, height, secure)
    local template = secure and "SecureActionButtonTemplate, BackdropTemplate" or "BackdropTemplate"
    local button = CreateFrame("Button", nil, parent, template)
    button:SetSize(width, height)
    button:SetBackdrop(FLAT_BACKDROP)
    button:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
    button:SetBackdropBorderColor(0.45, 0.38, 0.16, 0.95)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text)
    button.label = label
    button:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            self:SetBackdropColor(0.24, 0.20, 0.08, 0.98)
        end
    end)
    button:SetScript("OnLeave", function(self)
        if self.Paint then
            self:Paint()
            return
        end
        if self:IsEnabled() then
            self:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
            self:SetBackdropBorderColor(0.45, 0.38, 0.16, 0.95)
            self.label:SetTextColor(0.95, 0.9, 0.75)
        else
            self:SetBackdropColor(0.1, 0.1, 0.1, 0.85)
            self:SetBackdropBorderColor(0.28, 0.28, 0.28, 0.8)
            self.label:SetTextColor(0.45, 0.45, 0.45)
        end
    end)
    return button
end

function U.ClassRGB(classFile)
    classFile = PlainString(classFile)
    local colors = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not colors then
        return 0.9, 0.9, 0.9
    end
    return colors.r or 0.9, colors.g or 0.9, colors.b or 0.9
end

function U.ShowTip(owner, key)
    if not key then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local color = GeneralColor(key)
    local rgb = color and COLOR_RGB[color]
    local shown = SpokenName(key)
    if rgb then
        GameTooltip:SetText(shown, rgb[1], rgb[2], rgb[3])
    elseif FlaggedKos(key) then
        GameTooltip:SetText(shown, 1, 0.45, 0.35)
    else
        local r, g, b = SeenRGB(key)
        GameTooltip:SetText(shown, r, g, b)
    end
    if FlaggedKos(key) then
        GameTooltip:AddLine("Kill on sight", 1, 0.35, 0.3, true)
    end
    local function TimesPhrase(n)
        n = tonumber(n) or 0
        if n == 1 then
            return "1 time"
        end
        return n .. " times"
    end
    GameTooltip:AddLine("Been nearby: " .. TimesPhrase(SeenCount(key, "nearbyTimes")), 0.8, 0.86, 1, true)
    GameTooltip:AddLine("Been in the same zone: " .. TimesPhrase(SeenCount(key, "zoneTimes")), 0.8, 0.86, 1, true)
    local seen = sightings[key] or zoneSeen[key]
    if seen then
        local ago = GetTime() - (seen.at or GetTime())
        local minutes = math.floor(math.max(0, ago) / 60)
        local when
        if ago < 60 then
            when = "just now"
        elseif minutes == 1 then
            when = "1 minute ago"
        else
            when = minutes .. " minutes ago"
        end
        local area = seen.area
        if type(area) ~= "string" or area == "" then
            area = seen.zone
        end
        if type(area) ~= "string" or area == "" then
            local rec = db and db.players and db.players[key]
            area = type(rec) == "table" and rec.nearbyArea or nil
        end
        if type(area) == "string" and area ~= "" then
            if when == "just now" then
                GameTooltip:AddLine("Last seen just now in " .. area, 0.9, 0.9, 0.75, true)
            else
                GameTooltip:AddLine("Last seen " .. when .. " in " .. area, 0.9, 0.9, 0.75, true)
            end
        elseif when == "just now" then
            GameTooltip:AddLine("Last seen just now", 0.9, 0.9, 0.75, true)
        else
            GameTooltip:AddLine("Last seen " .. when, 0.9, 0.9, 0.75, true)
        end
    end
    local history = db and db.players and db.players[key]
    local places = type(history) == "table" and history.places
    if type(places) == "table" and #places > 0 then
        local names = {}
        for i = 1, #places do
            if type(places[i]) == "string" and places[i] ~= "" then
                names[#names + 1] = places[i]
            end
        end
        if #names > 0 then
            GameTooltip:AddLine("Seen before in " .. table.concat(names, ", "), 0.75, 0.85, 0.75, true)
        end
    end
    local general, good, okay, bad = Tally(key)
    if general then
        local tint = COLOR_RGB[general]
        GameTooltip:AddLine(
            "General: " .. COLOR_LABEL[general] .. string.format(" (%d good, %d okay, %d bad)", good, okay, bad),
            tint[1], tint[2], tint[3],
            true
        )
    else
        GameTooltip:AddLine("General: no mark yet", 0.7, 0.7, 0.7, true)
    end
    local mine = db.players[key]
    local myColor = type(mine) == "table" and ValidColor(mine.color)
    if myColor then
        local tint = COLOR_RGB[myColor]
        GameTooltip:AddLine("Your mark: " .. COLOR_LABEL[myColor], tint[1], tint[2], tint[3], true)
    elseif general then
        GameTooltip:AddLine("Your mark: none yet", 0.7, 0.7, 0.7, true)
    end
    local groups = type(mine) == "table" and tonumber(mine.groups) or 0
    if not groups or groups < 0 then
        groups = 0
    end
    if groups == 1 then
        GameTooltip:AddLine("Grouped together: 1 time", 0.85, 0.85, 0.85, true)
    else
        GameTooltip:AddLine("Grouped together: " .. groups .. " times", 0.85, 0.85, 0.85, true)
    end
    local flags = FlagCounts(key)
    if #flags > 0 then
        local parts = {}
        for _, entry in ipairs(flags) do
            if entry.count > 1 then
                parts[#parts + 1] = entry.flag .. " x" .. entry.count
            else
                parts[#parts + 1] = entry.flag
            end
        end
        GameTooltip:AddLine("Flags: " .. table.concat(parts, ", "), 0.75, 0.85, 1, true)
    else
        GameTooltip:AddLine("Flags: none", 0.55, 0.55, 0.55, true)
    end
    GameTooltip:Show()
end

function U.SavePosition()
    if not db then
        return
    end
    local point, _, rel, x, y = main:GetPoint(1)
    if not ANCHORS[point] or not ANCHORS[rel] then
        return
    end
    db.window = {
        point = point,
        rel = rel,
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
        w = main:GetWidth(),
        h = main:GetHeight(),
    }
end

function U.ApplySize()
    local window = db and db.window
    local w = FRAME_WIDTH
    local h = FRAME_HEIGHT
    if type(window) == "table" then
        w = tonumber(window.w) or w
        h = tonumber(window.h) or h
    end
    if w < 230 then
        w = 230
    end
    if h < 150 then
        h = 150
    end
    main:SetSize(w, h)
end

function U.PositionMain()
    main:ClearAllPoints()
    local window = db and db.window
    if type(window) == "table" and ANCHORS[window.point] and ANCHORS[window.rel] then
        main:SetPoint(window.point, UIParent, window.rel, tonumber(window.x) or 0, tonumber(window.y) or 0)
    elseif ChatFrame1 then
        main:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 30)
    else
        main:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 24, 240)
    end
    U.ApplySize()
end

function U.HideMain()
    main:Hide()
    if db then
        db.hidden = true
    end
    if menu then
        menu:Hide()
    end
    if settingsMenu then
        settingsMenu:Hide()
    end
end

function U.ShowMain()
    U.PositionMain()
    main:Show()
    if db then
        db.hidden = false
    end
    Scan()
end

function SocialForever_CompartmentClick()
    if not main then
        return
    end
    if main:IsShown() then
        U.HideMain()
    else
        U.ShowMain()
    end
end

--------------------------------------------------
-- Nearby list
--------------------------------------------------

function U.BuildMain()
    main = CreateFrame("Frame", "SocialForeverFrame", UIParent, "BackdropTemplate")
    main:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    main:SetFrameStrata("MEDIUM")
    main:SetClampedToScreen(true)
    main:SetMovable(true)
    main:SetResizable(true)
    if main.SetResizeBounds then
        main:SetResizeBounds(230, 150, 680, 900)
    end
    main:EnableMouse(true)
    U.Chrome(main)
    main:Hide()

    local drag = CreateFrame("Button", nil, main)
    drag:SetPoint("TOPLEFT", 26, -4)
    drag:SetPoint("TOPRIGHT", -48, -4)
    drag:SetHeight(20)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            return
        end
        main:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        main:StopMovingOrSizing()
        U.SavePosition()
    end)

    local title = main:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 28, -8)
    title:SetPoint("RIGHT", main, "RIGHT", -52, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText("Nearby")
    title:SetTextColor(1, 0.82, 0.25)
    main.title = title

    local settings = CreateFrame("Button", nil, main, "BackdropTemplate")
    settings:SetSize(18, 18)
    settings:SetPoint("TOPRIGHT", -26, -6)
    settings:SetBackdrop(FLAT_BACKDROP)
    settings:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
    settings:SetBackdropBorderColor(0.45, 0.38, 0.16, 0.95)
    local gear = settings:CreateTexture(nil, "ARTWORK")
    gear:SetPoint("CENTER")
    gear:SetSize(14, 14)
    gear:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    gear:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    settings:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.24, 0.20, 0.08, 0.98)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Settings", 1, 0.82, 0.25)
        GameTooltip:AddLine("Auto-invite, name size, and background.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    settings:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
    end)
    main.settings = settings

    local panel = CreateFrame("Frame", "SocialForeverSettings", UIParent, "BackdropTemplate")
    panel:SetFrameStrata("DIALOG")
    panel:SetSize(168, 228)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    U.Chrome(panel)
    settingsMenu = panel

    local function MenuRow(y, clickable)
        local button = CreateFrame("Button", nil, panel)
        button:SetSize(152, 18)
        button:SetPoint("TOPLEFT", 8, y)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", 4, 0)
        label:SetPoint("RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        button.label = label
        button:EnableMouse(clickable)
        button:SetScript("OnEnter", function(self)
            if clickable then
                self.label:SetTextColor(1, 0.95, 0.55)
            end
        end)
        return button
    end

    local head = MenuRow(-8, false)
    head.label:SetText("Settings")
    head.label:SetTextColor(1, 0.82, 0.25)
    local autoHead = MenuRow(-28, false)
    autoHead.label:SetText("Auto-invite friends")
    autoHead.label:SetTextColor(0.75, 0.68, 0.4)
    local autoOn = MenuRow(-46, true)
    local autoOff = MenuRow(-64, true)
    local sizeHead = MenuRow(-88, false)
    sizeHead.label:SetText("Name size")
    sizeHead.label:SetTextColor(0.75, 0.68, 0.4)
    local size16 = MenuRow(-106, true)
    local size18 = MenuRow(-124, true)
    local size20 = MenuRow(-142, true)
    local opacityHead = MenuRow(-166, false)
    opacityHead.label:SetText("Background")
    opacityHead.label:SetTextColor(0.75, 0.68, 0.4)
    local opacityValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    opacityValue:SetPoint("RIGHT", opacityHead, "RIGHT", -4, 0)
    opacityValue:SetTextColor(0.9, 0.9, 0.9)
    local slider = CreateFrame("Slider", nil, panel, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", 18, -188)
    slider:SetSize(132, 16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(15, 100)
    if slider.SetValueStep then
        slider:SetValueStep(1)
    end
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.28, 0.22, 0.08, 0.95)
    track:SetHeight(4)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.9, 0.75, 0.3, 1)
    thumb:SetSize(12, 16)
    slider:SetThumbTexture(thumb)
    slider:SetScript("OnMouseDown", function()
        panel.sliding = true
    end)
    slider:SetScript("OnMouseUp", function()
        panel.sliding = false
    end)
    slider:SetScript("OnValueChanged", function(self, value)
        if self.lock then
            return
        end
        value = math.floor((tonumber(value) or 94) + 0.5)
        if value < 15 then
            value = 15
        end
        if value > 100 then
            value = 100
        end
        opacityValue:SetText(value .. "%")
        if db then
            db.bgAlpha = value / 100
        end
        U.ApplyBackground()
    end)

    local function PaintChoice(button, selected, text)
        button.label:SetText((selected and "> " or "  ") .. text)
        if selected then
            button.label:SetTextColor(1, 0.82, 0.25)
        else
            button.label:SetTextColor(0.9, 0.9, 0.9)
        end
    end

    local function PaintSettingsMenu()
        local auto = FriendsAutoOn()
        local size = NameSize()
        PaintChoice(autoOn, auto, "On")
        PaintChoice(autoOff, not auto, "Off")
        PaintChoice(size16, size == 16, "16")
        PaintChoice(size18, size == 18, "18")
        PaintChoice(size20, size == 20, "20")
        local percent = math.floor(U.BackgroundAlpha() * 100 + 0.5)
        slider.lock = true
        slider:SetValue(percent)
        slider.lock = false
        opacityValue:SetText(percent .. "%")
    end

    local function LeaveChoice(button)
        button:SetScript("OnLeave", function()
            PaintSettingsMenu()
        end)
    end
    LeaveChoice(autoOn)
    LeaveChoice(autoOff)
    LeaveChoice(size16)
    LeaveChoice(size18)
    LeaveChoice(size20)

    autoOn:SetScript("OnClick", function()
        if not db then
            return
        end
        db.autoInviteFriends = true
        PaintSettingsMenu()
    end)
    autoOff:SetScript("OnClick", function()
        if not db then
            return
        end
        db.autoInviteFriends = false
        PaintSettingsMenu()
    end)
    local function PickSize(size)
        return function()
            if not db then
                return
            end
            db.nameSize = size
            PaintSettingsMenu()
            if RefreshList then
                RefreshList()
            end
        end
    end
    size16:SetScript("OnClick", PickSize(16))
    size18:SetScript("OnClick", PickSize(18))
    size20:SetScript("OnClick", PickSize(20))

    panel:SetScript("OnShow", function(self)
        self.block = true
        C_Timer.After(0.05, function()
            self.block = false
        end)
    end)
    panel:SetScript("OnUpdate", function(self)
        if self.block or not self:IsShown() then
            return
        end
        local over = self:IsMouseOver() or settings:IsMouseOver()
        if self.sliding then
            return
        end
        if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) and not over then
            self:Hide()
        end
    end)

    settings:SetScript("OnClick", function()
        if panel:IsShown() then
            panel:Hide()
            return
        end
        if menu then
            menu:Hide()
        end
        GameTooltip:Hide()
        panel:ClearAllPoints()
        panel:SetPoint("TOPRIGHT", settings, "BOTTOMRIGHT", 0, -2)
        PaintSettingsMenu()
        panel:Show()
    end)

    local close = CreateFrame("Button", nil, main)
    close:SetSize(18, 18)
    close:SetPoint("TOPLEFT", 6, -5)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    closeText:SetPoint("CENTER")
    closeText:SetText("x")
    close:SetScript("OnClick", U.HideMain)
    close:SetScript("OnEnter", function()
        closeText:SetTextColor(1, 0.4, 0.4)
        GameTooltip:SetOwner(close, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Close", 1, 0.82, 0.25)
        GameTooltip:AddLine("Type /sf or /socialforever to show the window again.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    close:SetScript("OnLeave", function()
        closeText:SetTextColor(1, 1, 1)
        GameTooltip:Hide()
    end)

    local line = main:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 10, -26)
    line:SetPoint("TOPRIGHT", -10, -26)
    line:SetHeight(1)
    line:SetColorTexture(0.6, 0.5, 0.2, 0.7)

    local list = CreateFrame("Frame", nil, main)
    list:SetPoint("TOPLEFT", 8, -30)
    list:SetPoint("BOTTOMRIGHT", -16, 18)
    list:EnableMouseWheel(true)
    main.list = list
    main.scroll = list
    main.scrollOffset = 0

    local bar = CreateFrame("Slider", nil, main, "BackdropTemplate")
    bar:SetOrientation("VERTICAL")
    bar:SetPoint("TOPRIGHT", -7, -32)
    bar:SetPoint("BOTTOMRIGHT", -7, 20)
    bar:SetWidth(8)
    bar:SetMinMaxValues(0, 1)
    if bar.SetValueStep then
        bar:SetValueStep(1)
    end
    if bar.SetObeyStepOnDrag then
        bar:SetObeyStepOnDrag(true)
    end
    bar:SetValue(0)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.75, 0.62, 0.22, 0.9)
    thumb:SetSize(8, 28)
    bar:SetThumbTexture(thumb)
    bar:SetScript("OnValueChanged", function(self, value)
        if self.lock or InCombatLockdown() then
            return
        end
        local nextOffset = math.floor((tonumber(value) or 0) + 0.5)
        if nextOffset < 0 then
            nextOffset = 0
        end
        if nextOffset ~= main.scrollOffset then
            main.scrollOffset = nextOffset
            if RefreshList then
                RefreshList()
            end
        end
    end)
    main.bar = bar

    local empty = main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -4)
    empty:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -4, 4)
    empty:SetJustifyH("CENTER")
    empty:SetJustifyV("MIDDLE")
    empty:SetTextColor(0.7, 0.7, 0.7)
    empty:SetText(EMPTY_TEXT)
    main.empty = empty

    local function VisibleSlots()
        local rowH = RowHeight()
        local view = list:GetHeight()
        if not view or view < rowH then
            return VISIBLE_ROWS
        end
        return math.max(1, math.floor((view / rowH) + 0.001))
    end

    local function ScrollBy(delta)
        if InCombatLockdown() then
            return
        end
        local maxOffset = math.max(0, (main.entryCount or 0) - VisibleSlots())
        local nextOffset = (main.scrollOffset or 0) - delta
        if nextOffset < 0 then
            nextOffset = 0
        end
        if nextOffset > maxOffset then
            nextOffset = maxOffset
        end
        if nextOffset == main.scrollOffset then
            return
        end
        main.scrollOffset = nextOffset
        if RefreshList then
            RefreshList()
        end
    end
    main.ScrollBy = ScrollBy

    list:SetScript("OnMouseWheel", function(_, delta)
        GameTooltip:Hide()
        ScrollBy(delta)
    end)

    main.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, list, "SecureActionButtonTemplate")
        row:SetSize(200, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
        row:RegisterForClicks("LeftButtonDown", "RightButtonDown")
        row:SetAttribute("useOnKeyDown", true)
        row:Hide()

        local mark = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        mark:SetPoint("LEFT", 6, 0)
        mark:SetWidth(16)
        mark:SetJustifyH("CENTER")
        row.mark = mark

        local invite = U.FlatButton(list, "Invite", 74, 18, true)
        invite.owner = row
        invite:SetPoint("LEFT", row, "RIGHT", 4, 0)
        invite:SetFrameLevel(row:GetFrameLevel() + 5)
        invite:RegisterForClicks("LeftButtonDown")
        invite:SetAttribute("useOnKeyDown", true)
        invite.Paint = PaintInvite
        invite:SetScript("PostClick", function(self)
            local key = self.key
            if not key or InCombatLockdown() or InMyParty(key) or IsBlocked(key) or FlaggedKos(key) then
                return
            end
            inviteState[key] = "invited"
            PaintInvite(self)
        end)
        invite:SetScript("OnEnter", function(self)
            local state = self.key and inviteState[self.key]
            if state == "declined" then
                self:SetBackdropColor(0.45, 0.1, 0.1, 1)
            elseif state == "invited" then
                self:SetBackdropColor(0.12, 0.5, 0.18, 1)
            else
                self:SetBackdropColor(0.14, 0.28, 0.14, 1)
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if state == "declined" then
                GameTooltip:SetText("Declined", 1, 0.45, 0.4)
            elseif state == "invited" then
                GameTooltip:SetText("Invited", 0.45, 1, 0.55)
            else
                GameTooltip:SetText("Invite", 0.35, 1, 0.45)
            end
            local macro = self.key and InviteMacro(self.key)
            if macro then
                GameTooltip:AddLine(macro, 0.75, 0.75, 0.75, true)
            end
            GameTooltip:Show()
        end)
        invite:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            PaintInvite(self)
        end)
        row.invite = invite

        local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", mark, "RIGHT", 8, 0)
        name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        row.name = name

        local highlight = row:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.06)
        highlight:Hide()
        row.highlight = highlight

        local targetBg = row:CreateTexture(nil, "BACKGROUND")
        targetBg:SetAllPoints()
        targetBg:SetColorTexture(1, 0.82, 0.25, 0.16)
        targetBg:Hide()
        row.targetBg = targetBg

        local targetEdges = {}
        local function TargetEdge(point, relative, x, y, width, height)
            local edge = row:CreateTexture(nil, "BORDER")
            edge:SetColorTexture(1, 0.82, 0.25, 0.95)
            edge:SetPoint(point, row, relative or point, x or 0, y or 0)
            if width then
                edge:SetWidth(width)
            end
            if height then
                edge:SetHeight(height)
            end
            edge:Hide()
            targetEdges[#targetEdges + 1] = edge
        end
        TargetEdge("TOPLEFT", "TOPLEFT", 0, 0, nil, 1)
        TargetEdge("BOTTOMLEFT", "BOTTOMLEFT", 0, 0, nil, 1)
        TargetEdge("TOPLEFT", "TOPLEFT", 0, 0, 1, nil)
        TargetEdge("TOPRIGHT", "TOPRIGHT", 0, 0, 1, nil)
        targetEdges[1]:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        targetEdges[2]:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        targetEdges[3]:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        targetEdges[4]:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        row.targetEdges = targetEdges

        function row:PaintTarget(on)
            if on then
                self.targetBg:Show()
                for i = 1, #self.targetEdges do
                    self.targetEdges[i]:Show()
                end
            else
                self.targetBg:Hide()
                for i = 1, #self.targetEdges do
                    self.targetEdges[i]:Hide()
                end
            end
        end

        row:SetScript("OnEnter", function(self)
            if not self.key then
                return
            end
            tipToken = tipToken + 1
            self.highlight:Show()
            U.ShowTip(self, self.key)
        end)
        row:SetScript("OnLeave", function(self)
            self.highlight:Hide()
            local token = tipToken
            C_Timer.After(0, function()
                if token ~= tipToken then
                    return
                end
                if not self:IsMouseOver() then
                    GameTooltip:Hide()
                end
            end)
        end)
        row:SetScript("PostClick", function(self, button)
            if button == "RightButton" and self.key then
                GameTooltip:Hide()
                OpenMenu(self.key)
                return
            end
            if button ~= "LeftButton" or not self.key or not sightings[self.key] then
                return
            end
            local key = self.key
            C_Timer.After(0.2, function()
                local id = UnitIdentity("target")
                if not id then
                    local existsOk, exists = pcall(UnitExists, "target")
                    if existsOk and PlainBool(exists) == true then
                        return
                    end
                end
                local function same(a, b)
                    if type(a) ~= "string" or type(b) ~= "string" then
                        return false
                    end
                    return a:gsub("[%s%-]+", ""):lower() == b:gsub("[%s%-]+", ""):lower()
                end
                if same(key, id) then
                    return
                end
                if not sightings[key] then
                    return
                end
                sightings[key] = nil
                inviteState[key] = nil
                Publish()
            end)
        end)

        main.rows[i] = row
    end

    local grip = CreateFrame("Button", nil, main)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    local gripText = grip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gripText:SetPoint("CENTER", -1, 2)
    gripText:SetText("..")
    gripText:SetTextColor(0.85, 0.7, 0.28)
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and not InCombatLockdown() then
            main:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            main:StopMovingOrSizing()
            U.SavePosition()
        end
    end)
    grip:SetScript("OnEnter", function()
        GameTooltip:SetOwner(grip, "ANCHOR_RIGHT")
        GameTooltip:SetText("Drag to resize", 1, 0.82, 0.25)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    main:SetScript("OnSizeChanged", function()
        if db and RefreshList and main.rows then
            RefreshList()
        end
    end)

    main:SetScript("OnUpdate", function()
        if not main.rows or main.fadingPaint then
            return
        end
        local now = GetTime()
        local finished = false
        for _, row in ipairs(main.rows) do
            local key = row.key
            if key and row:IsShown() and (fadeInAt[key] or fadeOutAt[key] or (moveWave and moveKeys[key])) then
                local alpha = RowFadeAlpha(key, now)
                row:SetAlpha(alpha)
                if row.invite then
                    row.invite:SetAlpha(row.invite:IsShown() and alpha or 0)
                end
                if fadeOutAt[key] and alpha <= 0 then
                    row:SetAlpha(0)
                    row:Hide()
                    if row.invite then
                        row.invite:SetAlpha(0)
                        row.invite:Hide()
                    end
                    finished = true
                end
            end
        end
        if moveWave and moveHeld and (now - moveWave) >= MOVE_HALF then
            finished = true
        elseif moveWave and (now - moveWave) >= (MOVE_HALF * 2) then
            finished = true
        end
        if finished and RefreshList then
            RefreshList()
        end
    end)
end

RowFadeAlpha = function(key, now)
    local outAt = fadeOutAt[key]
    if outAt then
        local fade = (now - outAt) / FADE_OUT_TIME
        if fade >= 1 then
            return 0
        end
        if fade < 0 then
            return 1
        end
        return 1 - fade
    end
    local inAt = fadeInAt[key]
    if inAt then
        local fade = (now - inAt) / FADE_IN_TIME
        if fade >= 1 then
            fadeInAt[key] = nil
            return 1
        end
        if fade < 0 then
            fade = 0
        end
        return fade
    end
    if moveWave and moveKeys[key] then
        local elapsed = now - moveWave
        if elapsed >= (MOVE_HALF * 2) then
            return 1
        end
        if elapsed < 0 then
            return 1
        end
        if elapsed < MOVE_HALF then
            return 1 - (0.5 * (elapsed / MOVE_HALF))
        end
        return 0.5 + (0.5 * ((elapsed - MOVE_HALF) / MOVE_HALF))
    end
    return 1
end

function U.HoldLeavingRows(ordered, now)
    local present = {}
    for i = 1, #ordered do
        local entry = ordered[i]
        if entry.key then
            present[entry.key] = true
            if fadeOutAt[entry.key] then
                fadeOutAt[entry.key] = nil
                fadeOutEntry[entry.key] = nil
                fadeInAt[entry.key] = now
            elseif not listedKeys[entry.key] then
                fadeInAt[entry.key] = now
            end
        end
    end
    for key, entry in pairs(listedKeys) do
        if not present[key] and not fadeOutAt[key] then
            fadeOutAt[key] = now
            fadeOutEntry[key] = entry
            fadeInAt[key] = nil
        end
    end
    local nextListed = {}
    for key in pairs(present) do
        for i = 1, #ordered do
            if ordered[i].key == key then
                nextListed[key] = ordered[i]
                break
            end
        end
    end
    listedKeys = nextListed

    local nearGhosts = {}
    local zoneGhosts = {}
    for key, entry in pairs(fadeOutEntry) do
        if not present[key] then
            local elapsed = now - (fadeOutAt[key] or now)
            if elapsed >= FADE_OUT_TIME then
                fadeOutAt[key] = nil
                fadeOutEntry[key] = nil
            else
                local copy = {}
                for field, value in pairs(entry) do
                    copy[field] = value
                end
                copy.fading = true
                if entry.bucket ~= nil then
                    nearGhosts[#nearGhosts + 1] = copy
                else
                    zoneGhosts[#zoneGhosts + 1] = copy
                end
            end
        end
    end
    if #nearGhosts == 0 and #zoneGhosts == 0 then
        return ordered
    end
    local merged = {}
    local placedNear = false
    for i = 1, #ordered do
        local entry = ordered[i]
        if not placedNear and entry.header then
            for g = 1, #nearGhosts do
                if #merged < MAX_ROWS then
                    merged[#merged + 1] = nearGhosts[g]
                end
            end
            placedNear = true
        end
        if #merged < MAX_ROWS then
            merged[#merged + 1] = entry
        end
    end
    if not placedNear then
        for g = 1, #nearGhosts do
            if #merged < MAX_ROWS then
                merged[#merged + 1] = nearGhosts[g]
            end
        end
    end
    for g = 1, #zoneGhosts do
        if #merged < MAX_ROWS then
            merged[#merged + 1] = zoneGhosts[g]
        end
    end
    return merged
end

RefreshList = function()
    if not main or not db or main.fadingPaint then
        return
    end
    main.fadingPaint = true
    local function SortSection(list, useYards)
        local hereZone = CurrentZone()
        local here = useYards and CurrentArea() or nil
        local now = GetTime()
        table.sort(list, function(a, b)
            local function zoneRank(entry)
                if not hereZone or not entry.zone then
                    return 1
                end
                if entry.zone == hereZone then
                    return 2
                end
                return 0
            end
            local zoneA, zoneB = zoneRank(a), zoneRank(b)
            if zoneA ~= zoneB then
                return zoneA > zoneB
            end
            if here then
                local function placeRank(entry)
                    if entry.area == here then
                        return 2
                    end
                    if not entry.area then
                        return 1
                    end
                    return 0
                end
                local placeA, placeB = placeRank(a), placeRank(b)
                if placeA ~= placeB then
                    return placeA > placeB
                end
            end
            local kosA = FlaggedKos(a.key) and 1 or 0
            local kosB = FlaggedKos(b.key) and 1 or 0
            if kosA ~= kosB then
                return kosA > kosB
            end
            local seenA, seenB = Familiarity(a.key), Familiarity(b.key)
            if seenA ~= seenB then
                return seenA > seenB
            end
            local function timeLeft(entry)
                local ttl = entry.ttl or (useYards and SEEN_TTL or ZONE_TTL)
                return ttl - (now - (entry.at or 0))
            end
            local leftA, leftB = timeLeft(a), timeLeft(b)
            if math.abs(leftA - leftB) > 0.5 then
                return leftA > leftB
            end
            if useYards then
                if a.yards and b.yards and math.abs(a.yards - b.yards) > 0.5 then
                    return a.yards < b.yards
                end
                if a.yards and not b.yards then
                    return true
                end
                if b.yards and not a.yards then
                    return false
                end
            end
            local timeA, timeB = a.at or 0, b.at or 0
            if timeA ~= timeB then
                return timeA > timeB
            end
            return a.key < b.key
        end)
    end

    local maxSeen = MaxFamiliarity()
    local nearList = {}
    for _, entry in pairs(nearby) do
        nearList[#nearList + 1] = entry
    end
    local zoneList = {}
    for _, entry in pairs(inZone) do
        zoneList[#zoneList + 1] = entry
    end
    local function KeysOf(list)
        local keys = {}
        for i = 1, #list do
            keys[i] = list[i].key
        end
        return keys
    end

    local function StableOrder(list, previous)
        local byKey = {}
        for i = 1, #list do
            byKey[list[i].key] = list[i]
        end
        local ordered = {}
        local used = {}
        for i = 1, #previous do
            local entry = byKey[previous[i]]
            if entry then
                ordered[#ordered + 1] = entry
                used[entry.key] = true
            end
        end
        for i = 1, #list do
            local entry = list[i]
            if not used[entry.key] then
                ordered[#ordered + 1] = entry
            end
        end
        return ordered
    end

    local now = GetTime()
    if now - (sortHold.at or 0) >= SORT_EVERY then
        SortSection(nearList, true)
        SortSection(zoneList, false)
        sortHold.at = now
        sortHold.near = KeysOf(nearList)
        sortHold.zone = KeysOf(zoneList)
    else
        nearList = StableOrder(nearList, sortHold.near)
        zoneList = StableOrder(zoneList, sortHold.zone)
    end

    local ordered = {}
    if #nearList == 0 and #zoneList > 0 then
        ordered[#ordered + 1] = { header = "No one nearby", dim = true }
    end
    for i = 1, #nearList do
        if #ordered >= MAX_ROWS then
            break
        end
        ordered[#ordered + 1] = nearList[i]
    end
    if #zoneList > 0 and #ordered < MAX_ROWS then
        ordered[#ordered + 1] = { header = "In this zone (" .. #zoneList .. ")" }
        for i = 1, #zoneList do
            if #ordered >= MAX_ROWS then
                break
            end
            ordered[#ordered + 1] = zoneList[i]
        end
    end
    ordered = U.HoldLeavingRows(ordered, now)

    local function CopySnap(list)
        local copy = {}
        for i = 1, #list do
            local entry = list[i]
            copy[i] = {
                key = entry.key,
                header = entry.header,
                dim = entry.dim,
                fading = entry.fading,
            }
        end
        return copy
    end

    local function Slots(list)
        local map = {}
        local n = 0
        for i = 1, #list do
            local entry = list[i]
            if not entry.fading then
                n = n + 1
                if entry.key then
                    map[entry.key] = n
                end
            end
        end
        return map
    end

    local function HeldDisplay(held, liveList)
        local byKey = {}
        for i = 1, #liveList do
            if liveList[i].key then
                byKey[liveList[i].key] = liveList[i]
            end
        end
        local out = {}
        for i = 1, #held do
            local item = held[i]
            if item.header then
                out[#out + 1] = { header = item.header, dim = item.dim }
            elseif item.key and not item.fading then
                if byKey[item.key] then
                    out[#out + 1] = byKey[item.key]
                elseif fadeOutEntry[item.key] then
                    out[#out + 1] = fadeOutEntry[item.key]
                end
            end
        end
        return out
    end

    local function HideUnshown(list)
        local showing = {}
        for i = 1, #list do
            if list[i].key then
                showing[list[i].key] = true
            end
        end
        for key in pairs(listedKeys) do
            if not showing[key] then
                listedKeys[key] = nil
                fadeInAt[key] = nil
            end
        end
    end

    if moveWave and (now - moveWave) >= (MOVE_HALF * 2) then
        moveWave = nil
        wipe(moveKeys)
        moveHeld = nil
    end
    if moveWave and moveHeld and (now - moveWave) < MOVE_HALF then
        ordered = HeldDisplay(moveHeld, ordered)
        HideUnshown(ordered)
    elseif moveWave and moveHeld then
        moveHeld = nil
    elseif not moveWave and lastShown then
        local oldSlots = Slots(lastShown)
        local newSlots = Slots(ordered)
        local keys = {}
        local changed = false
        for key, index in pairs(newSlots) do
            local prev = oldSlots[key]
            if prev and prev ~= index and not fadeOutAt[key] and not fadeInAt[key] then
                changed = true
                keys[key] = true
            end
        end
        if changed then
            moveWave = now
            moveKeys = keys
            moveHeld = CopySnap(lastShown)
            ordered = HeldDisplay(moveHeld, ordered)
            HideUnshown(ordered)
        end
    end
    lastShown = CopySnap(ordered)

    local viewWidth = main.list:GetWidth()
    if not viewWidth or viewWidth < 40 then
        viewWidth = FRAME_WIDTH - 28
    end
    local rowH = RowHeight()
    local font, fontSize, fontFlags = NameFont()
    local view = main.list:GetHeight()
    local visible = VISIBLE_ROWS
    if view and view >= rowH then
        visible = math.max(1, math.floor((view / rowH) + 0.001))
    end
    if visible > MAX_ROWS then
        visible = MAX_ROWS
    end
    main.entryCount = #ordered
    local maxOffset = math.max(0, #ordered - visible)
    local offset = main.scrollOffset or 0
    if offset > maxOffset then
        offset = maxOffset
        main.scrollOffset = offset
    end
    if offset < 0 then
        offset = 0
        main.scrollOffset = 0
    end
    local locked = InCombatLockdown()
    local targetKey = UnitIdentity("target")
    local function IsTarget(key)
        if not key or not targetKey then
            return false
        end
        if key == targetKey then
            return true
        end
        return key:gsub("[%s%-]+", ""):lower() == targetKey:gsub("[%s%-]+", ""):lower()
    end

    for i, row in ipairs(main.rows) do
        ApplyNameFont(row.name)
        pcall(row.mark.SetFont, row.mark, font, fontSize, fontFlags)
        row.mark:SetWidth(math.max(18, fontSize))
        local entry = (not locked) and ordered[offset + i] or nil
        if locked then
            if row.PaintTarget then
                row:PaintTarget(row:IsShown() and IsTarget(row.key))
            end
            -- Leave the secure buttons as they were. Moving them in combat is blocked.
        elseif i <= visible and entry and entry.header then
            row:SetHeight(rowH)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", main.list, "TOPLEFT", 0, -((i - 1) * rowH))
            row:SetWidth(viewWidth)
            row.key = nil
            row.invite.key = nil
            ApplyInvite(row.invite, nil)
            ApplyTarget(row, nil)
            row.highlight:Hide()
            row.mark:SetText("")
            row.name:SetText(entry.header)
            if entry.dim then
                row.name:SetTextColor(0.55, 0.55, 0.55)
            else
                row.name:SetTextColor(1, 0.82, 0.25)
            end
            row.invite:Hide()
            row.invite:SetAlpha(0)
            row:SetAlpha(1)
            row:PaintTarget(false)
            row:Show()
            row:SetAlpha(1)
        elseif i <= visible and entry then
            row:SetHeight(rowH)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", main.list, "TOPLEFT", 0, -((i - 1) * rowH))
            row:SetWidth(viewWidth)
            row.key = entry.key
            row.invite.key = entry.key
            ApplyInvite(row.invite, entry.key)
            ApplyTarget(row, entry.key)
            local color = GeneralColor(entry.key)
            local letter = color == "green" and "G" or color == "yellow" and "Y" or color == "red" and "R" or "-"
            if not color and FlaggedKos(entry.key) then
                letter = "K"
            end
            row.mark:SetText(letter)
            if color then
                local rgb = COLOR_RGB[color]
                row.mark:SetTextColor(rgb[1], rgb[2], rgb[3])
                row.name:SetTextColor(rgb[1], rgb[2], rgb[3])
            elseif FlaggedKos(entry.key) then
                row.mark:SetTextColor(1, 0.3, 0.25)
                row.name:SetTextColor(1, 0.45, 0.35)
            else
                local r, g, b = SeenRGB(entry.key, maxSeen)
                row.mark:SetTextColor(0.45, 0.45, 0.45)
                row.name:SetTextColor(r, g, b)
            end
            row.name:SetText(ListName(entry.key, entry.level))
            local grouped = InMyParty(entry.key)
            if grouped then
                row:SetWidth(viewWidth)
            else
                row:SetWidth(math.max(80, viewWidth - 78))
                row.invite:ClearAllPoints()
                row.invite:SetPoint("LEFT", row, "RIGHT", 4, 0)
            end
            PaintInvite(row.invite)
            local alpha = RowFadeAlpha(entry.key, GetTime())
            row:PaintTarget(IsTarget(entry.key))
            if fadeOutAt[entry.key] and alpha <= 0 then
                row:SetAlpha(0)
                row.invite:SetAlpha(0)
                row.invite:Hide()
                row:Hide()
            else
                row:SetAlpha(alpha)
                row.invite:SetAlpha(grouped and 0 or alpha)
                row:Show()
                row:SetAlpha(alpha)
                if grouped then
                    row.invite:Hide()
                    row.invite:SetAlpha(0)
                else
                    row.invite:Show()
                    row.invite:SetAlpha(alpha)
                end
            end
        else
            row.key = nil
            row.invite.key = nil
            ApplyInvite(row.invite, nil)
            ApplyTarget(row, nil)
            row.invite:SetAlpha(0)
            row.invite:Hide()
            row:SetAlpha(0)
            row:PaintTarget(false)
            row:Hide()
        end
    end

    local nearCount = 0
    for _ in pairs(nearby) do
        nearCount = nearCount + 1
    end
    local place = CurrentArea() or "Nearby"
    if nearCount == 0 and #zoneList == 0 and #ordered == 0 then
        main.title:SetText(place)
        main.empty:SetText(EMPTY_TEXT)
        main.empty:Show()
    else
        main.title:SetText(nearCount > 0 and (place .. " (" .. nearCount .. ")") or place)
        main.empty:Hide()
    end

    local maxOffset = math.max(0, #ordered - visible)
    main.bar.lock = true
    if maxOffset <= 0 then
        main.bar:Hide()
        main.bar:SetMinMaxValues(0, 1)
        main.bar:SetValue(0)
    else
        main.bar:Show()
        main.bar:SetMinMaxValues(0, maxOffset)
        main.bar:SetValue(main.scrollOffset or 0)
    end
    main.bar.lock = false

    if GameTooltip:IsShown() and main.rows then
        local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
        local ours = false
        if owner then
            for _, row in ipairs(main.rows) do
                if owner == row or owner == row.invite then
                    ours = true
                    break
                end
            end
        end
        if ours then
            local hovered = owner
            local row = owner.owner or owner
            if hovered == row.invite then
                if not hovered:IsShown() or not hovered:IsMouseOver() then
                    tipToken = tipToken + 1
                    GameTooltip:Hide()
                end
            elseif row:IsShown() and row:IsMouseOver() and row.key then
                U.ShowTip(row, row.key)
            else
                tipToken = tipToken + 1
                GameTooltip:Hide()
            end
        end
    end
    main.fadingPaint = false
end

--------------------------------------------------
-- Right-click menu
--------------------------------------------------

function U.BuildMenu()
    menu = CreateFrame("Frame", "SocialForeverMenu", UIParent, "BackdropTemplate")
    menu:SetSize(214, 120)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()
    U.Chrome(menu)
    menu.buttons = {}
    menu.used = 0

    local edit = CreateFrame("EditBox", nil, menu, "BackdropTemplate")
    edit:SetSize(132, 18)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(24)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetTextInsets(4, 4, 0, 0)
    edit:SetBackdrop(FLAT_BACKDROP)
    edit:SetBackdropColor(0, 0, 0, 0.55)
    edit:SetBackdropBorderColor(0.45, 0.38, 0.16, 0.9)
    menu.edit = edit

    local hint = edit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 5, 0)
    hint:SetText("New flag")
    edit:SetScript("OnTextChanged", function(self)
        hint:SetShown(self:GetText() == "")
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        menu:Hide()
    end)
    edit:SetScript("OnEnterPressed", function(self)
        local key = menu.key
        local text = self:GetText()
        self:SetText("")
        self:ClearFocus()
        if key then
            AddCustomFlag(key, text)
        end
    end)

    local add = U.FlatButton(menu, "Add", 46, 18)
    menu.add = add
    add:SetScript("OnClick", function()
        local key = menu.key
        local text = edit:GetText()
        edit:SetText("")
        edit:ClearFocus()
        if key then
            AddCustomFlag(key, text)
        end
    end)

    menu:SetScript("OnHide", function()
        edit:ClearFocus()
    end)
    menu:SetScript("OnShow", function(self)
        self.seenUp = false
    end)
    menu:SetScript("OnUpdate", function(self)
        if not self:IsShown() then
            return
        end
        local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
        if not self.seenUp then
            if not down then
                self.seenUp = true
            end
            return
        end
        local over = self:IsMouseOver() or self.edit:IsMouseOver() or self.add:IsMouseOver()
        if down and not over then
            self:Hide()
        end
    end)

    tinsert(UISpecialFrames, "SocialForeverMenu")
end

function U.MenuButton()
    menu.used = menu.used + 1
    local button = menu.buttons[menu.used]
    if not button then
        button = CreateFrame("Button", nil, menu)
        button:SetSize(198, 18)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", 4, 0)
        label:SetPoint("RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        button.label = label
        button:SetScript("OnEnter", function(self)
            if self.clickable then
                self.label:SetTextColor(1, 1, 0.7)
            end
        end)
        button:SetScript("OnLeave", function(self)
            if self.baseR then
                self.label:SetTextColor(self.baseR, self.baseG, self.baseB)
            end
        end)
        menu.buttons[menu.used] = button
    end
    button:Show()
    return button
end

function U.PlaceMenu(keepPlace)
    if keepPlace and menu.placed then
        return
    end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if scale and scale > 0 then
        x, y = x / scale, y / scale
    end
    local width, height = menu:GetWidth(), menu:GetHeight()
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    if x + width > screenW then
        x = screenW - width
    end
    if x < 0 then
        x = 0
    end
    if y - height < 0 then
        y = height
    end
    if y > screenH then
        y = screenH
    end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    menu.placed = true
end

OpenMenu = function(key, keepPlace)
    key = SafeKey(key)
    if not key or not menu then
        return
    end
    if settingsMenu then
        settingsMenu:Hide()
    end
    menu.key = key
    menu.used = 0
    local y = -8

    local function addLabel(text, r, g, b, onClick)
        local button = U.MenuButton()
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, y)
        button.label:SetText(text)
        button.baseR, button.baseG, button.baseB = r, g, b
        button.label:SetTextColor(r, g, b)
        button.clickable = onClick ~= nil
        button:SetScript("OnClick", onClick)
        button:EnableMouse(onClick ~= nil)
        y = y - 18
    end

    addLabel(SpokenName(key), 1, 0.82, 0.25, nil)
    y = y - 4
    addLabel("Mark", 0.85, 0.75, 0.4, nil)
    local mine = db.players[key]
    local myColor = type(mine) == "table" and ValidColor(mine.color)
    for _, color in ipairs({ "green", "yellow", "red" }) do
        local rgb = COLOR_RGB[color]
        local prefix = myColor == color and "> " or "  "
        addLabel(prefix .. COLOR_LABEL[color], rgb[1], rgb[2], rgb[3], function()
            SetColor(key, color)
            OpenMenu(key, true)
        end)
    end
    addLabel("  Clear mark", 0.6, 0.6, 0.6, function()
        SetColor(key, nil)
        OpenMenu(key, true)
    end)

    y = y - 4
    addLabel("Flags", 0.85, 0.75, 0.4, nil)
    for _, flag in ipairs(AllFlags()) do
        local on = PlayerHasFlag(key, flag)
        local prefix = on and "[x] " or "[ ] "
        addLabel(prefix .. flag, 0.75, 0.85, 1, function()
            ToggleFlag(key, flag)
        end)
    end

    y = y - 8
    menu.edit:ClearAllPoints()
    menu.edit:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, y)
    menu.add:ClearAllPoints()
    menu.add:SetPoint("LEFT", menu.edit, "RIGHT", 6, 0)
    y = y - 26

    y = y - 8
    local kos = FlaggedKos(key)
    addLabel(kos and "> Kill on sight" or "Kill on sight", 1, 0.35, 0.3, function()
        ToggleKos(key)
        OpenMenu(key, true)
    end)

    for i = menu.used + 1, #menu.buttons do
        menu.buttons[i]:Hide()
    end
    menu:SetHeight(-y + 8)
    if not keepPlace then
        menu.placed = false
    end
    menu:Show()
    U.PlaceMenu(keepPlace)
end

--------------------------------------------------
-- Rating window after the party ends
--------------------------------------------------

PaintChoice = function(row)
    local colors = { green = "Again", yellow = "Okay", red = "Bad" }
    local order = { "green", "yellow", "red" }
    for _, color in ipairs(order) do
        local button = row[color]
        local tint = COLOR_RGB[color]
        local selected = row.choice == color
        if selected then
            button:SetBackdropColor(tint[1] * 0.35, tint[2] * 0.35, tint[3] * 0.35, 0.98)
            button:SetBackdropBorderColor(tint[1], tint[2], tint[3], 1)
            button.label:SetTextColor(tint[1], tint[2], tint[3])
        else
            button:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
            button:SetBackdropBorderColor(0.45, 0.38, 0.16, 0.95)
            button.label:SetTextColor(0.9, 0.9, 0.9)
        end
        button.label:SetText(colors[color])
        button.Paint = function()
            PaintChoice(row)
        end
    end
end

function U.AllChosen()
    for _, row in ipairs(popup.rows) do
        if row:IsShown() and not row.choice then
            return false
        end
    end
    return true
end

function U.BuildPopup()
    popup = CreateFrame("Frame", "SocialForeverRateFrame", UIParent, "BackdropTemplate")
    popup:SetSize(340, 120)
    popup:SetFrameStrata("HIGH")
    popup:SetClampedToScreen(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:Hide()
    U.Chrome(popup)

    local drag = CreateFrame("Button", nil, popup)
    drag:SetPoint("TOPLEFT", 8, -4)
    drag:SetPoint("TOPRIGHT", -24, -4)
    drag:SetHeight(20)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            return
        end
        popup:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        popup:StopMovingOrSizing()
    end)

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -8)
    title:SetText("How was this group?")
    title:SetTextColor(1, 0.82, 0.25)
    popup.title = title

    local close = CreateFrame("Button", nil, popup)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -6, -5)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    closeText:SetPoint("CENTER")
    closeText:SetText("x")
    close:SetScript("OnClick", function()
        popup:Hide()
    end)

    popup.rows = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, popup)
        row:SetSize(316, 40)
        row:SetPoint("TOPLEFT", 12, -28 - ((i - 1) * 44))

        local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("TOPLEFT", 0, -1)
        name:SetPoint("RIGHT", row, "RIGHT", -188, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        row.name = name

        local sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sub:SetPoint("TOPLEFT", 0, -16)
        sub:SetPoint("RIGHT", row, "RIGHT", -188, 0)
        sub:SetJustifyH("LEFT")
        sub:SetWordWrap(false)
        sub:SetTextColor(0.65, 0.65, 0.65)
        row.sub = sub

        local x = 132
        for _, color in ipairs({ "green", "yellow", "red" }) do
            local label = color == "green" and "Again" or color == "yellow" and "Okay" or "Bad"
            local button = U.FlatButton(row, label, 56, 18)
            button:SetPoint("TOPLEFT", x, -8)
            button.color = color
            button:SetScript("OnClick", function(self)
                if not row.key then
                    return
                end
                row.choice = self.color
                SetColor(row.key, self.color)
                PaintChoice(row)
                if U.AllChosen() then
                    C_Timer.After(0.35, function()
                        if popup:IsShown() and U.AllChosen() then
                            popup:Hide()
                        end
                    end)
                end
            end)
            row[color] = button
            x = x + 60
        end
        row:Hide()
        popup.rows[i] = row
    end

    local done = U.FlatButton(popup, "Done", 64, 18)
    done:SetPoint("BOTTOM", 0, 10)
    done:SetScript("OnClick", function()
        popup:Hide()
    end)

    function popup:Anchor()
        self:ClearAllPoints()
        if main:IsShown() then
            local left = main:GetLeft() or 0
            if left > self:GetWidth() + 16 then
                self:SetPoint("TOPRIGHT", main, "TOPLEFT", -8, 0)
            else
                self:SetPoint("TOPLEFT", main, "TOPRIGHT", 8, 0)
            end
        elseif ChatFrame1 then
            self:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 30)
        else
            self:SetPoint("CENTER")
        end
    end

    tinsert(UISpecialFrames, "SocialForeverRateFrame")
end

--------------------------------------------------
-- Events
--------------------------------------------------

U.BuildMain()
U.BuildMenu()
U.BuildPopup()

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("GROUP_LEFT")
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("CHAT_MSG_SAY")
events:RegisterEvent("CHAT_MSG_EMOTE")
events:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("DUEL_REQUESTED")
events:RegisterEvent("TRADE_REQUEST")
events:RegisterEvent("TRADE_SHOW")
events:RegisterEvent("PLAYER_REGEN_ENABLED")

function U.Listen(name)
    pcall(events.RegisterEvent, events, name)
end

U.Listen("PLAYER_FOCUS_CHANGED")
U.Listen("PLAYER_SOFT_ENEMY_CHANGED")
U.Listen("PLAYER_SOFT_FRIEND_CHANGED")
U.Listen("PLAYER_SOFT_INTERACT_CHANGED")
U.Listen("CHAT_MSG_TRADESKILLS")
U.Listen("CHAT_MSG_SKILL")
U.Listen("CHAT_MSG_OPENING")
U.Listen("CHAT_MSG_PET_INFO")
U.Listen("CHAT_MSG_LOOT")
U.Listen("CHAT_MSG_COMBAT_HONOR_GAIN")
U.Listen("CHAT_MSG_COMBAT_MISC_INFO")
U.Listen("CHAT_MSG_CHANNEL")
U.Listen("FRIENDLIST_UPDATE")

events:SetScript("OnEvent", function(_, event, ...)
    local arg1, arg2, arg3, arg4 = ...
    if event == "ADDON_LOADED" and arg1 == ADDON then
        InitDB()
        return
    end
    if not db then
        return
    end
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        sendReady = true
        U.PositionMain()
        U.ApplyBackground()
        if main.settings and main.settings.Paint then
            main.settings:Paint()
        end
        if not db.hidden then
            main:Show()
        end
        if C_FriendList and C_FriendList.ShowFriends then
            pcall(C_FriendList.ShowFriends)
        end
        RefreshFriends()
        Scan()
        U.RefreshRoster()
        C_Timer.After(2, U.Arm)
        C_Timer.NewTicker(0.5, Scan)
        C_Timer.NewTicker(3, ScanCombatLog)
        C_Timer.NewTicker(0.25, Pump)
        C_Timer.NewTicker(45, ShareTick)
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        armed = false
        ClearSightings()
        nearby = {}
        RefreshList()
        U.RefreshRoster()
        C_Timer.After(2, U.Arm)
        return
    end
    if event == "CHAT_MSG_CHANNEL" then
        NoteZone(arg2, arg4, select(9, ...), select(12, ...))
        return
    end
    if event == "CHAT_MSG_SAY" or event == "CHAT_MSG_EMOTE" or event == "CHAT_MSG_TEXT_EMOTE" then
        NoteChat(arg2, select(12, ...))
        return
    end
    if event == "CHAT_MSG_TRADESKILLS" or event == "CHAT_MSG_SKILL" then
        NoteActivity(arg1, arg2, true)
        return
    end
    if event == "CHAT_MSG_OPENING"
        or event == "CHAT_MSG_LOOT"
        or event == "CHAT_MSG_COMBAT_HONOR_GAIN"
    then
        NoteActivity(arg1, arg2, false)
        return
    end
    if event == "CHAT_MSG_PET_INFO" or event == "CHAT_MSG_COMBAT_MISC_INFO" then
        NoteActivity(arg1, nil, false)
        return
    end
    if event == "FRIENDLIST_UPDATE" then
        RefreshFriends()
        Publish()
        return
    end
    if event == "DUEL_REQUESTED" or event == "TRADE_REQUEST" then
        NoteNamed(arg1, 1, CHAT_TTL)
        return
    end
    if event == "UPDATE_MOUSEOVER_UNIT"
        or event == "PLAYER_TARGET_CHANGED"
        or event == "PLAYER_FOCUS_CHANGED"
        or event == "PLAYER_SOFT_ENEMY_CHANGED"
        or event == "PLAYER_SOFT_FRIEND_CHANGED"
        or event == "PLAYER_SOFT_INTERACT_CHANGED"
        or event == "TRADE_SHOW"
    then
        Scan()
        return
    end
    if event == "GROUP_ROSTER_UPDATE" or event == "GROUP_LEFT" then
        U.RefreshRoster()
        return
    end
    if event == "CHAT_MSG_SYSTEM" then
        NoteDecline(arg1)
        return
    end
    if event == "CHAT_MSG_ADDON" then
        OnAddon(arg1, arg2, arg3, arg4)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        Scan()
    end
end)

SLASH_SOCIALFOREVER1 = "/sf"
SLASH_SOCIALFOREVER2 = "/socialforever"
SlashCmdList.SOCIALFOREVER = function(msg)
    msg = Trim(msg):lower()
    if msg == "hide" then
        U.HideMain()
    elseif msg == "show" then
        U.ShowMain()
    elseif main:IsShown() then
        U.HideMain()
    else
        U.ShowMain()
    end
end
