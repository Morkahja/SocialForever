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

function Sharing.CanWhisperTarget(target)
    if type(target) ~= "string" or target == "" or Util.Secret(target) then
        return false
    end
    if target:find("%s") then
        return false
    end
    local mine = Util.MyRealm()
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

function Sharing.MaybeHello(key)
    if not S.sendReady or not S.main:IsShown() then
        return
    end
    if not Sharing.CanWhisperTarget(key) then
        return
    end
    local now = GetTime()
    if S.helloAt[key] and now - S.helloAt[key] < C.HELLO_GAP then
        return
    end
    S.helloAt[key] = now
    if #S.queue < 80 then
        S.queue[#S.queue + 1] = { target = key, msg = "H1" }
    end
end

function Sharing.NoteEmpty(note)
    if Util.ValidColor(note.color) or Util.ValidStars(note.stars) then
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

function Sharing.Encode(subject, note, origin)
    local flags = {}
    if type(note.flags) == "table" then
        for flag, on in pairs(note.flags) do
            flag = Memory.SanitizeFlag(flag)
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
        local color = C.COLOR_WIRE[Util.ValidColor(note.color)] or "-"
        local stars = Util.ValidStars(note.stars) or 0
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

function Sharing.Enqueue(target, msg)
    if not S.sendReady or type(target) ~= "string" or type(msg) ~= "string" then
        return
    end
    if not Sharing.CanWhisperTarget(target) then
        return
    end
    if #msg > 250 or #S.queue >= 80 then
        return
    end
    S.queue[#S.queue + 1] = { target = target, msg = msg }
end

function Sharing.NearbyPeerList()
    local list = {}
    for key in pairs(S.nearby) do
        if S.peers[key] then
            list[#list + 1] = key
        end
    end
    table.sort(list)
    return list
end

function Sharing.SubjectsToShare()
    local list = {}
    local seen = {}
    local function add(key)
        key = Util.SafeKey(key)
        if not key or seen[key] or #list >= C.MAX_SHARE then
            return
        end
        local mine = SF.db.players[key]
        local remote = SF.db.remote[key]
        local anyRemote = false
        if type(remote) == "table" then
            for _, note in pairs(remote) do
                if type(note) == "table" and not Sharing.NoteEmpty(note) then
                    anyRemote = true
                    break
                end
            end
        end
        local touched = type(mine) == "table" and tonumber(mine.updated)
        if Memory.HasOpinion(mine) or anyRemote or touched then
            seen[key] = true
            list[#list + 1] = key
        end
    end
    for key in pairs(S.nearby) do
        add(key)
    end
    local extra = {}
    for key, rec in pairs(SF.db.players) do
        -- updated is set when a mark changes, including a clear, so a
        -- removed mark is still sent and other copies can drop it.
        if Memory.HasOpinion(rec) or tonumber(rec.updated) then
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

function Sharing.MessagesFor(subject)
    local messages = {}
    local me = Util.MyKey()
    local mine = SF.db.players[subject]
    if type(mine) == "table" and me then
        local msg = Sharing.Encode(subject, mine, me)
        if msg then
            messages[#messages + 1] = msg
        end
    end
    local remote = SF.db.remote[subject]
    if type(remote) == "table" then
        local relayed = 0
        for origin, note in pairs(remote) do
            if relayed >= 2 then
                break
            end
            origin = Util.SafeKey(origin)
            if origin and origin ~= me and type(note) == "table" and not Sharing.NoteEmpty(note) then
                local msg = Sharing.Encode(subject, note, origin)
                if msg then
                    messages[#messages + 1] = msg
                    relayed = relayed + 1
                end
            end
        end
    end
    return messages
end

function Sharing.PushRelevant(peer, force)
    peer = Util.SafeKey(peer)
    if not peer then
        return
    end
    local now = GetTime()
    if not force and S.pushedAt[peer] and now - S.pushedAt[peer] < 15 then
        return
    end
    S.pushedAt[peer] = now
    local sent = 0
    for _, subject in ipairs(Sharing.SubjectsToShare()) do
        for _, msg in ipairs(Sharing.MessagesFor(subject)) do
            if sent >= 12 then
                return
            end
            Sharing.Enqueue(peer, msg)
            sent = sent + 1
        end
    end
end

function Sharing.ShareSubject(key)
    local me = Util.MyKey()
    local mine = SF.db.players[key]
    if not me or type(mine) ~= "table" then
        return
    end
    local msg = Sharing.Encode(key, mine, me)
    if not msg then
        return
    end
    for _, peer in ipairs(Sharing.NearbyPeerList()) do
        Sharing.Enqueue(peer, msg)
    end
end

function Sharing.CapOrigins(subject)
    local bucket = SF.db.remote[subject]
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
    if #list <= C.MAX_ORIGINS then
        return
    end
    table.sort(list, function(a, b)
        return a.at < b.at
    end)
    for i = 1, #list - C.MAX_ORIGINS do
        bucket[list[i].origin] = nil
    end
end

function Sharing.StoreRemote(sender, msg)
    local _, subject, colorCode, stars, flagText, origin = strsplit("\t", msg)
    subject = Util.SafeKey(subject)
    origin = Util.SafeKey(origin) or sender
    local me = Util.MyKey()
    if not subject or not origin or origin == me or subject == me or subject == origin then
        return
    end
    local note = {
        color = C.WIRE_COLOR[colorCode],
        stars = Util.ValidStars(stars),
        flags = {},
        at = Util.Now(),
    }
    if type(flagText) == "string" and flagText ~= "" then
        local flags = { strsplit(",", flagText) }
        local count = 0
        for _, flag in ipairs(flags) do
            flag = Memory.SanitizeFlag(flag)
            if flag then
                note.flags[flag] = true
                count = count + 1
                if count >= 8 then
                    break
                end
            end
        end
    end
    if type(SF.db.remote[subject]) ~= "table" then
        SF.db.remote[subject] = {}
    end
    if Sharing.NoteEmpty(note) then
        SF.db.remote[subject][origin] = nil
    else
        SF.db.remote[subject][origin] = note
        Sharing.CapOrigins(subject)
    end
    if UI.RefreshList then
        UI.RefreshList()
    end
end

function Sharing.OnAddon(prefix, msg, channel, sender)
    if prefix ~= C.PREFIX or channel ~= "WHISPER" or type(msg) ~= "string" then
        return
    end
    local name, realm = strsplit("-", sender or "", 2)
    local senderKey = Util.MakeKey(name, realm)
    if not senderKey or Util.IsMe(senderKey) then
        return
    end
    S.peers[senderKey] = GetTime()
    if msg == "H1" then
        local now = GetTime()
        if not S.helloReplyAt[senderKey] or now - S.helloReplyAt[senderKey] > 20 then
            S.helloReplyAt[senderKey] = now
            Sharing.Enqueue(senderKey, "H1")
        end
        Sharing.PushRelevant(senderKey, false)
        return
    end
    if msg:sub(1, 2) == "D\t" then
        Sharing.StoreRemote(senderKey, msg)
    end
end

function Sharing.Pump()
    if not S.sendReady or #S.queue == 0 then
        return
    end
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
        wipe(S.queue)
        return
    end
    local item = table.remove(S.queue, 1)
    if not item or not Sharing.CanWhisperTarget(item.target) or type(item.msg) ~= "string" then
        return
    end
    pcall(C_ChatInfo.SendAddonMessage, C.PREFIX, item.msg, "WHISPER", item.target)
end

function Sharing.ShareTick()
    if InCombatLockdown() or not S.main or not S.main:IsShown() then
        return
    end
    local list = Sharing.NearbyPeerList()
    if #list == 0 then
        return
    end
    S.P.shareRotate = (S.P.shareRotate % #list) + 1
    Sharing.PushRelevant(list[S.P.shareRotate], false)
end
