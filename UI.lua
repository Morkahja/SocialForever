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

function UI.SpokenName(key)
    if type(key) ~= "string" then
        return key
    end
    return (key:gsub("-", " "))
end

function UI.ListName(key)
    return UI.SpokenName(key) or ""
end

function UI.EntryIdentity(entry)
    if not entry or not entry.key then
        return nil, nil, nil, nil
    end
    local classFile = Util.PlainString(entry.class)
    local raceFile = Util.NormRaceFile(entry.race)
    local faction = Util.NormFaction(entry.faction)
    local level = tonumber(entry.level)
    local rec = SF.db and SF.db.players and SF.db.players[entry.key]
    if type(rec) == "table" then
        if not classFile then
            classFile = Util.PlainString(rec.class)
        end
        if not raceFile then
            raceFile = Util.NormRaceFile(rec.race)
        end
        if not faction then
            faction = Util.NormFaction(rec.faction)
        end
        if not level or level < 1 then
            level = tonumber(rec.level)
        end
    end
    if not faction and raceFile then
        faction = C.FACTION_BY_RACE[raceFile]
    end
    if level and (level < 1 or level > 80) then
        level = nil
    end
    if level then
        level = math.floor(level)
    end
    return classFile, raceFile, level, faction
end

function UI.PaintRowIdentity(row, entry)
    if not row then
        return
    end
    if not entry or entry.header or not entry.key then
        if row.identity then
            row.identity:Hide()
        end
        if row.levelText then
            row.levelText:SetText("")
            row.levelText:Hide()
        end
        if row.name then
            row.name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        end
        return
    end
    local classFile, raceFile, level = UI.EntryIdentity(entry)
    local icon = Util.IdentityIcon(raceFile, classFile)
    local cr, cg, cb = UI.ClassRGB(classFile)
    local showLevel = level ~= nil
    local showIcon = icon ~= nil

    if row.levelText then
        if showLevel then
            row.levelText:SetText(tostring(level))
            if classFile then
                row.levelText:SetTextColor(cr, cg, cb)
            else
                row.levelText:SetTextColor(0.85, 0.85, 0.85)
            end
            row.levelText:Show()
        else
            row.levelText:SetText("")
            row.levelText:Hide()
        end
    end

    if row.identity then
        row.identity:ClearAllPoints()
        if showIcon then
            row.identity:SetTexture(icon)
            row.identity:SetVertexColor(1, 1, 1)
            if showLevel and row.levelText then
                row.identity:SetPoint("RIGHT", row.levelText, "LEFT", -4, 0)
            else
                row.identity:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            end
            row.identity:Show()
        else
            row.identity:Hide()
        end
    end

    if row.name then
        if showIcon and row.identity then
            row.name:SetPoint("RIGHT", row.identity, "LEFT", -4, 0)
        elseif showLevel and row.levelText then
            row.name:SetPoint("RIGHT", row.levelText, "LEFT", -4, 0)
        else
            row.name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        end
    end
end

function UI.TargetMacro(key)
    local spoken = UI.SpokenName(key)
    if type(spoken) ~= "string" then
        return nil
    end
    local first = spoken:match("^(%S+)")
    if not first or first == "" then
        return nil
    end
    return "/target " .. first
end

function UI.ApplyMacro(button, macro, anyClick)
    if not button or InCombatLockdown() then
        return false
    end
    macro = macro or ""
    local stamp = macro .. (anyClick and ":any" or ":left")
    if button.lastMacro == stamp then
        return true
    end
    button.lastMacro = stamp
    button:SetAttribute("*type1", nil)
    button:SetAttribute("*macrotext1", nil)
    button:SetAttribute("type", nil)
    button:SetAttribute("macrotext", nil)
    button:SetAttribute("type1", nil)
    button:SetAttribute("macrotext1", nil)
    if macro == "" then
        return true
    end
    button:SetAttribute("type1", "macro")
    button:SetAttribute("macrotext1", macro)
    if anyClick then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", macro)
    end
    return true
end

function UI.ApplyTarget(row, key)
    if UI.ApplyMacro(row, UI.TargetMacro(key), false) then
        row.secureKey = key
    end
end

-- Blocks secure target/invite clicks when the visible name no longer matches
-- the macros (common for new rows that appear during combat).
function UI.EnsureCombatShield(row)
    if not row then
        return nil
    end
    if row.combatShield then
        return row.combatShield
    end
    local shield = CreateFrame("Button", nil, row)
    shield:SetAllPoints(row)
    shield:SetFrameLevel((row:GetFrameLevel() or 1) + 25)
    shield:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    shield:Hide()
    shield:SetScript("OnEnter", function(self)
        local owner = self:GetParent()
        UI.NoteListEnter()
        if not owner or not owner.key then
            return
        end
        S.tipToken = S.tipToken + 1
        if owner.highlight then
            owner.highlight:Show()
        end
        UI.ShowTip(owner, owner.key)
    end)
    shield:SetScript("OnLeave", function(self)
        local owner = self:GetParent()
        if owner and owner.highlight then
            owner.highlight:Hide()
        end
        UI.NoteListLeave()
        local token = S.tipToken
        C_Timer.After(0, function()
            if token ~= S.tipToken then
                return
            end
            if owner and not owner:IsMouseOver() and not (owner.combatShield and owner.combatShield:IsMouseOver()) then
                GameTooltip:Hide()
            end
        end)
    end)
    shield:SetScript("OnClick", function(self, button)
        local owner = self:GetParent()
        if button == "RightButton" and owner and owner.key then
            GameTooltip:Hide()
            UI.OpenMenu(owner.key)
        end
    end)
    row.combatShield = shield
    return shield
end

function UI.SetCombatDisplayOnly(row, displayOnly)
    if not row then
        return
    end
    local shield = UI.EnsureCombatShield(row)
    if displayOnly then
        if shield then
            shield:Show()
        end
    elseif shield then
        shield:Hide()
    end
end

function UI.SlashName(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end
    local name = key
    local mine = Util.MyRealm()
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

function UI.InviteMacro(key)
    local name = UI.SlashName(key)
    if not name then
        return nil
    end
    return "/invite " .. name
end

function UI.MatchKnownKey(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local function same(key)
        return key == name or UI.SpokenName(key) == name
    end
    if SF.db and type(SF.db.players) == "table" then
        for key in pairs(SF.db.players) do
            if same(key) then
                return key
            end
        end
    end
    for key in pairs(S.sightings) do
        if same(key) then
            return key
        end
    end
    for key in pairs(S.zoneSeen) do
        if same(key) then
            return key
        end
    end
    return Util.SafeKey(name:gsub(" ", "-"))
end

function UI.NoteDecline(message)
    message = Util.PlainString(message)
    if type(message) ~= "string" then
        return
    end
    local name = message:match("^(.-) declines your group invitation%.?$")
        or message:match("^(.-) declines your invitation%.?$")
    if not name then
        return
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    local key = UI.MatchKnownKey(name)
    if not key then
        return
    end
    S.inviteState[key] = "declined"
    if UI.RefreshList then
        UI.RefreshList()
    end
end

function UI.ApplyInvite(button, key)
    local blocked = (not key) or Group.InMyGroup(key) or Memory.IsBlocked(key) or Memory.FlaggedKos(key)
    local macro = (not blocked) and UI.InviteMacro(key) or nil
    if UI.ApplyMacro(button, macro, true) then
        button.secureKey = key
    end
end

function UI.InviteKey(key)
    if not key or Group.InMyGroup(key) or Memory.IsBlocked(key) or Memory.FlaggedKos(key) then
        return
    end
    S.inviteState[key] = "invited"
    if UI.RefreshList then
        UI.RefreshList()
    end
end

function UI.PaintInvite(button)
    if not button then
        return
    end
    local state = button.key and S.inviteState[button.key]
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

function UI.TryAutoInvite()
end

function UI.BackgroundAlpha()
    local alpha = SF.db and tonumber(SF.db.bgAlpha)
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

function UI.ApplyBackground()
    local alpha = UI.BackgroundAlpha()
    if S.main then
        S.main:SetBackdropColor(0.04, 0.04, 0.04, alpha)
    end
    if S.popup then
        S.popup:SetBackdropColor(0.04, 0.04, 0.04, alpha)
    end
    if S.sameMobPopup then
        S.sameMobPopup:SetBackdropColor(0.04, 0.04, 0.04, alpha)
    end
end

function UI.Chrome(frame)
    frame:SetBackdrop(C.PANEL_BACKDROP)
    frame:SetBackdropColor(0.04, 0.04, 0.04, 0.94)
    frame:SetBackdropBorderColor(0.72, 0.58, 0.18, 0.95)
end

function UI.FlatButton(parent, text, width, height, secure)
    local template = secure and "SecureActionButtonTemplate, BackdropTemplate" or "BackdropTemplate"
    local button = CreateFrame("Button", nil, parent, template)
    button:SetSize(width, height)
    button:SetBackdrop(C.FLAT_BACKDROP)
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

function UI.ClassRGB(classFile)
    classFile = Util.NormClassFile(classFile)
    local colors = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not colors then
        return 0.9, 0.9, 0.9
    end
    return colors.r or 0.9, colors.g or 0.9, colors.b or 0.9
end

function UI.ClassLabel(classFile)
    classFile = Util.NormClassFile(classFile)
    if not classFile then
        return nil
    end
    local names = LOCALIZED_CLASS_NAMES_MALE
    if type(names) == "table" and type(names[classFile]) == "string" and names[classFile] ~= "" then
        return names[classFile]
    end
    return classFile:sub(1, 1) .. classFile:sub(2):lower()
end

function UI.RaceLabel(raceFile)
    raceFile = Util.NormRaceFile(raceFile)
    if not raceFile then
        return nil
    end
    local labels = {
        Human = "Human",
        Dwarf = "Dwarf",
        NightElf = "Night Elf",
        Gnome = "Gnome",
        Draenei = "Draenei",
        Orc = "Orc",
        Troll = "Troll",
        Tauren = "Tauren",
        Scourge = "Undead",
        BloodElf = "Blood Elf",
        Skyborne = "Skyborne",
    }
    if labels[raceFile] then
        return labels[raceFile]
    end
    return raceFile
end

function UI.ShowTip(owner, key)
    if not key then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local color = Memory.GeneralColor(key)
    local rgb = color and C.COLOR_RGB[color]
    local shown = UI.SpokenName(key)
    if rgb then
        GameTooltip:SetText(shown, rgb[1], rgb[2], rgb[3])
    elseif Memory.FlaggedKos(key) then
        GameTooltip:SetText(shown, 1, 0.45, 0.35)
    else
        local r, g, b = Memory.NameRGB(key, S.sightings[key] or S.zoneSeen[key] or (S.inZone and S.inZone[key]))
        GameTooltip:SetText(shown, r, g, b)
    end
    local tipEntry = (S.nearby and S.nearby[key])
        or (S.inZone and S.inZone[key])
        or (S.sightings and S.sightings[key])
        or (S.zoneSeen and S.zoneSeen[key])
        or { key = key }
    local classFile, raceFile, level = UI.EntryIdentity(tipEntry)
    local className = UI.ClassLabel(classFile)
    local raceName = UI.RaceLabel(raceFile)
    if level or raceName or className then
        local cr, cg, cb = UI.ClassRGB(classFile)
        local parts = {}
        if level then
            parts[#parts + 1] = "Level " .. level
        end
        if raceName then
            parts[#parts + 1] = raceName
        end
        if className then
            parts[#parts + 1] = className
        end
        GameTooltip:AddLine(table.concat(parts, " "), cr, cg, cb, true)
    end
    if Memory.FlaggedKos(key) then
        GameTooltip:AddLine("Kill on sight", 1, 0.35, 0.3, true)
    end
    local function TimesPhrase(n)
        n = tonumber(n) or 0
        if n == 1 then
            return "1 time"
        end
        return n .. " times"
    end
    GameTooltip:AddLine("Been nearby: " .. TimesPhrase(Memory.SeenCount(key, "nearbyTimes")), 0.8, 0.86, 1, true)
    local seen = S.sightings[key] or S.zoneSeen[key]
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
            local rec = SF.db and SF.db.players and SF.db.players[key]
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
    local history = SF.db and SF.db.players and SF.db.players[key]
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
    local general, good, okay, bad = Memory.Tally(key)
    if general then
        local tint = C.COLOR_RGB[general]
        GameTooltip:AddLine(
            "General: " .. C.COLOR_LABEL[general] .. string.format(" (%d good, %d okay, %d bad)", good, okay, bad),
            tint[1], tint[2], tint[3],
            true
        )
    else
        GameTooltip:AddLine("General: no mark yet", 0.7, 0.7, 0.7, true)
    end
    local mine = SF.db.players[key]
    local myColor = type(mine) == "table" and Util.ValidColor(mine.color)
    if myColor then
        local tint = C.COLOR_RGB[myColor]
        GameTooltip:AddLine("Your mark: " .. C.COLOR_LABEL[myColor], tint[1], tint[2], tint[3], true)
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
    local flags = Memory.FlagCounts(key)
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

function UI.SavePosition()
    if not SF.db then
        return
    end
    local point, _, rel, x, y = S.main:GetPoint(1)
    if not C.ANCHORS[point] or not C.ANCHORS[rel] then
        return
    end
    SF.db.window = {
        point = point,
        rel = rel,
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
        w = S.main:GetWidth(),
        h = S.main:GetHeight(),
    }
end

function UI.ApplySize()
    local window = SF.db and SF.db.window
    local w = C.FRAME_WIDTH
    local h = C.FRAME_HEIGHT
    if type(window) == "table" then
        w = tonumber(window.w) or w
        h = tonumber(window.h) or h
    end
    if w < 230 then
        w = 230
    end
    if h < 170 then
        h = 170
    end
    S.main:SetSize(w, h)
end

function UI.PositionMain()
    S.main:ClearAllPoints()
    local window = SF.db and SF.db.window
    if type(window) == "table" and C.ANCHORS[window.point] and C.ANCHORS[window.rel] then
        S.main:SetPoint(window.point, UIParent, window.rel, tonumber(window.x) or 0, tonumber(window.y) or 0)
    elseif ChatFrame1 then
        S.main:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 30)
    else
        S.main:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 24, 240)
    end
    UI.ApplySize()
end

function UI.HideMain()
    S.main:Hide()
    if SF.db then
        SF.db.hidden = true
    end
    if S.menu then
        S.menu:Hide()
    end
    if S.settingsMenu then
        S.settingsMenu:Hide()
    end
end

function UI.ShowMain()
    UI.PositionMain()
    S.main:Show()
    if SF.db then
        SF.db.hidden = false
    end
    Detection.Scan()
end

function UI.BuildMain()
    S.main = CreateFrame("Frame", "SocialForeverFrame", UIParent, "BackdropTemplate")
    S.main:SetSize(C.FRAME_WIDTH, C.FRAME_HEIGHT)
    S.main:SetFrameStrata("MEDIUM")
    S.main:SetClampedToScreen(true)
    S.main:SetMovable(true)
    S.main:SetResizable(true)
    if S.main.SetResizeBounds then
        S.main:SetResizeBounds(230, 170, 680, 900)
    end
    S.main:EnableMouse(true)
    UI.Chrome(S.main)
    S.main:Hide()

    local drag = CreateFrame("Button", nil, S.main)
    drag:SetPoint("TOPLEFT", 26, -4)
    drag:SetPoint("TOPRIGHT", -48, -4)
    drag:SetHeight(20)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            return
        end
        S.main:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        S.main:StopMovingOrSizing()
        UI.SavePosition()
    end)

    local settings = CreateFrame("Button", nil, S.main, "BackdropTemplate")
    settings:SetSize(18, 18)
    settings:SetPoint("TOPRIGHT", -26, -6)
    settings:SetBackdrop(C.FLAT_BACKDROP)
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
        GameTooltip:AddLine("Grouping, name size, and background.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    settings:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
    end)
    S.main.settings = settings

    local panel = CreateFrame("Frame", "SocialForeverSettings", UIParent, "BackdropTemplate")
    panel:SetFrameStrata("DIALOG")
    panel:SetSize(176, 348)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    UI.Chrome(panel)
    S.settingsMenu = panel

    local function MenuRow(y, clickable)
        local button = CreateFrame("Button", nil, panel)
        button:SetSize(160, 18)
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
    local sameHead = MenuRow(-88, false)
    sameHead.label:SetText("Same-mob grouping")
    sameHead.label:SetTextColor(0.75, 0.68, 0.4)
    local askHead = MenuRow(-106, false)
    askHead.label:SetText("Ask before inviting")
    askHead.label:SetTextColor(0.65, 0.65, 0.65)
    local askOn = MenuRow(-124, true)
    local askOff = MenuRow(-142, true)
    local sameAutoHead = MenuRow(-166, false)
    sameAutoHead.label:SetText("Auto-invite")
    sameAutoHead.label:SetTextColor(0.65, 0.65, 0.65)
    local sameAutoOn = MenuRow(-184, true)
    local sameAutoOff = MenuRow(-202, true)
    local sizeHead = MenuRow(-226, false)
    sizeHead.label:SetText("Name size")
    sizeHead.label:SetTextColor(0.75, 0.68, 0.4)
    local size16 = MenuRow(-244, true)
    local size18 = MenuRow(-262, true)
    local size20 = MenuRow(-280, true)
    local opacityHead = MenuRow(-304, false)
    opacityHead.label:SetText("Background")
    opacityHead.label:SetTextColor(0.75, 0.68, 0.4)
    local opacityValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    opacityValue:SetPoint("RIGHT", opacityHead, "RIGHT", -4, 0)
    opacityValue:SetTextColor(0.9, 0.9, 0.9)
    local slider = CreateFrame("Slider", nil, panel, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", 18, -326)
    slider:SetSize(140, 16)
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
        if SF.db then
            SF.db.bgAlpha = value / 100
        end
        UI.ApplyBackground()
    end)

    local function PaintSettingsChoice(button, selected, text)
        button.label:SetText((selected and "> " or "  ") .. text)
        if selected then
            button.label:SetTextColor(1, 0.82, 0.25)
        else
            button.label:SetTextColor(0.9, 0.9, 0.9)
        end
    end

    local function PaintSettingsMenu()
        local auto = Group.FriendsAutoOn()
        local ask = Group.SameMobAskOn and Group.SameMobAskOn()
        local sameAuto = Group.SameMobAutoOn and Group.SameMobAutoOn()
        local size = Util.NameSize()
        PaintSettingsChoice(autoOn, auto, "On")
        PaintSettingsChoice(autoOff, not auto, "Off")
        PaintSettingsChoice(askOn, ask, "On")
        PaintSettingsChoice(askOff, not ask, "Off")
        PaintSettingsChoice(sameAutoOn, sameAuto, "On")
        PaintSettingsChoice(sameAutoOff, not sameAuto, "Off")
        PaintSettingsChoice(size16, size == 16, "16")
        PaintSettingsChoice(size18, size == 18, "18")
        PaintSettingsChoice(size20, size == 20, "20")
        local percent = math.floor(UI.BackgroundAlpha() * 100 + 0.5)
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
    LeaveChoice(askOn)
    LeaveChoice(askOff)
    LeaveChoice(sameAutoOn)
    LeaveChoice(sameAutoOff)
    LeaveChoice(size16)
    LeaveChoice(size18)
    LeaveChoice(size20)

    autoOn:SetScript("OnClick", function()
        if not SF.db then
            return
        end
        SF.db.autoInviteFriends = true
        PaintSettingsMenu()
    end)
    autoOff:SetScript("OnClick", function()
        if not SF.db then
            return
        end
        SF.db.autoInviteFriends = false
        PaintSettingsMenu()
    end)
    askOn:SetScript("OnClick", function()
        if Group.SetSameMobAsk then
            Group.SetSameMobAsk(true)
        end
        PaintSettingsMenu()
    end)
    askOff:SetScript("OnClick", function()
        if Group.SetSameMobAsk then
            Group.SetSameMobAsk(false)
        end
        PaintSettingsMenu()
    end)
    sameAutoOn:SetScript("OnClick", function()
        if Group.SetSameMobAuto then
            Group.SetSameMobAuto(true)
        end
        PaintSettingsMenu()
    end)
    sameAutoOff:SetScript("OnClick", function()
        if Group.SetSameMobAuto then
            Group.SetSameMobAuto(false)
        end
        PaintSettingsMenu()
    end)
    local function PickSize(size)
        return function()
            if not SF.db then
                return
            end
            SF.db.nameSize = size
            PaintSettingsMenu()
            if UI.RefreshList then
                UI.RefreshList()
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
        if S.menu then
            S.menu:Hide()
        end
        GameTooltip:Hide()
        panel:ClearAllPoints()
        panel:SetPoint("TOPRIGHT", settings, "BOTTOMRIGHT", 0, -2)
        PaintSettingsMenu()
        panel:Show()
    end)

    local close = CreateFrame("Button", nil, S.main)
    close:SetSize(18, 18)
    close:SetPoint("TOPLEFT", 6, -5)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    closeText:SetPoint("CENTER")
    closeText:SetText("x")
    close:SetScript("OnClick", UI.HideMain)
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

    local function MakeTab(id)
        local tab = CreateFrame("Button", nil, S.main, "BackdropTemplate")
        tab:SetHeight(20)
        tab:SetBackdrop(C.FLAT_BACKDROP)
        tab:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        tab:SetBackdropBorderColor(0.45, 0.38, 0.16, 0.9)
        local label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", 6, 0)
        label:SetPoint("RIGHT", -6, 0)
        label:SetJustifyH("CENTER")
        label:SetWordWrap(false)
        tab.label = label
        tab.tabId = id
        tab:SetScript("OnClick", function(self)
            UI.SetListTab(self.tabId)
        end)
        tab:SetScript("OnEnter", function(self)
            if UI.GetListTab() ~= self.tabId then
                self:SetBackdropColor(0.16, 0.14, 0.08, 0.98)
            end
        end)
        tab:SetScript("OnLeave", function()
            UI.PaintListTabs()
        end)
        return tab
    end

    local tabNearby = MakeTab("nearby")
    tabNearby:SetPoint("TOPLEFT", 8, -26)
    tabNearby:SetPoint("TOPRIGHT", S.main, "TOP", -2, -26)
    local tabZone = MakeTab("zone")
    tabZone:SetPoint("TOPLEFT", S.main, "TOP", 2, -26)
    tabZone:SetPoint("TOPRIGHT", S.main, "TOPRIGHT", -16, -26)
    S.main.tabNearby = tabNearby
    S.main.tabZone = tabZone
    -- Keep a title handle for older empty-state code paths.
    S.main.title = tabNearby.label
    UI.PaintListTabs(0, 0)

    local line = S.main:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 10, -48)
    line:SetPoint("TOPRIGHT", -10, -48)
    line:SetHeight(1)
    line:SetColorTexture(0.6, 0.5, 0.2, 0.7)

    local list = CreateFrame("Frame", nil, S.main)
    list:SetPoint("TOPLEFT", 8, -52)
    list:SetPoint("BOTTOMRIGHT", -16, 18)
    -- Do not EnableMouse on the empty list chrome: that blocks world mouseover
    -- through the frame and was freezing the UI after stray OnEnter hits.
    -- Rows, Invite, and the scrollbar still freeze while the cursor is on them.
    list:EnableMouse(false)
    list:EnableMouseWheel(true)
    S.main.list = list
    S.main.scroll = list
    S.main.scrollOffset = 0

    local bar = CreateFrame("Slider", nil, S.main, "BackdropTemplate")
    bar:SetOrientation("VERTICAL")
    bar:SetPoint("TOPRIGHT", -7, -54)
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
        if nextOffset ~= S.main.scrollOffset then
            S.main.scrollOffset = nextOffset
            if UI.RequestListPaint then
                UI.RequestListPaint()
            end
        end
    end)
    bar:SetScript("OnEnter", function()
        UI.NoteListEnter()
    end)
    bar:SetScript("OnLeave", function()
        UI.NoteListLeave()
    end)
    S.main.bar = bar

    local empty = S.main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -4)
    empty:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -4, 4)
    empty:SetJustifyH("CENTER")
    empty:SetJustifyV("MIDDLE")
    empty:SetTextColor(0.7, 0.7, 0.7)
    empty:SetText(C.EMPTY_TEXT)
    S.main.empty = empty

    local function VisibleSlots()
        local rowH = Util.RowHeight()
        local view = list:GetHeight()
        if not view or view < rowH then
            return C.VISIBLE_ROWS
        end
        return math.max(1, math.floor((view / rowH) + 0.001))
    end

    local function ScrollBy(delta)
        if InCombatLockdown() then
            return
        end
        local maxOffset = math.max(0, (S.main.entryCount or 0) - VisibleSlots())
        local nextOffset = (S.main.scrollOffset or 0) - delta
        if nextOffset < 0 then
            nextOffset = 0
        end
        if nextOffset > maxOffset then
            nextOffset = maxOffset
        end
        if nextOffset == S.main.scrollOffset then
            return
        end
        S.main.scrollOffset = nextOffset
        if UI.RequestListPaint then
            UI.RequestListPaint()
        end
    end
    S.main.ScrollBy = ScrollBy

    list:SetScript("OnMouseWheel", function(_, delta)
        GameTooltip:Hide()
        ScrollBy(delta)
    end)

    S.main.rows = {}
    for i = 1, C.MAX_ROWS do
        local row = CreateFrame("Button", nil, list, "SecureActionButtonTemplate")
        row:SetSize(200, C.ROW_HEIGHT)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -((i - 1) * C.ROW_HEIGHT))
        row:RegisterForClicks("LeftButtonDown", "RightButtonDown")
        row:SetAttribute("useOnKeyDown", true)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            GameTooltip:Hide()
            ScrollBy(delta)
        end)
        row:Hide()

        local mark = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        mark:SetPoint("LEFT", 6, 0)
        mark:SetWidth(16)
        mark:SetJustifyH("CENTER")
        row.mark = mark

        local invite = UI.FlatButton(list, "Invite", 74, 18, true)
        invite.owner = row
        invite:SetPoint("LEFT", row, "RIGHT", 4, 0)
        invite:SetFrameLevel(row:GetFrameLevel() + 5)
        invite:RegisterForClicks("LeftButtonDown")
        invite:SetAttribute("useOnKeyDown", true)
        invite.Paint = UI.PaintInvite
        invite:SetScript("PostClick", function(self)
            local key = self.key
            if not key or InCombatLockdown() or Group.InMyGroup(key) or Memory.IsBlocked(key) or Memory.FlaggedKos(key) then
                return
            end
            S.inviteState[key] = "invited"
            UI.PaintInvite(self)
        end)
        invite:SetScript("OnEnter", function(self)
            UI.NoteListEnter()
            local state = self.key and S.inviteState[self.key]
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
            local macro = self.key and UI.InviteMacro(self.key)
            if macro then
                GameTooltip:AddLine(macro, 0.75, 0.75, 0.75, true)
            end
            GameTooltip:Show()
        end)
        invite:EnableMouseWheel(true)
        invite:SetScript("OnMouseWheel", function(_, delta)
            GameTooltip:Hide()
            ScrollBy(delta)
        end)
        invite:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            UI.PaintInvite(self)
            UI.NoteListLeave()
        end)
        row.invite = invite

        local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", mark, "RIGHT", 8, 0)
        name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        row.name = name

        local levelText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        levelText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        levelText:SetJustifyH("RIGHT")
        levelText:SetWidth(28)
        levelText:Hide()
        row.levelText = levelText

        local identity = row:CreateTexture(nil, "ARTWORK")
        identity:SetSize(14, 14)
        identity:SetPoint("RIGHT", levelText, "LEFT", -4, 0)
        identity:Hide()
        row.identity = identity

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
            UI.NoteListEnter()
            if not self.key then
                return
            end
            S.tipToken = S.tipToken + 1
            self.highlight:Show()
            UI.ShowTip(self, self.key)
        end)
        row:SetScript("OnLeave", function(self)
            self.highlight:Hide()
            UI.NoteListLeave()
            local token = S.tipToken
            C_Timer.After(0, function()
                if token ~= S.tipToken then
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
                UI.OpenMenu(self.key)
                return
            end
            if button ~= "LeftButton" or not self.key or not S.sightings[self.key] then
                return
            end
            local key = self.key
            C_Timer.After(0.2, function()
                local id = Util.UnitIdentity("target")
                if not id then
                    local existsOk, exists = pcall(UnitExists, "target")
                    if existsOk and Util.PlainBool(exists) == true then
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
                if not S.sightings[key] then
                    return
                end
                S.sightings[key] = nil
                S.inviteState[key] = nil
                Detection.Publish()
            end)
        end)

        S.main.rows[i] = row
    end

    local grip = CreateFrame("Button", nil, S.main)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    local gripText = grip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gripText:SetPoint("CENTER", -1, 2)
    gripText:SetText("..")
    gripText:SetTextColor(0.85, 0.7, 0.28)
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and not InCombatLockdown() then
            S.main:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            S.main:StopMovingOrSizing()
            UI.SavePosition()
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

    S.main:SetScript("OnSizeChanged", function()
        if SF.db and S.main.rows then
            if UI.RequestListPaint then
                UI.RequestListPaint()
            elseif UI.RefreshList then
                UI.RefreshList()
            end
        end
    end)

    S.main:SetScript("OnUpdate", nil)
end

function UI.AnimActive()
    if S.moveWave then
        return true
    end
    if next(S.fadeInAt) ~= nil then
        return true
    end
    if next(S.fadeOutAt) ~= nil then
        return true
    end
    return false
end

function UI.KickAnimUpdate()
    if not S.main or S.main:GetScript("OnUpdate") then
        return
    end
    S.main:SetScript("OnUpdate", UI.OnMainAnimUpdate)
end

function UI.OnMainAnimUpdate()
    if not S.main.rows or S.main.fadingPaint then
        if not UI.AnimActive() then
            S.main:SetScript("OnUpdate", nil)
        end
        return
    end
    -- While the mouse is over the list, keep row identity stable — pause visual mutates.
    if S.listFrozen then
        return
    end
    local now = GetTime()
    local finished = false
    for _, row in ipairs(S.main.rows) do
        local key = row.key
        if key and row:IsShown() and (S.fadeInAt[key] or S.fadeOutAt[key] or (S.moveWave and S.moveKeys[key])) then
            local alpha = UI.RowFadeAlpha(key, now)
            row:SetAlpha(alpha)
            if row.invite then
                row.invite:SetAlpha(row.invite:IsShown() and alpha or 0)
            end
            if S.fadeOutAt[key] and alpha <= 0 then
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
    if S.moveWave and S.moveHeld and (now - S.moveWave) >= C.MOVE_HALF then
        finished = true
    elseif S.moveWave and (now - S.moveWave) >= (C.MOVE_HALF * 2) then
        finished = true
    end
    if finished and UI.RefreshList then
        UI.RefreshList()
    end
    if not UI.AnimActive() then
        S.main:SetScript("OnUpdate", nil)
    end
end

function UI.IsListHovered()
    if not S.main then
        return false
    end
    if S.main.list and S.main.list:IsMouseOver() then
        return true
    end
    if S.main.bar and S.main.bar:IsShown() and S.main.bar:IsMouseOver() then
        return true
    end
    if S.main.rows then
        for i = 1, #S.main.rows do
            local row = S.main.rows[i]
            if row:IsShown() then
                if row:IsMouseOver() then
                    return true
                end
                if row.invite and row.invite:IsShown() and row.invite:IsMouseOver() then
                    return true
                end
            end
        end
    end
    return false
end

function UI.PaintTargetHighlightsOnly()
    if not S.main or not S.main.rows then
        return
    end
    local targetKey = Util.UnitIdentity("target")
    for i = 1, #S.main.rows do
        local row = S.main.rows[i]
        if row:IsShown() and row.key and row.PaintTarget then
            row:PaintTarget(Util.SameKey(row.key, targetKey))
        end
    end
end

-- Update mark letter/colors (and invite block state) for one player without
-- reordering rows. Safe while the list is frozen or in combat for font colors.
function UI.PaintRowAppearance(key)
    key = Util.SafeKey(key)
    if not key or not S.main or not S.main.rows then
        return
    end
    local entry = (S.nearby and S.nearby[key])
        or (S.inZone and S.inZone[key])
        or (S.sightings and S.sightings[key])
        or (S.zoneSeen and S.zoneSeen[key])
        or { key = key }
    local color = Memory.GeneralColor(key)
    local kos = Memory.FlaggedKos(key)
    local letter = color == "green" and "G" or color == "yellow" and "Y" or color == "red" and "R" or "-"
    if not color and kos then
        letter = "K"
    end
    local mr, mg, mb, nr, ng, nb
    if color then
        local rgb = C.COLOR_RGB[color]
        mr, mg, mb = rgb[1], rgb[2], rgb[3]
        nr, ng, nb = mr, mg, mb
    elseif kos then
        mr, mg, mb = 1, 0.3, 0.25
        nr, ng, nb = 1, 0.45, 0.35
    else
        mr, mg, mb = 0.45, 0.45, 0.45
        nr, ng, nb = Memory.NameRGB(key, entry, Memory.MaxFamiliarity())
    end
    local locked = InCombatLockdown()
    for i = 1, #S.main.rows do
        local row = S.main.rows[i]
        if row:IsShown() and row.key and Util.SameKey(row.key, key) then
            if row.mark then
                row.mark:SetText(letter)
                row.mark:SetTextColor(mr, mg, mb)
            end
            if row.name then
                row.name:SetTextColor(nr, ng, nb)
            end
            if row.invite then
                if not locked then
                    UI.ApplyInvite(row.invite, key)
                end
                UI.PaintInvite(row.invite)
            end
        end
    end
end

function UI.SetListFrozen(frozen)
    if frozen then
        if S.listFrozen then
            return
        end
        S.listFrozen = true
        return
    end
    if not S.listFrozen then
        return
    end
    S.listFrozen = false
    -- Always rebuild once on leave so deferred detection/sort/mark order catch up,
    -- even if only appearance paints ran while frozen.
    S.listDirty = false
    if UI.RefreshList then
        UI.RefreshList({ force = true, skipMove = true })
    end
end

-- If freeze was left on after the cursor left (menu, strata, missed OnLeave),
-- clear it so mouseover/target detection can paint again immediately.
-- Only clears the flag — caller should RefreshList (avoids nested rebuilds).
function UI.EnsureListFreezeHonest()
    if S.listFrozen and not UI.IsListHovered() then
        S.listFrozen = false
        return true
    end
    return false
end

function UI.NoteListEnter()
    UI.SetListFrozen(true)
end

function UI.NoteListLeave()
    C_Timer.After(0, function()
        if not UI.IsListHovered() then
            UI.SetListFrozen(false)
        end
    end)
end

-- Marks/KOS change sort priority; expire the stable-hold so the next rebuild reorders.
function UI.InvalidateListSort()
    if S.sortHold then
        S.sortHold.at = 0
    end
end

function UI.PinNearbyTarget(list)
    local targetKey = Util.UnitIdentity("target")
    if not targetKey or Util.IsMe(targetKey) then
        return nil
    end
    local idx
    for i = 1, #list do
        if Util.SameKey(list[i].key, targetKey) then
            idx = i
            break
        end
    end
    if not idx then
        return nil
    end
    if idx ~= 1 then
        local entry = table.remove(list, idx)
        table.insert(list, 1, entry)
    end
    return list[1].key
end

function UI.RequestListPaint()
    if S.listFrozen then
        UI.RefreshList({ scrollOnly = true })
    else
        UI.RefreshList()
    end
end

function UI.GetListTab()
    local tab = (SF.db and SF.db.listTab) or S.listTab or "nearby"
    if tab == "zone" then
        return "zone"
    end
    return "nearby"
end

function UI.SetListTab(tab)
    if tab ~= "zone" then
        tab = "nearby"
    end
    if UI.GetListTab() == tab then
        UI.PaintListTabs()
        return
    end
    S.listTab = tab
    if SF.db then
        SF.db.listTab = tab
    end
    if S.main then
        S.main.scrollOffset = 0
    end
    S.moveWave = nil
    wipe(S.moveKeys)
    S.moveHeld = nil
    S.lastShown = nil
    wipe(S.fadeInAt)
    wipe(S.fadeOutAt)
    wipe(S.fadeOutEntry)
    wipe(S.listedKeys)
    S.listDirty = false
    if UI.RefreshList then
        UI.RefreshList({ force = true, skipMove = true })
    end
end

function UI.PaintListTabs(nearCount, zoneCount)
    if not S.main or not S.main.tabNearby or not S.main.tabZone then
        return
    end
    nearCount = tonumber(nearCount)
    if not nearCount then
        nearCount = 0
        for _ in pairs(S.nearby or {}) do
            nearCount = nearCount + 1
        end
    end
    zoneCount = tonumber(zoneCount)
    if not zoneCount then
        zoneCount = 0
        for _ in pairs(S.inZone or {}) do
            zoneCount = zoneCount + 1
        end
    end
    local place = Memory.CurrentArea() or "Nearby"
    local zoneName = Memory.CurrentZone() or "This zone"
    local plusAt = C.ZONE_LIST_PLUS or C.MAX_ROWS or 100
    local zoneCountLabel = tostring(zoneCount)
    if S.P.zoneRosterFull or zoneCount >= plusAt then
        zoneCountLabel = plusAt .. "+"
    end
    local nearLabel = place
    if nearCount > 0 then
        nearLabel = place .. " (" .. nearCount .. ")"
    end
    local zoneLabel = zoneName .. " (" .. zoneCountLabel .. ")"
    if zoneCount == 0 and not S.P.zoneRosterFull then
        zoneLabel = zoneName
    end
    S.main.tabNearby.label:SetText(nearLabel)
    S.main.tabZone.label:SetText(zoneLabel)
    local active = UI.GetListTab()
    local function paint(tab, selected)
        if selected then
            tab:SetBackdropColor(0.22, 0.18, 0.08, 0.98)
            tab:SetBackdropBorderColor(1, 0.82, 0.25, 1)
            tab.label:SetTextColor(1, 0.86, 0.35)
        else
            tab:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
            tab:SetBackdropBorderColor(0.4, 0.34, 0.16, 0.85)
            tab.label:SetTextColor(0.75, 0.7, 0.55)
        end
    end
    paint(S.main.tabNearby, active == "nearby")
    paint(S.main.tabZone, active == "zone")
end

function UI.RowFadeAlpha(key, now)
    local outAt = S.fadeOutAt[key]
    if outAt then
        local fade = (now - outAt) / C.FADE_OUT_TIME
        if fade >= 1 then
            return 0
        end
        if fade < 0 then
            return 1
        end
        return 1 - fade
    end
    local inAt = S.fadeInAt[key]
    if inAt then
        local fade = (now - inAt) / C.FADE_IN_TIME
        if fade >= 1 then
            S.fadeInAt[key] = nil
            return 1
        end
        if fade < 0 then
            fade = 0
        end
        return fade
    end
    if S.moveWave and S.moveKeys[key] then
        local elapsed = now - S.moveWave
        if elapsed >= (C.MOVE_HALF * 2) then
            return 1
        end
        if elapsed < 0 then
            return 1
        end
        if elapsed < C.MOVE_HALF then
            return 1 - (0.5 * (elapsed / C.MOVE_HALF))
        end
        return 0.5 + (0.5 * ((elapsed - C.MOVE_HALF) / C.MOVE_HALF))
    end
    return 1
end

function UI.HoldLeavingRows(ordered, now)
    local present = {}
    for i = 1, #ordered do
        local entry = ordered[i]
        if entry.key then
            present[entry.key] = true
            if S.fadeOutAt[entry.key] then
                S.fadeOutAt[entry.key] = nil
                S.fadeOutEntry[entry.key] = nil
                S.fadeInAt[entry.key] = now
            elseif not S.listedKeys[entry.key] then
                S.fadeInAt[entry.key] = now
            end
        end
    end
    for key, entry in pairs(S.listedKeys) do
        if not present[key] and not S.fadeOutAt[key] then
            S.fadeOutAt[key] = now
            S.fadeOutEntry[key] = entry
            S.fadeInAt[key] = nil
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
    S.listedKeys = nextListed

    local nearGhosts = {}
    local zoneGhosts = {}
    for key, entry in pairs(S.fadeOutEntry) do
        if not present[key] then
            local elapsed = now - (S.fadeOutAt[key] or now)
            if elapsed >= C.FADE_OUT_TIME then
                S.fadeOutAt[key] = nil
                S.fadeOutEntry[key] = nil
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
                if #merged < C.MAX_ROWS then
                    merged[#merged + 1] = nearGhosts[g]
                end
            end
            placedNear = true
        end
        if #merged < C.MAX_ROWS then
            merged[#merged + 1] = entry
        end
    end
    if not placedNear then
        for g = 1, #nearGhosts do
            if #merged < C.MAX_ROWS then
                merged[#merged + 1] = nearGhosts[g]
            end
        end
    end
    for g = 1, #zoneGhosts do
        if #merged < C.MAX_ROWS then
            merged[#merged + 1] = zoneGhosts[g]
        end
    end
    return merged
end

function UI.RefreshList(opts)
    if type(opts) ~= "table" then
        opts = nil
    end
    local force = opts and opts.force
    local scrollOnly = opts and opts.scrollOnly
    local skipMove = opts and opts.skipMove

    if not force and not scrollOnly then
        UI.EnsureListFreezeHonest()
    end

    if S.listFrozen and not force and not scrollOnly then
        S.listDirty = true
        UI.PaintTargetHighlightsOnly()
        UI.PaintListTabs()
        return
    end

    if not S.main or not SF.db then
        return
    end
    if S.main.fadingPaint then
        -- Do not drop a publish/mark update that arrived mid-paint.
        S.listDirty = true
        return
    end
    S.main.fadingPaint = true

    local ordered
    local zoneList
    local nearCount = 0
    local listTab = UI.GetListTab()

    if scrollOnly and S.displayOrdered then
        ordered = S.displayOrdered
        zoneList = {}
        nearCount = S.displayNearCount or 0
        for _ = 1, S.displayZoneCount or 0 do
            zoneList[#zoneList + 1] = true
        end
    else
    local function SortSection(list, useYards)
        local hereZone = Memory.CurrentZone()
        local here = useYards and Memory.CurrentArea() or nil
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
            local kosA = Memory.FlaggedKos(a.key) and 1 or 0
            local kosB = Memory.FlaggedKos(b.key) and 1 or 0
            if kosA ~= kosB then
                return kosA > kosB
            end
            local seenA, seenB = Memory.Familiarity(a.key), Memory.Familiarity(b.key)
            if seenA ~= seenB then
                return seenA > seenB
            end
            local function timeLeft(entry)
                local ttl = entry.ttl or (useYards and C.SEEN_TTL or C.ZONE_TTL)
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

    local nearList = {}
    for _, entry in pairs(S.nearby) do
        nearList[#nearList + 1] = entry
    end
    zoneList = {}
    for _, entry in pairs(S.inZone) do
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
        local stable = {}
        local used = {}
        for i = 1, #previous do
            local entry = byKey[previous[i]]
            if entry then
                stable[#stable + 1] = entry
                used[entry.key] = true
            end
        end
        for i = 1, #list do
            local entry = list[i]
            if not used[entry.key] then
                stable[#stable + 1] = entry
            end
        end
        return stable
    end

    local targetKey = Util.UnitIdentity("target")
    if targetKey and Util.IsMe(targetKey) then
        targetKey = nil
    end
    local pinKey = nil
    if targetKey then
        for i = 1, #nearList do
            if Util.SameKey(nearList[i].key, targetKey) then
                pinKey = nearList[i].key
                break
            end
        end
    end
    local pinChanged = (pinKey or false) ~= (S.pinnedNearKey or false)
    S.pinnedNearKey = pinKey

    local now = GetTime()
    if pinChanged or now - (S.sortHold.at or 0) >= C.SORT_EVERY then
        SortSection(nearList, true)
        SortSection(zoneList, false)
        S.sortHold.at = now
        S.sortHold.zone = KeysOf(zoneList)
    else
        nearList = StableOrder(nearList, S.sortHold.near)
        zoneList = StableOrder(zoneList, S.sortHold.zone)
    end
    if pinKey then
        UI.PinNearbyTarget(nearList)
    end
    S.sortHold.near = KeysOf(nearList)

    ordered = {}
    if listTab == "zone" then
        for i = 1, #zoneList do
            if #ordered >= C.MAX_ROWS then
                break
            end
            ordered[#ordered + 1] = zoneList[i]
        end
    else
        for i = 1, #nearList do
            if #ordered >= C.MAX_ROWS then
                break
            end
            ordered[#ordered + 1] = nearList[i]
        end
    end
    ordered = UI.HoldLeavingRows(ordered, now)

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
        local used = {}
        for i = 1, #held do
            local item = held[i]
            if item.header then
                out[#out + 1] = { header = item.header, dim = item.dim }
            elseif item.key and not item.fading then
                used[item.key] = true
                if byKey[item.key] then
                    out[#out + 1] = byKey[item.key]
                elseif S.fadeOutEntry[item.key] then
                    out[#out + 1] = S.fadeOutEntry[item.key]
                end
            end
        end
        -- Keep existing row order stable during the move fade, but still show
        -- brand-new mouseovers/sightings instead of waiting out the animation.
        for i = 1, #liveList do
            local entry = liveList[i]
            if entry.key and not used[entry.key] and not entry.fading then
                out[#out + 1] = entry
                used[entry.key] = true
            elseif entry.header and not entry.dim then
                -- Allow a live zone header + its new rows if the hold had none.
                local already = false
                for j = 1, #out do
                    if out[j].header and not out[j].dim then
                        already = true
                        break
                    end
                end
                if not already then
                    out[#out + 1] = { header = entry.header, dim = entry.dim }
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
        for key in pairs(S.listedKeys) do
            if not showing[key] then
                S.listedKeys[key] = nil
                S.fadeInAt[key] = nil
            end
        end
    end

    if skipMove then
        S.moveWave = nil
        wipe(S.moveKeys)
        S.moveHeld = nil
    elseif S.moveWave and (now - S.moveWave) >= (C.MOVE_HALF * 2) then
        S.moveWave = nil
        wipe(S.moveKeys)
        S.moveHeld = nil
    end
    if not skipMove then
        if S.moveWave and S.moveHeld and (now - S.moveWave) < C.MOVE_HALF then
            ordered = HeldDisplay(S.moveHeld, ordered)
            HideUnshown(ordered)
        elseif S.moveWave and S.moveHeld then
            S.moveHeld = nil
        elseif not S.moveWave and S.lastShown then
            local oldSlots = Slots(S.lastShown)
            local newSlots = Slots(ordered)
            local keys = {}
            local changed = false
            for key, index in pairs(newSlots) do
                local prev = oldSlots[key]
                if prev and prev ~= index and not S.fadeOutAt[key] and not S.fadeInAt[key] then
                    changed = true
                    keys[key] = true
                end
            end
            if changed then
                S.moveWave = now
                S.moveKeys = keys
                S.moveHeld = CopySnap(S.lastShown)
                ordered = HeldDisplay(S.moveHeld, ordered)
                HideUnshown(ordered)
            end
        end
    end
    S.lastShown = CopySnap(ordered)
    S.displayOrdered = ordered
    nearCount = 0
    for _ in pairs(S.nearby) do
        nearCount = nearCount + 1
    end
    S.displayNearCount = nearCount
    S.displayZoneCount = #zoneList
    end -- full rebuild (not scrollOnly)

    local maxSeen = Memory.MaxFamiliarity()
    local viewWidth = S.main.list:GetWidth()
    if not viewWidth or viewWidth < 40 then
        viewWidth = C.FRAME_WIDTH - 28
    end
    local rowH = Util.RowHeight()
    local font, fontSize, fontFlags = Util.NameFont()
    local view = S.main.list:GetHeight()
    local visible = C.VISIBLE_ROWS
    if view and view >= rowH then
        visible = math.max(1, math.floor((view / rowH) + 0.001))
    end
    if visible > C.MAX_ROWS then
        visible = C.MAX_ROWS
    end
    S.main.entryCount = #ordered
    local maxOffset = math.max(0, #ordered - visible)
    local offset = S.main.scrollOffset or 0
    if offset > maxOffset then
        offset = maxOffset
        S.main.scrollOffset = offset
    end
    if offset < 0 then
        offset = 0
        S.main.scrollOffset = 0
    end
    local locked = InCombatLockdown()
    local targetKey = Util.UnitIdentity("target")
    local function IsTarget(key)
        if not key or not targetKey then
            return false
        end
        if key == targetKey then
            return true
        end
        return key:gsub("[%s%-]+", ""):lower() == targetKey:gsub("[%s%-]+", ""):lower()
    end

    for i, row in ipairs(S.main.rows) do
        Util.ApplyNameFont(row.name)
        if row.levelText then
            Util.ApplyNameFont(row.levelText)
        end
        if row.identity then
            local iconSize = math.max(12, math.min(18, fontSize - 2))
            row.identity:SetSize(iconSize, iconSize)
        end
        pcall(row.mark.SetFont, row.mark, font, fontSize, fontFlags)
        row.mark:SetWidth(math.max(18, fontSize))
        local entry = ordered[offset + i]
        if i <= visible and entry and entry.header then
            row:SetHeight(rowH)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", S.main.list, "TOPLEFT", 0, -((i - 1) * rowH))
            row:SetWidth(viewWidth)
            row.key = nil
            row.invite.key = nil
            if not locked then
                UI.ApplyInvite(row.invite, nil)
                UI.ApplyTarget(row, nil)
            end
            UI.SetCombatDisplayOnly(row, locked)
            row.highlight:Hide()
            row.mark:SetText("")
            row.name:SetText(entry.header)
            if entry.dim then
                row.name:SetTextColor(0.55, 0.55, 0.55)
            else
                row.name:SetTextColor(1, 0.82, 0.25)
            end
            UI.PaintRowIdentity(row, nil)
            row.invite:Hide()
            row.invite:SetAlpha(0)
            row:SetAlpha(1)
            row:PaintTarget(false)
            row:Show()
            row:SetAlpha(1)
        elseif i <= visible and entry then
            row:SetHeight(rowH)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", S.main.list, "TOPLEFT", 0, -((i - 1) * rowH))
            row:SetWidth(viewWidth)
            row.key = entry.key
            row.invite.key = entry.key
            -- Macros can only be rewritten out of combat. If this row's secure
            -- target still matches, clicks stay live; otherwise show the name
            -- and block clicks so we never target the wrong person.
            local secureOk = (not locked) or Util.SameKey(row.secureKey, entry.key)
            if not locked then
                UI.ApplyInvite(row.invite, entry.key)
                UI.ApplyTarget(row, entry.key)
                secureOk = true
            end
            UI.SetCombatDisplayOnly(row, locked and not secureOk)
            local color = Memory.GeneralColor(entry.key)
            local letter = color == "green" and "G" or color == "yellow" and "Y" or color == "red" and "R" or "-"
            if not color and Memory.FlaggedKos(entry.key) then
                letter = "K"
            end
            row.mark:SetText(letter)
            if color then
                local rgb = C.COLOR_RGB[color]
                row.mark:SetTextColor(rgb[1], rgb[2], rgb[3])
                row.name:SetTextColor(rgb[1], rgb[2], rgb[3])
            elseif Memory.FlaggedKos(entry.key) then
                row.mark:SetTextColor(1, 0.3, 0.25)
                row.name:SetTextColor(1, 0.45, 0.35)
            else
                local r, g, b = Memory.NameRGB(entry.key, entry, maxSeen)
                row.mark:SetTextColor(0.45, 0.45, 0.45)
                row.name:SetTextColor(r, g, b)
            end
            row.name:SetText(UI.ListName(entry.key))
            UI.PaintRowIdentity(row, entry)
            local grouped = Group.InMyGroup(entry.key)
            local showInvite = (not grouped) and secureOk and not (locked and not secureOk)
            if grouped or not showInvite then
                row:SetWidth(viewWidth)
            else
                row:SetWidth(math.max(80, viewWidth - 78))
                row.invite:ClearAllPoints()
                row.invite:SetPoint("LEFT", row, "RIGHT", 4, 0)
            end
            UI.PaintInvite(row.invite)
            local alpha = UI.RowFadeAlpha(entry.key, GetTime())
            row:PaintTarget(IsTarget(entry.key))
            if S.fadeOutAt[entry.key] and alpha <= 0 then
                row:SetAlpha(0)
                row.invite:SetAlpha(0)
                row.invite:Hide()
                UI.SetCombatDisplayOnly(row, false)
                row:Hide()
            else
                row:SetAlpha(alpha)
                row:Show()
                row:SetAlpha(alpha)
                if showInvite then
                    row.invite:Show()
                    row.invite:SetAlpha(alpha)
                else
                    row.invite:Hide()
                    row.invite:SetAlpha(0)
                end
            end
        else
            row.key = nil
            row.invite.key = nil
            if not locked then
                UI.ApplyInvite(row.invite, nil)
                UI.ApplyTarget(row, nil)
            end
            UI.SetCombatDisplayOnly(row, false)
            UI.PaintRowIdentity(row, nil)
            row.invite:SetAlpha(0)
            row.invite:Hide()
            row:SetAlpha(0)
            row:PaintTarget(false)
            row:Hide()
        end
    end

    UI.PaintListTabs(nearCount, #zoneList)
    if #ordered == 0 then
        if listTab == "zone" then
            S.main.empty:SetText(C.EMPTY_ZONE or "No one else listed in this zone yet.")
        else
            S.main.empty:SetText(C.EMPTY_NEARBY or "No one nearby")
        end
        S.main.empty:Show()
    else
        S.main.empty:Hide()
    end

    local maxOffset = math.max(0, #ordered - visible)
    S.main.bar.lock = true
    if maxOffset <= 0 then
        S.main.bar:Hide()
        S.main.bar:SetMinMaxValues(0, 1)
        S.main.bar:SetValue(0)
    else
        S.main.bar:Show()
        S.main.bar:SetMinMaxValues(0, maxOffset)
        S.main.bar:SetValue(S.main.scrollOffset or 0)
    end
    S.main.bar.lock = false

    if GameTooltip:IsShown() and S.main.rows then
        local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
        local ours = false
        if owner then
            for _, row in ipairs(S.main.rows) do
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
                    S.tipToken = S.tipToken + 1
                    GameTooltip:Hide()
                end
            elseif row:IsShown() and row:IsMouseOver() and row.key then
                UI.ShowTip(row, row.key)
            else
                S.tipToken = S.tipToken + 1
                GameTooltip:Hide()
            end
        end
    end
    if UI.AnimActive() then
        UI.KickAnimUpdate()
    end
    S.main.fadingPaint = false
    -- A refresh was requested while this paint was running — run one more pass.
    if S.listDirty and not S.listFrozen then
        S.listDirty = false
        C_Timer.After(0, function()
            if S.listFrozen or not UI.RefreshList then
                if S.listFrozen then
                    S.listDirty = true
                end
                return
            end
            UI.RefreshList()
        end)
    end
end

function UI.BuildMenu()
    S.menu = CreateFrame("Frame", "SocialForeverMenu", UIParent, "BackdropTemplate")
    S.menu:SetSize(214, 120)
    S.menu:SetFrameStrata("DIALOG")
    S.menu:SetClampedToScreen(true)
    S.menu:EnableMouse(true)
    S.menu:Hide()
    UI.Chrome(S.menu)
    S.menu.buttons = {}
    S.menu.used = 0

    local edit = CreateFrame("EditBox", nil, S.menu, "BackdropTemplate")
    edit:SetSize(132, 18)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(24)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetTextInsets(4, 4, 0, 0)
    edit:SetBackdrop(C.FLAT_BACKDROP)
    edit:SetBackdropColor(0, 0, 0, 0.55)
    edit:SetBackdropBorderColor(0.45, 0.38, 0.16, 0.9)
    S.menu.edit = edit

    local hint = edit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 5, 0)
    hint:SetText("New flag")
    edit:SetScript("OnTextChanged", function(self)
        hint:SetShown(self:GetText() == "")
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        S.menu:Hide()
    end)
    edit:SetScript("OnEnterPressed", function(self)
        local key = S.menu.key
        local text = self:GetText()
        self:SetText("")
        self:ClearFocus()
        if key then
            Memory.AddCustomFlag(key, text)
        end
    end)

    local add = UI.FlatButton(S.menu, "Add", 46, 18)
    S.menu.add = add
    add:SetScript("OnClick", function()
        local key = S.menu.key
        local text = edit:GetText()
        edit:SetText("")
        edit:ClearFocus()
        if key then
            Memory.AddCustomFlag(key, text)
        end
    end)

    S.menu:SetScript("OnHide", function()
        edit:ClearFocus()
    end)
    S.menu:SetScript("OnShow", function(self)
        self.seenUp = false
    end)
    S.menu:SetScript("OnHide", function()
        -- Menu often sits over the list; re-check freeze so normal updates resume.
        UI.NoteListLeave()
    end)
    S.menu:SetScript("OnUpdate", function(self)
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

function UI.MenuButton()
    S.menu.used = S.menu.used + 1
    local button = S.menu.buttons[S.menu.used]
    if not button then
        button = CreateFrame("Button", nil, S.menu)
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
        S.menu.buttons[S.menu.used] = button
    end
    button:Show()
    return button
end

function UI.PlaceMenu(keepPlace)
    if keepPlace and S.menu.placed then
        return
    end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if scale and scale > 0 then
        x, y = x / scale, y / scale
    end
    local width, height = S.menu:GetWidth(), S.menu:GetHeight()
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
    S.menu:ClearAllPoints()
    S.menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    S.menu.placed = true
end

function UI.OpenMenu(key, keepPlace)
    key = Util.SafeKey(key)
    if not key or not S.menu then
        return
    end
    if S.settingsMenu then
        S.settingsMenu:Hide()
    end
    S.menu.key = key
    S.menu.used = 0
    local y = -8

    local function addLabel(text, r, g, b, onClick)
        local button = UI.MenuButton()
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", S.menu, "TOPLEFT", 8, y)
        button.label:SetText(text)
        button.baseR, button.baseG, button.baseB = r, g, b
        button.label:SetTextColor(r, g, b)
        button.clickable = onClick ~= nil
        button:SetScript("OnClick", onClick)
        button:EnableMouse(onClick ~= nil)
        y = y - 18
    end

    addLabel(UI.SpokenName(key), 1, 0.82, 0.25, nil)
    y = y - 4
    addLabel("Mark", 0.85, 0.75, 0.4, nil)
    local mine = SF.db.players[key]
    local myColor = type(mine) == "table" and Util.ValidColor(mine.color)
    for _, color in ipairs({ "green", "yellow", "red" }) do
        local rgb = C.COLOR_RGB[color]
        local prefix = myColor == color and "> " or "  "
        addLabel(prefix .. C.COLOR_LABEL[color], rgb[1], rgb[2], rgb[3], function()
            Memory.SetColor(key, color)
            UI.OpenMenu(key, true)
        end)
    end
    addLabel("  Clear mark", 0.6, 0.6, 0.6, function()
        Memory.SetColor(key, nil)
        UI.OpenMenu(key, true)
    end)

    y = y - 4
    addLabel("Flags", 0.85, 0.75, 0.4, nil)
    for _, flag in ipairs(Memory.AllFlags()) do
        local on = Memory.PlayerHasFlag(key, flag)
        local prefix = on and "[x] " or "[ ] "
        addLabel(prefix .. flag, 0.75, 0.85, 1, function()
            Memory.ToggleFlag(key, flag)
        end)
    end

    y = y - 8
    S.menu.edit:ClearAllPoints()
    S.menu.edit:SetPoint("TOPLEFT", S.menu, "TOPLEFT", 8, y)
    S.menu.add:ClearAllPoints()
    S.menu.add:SetPoint("LEFT", S.menu.edit, "RIGHT", 6, 0)
    y = y - 26

    y = y - 8
    local kos = Memory.FlaggedKos(key)
    addLabel(kos and "> Kill on sight" or "Kill on sight", 1, 0.35, 0.3, function()
        Memory.ToggleKos(key)
        UI.OpenMenu(key, true)
    end)

    for i = S.menu.used + 1, #S.menu.buttons do
        S.menu.buttons[i]:Hide()
    end
    S.menu:SetHeight(-y + 8)
    if not keepPlace then
        S.menu.placed = false
    end
    S.menu:Show()
    UI.PlaceMenu(keepPlace)
end

function UI.PaintChoice(row)
    local colors = { green = "Again", yellow = "Okay", red = "Bad" }
    local order = { "green", "yellow", "red" }
    for _, color in ipairs(order) do
        local button = row[color]
        local tint = C.COLOR_RGB[color]
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
            UI.PaintChoice(row)
        end
    end
end

function UI.AllChosen()
    for _, row in ipairs(S.popup.rows) do
        if row:IsShown() and not row.choice then
            return false
        end
    end
    return true
end

function UI.BuildPopup()
    S.popup = CreateFrame("Frame", "SocialForeverRateFrame", UIParent, "BackdropTemplate")
    S.popup:SetSize(340, 120)
    S.popup:SetFrameStrata("HIGH")
    S.popup:SetClampedToScreen(true)
    S.popup:SetMovable(true)
    S.popup:EnableMouse(true)
    S.popup:Hide()
    UI.Chrome(S.popup)

    local drag = CreateFrame("Button", nil, S.popup)
    drag:SetPoint("TOPLEFT", 8, -4)
    drag:SetPoint("TOPRIGHT", -24, -4)
    drag:SetHeight(20)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            return
        end
        S.popup:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        S.popup:StopMovingOrSizing()
    end)

    local title = S.popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -8)
    title:SetText("How was this group?")
    title:SetTextColor(1, 0.82, 0.25)
    S.popup.title = title

    local close = CreateFrame("Button", nil, S.popup)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -6, -5)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    closeText:SetPoint("CENTER")
    closeText:SetText("x")
    close:SetScript("OnClick", function()
        S.popup:Hide()
    end)

    S.popup.rows = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, S.popup)
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
            local button = UI.FlatButton(row, label, 56, 18)
            button:SetPoint("TOPLEFT", x, -8)
            button.color = color
            button:SetScript("OnClick", function(self)
                if not row.key then
                    return
                end
                row.choice = self.color
                Memory.SetColor(row.key, self.color)
                UI.PaintChoice(row)
                if UI.AllChosen() then
                    C_Timer.After(0.35, function()
                        if S.popup:IsShown() and UI.AllChosen() then
                            S.popup:Hide()
                        end
                    end)
                end
            end)
            row[color] = button
            x = x + 60
        end
        row:Hide()
        S.popup.rows[i] = row
    end

    local done = UI.FlatButton(S.popup, "Done", 64, 18)
    done:SetPoint("BOTTOM", 0, 10)
    done:SetScript("OnClick", function()
        S.popup:Hide()
    end)

    function S.popup:Anchor()
        self:ClearAllPoints()
        if S.main:IsShown() then
            local left = S.main:GetLeft() or 0
            if left > self:GetWidth() + 16 then
                self:SetPoint("TOPRIGHT", S.main, "TOPLEFT", -8, 0)
            else
                self:SetPoint("TOPLEFT", S.main, "TOPRIGHT", 8, 0)
            end
        elseif ChatFrame1 then
            self:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 30)
        else
            self:SetPoint("CENTER")
        end
    end

    tinsert(UISpecialFrames, "SocialForeverRateFrame")
end

function UI.BuildSameMobPopup()
    local frame = CreateFrame("Frame", "SocialForeverSameMobFrame", UIParent, "BackdropTemplate")
    frame:SetSize(320, 110)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    UI.Chrome(frame)
    S.sameMobPopup = frame

    local drag = CreateFrame("Button", nil, frame)
    drag:SetPoint("TOPLEFT", 8, -4)
    drag:SetPoint("TOPRIGHT", -28, -4)
    drag:SetHeight(18)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -8)
    title:SetPoint("RIGHT", -28, 0)
    title:SetJustifyH("LEFT")
    title:SetText("Same fight")
    title:SetTextColor(1, 0.82, 0.25)
    frame.title = title

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -6, -5)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    closeText:SetPoint("CENTER")
    closeText:SetText("x")
    close:SetScript("OnClick", function()
        if frame.key then
            Detection.MarkSameMobCooldown(frame.key)
        end
        wipe(S.sameMobQueue)
        frame.key = nil
        frame:Hide()
        if not InCombatLockdown() then
            UI.ApplyInvite(frame.invite, nil)
        end
    end)

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", 12, -30)
    body:SetPoint("RIGHT", -12, 0)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)
    body:SetTextColor(0.9, 0.9, 0.85)
    frame.body = body

    local invite = UI.FlatButton(frame, "Invite", 88, 20, true)
    invite:SetPoint("BOTTOMLEFT", 16, 12)
    invite:RegisterForClicks("LeftButtonDown")
    invite:SetAttribute("useOnKeyDown", true)
    invite.Paint = function(self)
        self:SetBackdropColor(0.1, 0.16, 0.1, 1)
        self:SetBackdropBorderColor(0.3, 0.7, 0.35, 1)
        self.label:SetTextColor(0.55, 1, 0.62)
    end
    invite:Paint()
    invite:SetScript("PostClick", function(self)
        local key = frame.key
        if key then
            Detection.MarkSameMobCooldown(key)
            S.inviteState[key] = "invited"
            if UI.RefreshList then
                UI.RefreshList()
            end
        end
        UI.DismissSameMobPrompt(true)
    end)
    frame.invite = invite

    local noThanks = UI.FlatButton(frame, "No thanks", 88, 20)
    noThanks:SetPoint("LEFT", invite, "RIGHT", 10, 0)
    noThanks:SetScript("OnClick", function()
        UI.DismissSameMobPrompt(false)
    end)
    frame.noThanks = noThanks

    function frame:Anchor()
        self:ClearAllPoints()
        if S.main and S.main:IsShown() then
            local left = S.main:GetLeft() or 0
            if left > self:GetWidth() + 16 then
                self:SetPoint("TOPRIGHT", S.main, "TOPLEFT", -8, 0)
            else
                self:SetPoint("TOPLEFT", S.main, "TOPRIGHT", 8, 0)
            end
        elseif ChatFrame1 then
            self:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 60)
        else
            self:SetPoint("CENTER")
        end
    end

    tinsert(UISpecialFrames, "SocialForeverSameMobFrame")
end

function UI.DismissSameMobPrompt(accepted)
    local frame = S.sameMobPopup
    local key = frame and frame.key
    if key and not accepted then
        Detection.MarkSameMobCooldown(key)
    end
    if frame then
        frame.key = nil
        frame.mob = nil
        frame:Hide()
        if not InCombatLockdown() then
            UI.ApplyInvite(frame.invite, nil)
        end
    end
    if accepted or (key and not accepted) then
        -- Continue with remaining candidates after a beat.
        C_Timer.After(0.15, function()
            if UI.ShowSameMobPrompt then
                UI.ShowSameMobPrompt()
            end
        end)
    end
end

function UI.ShowSameMobPrompt()
    if InCombatLockdown() then
        return
    end
    if not S.sameMobPopup then
        return
    end
    if S.sameMobPopup:IsShown() then
        return
    end
    if not Group.PartyHasRoom() then
        wipe(S.sameMobQueue)
        return
    end
    while #S.sameMobQueue > 0 do
        local cand = table.remove(S.sameMobQueue, 1)
        if cand and cand.key and Detection.SameMobEligible(cand.key, cand) then
            local spoken = UI.SpokenName(cand.key) or cand.key
            local mob = cand.mob or "the same mob"
            S.sameMobPopup.key = cand.key
            S.sameMobPopup.mob = mob
            S.sameMobPopup.body:SetText(spoken .. " was fighting the same " .. mob .. ".\nGroup up?")
            UI.ApplyInvite(S.sameMobPopup.invite, cand.key)
            S.sameMobPopup:Show()
            S.sameMobPopup:Raise()
            if S.sameMobPopup.Anchor then
                S.sameMobPopup:Anchor()
            end
            return
        end
    end
end
