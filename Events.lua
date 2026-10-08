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

SF.UI.BuildMain()
SF.UI.BuildMenu()
SF.UI.BuildPopup()
SF.UI.BuildSameMobPopup()

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
events:RegisterEvent("PLAYER_REGEN_DISABLED")

function SF.Events.Listen(name)
    pcall(events.RegisterEvent, events, name)
end

SF.Events.Listen("PLAYER_FOCUS_CHANGED")
SF.Events.Listen("PLAYER_SOFT_ENEMY_CHANGED")
SF.Events.Listen("PLAYER_SOFT_FRIEND_CHANGED")
SF.Events.Listen("PLAYER_SOFT_INTERACT_CHANGED")
SF.Events.Listen("CHAT_MSG_TRADESKILLS")
SF.Events.Listen("CHAT_MSG_SKILL")
SF.Events.Listen("CHAT_MSG_OPENING")
SF.Events.Listen("CHAT_MSG_PET_INFO")
SF.Events.Listen("CHAT_MSG_LOOT")
SF.Events.Listen("CHAT_MSG_COMBAT_HONOR_GAIN")
SF.Events.Listen("CHAT_MSG_COMBAT_MISC_INFO")
SF.Events.Listen("CHAT_MSG_CHANNEL")
SF.Events.Listen("CHAT_MSG_YELL")
SF.Events.Listen("FRIENDLIST_UPDATE")
SF.Events.Listen("NAME_PLATE_UNIT_ADDED")
SF.Events.Listen("NAME_PLATE_UNIT_REMOVED")
SF.Events.Listen("UNIT_AURA")
SF.Events.Listen("CHANNEL_ROSTER_UPDATE")
SF.Events.Listen("CHANNEL_COUNT_UPDATE")
SF.Events.Listen("PARTY_INVITE_REQUEST")
SF.Events.Listen("RESURRECT_REQUEST")
SF.Events.Listen("DAMAGE_METER_CURRENT_SESSION_UPDATED")
SF.Events.Listen("DAMAGE_METER_COMBAT_SESSION_UPDATED")
if events.RegisterUnitEvent then
    pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
end

events:SetScript("OnEvent", function(_, event, ...)
    local arg1, arg2, arg3, arg4 = ...
    if event == "ADDON_LOADED" and arg1 == C.ADDON then
        Util.InitDB()
        return
    end
    if not SF.db then
        return
    end
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(C.PREFIX)
        end
        S.sendReady = true
        UI.PositionMain()
        UI.ApplyBackground()
        if S.main.settings and S.main.settings.Paint then
            S.main.settings:Paint()
        end
        if not SF.db.hidden then
            S.main:Show()
        end
        if C_FriendList and C_FriendList.ShowFriends then
            pcall(C_FriendList.ShowFriends)
        end
        Group.RefreshFriends()
        Group.RebuildGroupMembers()
        Detection.SyncRaidTicker()
        Detection.Scan()
        Group.RefreshRoster()
        C_Timer.After(2, Group.Arm)
        C_Timer.After(3, function()
            Detection.RequestGeneralRoster(true)
        end)
        C_Timer.NewTicker(0.5, Detection.Scan)
        C_Timer.NewTicker(5, Detection.ValidatePresence)
        C_Timer.NewTicker(3, Detection.ScanCombatLog)
        C_Timer.NewTicker(0.25, Sharing.Pump)
        C_Timer.NewTicker(45, Sharing.ShareTick)
        C_Timer.NewTicker(60, function()
            Detection.RequestGeneralRoster(true)
        end)
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        S.armed = false
        Detection.ClearSightings()
        S.nearby = {}
        UI.RefreshList()
        Group.RebuildGroupMembers()
        Detection.SyncRaidTicker()
        Group.RefreshRoster()
        C_Timer.After(2, Group.Arm)
        C_Timer.After(3, function()
            Detection.RequestGeneralRoster(true)
        end)
        return
    end
    if event == "CHAT_MSG_CHANNEL" then
        Detection.NoteZone(arg2, arg4, select(9, ...), select(12, ...))
        return
    end
    if event == "CHAT_MSG_YELL" then
        Detection.NoteZoneWeak(arg2, select(12, ...))
        return
    end
    if event == "CHAT_MSG_SAY" or event == "CHAT_MSG_EMOTE" or event == "CHAT_MSG_TEXT_EMOTE" then
        Detection.NoteChat(arg2, select(12, ...))
        return
    end
    if event == "CHAT_MSG_TRADESKILLS" or event == "CHAT_MSG_SKILL" then
        Detection.NoteActivity(arg1, arg2, true)
        return
    end
    if event == "CHAT_MSG_OPENING"
        or event == "CHAT_MSG_LOOT"
        or event == "CHAT_MSG_COMBAT_HONOR_GAIN"
    then
        Detection.NoteActivity(arg1, arg2, false)
        return
    end
    if event == "CHAT_MSG_PET_INFO" or event == "CHAT_MSG_COMBAT_MISC_INFO" then
        Detection.NoteActivity(arg1, nil, false)
        return
    end
    if event == "FRIENDLIST_UPDATE" then
        Group.RefreshFriends()
        Detection.Publish()
        return
    end
    if event == "DUEL_REQUESTED" or event == "TRADE_REQUEST" then
        Detection.NoteNamed(arg1, 1, C.CHAT_TTL)
        return
    end
    if event == "PARTY_INVITE_REQUEST" then
        Detection.NoteZoneWeak(arg1, arg2)
        return
    end
    if event == "RESURRECT_REQUEST" then
        Detection.NoteNearbyNamed(arg1, arg2)
        return
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        Detection.OnNameplateAdded(arg1)
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        Detection.OnNameplateRemoved(arg1)
        return
    end
    if event == "UNIT_AURA" then
        Detection.OnPlayerAura(arg1, arg2)
        return
    end
    if event == "CHANNEL_ROSTER_UPDATE" or event == "CHANNEL_COUNT_UPDATE" then
        Detection.RequestGeneralRoster(false)
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
        Detection.Scan()
        return
    end
    if event == "GROUP_ROSTER_UPDATE" or event == "GROUP_LEFT" then
        Group.RefreshRoster()
        return
    end
    if event == "CHAT_MSG_SYSTEM" then
        UI.NoteDecline(arg1)
        return
    end
    if event == "CHAT_MSG_ADDON" then
        Sharing.OnAddon(arg1, arg2, arg3, arg4)
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        S.P.combatGen = S.P.combatGen + 1
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        Detection.Scan()
        Detection.QueueDamageMeterHarvest()
        return
    end
    if event == "DAMAGE_METER_CURRENT_SESSION_UPDATED"
        or event == "DAMAGE_METER_COMBAT_SESSION_UPDATED"
    then
        if not InCombatLockdown() then
            Detection.QueueDamageMeterHarvest()
        end
    end
end)

function SocialForever_CompartmentClick()
    if not S.main then
        return
    end
    if S.main:IsShown() then
        UI.HideMain()
    else
        UI.ShowMain()
    end
end

SLASH_SOCIALFOREVER1 = "/sf"
SLASH_SOCIALFOREVER2 = "/socialforever"
SlashCmdList.SOCIALFOREVER = function(msg)
    msg = Util.Trim(msg):lower()
    if msg == "hide" then
        UI.HideMain()
    elseif msg == "show" then
        UI.ShowMain()
    elseif S.main:IsShown() then
        UI.HideMain()
    else
        UI.ShowMain()
    end
end
