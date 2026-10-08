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

function Group.PartyKeys()
    local list = {}
    for i = 1, 4 do
        local unit = "party" .. i
        local ok, exists = pcall(UnitExists, unit)
        if ok and Util.PlainBool(exists) and Detection.UnitConnectedPlain(unit) ~= false then
            local key = Util.UnitIdentity(unit)
            if key and not Util.IsMe(key) then
                list[#list + 1] = key
            end
        end
    end
    return list
end

function Group.RebuildGroupMembers()
    wipe(S.P.groupByKey)
    wipe(S.P.groupByNorm)
    local function addUnit(unit)
        local ok, exists = pcall(UnitExists, unit)
        if not ok or Util.PlainBool(exists) ~= true then
            return
        end
        if Detection.UnitConnectedPlain(unit) == false then
            return
        end
        local key = Util.UnitIdentity(unit)
        if not key or Util.IsMe(key) then
            return
        end
        S.P.groupByKey[key] = true
        local norm = key:gsub("[%s%-]+", ""):lower()
        S.P.groupByNorm[norm] = true
    end
    local raidOk, inRaid = pcall(IsInRaid)
    if raidOk and Util.PlainBool(inRaid) == true then
        for i = 1, 40 do
            addUnit("raid" .. i)
        end
        return
    end
    local groupOk, inGroup = pcall(IsInGroup)
    if groupOk and Util.PlainBool(inGroup) == true then
        for i = 1, 4 do
            addUnit("party" .. i)
        end
    end
end

Group.InMyGroup = function(key)
    if not key then
        return false
    end
    if S.P.groupByKey[key] then
        return true
    end
    local norm = key:gsub("[%s%-]+", ""):lower()
    return S.P.groupByNorm[norm] == true
end

function Group.RefreshFriends()
    wipe(S.friendNames)
    if not (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex) then
        return
    end
    local ok, count = pcall(C_FriendList.GetNumFriends)
    count = ok and Util.PlainNumber(count) or nil
    if not count or count < 1 then
        return
    end
    if count > 200 then
        count = 200
    end
    for i = 1, count do
        local infoOk, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
        if infoOk then
            local name = type(info) == "table" and Util.PlainString(info.name) or Util.PlainString(info)
            if name then
                S.friendNames[name] = true
                local short = name:match("^([^%-]+)")
                if short and short ~= name then
                    S.friendNames[short] = true
                end
            end
        end
    end
end

function Group.FriendsAutoOn()
    return SF.db and SF.db.autoInviteFriends ~= false
end

function Group.NoteGroupButtons(members)
    local nowIn = {}
    for _, key in ipairs(members) do
        nowIn[key] = true
        S.inviteState[key] = nil
    end
    for key in pairs(S.groupedBefore) do
        if not nowIn[key] and S.inviteState[key] ~= "declined" then
            S.inviteState[key] = nil
        end
    end
    wipe(S.groupedBefore)
    for key in pairs(nowIn) do
        S.groupedBefore[key] = true
    end
end

function Group.GroupState()
    local okG, grouped = pcall(IsInGroup)
    local okR, raid = pcall(IsInRaid)
    if not okG or not okR then
        return nil
    end
    grouped = Util.PlainBool(grouped)
    raid = Util.PlainBool(raid)
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

function Group.EndPartySession()
    SF.db.partyId = nil
    SF.db.partyCounted = nil
end

function Group.NoteMembers(members)
    if not SF.db.partyId then
        SF.db.nextPartyId = (tonumber(SF.db.nextPartyId) or 0) + 1
        SF.db.partyId = SF.db.nextPartyId
        SF.db.partyCounted = {}
    end
    if type(SF.db.partyCounted) ~= "table" then
        SF.db.partyCounted = {}
    end
    for _, key in ipairs(members) do
        if not SF.db.partyCounted[key] then
            SF.db.partyCounted[key] = true
            local rec = Memory.EnsurePlayer(key)
            rec.groups = (tonumber(rec.groups) or 0) + 1
        end
    end
    S.lastMembers = members
end

function Group.CopyMembers(members)
    local copy = {}
    for i = 1, math.min(4, #members) do
        copy[i] = members[i]
    end
    return copy
end

function Group.PlayTick()
    local kit = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
    if kit then
        pcall(PlaySound, kit)
    end
end

function Group.ShowRatePopup(members)
    if not S.armed or not S.popup then
        return
    end
    local list = {}
    local seen = {}
    for _, key in ipairs(members) do
        key = Util.SafeKey(key)
        if key and not Util.IsMe(key) and not seen[key] then
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
    if sig == S.lastPopupSig and now - S.lastPopupAt < 3 then
        return
    end
    S.lastPopupSig = sig
    S.lastPopupAt = now

    S.popup.title:SetText(#list == 1 and "How was this player?" or "How was this group?")
    for i = 1, 4 do
        local row = S.popup.rows[i]
        local key = list[i]
        if key then
            row.key = key
            row.choice = nil
            row.name:SetText(UI.SpokenName(key))
            row.sub:SetText(Memory.HistoryLine(key))
            if UI.PaintChoice then
                UI.PaintChoice(row)
            end
            row:Show()
        else
            row.key = nil
            row:Hide()
        end
    end
    S.popup:SetHeight(46 + #list * 44 + 34)
    S.popup:Show()
    S.popup:Raise()
    C_Timer.After(0, function()
        if S.popup:IsShown() and S.popup.Anchor then
            S.popup:Anchor()
        end
    end)
    Group.PlayTick()
end

function Group.RefreshRoster()
    if not SF.db then
        return
    end
    Group.RebuildGroupMembers()
    Detection.SyncRaidTicker()
    local state = Group.GroupState()
    if state == nil then
        return
    end
    if state == "party" then
        Group.NoteGroupButtons(Group.PartyKeys())
    elseif state == "solo" then
        Group.NoteGroupButtons({})
    end
    if state == "party" then
        local members = Group.PartyKeys()
        if S.wasParty then
            local still = {}
            for _, key in ipairs(members) do
                still[key] = true
            end
            local left = {}
            for _, key in ipairs(S.lastMembers) do
                if not still[key] then
                    left[#left + 1] = key
                end
            end
            if #left > 0 then
                Group.ShowRatePopup(left)
            end
        end
        if #members > 0 then
            Group.NoteMembers(members)
        end
        S.wasParty = true
        Detection.Publish()
        return
    end
    if not S.armed then
        return
    end
    if S.wasParty and state == "solo" then
        local members = Group.CopyMembers(S.lastMembers)
        S.wasParty = false
        S.lastMembers = {}
        Group.EndPartySession()
        Group.ShowRatePopup(members)
    else
        S.wasParty = false
        S.lastMembers = {}
        Group.EndPartySession()
    end
    Detection.Publish()
end

function Group.Arm()
    S.armed = true
    if not S.wasParty then
        local state = Group.GroupState()
        if state == "solo" or state == "raid" or state == nil then
            Group.EndPartySession()
        end
    end
end

function Group.PartyHasRoom()
    local state = Group.GroupState()
    if state == "raid" then
        local ok, n = pcall(GetNumGroupMembers)
        n = ok and Util.PlainNumber(n) or nil
        return n ~= nil and n < 40
    end
    if state == "party" then
        local ok, n = pcall(GetNumGroupMembers)
        n = ok and Util.PlainNumber(n) or nil
        return n ~= nil and n < 5
    end
    return true
end

-- Direct invite when Forever allows it. Returns true on accepted call.
-- Sets S.P.sameMobApiInvite to false if the client rejects automation.
function Group.InviteByKey(key)
    key = Util.SafeKey(key)
    if not key or InCombatLockdown() then
        return false
    end
    if Group.InMyGroup(key) or Memory.IsBlocked(key) or Memory.FlaggedKos(key) then
        return false
    end
    if Util.IsOtherFaction(key) then
        return false
    end
    if not Group.PartyHasRoom() then
        return false
    end
    if S.P.sameMobApiInvite == false then
        return false
    end
    local name = UI.SlashName and UI.SlashName(key) or nil
    if not name then
        return false
    end
    if C_PartyInfo and type(C_PartyInfo.InviteUnit) == "function" then
        local ok = pcall(C_PartyInfo.InviteUnit, name)
        if ok then
            S.P.sameMobApiInvite = true
            S.inviteState[key] = "invited"
            return true
        end
    end
    if type(InviteUnit) == "function" then
        local ok = pcall(InviteUnit, name)
        if ok then
            S.P.sameMobApiInvite = true
            S.inviteState[key] = "invited"
            return true
        end
    end
    S.P.sameMobApiInvite = false
    return false
end

function Group.SameMobAskOn()
    return SF.db and SF.db.sameMobAsk == true
end

function Group.SameMobAutoOn()
    return SF.db and SF.db.sameMobAutoInvite == true
end

function Group.SetSameMobAsk(on)
    if not SF.db then
        return
    end
    if on then
        SF.db.sameMobAsk = true
        SF.db.sameMobAutoInvite = false
    else
        SF.db.sameMobAsk = false
    end
end

function Group.SetSameMobAuto(on)
    if not SF.db then
        return
    end
    if on then
        SF.db.sameMobAutoInvite = true
        SF.db.sameMobAsk = false
    else
        SF.db.sameMobAutoInvite = false
    end
end
