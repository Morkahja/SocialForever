-- Social Forever
-- Nearby players for questing groups, and a memory of who you liked grouping with.
-- Built for World of Warcraft: Forever 1.60.1 (Interface 16001).

SocialForever = SocialForever or {}
local SF = SocialForever

SF.Const = SF.Const or {}
SF.State = SF.State or {}
SF.Util = SF.Util or {}
SF.Memory = SF.Memory or {}
SF.Group = SF.Group or {}
SF.Detection = SF.Detection or {}
SF.Sharing = SF.Sharing or {}
SF.UI = SF.UI or {}
SF.Events = SF.Events or {}

local C = SF.Const
local S = SF.State
local Util = SF.Util

C.ADDON = "SocialForever"
C.PREFIX = "SocialForever"
C.VISIBLE_ROWS = 5
C.ROW_HEIGHT = 24
-- How many player rows the list can hold (Nearby or Zone tab). Zone still
-- harvests up to 200 from General, then keeps the best 100 after sorting.
C.MAX_ROWS = 100
C.ZONE_LIST_PLUS = 100
C.FRAME_WIDTH = 280
C.FRAME_HEIGHT = 220
C.MAX_YARDS = 50
C.SEEN_TTL = 180
C.SORT_EVERY = 3
C.ZONE_TTL = 600
-- After a zone change, keep other-zone names at least this long before purging.
C.ZONE_PURGE_DELAY = 30
-- After a subzone/area change outdoors, keep prior-area names at least this long.
C.AREA_PURGE_DELAY = 15
C.CHAT_TTL = C.SEEN_TTL
C.UNIT_TTL = C.SEEN_TTL
C.EMPTY_NEARBY = "No one nearby"
C.EMPTY_ZONE = "No one else listed in this zone yet."
C.EMPTY_TEXT = C.EMPTY_NEARBY
C.MAX_ORIGINS = 12
C.MAX_SHARE = 8
C.HELLO_GAP = 300
C.SAME_MOB_COOLDOWN = 300
C.SAME_MOB_NEARBY_GRACE = 60

C.PRESET_FLAGS = {
    "Really friendly",
    "Generous",
    "Weird",
    "Bad behavior",
}

C.COLOR_SCORE = { green = 1, yellow = 0, red = -1 }
C.COLOR_RGB = {
    green = { 0.35, 1, 0.45 },
    yellow = { 1, 0.86, 0.25 },
    red = { 1, 0.35, 0.30 },
}
-- Other-faction names: muted war / dusty red, not the bright mark-red.
C.ENEMY_FACTION_RGB = { 0.68, 0.38, 0.32 }
C.COLOR_LABEL = {
    green = "Green - group again",
    yellow = "Yellow - neutral",
    red = "Red - unpleasant",
}
C.WIRE_COLOR = { G = "green", Y = "yellow", R = "red" }
C.COLOR_WIRE = { green = "G", yellow = "Y", red = "R" }

C.ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

C.PANEL_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

C.FLAT_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

C.FADE_IN_TIME = 0.4
C.FADE_OUT_TIME = 3
C.MOVE_HALF = 0.8

S.nearby = {}
S.inZone = {}
S.peers = {}
S.lastMembers = {}
S.wasParty = false
S.armed = false
S.queue = {}
S.sendReady = false
S.helloAt = {}
S.helloReplyAt = {}
S.pushedAt = {}
S.lastPopupSig = ""
S.lastPopupAt = 0
S.tipToken = 0
S.sightings = {}
S.zoneSeen = {}
S.zoneRoster = {}
S.inviteState = {}
S.groupedBefore = {}
S.sortHold = { at = 0, near = {}, zone = {} }
S.listedKeys = {}
S.fadeInAt = {}
S.fadeOutAt = {}
S.fadeOutEntry = {}
S.moveWave = nil
S.moveKeys = {}
S.moveHeld = nil
S.lastShown = nil
S.trackedZone = nil
S.zonePurgeAt = nil
S.trackedArea = nil
S.areaPurgeAt = nil
S.friendNames = {}
S.combatLogSeen = 0
S.main = nil
S.popup = nil
S.menu = nil
S.settingsMenu = nil
S.listFrozen = false
S.listDirty = false
S.pinnedNearKey = nil
S.displayOrdered = nil
S.displayNearCount = 0
S.displayZoneCount = 0
S.listTab = "nearby"
S.sameMobInviteAt = {}
S.sameMobQueue = {}
S.sameMobPopup = nil
-- Plumbing state bundled to stay under the chunk local limit.
S.P = {
    publishSig = nil,
    maxFamiliarity = nil,
    groupByKey = {},
    groupByNorm = {},
    raidTicker = nil,
    combatGen = 0,
    harvestedGen = nil,
    meterPending = false,
    rosterPending = false,
    zoneRosterFull = false,
    shareRotate = 1,
    nameplateByUnit = {},
    staleTrackable = 18,
    staleInteraction = 25,
    sameMobApiInvite = nil,
    sameMobStamp = nil,
}

C.LOOK_UNITS = {
    "mouseover",
    "target",
    "focus",
    "softfriend",
    "softenemy",
    "softinteract",
    "targettarget",
    "mouseovertarget",
    "focustarget",
    "softfriendtarget",
    "softenemytarget",
    "softinteracttarget",
    "pettarget",
    "party1target",
    "party2target",
    "party3target",
    "party4target",
    "npc",
}

C.SKIP_WORDS = {
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

C.MOB_UNITS = {
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

C.SEEN_RGB = {
    white = { 0.95, 0.95, 0.95 },
    blue = { 0.45, 0.7, 1 },
    purple = { 0.76, 0.45, 1 },
}

C.CITY_ZONES = {
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

-- Skyborne pick Alliance or Horde at creation, so they are not listed here.
C.FACTION_BY_RACE = {
    Human = "Alliance",
    Dwarf = "Alliance",
    NightElf = "Alliance",
    Gnome = "Alliance",
    Draenei = "Alliance",
    Orc = "Horde",
    Troll = "Horde",
    Tauren = "Horde",
    Scourge = "Horde",
    BloodElf = "Horde",
}

C.CRAFT_VERBS = {
    creates = true,
    create = true,
    created = true,
    performs = true,
    perform = true,
    performed = true,
}

-- One portrait per race+class when known; otherwise the race face.
-- Skyborne use flight / air-themed icons (no stock race portrait yet).
C.RACE_ICONS = {
    Human = "Interface\\Icons\\Achievement_Character_Human_Male",
    Dwarf = "Interface\\Icons\\Achievement_Character_Dwarf_Male",
    NightElf = "Interface\\Icons\\Achievement_Character_Nightelf_Male",
    Gnome = "Interface\\Icons\\Achievement_Character_Gnome_Male",
    Draenei = "Interface\\Icons\\Achievement_Character_Draenei_Male",
    Orc = "Interface\\Icons\\Achievement_Character_Orc_Male",
    Troll = "Interface\\Icons\\Achievement_Character_Troll_Male",
    Tauren = "Interface\\Icons\\Achievement_Character_Tauren_Male",
    Scourge = "Interface\\Icons\\Achievement_Character_Undead_Male",
    Undead = "Interface\\Icons\\Achievement_Character_Undead_Male",
    BloodElf = "Interface\\Icons\\Achievement_Character_Bloodelf_Male",
    Skyborne = "Interface\\Icons\\Ability_Druid_FlightForm",
    Skyborn = "Interface\\Icons\\Ability_Druid_FlightForm",
}

-- Race+class overrides when a clearer combo icon exists.
C.RACE_CLASS_ICONS = {
    Human = {
        WARRIOR = "Interface\\Icons\\Achievement_Character_Human_Male",
        PALADIN = "Interface\\Icons\\Spell_Holy_AvengineWrath",
        HUNTER = "Interface\\Icons\\Ability_Hunter_SniperShot",
        ROGUE = "Interface\\Icons\\Ability_Stealth",
        PRIEST = "Interface\\Icons\\Spell_Holy_DivineSpirit",
        MAGE = "Interface\\Icons\\Spell_Holy_MagicalSentry",
        WARLOCK = "Interface\\Icons\\Spell_Shadow_SummonImp",
        DEATHKNIGHT = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
    },
    Dwarf = {
        WARRIOR = "Interface\\Icons\\Achievement_Character_Dwarf_Male",
        PALADIN = "Interface\\Icons\\Spell_Holy_SealOfMight",
        HUNTER = "Interface\\Icons\\Ability_Hunter_RunningShot",
        ROGUE = "Interface\\Icons\\Ability_Rogue_Disguise",
        PRIEST = "Interface\\Icons\\Spell_Holy_WordFortitude",
        MAGE = "Interface\\Icons\\Spell_Frost_IceStorm",
        WARLOCK = "Interface\\Icons\\Spell_Shadow_CurseOfTounges",
        DEATHKNIGHT = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
    },
    NightElf = {
        WARRIOR = "Interface\\Icons\\Achievement_Character_Nightelf_Male",
        HUNTER = "Interface\\Icons\\Ability_Hunter_Pet_Owl",
        ROGUE = "Interface\\Icons\\Ability_Druid_SupriseAttack",
        PRIEST = "Interface\\Icons\\Spell_Nature_Moonglow",
        MAGE = "Interface\\Icons\\Spell_Arcane_Blink",
        DRUID = "Interface\\Icons\\Ability_Racial_ShadowMeld",
        DEATHKNIGHT = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
    },
    Gnome = {
        WARRIOR = "Interface\\Icons\\Achievement_Character_Gnome_Male",
        ROGUE = "Interface\\Icons\\Ability_Rogue_FleetFooted",
        MAGE = "Interface\\Icons\\Spell_Arcane_MindMastery",
        WARLOCK = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
        DEATHKNIGHT = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
    },
    Draenei = {
        WARRIOR = "Interface\\Icons\\Achievement_Character_Draenei_Male",
        PALADIN = "Interface\\Icons\\Spell_Holy_HolyGuidance",
        HUNTER = "Interface\\Icons\\Ability_Hunter_Pet_WarpStalker",
        PRIEST = "Interface\\Icons\\Spell_Holy_HolyProtection",
        MAGE = "Interface\\Icons\\Spell_Arcane_PortalShattrath",
        SHAMAN = "Interface\\Icons\\Spell_Nature_BloodLust",
        DEATHKNIGHT = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
    },
    Orc = {
        WARRIOR = "Interface\\Icons\\Achievement_Character_Orc_Male",
        HUNTER = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
        ROGUE = "Interface\\Icons\\Ability_Rogue_BladeFlurry",
        SHAMAN = "Interface\\Icons\\Spell_Nature_BloodLust",
        MAGE = "Interface\\Icons\\Spell_Fire_Fireball02",
        WARLOCK = "Interface\\Icons\\Spell_Shadow_SummonFelHunter",
        DEATHKNIGHT = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
    },
    Troll = {
        WARRIOR = "Interface\\Icons\\Achievement_Character_Troll_Male",
        HUNTER = "Interface\\Icons\\Ability_Hunter_Pet_Raptor",
        ROGUE = "Interface\\Icons\\Ability_Rogue_DualWeild",
        PRIEST = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
        SHAMAN = "Interface\\Icons\\Spell_Nature_Lightning",
        MAGE = "Interface\\Icons\\Spell_Fire_Fireball",
        WARLOCK = "Interface\\Icons\\Spell_Shadow_CurseOfMannoroth",
        DRUID = "Interface\\Icons\\Ability_Druid_CatForm",
        DEATHKNIGHT = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
    },
    Tauren = {
        WARRIOR = "Interface\\Icons\\Achievement_Character_Tauren_Male",
        HUNTER = "Interface\\Icons\\Ability_Hunter_Pet_TallStrider",
        SHAMAN = "Interface\\Icons\\Spell_Nature_EarthBindTotem",
        DRUID = "Interface\\Icons\\Ability_Racial_BearForm",
        DEATHKNIGHT = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
        PALADIN = "Interface\\Icons\\Spell_Holy_SealOfMight",
        PRIEST = "Interface\\Icons\\Spell_Holy_WordFortitude",
        MAGE = "Interface\\Icons\\Spell_Arcane_Blast",
    },
    Scourge = {
        WARRIOR = "Interface\\Icons\\Achievement_Character_Undead_Male",
        HUNTER = "Interface\\Icons\\Spell_Shadow_Twilight",
        ROGUE = "Interface\\Icons\\Ability_Stealth",
        PRIEST = "Interface\\Icons\\Spell_Shadow_Shadowform",
        MAGE = "Interface\\Icons\\Spell_Frost_FrostBolt02",
        WARLOCK = "Interface\\Icons\\Spell_Shadow_DeathCoil",
        DEATHKNIGHT = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
    },
    BloodElf = {
        WARRIOR = "Interface\\Icons\\Achievement_Character_Bloodelf_Male",
        PALADIN = "Interface\\Icons\\Spell_Holy_WeaponMastery",
        HUNTER = "Interface\\Icons\\Ability_Hunter_Pet_DragonHawk",
        ROGUE = "Interface\\Icons\\Ability_Rogue_ShadowStrikes",
        PRIEST = "Interface\\Icons\\Spell_Holy_PowerWordShield",
        MAGE = "Interface\\Icons\\Spell_Arcane_ArcaneTorrent",
        WARLOCK = "Interface\\Icons\\Spell_Shadow_SummonVoidWalker",
        DEATHKNIGHT = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
    },
    Skyborne = {
        WARRIOR = "Interface\\Icons\\Ability_Warrior_Charge",
        HUNTER = "Interface\\Icons\\Ability_Hunter_Pet_DragonHawk",
        ROGUE = "Interface\\Icons\\Ability_Rogue_Sprint",
        MAGE = "Interface\\Icons\\Spell_Arcane_TeleportDarnassus",
        SHAMAN = "Interface\\Icons\\Spell_Nature_Cyclone",
        DRUID = "Interface\\Icons\\Ability_Druid_FlightForm",
        PRIEST = "Interface\\Icons\\Spell_Holy_HolyBolt",
        WARLOCK = "Interface\\Icons\\Spell_Shadow_SoulLeech_3",
        DEATHKNIGHT = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
        PALADIN = "Interface\\Icons\\Spell_Holy_AvengineWrath",
    },
}

C.CLASS_ICONS = {
    WARRIOR = "Interface\\Icons\\ClassIcon_Warrior",
    PALADIN = "Interface\\Icons\\ClassIcon_Paladin",
    HUNTER = "Interface\\Icons\\ClassIcon_Hunter",
    ROGUE = "Interface\\Icons\\ClassIcon_Rogue",
    PRIEST = "Interface\\Icons\\ClassIcon_Priest",
    DEATHKNIGHT = "Interface\\Icons\\ClassIcon_DeathKnight",
    SHAMAN = "Interface\\Icons\\ClassIcon_Shaman",
    MAGE = "Interface\\Icons\\ClassIcon_Mage",
    WARLOCK = "Interface\\Icons\\ClassIcon_Warlock",
    DRUID = "Interface\\Icons\\ClassIcon_Druid",
}

C.RACE_CLASS_ICONS.Undead = C.RACE_CLASS_ICONS.Scourge
C.RACE_CLASS_ICONS.Skyborn = C.RACE_CLASS_ICONS.Skyborne

--------------------------------------------------
-- Values the client may seal in combat
--------------------------------------------------

function Util.Secret(value)
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

function Util.PlainString(value)
    if type(value) ~= "string" or Util.Secret(value) then
        return nil
    end
    if value == "" then
        return nil
    end
    return value
end

function Util.PlainBool(value)
    if type(value) ~= "boolean" or Util.Secret(value) then
        return nil
    end
    return value
end

function Util.PlainNumber(value)
    if type(value) ~= "number" or Util.Secret(value) then
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

function Util.Now()
    if type(GetServerTime) == "function" then
        return GetServerTime()
    end
    return time()
end

function Util.Trim(text)
    if type(text) ~= "string" then
        return ""
    end
    if strtrim then
        return strtrim(text)
    end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.NormRealm(realm)
    realm = Util.PlainString(realm)
    if not realm then
        return nil
    end
    realm = realm:gsub("%s+", "")
    if realm == "" then
        return nil
    end
    return realm
end

function Util.MyRealm()
    if type(GetNormalizedRealmName) == "function" then
        local realm = Util.NormRealm(GetNormalizedRealmName())
        if realm then
            return realm
        end
    end
    return Util.NormRealm(GetRealmName())
end

function Util.MakeKey(name, realm)
    name = Util.PlainString(name)
    if not name then
        return nil
    end
    -- Forever two-word names arrive with a space or a hyphen. One form only.
    name = name:gsub("%s+", "-")
    if #name < 2 or #name > 24 then
        return nil
    end
    if name:find("[%c|%%%[%]]") then
        return nil
    end
    local theirs = Util.NormRealm(realm)
    local mine = Util.MyRealm()
    if theirs and mine and theirs:lower() ~= mine:lower() then
        return name .. "-" .. theirs
    end
    return name
end

function Util.SafeKey(key)
    if type(key) ~= "string" then
        return nil
    end
    key = key:gsub("%s+", "-")
    if #key < 2 or #key > 50 then
        return nil
    end
    if key:find("[%c|%%%[%]]") then
        return nil
    end
    return key
end

function Util.SameKey(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then
        return false
    end
    return a:gsub("[%s%-]+", ""):lower() == b:gsub("[%s%-]+", ""):lower()
end

function Util.MyKey()
    local ok, name, realm = pcall(UnitName, "player")
    if not ok then
        return nil
    end
    return Util.MakeKey(name, realm)
end

function Util.IsMe(key)
    return Util.SameKey(key, Util.MyKey())
end

function Util.ValidColor(color)
    if color == "green" or color == "yellow" or color == "red" then
        return color
    end
    return nil
end

function Util.ValidStars(stars)
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

function Util.NameSize()
    local size = SF.db and tonumber(SF.db.nameSize)
    if size == 18 or size == 20 then
        return size
    end
    return 16
end

function Util.RowHeight()
    return Util.NameSize() + 8
end

function Util.NameFont()
    local font, _, flags = GameFontHighlight:GetFont()
    if type(font) ~= "string" or font == "" then
        font = "Fonts\\FRIZQT__.TTF"
    end
    return font, Util.NameSize(), flags or ""
end

-- SetFont keeps only the Latin face. Chinese names then draw as empty boxes.
function Util.ApplyNameFont(fontString)
    if not fontString or not fontString.SetFontObject then
        return
    end
    fontString:SetFontObject(GameFontHighlight)
    local size = Util.NameSize()
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

function Util.InitDB()
    if type(SocialForeverDB) ~= "table" then
        SocialForeverDB = {}
    end
    SF.db = SocialForeverDB
    local db = SF.db
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
    if db.listTab ~= "nearby" and db.listTab ~= "zone" then
        db.listTab = "nearby"
    end
    S.listTab = db.listTab
    if db.sameMobAsk ~= true then
        db.sameMobAsk = false
    end
    if db.sameMobAutoInvite ~= true then
        db.sameMobAutoInvite = false
    end
    if db.sameMobAsk and db.sameMobAutoInvite then
        db.sameMobAutoInvite = false
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
                local rec = SF.Memory.EnsurePlayer(key)
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
    SF.Memory.InvalidateMaxFamiliarity()
end

function Util.DistanceYards(unit)
    if type(UnitDistanceSquared) ~= "function" then
        return nil
    end
    local ok, distSq, checked = pcall(UnitDistanceSquared, unit)
    if not ok or Util.PlainBool(checked) ~= true then
        return nil
    end
    local sq = Util.PlainNumber(distSq)
    if not sq or sq < 0 then
        return nil
    end
    return math.sqrt(sq)
end

function Util.Interact(unit, index)
    if type(CheckInteractDistance) ~= "function" then
        return nil
    end
    local ok, value = pcall(CheckInteractDistance, unit, index)
    if not ok then
        return nil
    end
    return Util.PlainBool(value)
end

function Util.UnitIdentity(unit)
    local ok, name, realm = pcall(UnitName, unit)
    if not ok then
        return nil
    end
    local key = Util.MakeKey(name, realm)
    if not key then
        return nil
    end
    local classFile
    local classOk, _, file = pcall(UnitClass, unit)
    if classOk then
        classFile = Util.PlainString(file)
    end
    local raceFile
    local raceOk, _, raceToken = pcall(UnitRace, unit)
    if raceOk then
        raceFile = Util.PlainString(raceToken)
    end
    local faction
    if type(UnitFactionGroup) == "function" then
        local factionOk, factionToken = pcall(UnitFactionGroup, unit)
        if factionOk then
            faction = Util.PlainString(factionToken)
            if faction ~= "Alliance" and faction ~= "Horde" then
                faction = nil
            end
        end
    end
    return key, classFile, raceFile, faction
end

function Util.NormRaceFile(raceFile)
    raceFile = Util.PlainString(raceFile)
    if not raceFile then
        return nil
    end
    if raceFile == "Undead" then
        return "Scourge"
    end
    if raceFile == "Skyborn" then
        return "Skyborne"
    end
    return raceFile
end

function Util.NormClassFile(classFile)
    classFile = Util.PlainString(classFile)
    if not classFile then
        return nil
    end
    return classFile:upper()
end

function Util.IdentityIcon(raceFile, classFile)
    raceFile = Util.NormRaceFile(raceFile)
    classFile = Util.NormClassFile(classFile)
    if raceFile and classFile then
        local byRace = C.RACE_CLASS_ICONS[raceFile]
        if byRace and byRace[classFile] then
            return byRace[classFile]
        end
    end
    if raceFile and C.RACE_ICONS[raceFile] then
        return C.RACE_ICONS[raceFile]
    end
    if classFile and C.CLASS_ICONS[classFile] then
        return C.CLASS_ICONS[classFile]
    end
    return nil
end

function Util.NormFaction(faction)
    faction = Util.PlainString(faction)
    if faction == "Alliance" or faction == "Horde" then
        return faction
    end
    return nil
end

function Util.MyFaction()
    if type(UnitFactionGroup) ~= "function" then
        return nil
    end
    local ok, faction = pcall(UnitFactionGroup, "player")
    if not ok then
        return nil
    end
    return Util.NormFaction(faction)
end

function Util.FactionOf(key, entry)
    local faction = entry and Util.NormFaction(entry.faction) or nil
    if not faction and entry then
        local raceFile = Util.NormRaceFile(entry.race)
        faction = raceFile and C.FACTION_BY_RACE[raceFile] or nil
    end
    if not faction and key then
        local seen = S.sightings[key] or S.zoneSeen[key] or (S.inZone and S.inZone[key])
        if type(seen) == "table" then
            faction = Util.NormFaction(seen.faction)
            if not faction then
                local raceFile = Util.NormRaceFile(seen.race)
                faction = raceFile and C.FACTION_BY_RACE[raceFile] or nil
            end
        end
    end
    if not faction and key then
        local rec = SF.db and SF.db.players and SF.db.players[key]
        if type(rec) == "table" then
            faction = Util.NormFaction(rec.faction)
            if not faction then
                local raceFile = Util.NormRaceFile(rec.race)
                faction = raceFile and C.FACTION_BY_RACE[raceFile] or nil
            end
        end
    end
    return faction
end

function Util.IsOtherFaction(key, entry)
    local mine = Util.MyFaction()
    local theirs = Util.FactionOf(key, entry)
    return mine ~= nil and theirs ~= nil and mine ~= theirs
end
