--[[
Majong Masters 麻將大師
Author: 晓输童

AI module source code reference:
https://www.curseforge.com/wow/addons/majiang
Original author: shenmidigua2 神秘地瓜
]]

local ADDON_NAME, NS = ...
ADDON_NAME = ADDON_NAME or "MaJiang"
if type(NS) ~= "table" then
    NS = _G.MaJiangNS or {}
    _G.MaJiangNS = NS
end

local ADDON_PREFIX = "MJ120PVP"
local UI_TITLE = "Mahjong Masters"

local IMG_ROOT = "Interface\\AddOns\\MahJiang\\ui\\img\\"
local AUDIO_ROOT = "Interface\\AddOns\\MahJiang\\ui\\audio\\"
local NET_PROTO = 3
local NET_PACKET_MAX_BYTES = 240

local SEND_RESULT = (Enum and Enum.SendAddonMessageResult) or {
    Success = 0,
    InvalidPrefix = 1,
    InvalidMessage = 2,
    AddonMessageThrottle = 3,
    InvalidChatType = 4,
    NotInGroup = 5,
    TargetRequired = 6,
    InvalidChannel = 7,
    ChannelThrottle = 8,
    GeneralError = 9,
    NotInGuild = 10,
    AddOnMessageLockdown = 11,
    TargetOffline = 12,
}

local DB_DEFAULTS = {
    audio = {
        bgmEnabled = true,
        sfxEnabled = true,
        voiceGender = "woman", -- woman | man
    },
    ai = {
        difficulty = "advanced", -- beginner | advanced | expert | master
    },
    rules = {
        defaultRule = "guangdong", -- see modules/ruleset.lua (27 rules incl. international/japanese)
    },
    timer = {
        discardSec = 15,
        actionSec = 12,
        alarmLast3Sec = true,
    },
    history = {
        maxRecords = 200,
        records = {},
    },
    minimap = {
        hide = false,
        angle = 225,
    },
}

local MajongMastersDB
local I18N = assert(NS.I18N, "MaJiang module missing: modules/i18n.lua")
local Core = assert(NS.Core, "MaJiang module missing: modules/core_utils.lua")
local RuleSet = assert(NS.RuleSet, "MaJiang module missing: modules/ruleset.lua")
local Rules = assert(NS.Rules, "MaJiang module missing: modules/game_rules.lua")
local AI = assert(NS.AI, "MaJiang module missing: modules/ai_engine.lua")
local Scoring = assert(NS.Scoring, "MaJiang module missing: modules/scoring.lua")
local AddonAudioModule = assert(NS.AddonAudio, "MaJiang module missing: modules/addon_audio.lua")
local AddonResultOpsModule = assert(NS.AddonResultOps, "MaJiang module missing: modules/addon_result_ops.lua")
local AddonUIUtilsModule = assert(NS.AddonUIUtils, "MaJiang module missing: modules/addon_ui_utils.lua")
local STATE

local CloneTable = Core.CloneTable
local MergeDefaults = Core.MergeDefaults
local Split = Core.Split
local Join = Core.Join
local RemoveByValue = Core.RemoveByValue
local CountMap = Core.CountMap
local CopyArray = Core.CopyArray
local TileSuitAndValue = Core.TileSuitAndValue
local TileLess = Core.TileLess
local SortHand = Core.SortHand
local CardToImageKey = Core.CardToImageKey
local CardToVoiceIndex = Core.CardToVoiceIndex

--local IsSevenPairs = Rules.IsSevenPairs
--local IsKokushi = Rules.IsKokushi
local IsWinWithMelds = Rules.IsWinWithMelds
--local IsPengPengHu = Rules.IsPengPengHu
--local GetTingListWithMelds = Rules.GetTingListWithMelds

local GetKongCandidates = AI.GetKongCandidates
local GetChowCandidates = AI.GetChowCandidates
local GetShanten = AI.GetShanten
local ChooseAIDiscard = AI.ChooseAIDiscard
local NormalizeAIDifficulty = AI.NormalizeDifficulty
local GetAIDifficultyLabel = AI.GetDifficultyLabel
local DecideAIResponse = AI.DecideResponse
local SelectKongInDraw = AI.SelectKongInDraw

local EvaluateFan = Scoring.EvaluateFan
local SumFan = Scoring.SumFan

local function T(key, ...)
    return I18N.T(key, ...)
end

UI_TITLE = T("麻將大師")

local NormalizeRuleId = RuleSet.NormalizeRuleId
local GetRuleNameRaw = RuleSet.GetRuleName
local GetRuleOptions = RuleSet.GetRuleOptions
local BuildRuleDeck = RuleSet.BuildDeck
local AllowsChi = RuleSet.AllowsChi
local IsBloodRiver = RuleSet.IsBloodRiver
local GetRuleWinOptions = RuleSet.GetWinOptions
local GetRuleCandidateTiles = RuleSet.GetCandidateTiles
local RequiresMissingSuit = RuleSet.RequiresMissingSuit
local ChooseMissingSuit = RuleSet.ChooseMissingSuit
local CanDiscardByRule = RuleSet.CanDiscard
local IsMissingSuitCleared = RuleSet.IsMissingSuitCleared
local HasIllegalHonors = RuleSet.HasIllegalHonors

local function GetRuleName(ruleId)
    local id = NormalizeRuleId(ruleId)
    return T(GetRuleNameRaw(id))
end

local function InitDB()
    I18N.RefreshLocale()
    local db = _G["MahjongMastersDB"]
    if type(db) ~= "table" and type(_G["MajongMastersDB"]) == "table" then
        db = _G["MajongMastersDB"]
    end
    if type(db) ~= "table" then
        db = CloneTable(DB_DEFAULTS)
    end
    _G["MahjongMastersDB"] = db
    _G["MajongMastersDB"] = db
    MajongMastersDB = db
    MergeDefaults(MajongMastersDB, DB_DEFAULTS)
    MajongMastersDB.timer.discardSec = math.max(5, tonumber(MajongMastersDB.timer.discardSec) or DB_DEFAULTS.timer.discardSec)
    MajongMastersDB.timer.actionSec = math.max(12, tonumber(MajongMastersDB.timer.actionSec) or DB_DEFAULTS.timer.actionSec)
    if type(MajongMastersDB.history.records) ~= "table" then
        MajongMastersDB.history.records = {}
    end
    MajongMastersDB.history.maxRecords = math.max(20, tonumber(MajongMastersDB.history.maxRecords) or DB_DEFAULTS.history.maxRecords)
    MajongMastersDB.ai.difficulty = NormalizeAIDifficulty(MajongMastersDB.ai.difficulty)
    MajongMastersDB.rules.defaultRule = NormalizeRuleId(MajongMastersDB.rules.defaultRule)
end

local function GetConfiguredAIDifficulty()
    if not MajongMastersDB or type(MajongMastersDB.ai) ~= "table" then
        return "advanced"
    end
    local normalized = NormalizeAIDifficulty(MajongMastersDB.ai.difficulty)
    if normalized ~= MajongMastersDB.ai.difficulty then
        MajongMastersDB.ai.difficulty = normalized
    end
    return normalized
end

local function GetConfiguredRuleId()
    if not MajongMastersDB or type(MajongMastersDB.rules) ~= "table" then
        return "guangdong"
    end
    local normalized = NormalizeRuleId(MajongMastersDB.rules.defaultRule)
    if normalized ~= MajongMastersDB.rules.defaultRule then
        MajongMastersDB.rules.defaultRule = normalized
    end
    return normalized
end

local function GetActiveRuleId()
    return NormalizeRuleId(STATE.ruleId or GetConfiguredRuleId())
end

local function PrintInfo(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. tostring(UI_TITLE) .. "|r " .. tostring(msg))
end

local function SafeCall(fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then
        return a, b, c, d
    end
end

local function FullNameFromUnit(unit)
    local name, realm = UnitFullName(unit)
    if not name then
        return nil
    end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    local localRealm = GetRealmName() or ""
    localRealm = localRealm:gsub("%s+", "")
    if localRealm ~= "" then
        return name .. "-" .. localRealm
    end
    return name
end

local function ShortName(fullName)
    if not fullName then
        return ""
    end
    return Ambiguate(fullName, "none")
end

local function CanonicalFullName(name)
    if not name or name == "" then
        return name
    end
    if string.find(name, "-", 1, true) then
        return name
    end
    local realm = (GetRealmName() or ""):gsub("%s+", "")
    if realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function Atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end
    return math.atan(y, x)
end

local AudioImpl = AddonAudioModule.New({
    T = T,
    GetDB = function() return MajongMastersDB end,
    PrintInfo = PrintInfo,
    CardToVoiceIndex = CardToVoiceIndex,
    AUDIO_ROOT = AUDIO_ROOT,
})
local PlayBGM = AudioImpl.PlayBGM
local StopBGM = AudioImpl.StopBGM
local PlayActionVoice = AudioImpl.PlayActionVoice
local PlayDiscardVoice = AudioImpl.PlayDiscardVoice
local PlayCountdownAlarm = AudioImpl.PlayCountdownAlarm

STATE = {
    mode = "NONE", -- NONE | SINGLE | BATTLE
    phase = "IDLE", -- IDLE | LOBBY | PLAYING | FINISHED | PAUSED
    ruleId = "guangdong",
    players = {},
    deck = {},
    turn = 1,
    dealerSeat = 1,
    lastDiscard = nil,
    revealWinner = {},
    localSeat = 1,
    scores = { 0, 0, 0, 0 },
    currentRound = 0,
    host = false,
    room = {
        id = nil,
        gameId = nil,
        ruleId = "guangdong",
        hostName = nil,
        players = {},
        watchers = {},
        announced = nil,
    },
    net = {
        seq = 0,
        recvSeq = 0,
        recvSeqBySender = {},
        maxAckSeq = 0,
        queue = {},
        queueTicker = nil,
        pendingActionToken = nil,
        pendingReliable = {},
        seenActionIds = {},
        snapshotInbox = {},
        resyncPending = false,
        resyncAt = 0,
        eventHash = "0",
        selfGangPromptToken = nil,
        selfGangPromptDismissedToken = nil,
    },
    discardTimer = nil,
    actionTimer = nil,
    lastAlarmSecond = nil,
    lastAlarmTimerKey = nil,
    responseWindow = nil,
    roundLog = {},
    lastRoundResult = nil,
    nextRoundToken = nil,
    nextRoundPrompted = false,
    nextRoundJoinedBy = {},
}

local UI = {}
local EventFrame = CreateFrame("Frame")
local ClearChildren

local function BuildPlayer(name, isHuman)
    return {
        name = name or T("未知"),
        hand = {},
        discards = {},
        melds = {},
        meldSetCount = 0,
        isHuman = isHuman ~= false,
        missingSuit = nil,
        winCount = 0,
    }
end

local function GetPlayer(seat)
    return STATE.players[seat]
end

local function SeatDistance(fromSeat, toSeat)
    return (toSeat - fromSeat + 4) % 4
end

local function IsHomeGroupReadyForBattle()
    local cat = LE_PARTY_CATEGORY_HOME or 1
    if not IsInGroup(cat) then
        return false, T("请先组建 4~5 人小队（HOME 组队）")
    end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then
        return false, T("不支持 INSTANCE 临时队伍")
    end
    local n = GetNumGroupMembers(cat)
    if n < 4 or n > 5 then
        return false, T("对战模式需要 4~5 人 HOME 组队")
    end
    return true
end

local function IsRestrictedByMapOrLockdown()
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType and instanceType ~= "none" then
        return true, T("对战模式禁止在副本地图运行")
    end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return true, T("当前处于聊天限制态")
    end
    if C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then
        return true, T("当前服务器限制发送 AddOn 通信")
    end
    if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState then
        for t = 0, 4 do
            local state = SafeCall(C_RestrictedActions.GetAddOnRestrictionState, t)
            if state and state ~= 0 and state ~= "Inactive" then
                return true, T("当前处于 AddOn 限制态")
            end
        end
    end
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive then
        for t = 0, 4 do
            local active = SafeCall(C_RestrictedActions.IsAddOnRestrictionActive, t)
            if active then
                return true, T("当前处于 AddOn 限制态")
            end
        end
    end
    return false
end

local function EnsurePrefixRegistered()
    if not C_ChatInfo then
        return false, T("缺少 C_ChatInfo")
    end
    if C_ChatInfo.IsAddonMessagePrefixRegistered and C_ChatInfo.IsAddonMessagePrefixRegistered(ADDON_PREFIX) then
        return true
    end
    SafeCall(C_ChatInfo.RegisterAddonMessagePrefix, ADDON_PREFIX)
    if C_ChatInfo.IsAddonMessagePrefixRegistered and C_ChatInfo.IsAddonMessagePrefixRegistered(ADDON_PREFIX) then
        return true
    end
    return false, T("注册通信前缀失败")
end

local function EncodePacket(packet)
    if C_EncodingUtil and C_EncodingUtil.SerializeJSON then
        local payload = SafeCall(C_EncodingUtil.SerializeJSON, packet)
        if type(payload) == "string" then
            return payload
        end
    end
    return nil
end

local function DecodePacket(payload)
    if C_EncodingUtil and C_EncodingUtil.DeserializeJSON then
        local obj = SafeCall(C_EncodingUtil.DeserializeJSON, payload)
        if type(obj) == "table" then
            return obj
        end
    end
    return nil
end

local RELIABLE_MSG_TYPES = {
    GAME_START = true,
    HAND_SYNC = true,
    TURN_START = true,
    ACTION_PROMPT = true,
    DRAW_APPLY = true,
    DISCARD_APPLY = true,
    MELD_APPLY = true,
    ROUND_FINISH = true,
    SNAPSHOT_REQ = true,
    SNAPSHOT_PART = true,
    ROUND_NEXT_PROMPT = true,
    ROUND_NEXT_JOIN = true,
}

local HASH_CHAIN_MSG_TYPES = {
    GAME_START = true,
    TURN_START = true,
    DRAW_APPLY = true,
    DISCARD_APPLY = true,
    MELD_APPLY = true,
    ROUND_FINISH = true,
}

local function IsThrottleCode(code)
    return code == SEND_RESULT.AddonMessageThrottle or code == SEND_RESULT.ChannelThrottle
end

local function IsLockdownCode(code)
    return code == SEND_RESULT.AddOnMessageLockdown
end

local function PayloadSummarySize(payload)
    if type(payload) ~= "table" then
        return payload and #tostring(payload) or 0
    end
    local total = 0
    for k, v in pairs(payload) do
        total = total + #tostring(k) + #tostring(v)
    end
    return total
end

local function RollingChecksum(str)
    local sum = 216613
    for i = 1, #str do
        sum = (sum * 131 + string.byte(str, i)) % 2147483647
    end
    return tostring(sum)
end

local function ComputePacketCRC(packet)
    local src = table.concat({
        tostring(packet.proto or 0),
        tostring(packet.msgType or packet.t or ""),
        tostring(packet.seq or packet.s or 0),
        tostring(packet.ack or packet.a or 0),
        tostring(packet.roomId or packet.room or ""),
        tostring(packet.gameId or packet.g or ""),
        tostring(packet.epoch or 0),
        tostring(packet.actionId or packet.id or ""),
        tostring(PayloadSummarySize(packet.payload or packet.p)),
    }, "|")
    return RollingChecksum(src)
end

local function NormalizePacket(packet)
    if type(packet) ~= "table" then
        return nil
    end
    packet.msgType = packet.msgType or packet.t
    packet.t = packet.msgType
    packet.seq = tonumber(packet.seq or packet.s) or 0
    packet.s = packet.seq
    packet.ack = tonumber(packet.ack or packet.a) or 0
    packet.a = packet.ack
    packet.roomId = packet.roomId or packet.room or ""
    packet.room = packet.roomId
    packet.gameId = packet.gameId or packet.g or ""
    packet.g = packet.gameId
    packet.epoch = tonumber(packet.epoch) or 0
    packet.payload = packet.payload or packet.p or {}
    packet.p = packet.payload
    packet.actionId = packet.actionId or packet.id or ""
    packet.id = packet.actionId
    packet.senderGuid = packet.senderGuid or packet.guid or ""
    packet.guid = packet.senderGuid
    packet.prevHash = packet.prevHash or packet.ph or ""
    packet.ph = packet.prevHash
    packet.eventHash = packet.eventHash or packet.h or ""
    packet.h = packet.eventHash
    packet.crc = packet.crc or packet.c or ""
    packet.c = packet.crc
    return packet
end

local function ValidatePacket(packet)
    if not packet.msgType then
        return false, "missing_msg_type"
    end
    if packet.proto and packet.proto ~= NET_PROTO then
        return false, "proto_mismatch"
    end
    if packet.crc and packet.crc ~= "" then
        local expect = ComputePacketCRC(packet)
        if expect ~= packet.crc then
            return false, "crc_mismatch"
        end
    end
    return true
end

local function BuildActionId(msgType, payload)
    if type(payload) == "table" and payload.actionId then
        return tostring(payload.actionId)
    end
    local now = math.floor(GetTimePreciseSec() * 1000)
    return table.concat({
        tostring(msgType or "MSG"),
        tostring(STATE.currentRound or 0),
        tostring((STATE.net.seq or 0) + 1),
        tostring(now),
    }, "-")
end

local function SendAddonRaw(chatType, target, payload)
    local result = C_ChatInfo.SendAddonMessage(ADDON_PREFIX, payload, chatType, target)
    if result == SEND_RESULT.Success then
        return true
    end
    return false, result
end

local function QueuePacket(chatType, target, payload, retryCount)
    STATE.net.queue[#STATE.net.queue + 1] = {
        chatType = chatType,
        target = target,
        payload = payload,
        nextTry = GetTimePreciseSec(),
        retry = retryCount or 0,
    }
end

local function AckReliable(actionId, ackSeq)
    if not actionId then
        return
    end
    local pending = STATE.net.pendingReliable[actionId]
    if pending then
        STATE.net.pendingReliable[actionId] = nil
    end
    if ackSeq and ackSeq > (STATE.net.maxAckSeq or 0) then
        STATE.net.maxAckSeq = ackSeq
    end
end

local function PumpNetQueue()
    if #STATE.net.queue == 0 then
        return
    end
    local now = GetTimePreciseSec()
    local item = STATE.net.queue[1]
    if now < item.nextTry then
        return
    end
    local ok, code = SendAddonRaw(item.chatType, item.target, item.payload)
    if ok then
        table.remove(STATE.net.queue, 1)
        return
    end
    if IsThrottleCode(code) or IsLockdownCode(code) then
        item.retry = item.retry + 1
        item.nextTry = now + math.min(2.5, 0.4 + item.retry * 0.25)
        return
    end
    table.remove(STATE.net.queue, 1)
end

local function PumpReliableResend()
    local now = GetTimePreciseSec()
    for actionId, item in pairs(STATE.net.pendingReliable) do
        if now >= item.expireAt then
            STATE.net.pendingReliable[actionId] = nil
        elseif now >= item.nextTry then
            local ok, code = SendAddonRaw(item.chatType, item.target, item.payload)
            if ok then
                item.retry = item.retry + 1
                item.nextTry = now + math.min(2.8, 0.7 + item.retry * 0.25)
            elseif IsThrottleCode(code) or IsLockdownCode(code) then
                item.retry = item.retry + 1
                item.nextTry = now + math.min(2.8, 0.7 + item.retry * 0.3)
            else
                STATE.net.pendingReliable[actionId] = nil
            end
        end
    end
    for actionId, ts in pairs(STATE.net.seenActionIds) do
        if now - ts > 120 then
            STATE.net.seenActionIds[actionId] = nil
        end
    end
    for sid, box in pairs(STATE.net.snapshotInbox) do
        if now - (box.at or now) > 10 then
            STATE.net.snapshotInbox[sid] = nil
        end
    end
    if STATE.net.resyncPending and now - (STATE.net.resyncAt or 0) > 8 then
        STATE.net.resyncPending = false
        STATE.net.resyncAt = 0
    end
end

local function EnsureNetTicker()
    if STATE.net.queueTicker then
        return
    end
    STATE.net.queueTicker = C_Timer.NewTicker(0.1, function()
        PumpNetQueue()
        PumpReliableResend()
    end)
end

local function SendPacket(msgType, payload, chatType, target, opts)
    if STATE.mode ~= "BATTLE" then
        return false
    end
    opts = opts or {}
    STATE.net.seq = STATE.net.seq + 1
    local actionId = opts.actionId or BuildActionId(msgType, payload)
    local packet = {
        proto = NET_PROTO,
        msgType = msgType,
        seq = STATE.net.seq,
        ack = STATE.net.maxAckSeq or 0,
        roomId = STATE.room.id or "",
        gameId = STATE.room.gameId or "",
        epoch = STATE.currentRound or 0,
        payload = payload or {},
        actionId = actionId,
        senderGuid = UnitGUID("player") or "",
        prevHash = STATE.net.eventHash or "0",
    }

    if STATE.host and HASH_CHAIN_MSG_TYPES[msgType] then
        local newHash = RollingChecksum(table.concat({
            tostring(packet.prevHash),
            tostring(packet.msgType),
            tostring(packet.seq),
            tostring(packet.actionId),
        }, "|"))
        packet.eventHash = newHash
        STATE.net.eventHash = newHash
    else
        packet.eventHash = STATE.net.eventHash or "0"
    end

    packet.crc = ComputePacketCRC(packet)

    local body = EncodePacket(packet)
    if not body then
        return false
    end
    if #body > NET_PACKET_MAX_BYTES then
        PrintInfo(T("消息过长，已忽略：%s", tostring(msgType)))
        return false
    end

    local sendType = chatType or "PARTY"
    local ok, code = SendAddonRaw(sendType, target, body)
    if not ok then
        if IsThrottleCode(code) or IsLockdownCode(code) then
            QueuePacket(sendType, target, body, 0)
            EnsureNetTicker()
        else
            PrintInfo(T("发送失败(%s): %s", tostring(code), tostring(msgType)))
        end
        return false
    end

    if RELIABLE_MSG_TYPES[msgType] and not opts.skipReliable and actionId ~= "" then
        STATE.net.pendingReliable[actionId] = {
            payload = body,
            chatType = sendType,
            target = target,
            retry = 0,
            nextTry = GetTimePreciseSec() + 0.9,
            expireAt = GetTimePreciseSec() + 10.0,
        }
    end
    return true, actionId
end

local function Broadcast(msgType, payload)
    SendPacket(msgType, payload, "PARTY")
end

local function Whisper(target, msgType, payload)
    SendPacket(msgType, payload, "WHISPER", target)
end

local function ResetTimers()
    if STATE.discardTimer and STATE.discardTimer.ticker then
        STATE.discardTimer.ticker:Cancel()
    end
    if STATE.actionTimer and STATE.actionTimer.ticker then
        STATE.actionTimer.ticker:Cancel()
    end
    STATE.discardTimer = nil
    STATE.actionTimer = nil
    STATE.lastAlarmSecond = nil
    STATE.lastAlarmTimerKey = nil
end

local function UpdateActionPanelTimerText(text)
    if UI.ActionPanel and UI.ActionPanel.TimerText then
        UI.ActionPanel.TimerText:SetText(text or "")
    end
end

local function UpdateStatusTimerText(text, seat)
    if UI.TimerText then
        UI.TimerText:SetText("")
    end
    if not UI.PlayerAreas then
        return
    end
    for i = 1, 4 do
        local area = UI.PlayerAreas[i]
        if area and area.TurnTimerText then
            if i == seat and text and text ~= "" then
                area.TurnTimerText:SetText(text)
            else
                area.TurnTimerText:SetText("")
            end
        end
    end
end

local function ClearActionPanel()
    if UI.ActionPanel then
        UI.ActionPanel:Hide()
    end
    STATE.net.selfGangPromptToken = nil
    UpdateActionPanelTimerText("")
end

local function AddScore(seat, delta)
    STATE.scores[seat] = (STATE.scores[seat] or 0) + delta
end

local function ScoreWin(winSeat, discardSeat, selfDraw, fanList, opts)
    opts = opts or {}
    local totalFan = SumFan(fanList)
    local base = 2 ^ (totalFan + 1)
    if totalFan >= 13 then
        base = 32000
    end
    local roundDelta = { 0, 0, 0, 0 }
    local function addWithDelta(seat, delta)
        if not seat then
            return
        end
        roundDelta[seat] = (roundDelta[seat] or 0) + delta
        AddScore(seat, delta)
    end
    local paySeats = opts.paySeats
    local function eachPaySeat(fn)
        if type(paySeats) == "table" and #paySeats > 0 then
            for _, seat in ipairs(paySeats) do
                if seat ~= winSeat then
                    fn(seat)
                end
            end
            return
        end
        for s = 1, 4 do
            if s ~= winSeat then
                fn(s)
            end
        end
    end
    if selfDraw then
        eachPaySeat(function(s)
            addWithDelta(s, -base)
            addWithDelta(winSeat, base)
        end)
    else
        local payer = discardSeat
        if not payer or payer == winSeat then
            if type(paySeats) == "table" then
                for _, seat in ipairs(paySeats) do
                    if seat ~= winSeat then
                        payer = seat
                        break
                    end
                end
            end
        end
        if payer and payer ~= winSeat then
            addWithDelta(payer, -base * 2)
            addWithDelta(winSeat, base * 2)
        end
    end
    return roundDelta, base, totalFan
end

local ResultOps = AddonResultOpsModule.New({
    UI = UI,
    STATE = STATE,
    T = T,
    Join = Join,
    TileSuitAndValue = TileSuitAndValue,
    GetPlayer = GetPlayer,
    GetActiveRuleId = GetActiveRuleId,
    GetRuleName = GetRuleName,
    CloneTable = CloneTable,
    CopyArray = CopyArray,
    GetDB = function() return MajongMastersDB end,
    ShortName = ShortName,
    SafeCall = SafeCall,
    CanonicalFullName = CanonicalFullName,
    FullNameFromUnit = FullNameFromUnit,
    GetClearChildren = function() return ClearChildren end,
    IMG_ROOT = IMG_ROOT,
})

local function BuildGroupMembers()
    local members = {}
    local cat = LE_PARTY_CATEGORY_HOME or 1
    if not IsInGroup(cat) then
        members[#members + 1] = FullNameFromUnit("player")
        return members
    end
    if IsInRaid(cat) then
        local n = GetNumGroupMembers(cat)
        for i = 1, n do
            local name = FullNameFromUnit("raid" .. i)
            if name then
                members[#members + 1] = name
            end
        end
    else
        local selfName = FullNameFromUnit("player")
        members[#members + 1] = selfName
        local n = GetNumSubgroupMembers(cat)
        for i = 1, n do
            local name = FullNameFromUnit("party" .. i)
            if name then
                members[#members + 1] = name
            end
        end
    end
    table.sort(members)
    return members
end

local function FindSeatByName(fullName)
    local target = CanonicalFullName(fullName)
    for i = 1, 4 do
        if STATE.players[i] and CanonicalFullName(STATE.players[i].name) == target then
            return i
        end
    end
    return nil
end

local function NotifyPause(reason)
    if STATE.phase == "PLAYING" then
        STATE.phase = "PAUSED"
        ResetTimers()
        ClearActionPanel()
        UpdateStatusTimerText("")
        if UI.StatusText then
            UI.StatusText:SetText(T("暂停：%s", (reason or T("受限制状态"))))
        end
        PrintInfo(T("牌局已暂停：%s", tostring(reason)))
    end
end

local function ResumeIfPossible()
    local blocked, reason = IsRestrictedByMapOrLockdown()
    if blocked then
        return false, reason
    end
    if STATE.phase == "PAUSED" then
        STATE.phase = "PLAYING"
        return true
    end
    return false
end

local function NewActionToken()
    return tostring(math.random(100000, 999999)) .. "-" .. tostring(GetTimePreciseSec())
end

local function UpdatePlayerNameTags()
    for seat = 1, 4 do
        local area = UI.PlayerAreas and UI.PlayerAreas[seat]
        local player = STATE.players[seat]
        if area and player then
            local isDealer = seat == STATE.dealerSeat
            area.RoleIcon:SetTexture(isDealer and (IMG_ROOT .. "zhangjia.png") or (IMG_ROOT .. "icon_gold.png"))
            area.NameText:SetText(PlayerDisplayName(player))
        end
    end
end

local function SetWallText(text)
    if UI.WallText then
        UI.WallText:SetText(text or "")
    end
end

local function SetStatusText(text)
    if UI.StatusText then
        UI.StatusText:SetText(text or "")
    end
end

local function BuildRuleWinCheckOptions()
    local ruleId = GetActiveRuleId()
    local opts = GetRuleWinOptions(ruleId) or {}
    opts.ruleId = ruleId
    opts.candidateTiles = GetRuleCandidateTiles(ruleId)
    return opts
end

local function RuleInfoText(ruleId)
    return T("玩法：%s", GetRuleName(ruleId))
end

local UIUtils = AddonUIUtilsModule.New({
    UI = UI,
    T = T,
    NormalizeRuleId = NormalizeRuleId,
    GetRuleOptions = GetRuleOptions,
    GetRuleName = GetRuleName,
    CardToImageKey = CardToImageKey,
    IMG_ROOT = IMG_ROOT,
})
local CloseAllRuleSelectorLists = UIUtils.CloseAllRuleSelectorLists
local CreateRuleListSelector = UIUtils.CreateRuleListSelector
local CreateTileFrame = UIUtils.CreateTileFrame
UI.CreateTileFrame = CreateTileFrame
ClearChildren = UIUtils.ClearChildren

local function CurrentPlayerName()
    local p = GetPlayer(STATE.turn)
    return p and ShortName(p.name) or T("待机")
end

local function PlayerDisplayName(player)
    if not player then
        return ""
    end
    local text = ShortName(player.name)
    if RequiresMissingSuit(GetActiveRuleId()) and player.missingSuit then
        text = text .. T(" 缺%s", tostring(player.missingSuit))
    end
    if (player.winCount or 0) > 0 then
        text = text .. " x" .. tostring(player.winCount)
    end
    return text
end

local function HiddenBackTextureForSeat(seat)
    local dist = SeatDistance(STATE.localSeat, seat)
    if dist == 2 then
        return IMG_ROOT .. "zheng_li.png"
    end
    return IMG_ROOT .. "ce_an.png"
end

local function MissingSuitMaskColor(suit)
    if suit == "W" then
        return 1, 0.38, 0.38, 0.18
    elseif suit == "T" then
        return 0.42, 1, 0.52, 0.18
    elseif suit == "S" then
        return 0.46, 0.72, 1, 0.18
    end
    return 1, 0.8, 0.28, 0.18
end

local function HideStartButtons()
    CloseAllRuleSelectorLists(nil)
    if UI.StartSingleBtn then UI.StartSingleBtn:Hide() end
    if UI.StartSingleBackBtn then UI.StartSingleBackBtn:Hide() end
    if UI.BattlePanel then UI.BattlePanel:Hide() end
    if UI.ModePanel then UI.ModePanel:Hide() end
end

local function ShowModePanel()
    CloseAllRuleSelectorLists(nil)
    if UI.ModePanel then
        UI.ModePanel:Show()
    end
    if UI.BattlePanel then
        UI.BattlePanel:Hide()
    end
    if UI.StartSingleBtn then
        UI.StartSingleBtn:Hide()
    end
    if UI.StartSingleBackBtn then
        UI.StartSingleBackBtn:Hide()
    end
    if UI.HomeBtn then
        UI.HomeBtn:Hide()
    end
end

local function ShowBattlePanel()
    CloseAllRuleSelectorLists(nil)
    if UI.BattlePanel then
        UI.BattlePanel:Show()
    end
    if UI.StartSingleBtn then
        UI.StartSingleBtn:Hide()
    end
    if UI.ModePanel then
        UI.ModePanel:Hide()
    end
    if UI.StartSingleBackBtn then
        UI.StartSingleBackBtn:Hide()
    end
    if UI.HomeBtn then
        UI.HomeBtn:Hide()
    end
    if UI.BattlePanel and UI.BattlePanel.RefreshAvailability then
        UI.BattlePanel:RefreshAvailability()
    end
end

local function ShowSingleStart()
    CloseAllRuleSelectorLists(nil)
    if UI.StartSingleBtn then
        UI.StartSingleBtn:Show()
    end
    if UI.StartSingleBackBtn then
        UI.StartSingleBackBtn:Show()
    end
    if UI.BattlePanel then
        UI.BattlePanel:Hide()
    end
    if UI.ModePanel then
        UI.ModePanel:Hide()
    end
    if UI.HomeBtn then
        UI.HomeBtn:Hide()
    end
    if UI.SingleRuleSelection and UI.SingleRuleSelection.SetRule then
        UI.SingleRuleSelection.SetRule(GetConfiguredRuleId(), true)
    end
end

local function ResetRoundCommon()
    ResetTimers()
    STATE.deck = {}
    STATE.players = {}
    STATE.turn = 1
    STATE.dealerSeat = 1
    STATE.lastDiscard = nil
    STATE.revealWinner = {}
    STATE.responseWindow = nil
    STATE.net.seq = 0
    STATE.net.recvSeq = 0
    STATE.net.recvSeqBySender = {}
    STATE.net.maxAckSeq = 0
    STATE.net.pendingActionToken = nil
    STATE.net.pendingReliable = {}
    STATE.net.seenActionIds = {}
    STATE.net.snapshotInbox = {}
    STATE.net.resyncPending = false
    STATE.net.resyncAt = 0
    STATE.net.eventHash = "0"
    STATE.net.selfGangPromptToken = nil
    STATE.net.selfGangPromptDismissedToken = nil
    STATE.roundLog = {}
    STATE.lastRoundResult = nil
    STATE.nextRoundToken = nil
    STATE.nextRoundPrompted = false
    STATE.nextRoundJoinedBy = {}
    ClearActionPanel()
    if UI.ResultPanel then
        UI.ResultPanel:Hide()
    end
    if UI.HistoryPanel then
        UI.HistoryPanel:Hide()
    end
end

local function RefreshTable()
    if UI.MainCloseBtn then
        local locked = (STATE.phase == "PLAYING" or STATE.phase == "PAUSED" or STATE.phase == "FINISHED")
        UI.MainCloseBtn:SetShown(not locked)
    end
    local inModeScreen = (UI.ModePanel and UI.ModePanel:IsShown()) or (UI.StartSingleBtn and UI.StartSingleBtn:IsShown())
    local ruleInfo = RuleInfoText(GetActiveRuleId())
    if STATE.phase == "IDLE" or inModeScreen then
        SetStatusText(T("请选择模式"))
    else
        SetStatusText(T("当前回合: %s", CurrentPlayerName()) .. "\n" .. ruleInfo)
    end

    if inModeScreen or STATE.phase == "IDLE" or STATE.phase == "LOBBY" then
        SetWallText("")
    elseif STATE.phase == "FINISHED" then
        -- handled by result text
    elseif IsBloodRiver(GetActiveRuleId()) and #STATE.roundLog > 0 then
        SetWallText(T("牌墙剩余 %s", tostring(#STATE.deck)) .. "\n" .. Join(STATE.roundLog, "\n"))
    elseif #STATE.deck > 0 then
        SetWallText(T("牌墙剩余") .. "\n" .. tostring(#STATE.deck))
    else
        SetWallText(T("流局"))
    end

    for seat = 1, 4 do
        local area = UI.PlayerAreas[seat]
        local p = STATE.players[seat]
        if area then
            if p then
                local activeRuleId = GetActiveRuleId()
                local missingSuit = (RequiresMissingSuit(activeRuleId) and p.missingSuit) and p.missingSuit or nil
                local showMissingSuitMask = missingSuit and not IsMissingSuitCleared(activeRuleId, p)
                area.RoleText:SetText("")
                area.NameText:SetText(PlayerDisplayName(p))
                if area.ScoreText then
                    area.ScoreText:SetText(T("累计: %d", tonumber(STATE.scores[seat]) or 0))
                end
                local isDealer = seat == STATE.dealerSeat
                local tableTileRoot = IMG_ROOT
                if STATE.phase == "FINISHED" and STATE.revealWinner and STATE.revealWinner[seat] then
                    local dist = SeatDistance(STATE.localSeat or 1, seat)
                    if dist == 1 then
                        tableTileRoot = IMG_ROOT .. "y\\"
                    elseif dist == 3 then
                        tableTileRoot = IMG_ROOT .. "z\\"
                    end
                end
                area.RoleIcon:SetTexture(isDealer and (IMG_ROOT .. "zhangjia.png") or (IMG_ROOT .. "icon_gold.png"))

                ClearChildren(area.Melds)
                for mIdx, meld in ipairs(p.melds) do
                    for tIdx, card in ipairs(meld.tiles) do
                        local w, h = 28, 40
                        local tile = CreateTileFrame(area.Melds, w, h, card, false, false, nil, nil, tableTileRoot)
                        if seat == 1 then
                            tile:SetPoint("BOTTOMLEFT", (mIdx - 1) * 95 + (tIdx - 1) * 30, 0)
                        elseif seat == 3 then
                            tile:SetPoint("TOPRIGHT", -((mIdx - 1) * 95 + (tIdx - 1) * 30), 0)
                        elseif seat == 2 then
                            tile:SetPoint("TOPLEFT", (tIdx - 1) * 30, -((mIdx - 1) * 42))
                        else
                            tile:SetPoint("BOTTOMLEFT", (tIdx - 1) * 30, (mIdx - 1) * 42)
                        end
                    end
                end

                ClearChildren(area.Hand)
                local hand = p.hand
                local handSize = #hand
                for idx = 1, handSize do
                    local card = hand[idx]
                    local isLastDraw = (idx == handSize and handSize % 3 == 2 and STATE.turn == seat)
                    if seat == 1 then
                        local click = CreateFrame("Button", nil, area.Hand)
                        click:SetSize(44, 64)
                        click:SetPoint("BOTTOMLEFT", (idx - 1) * 46 + (isLastDraw and 12 or 0), 0)
                        local visual = CreateTileFrame(click, 44, 64, card, false, isLastDraw, nil, nil, tableTileRoot)
                        visual:SetPoint("BOTTOMLEFT", 0, 0)
                        click.Visual = visual
                        if showMissingSuitMask then
                            local suit = TileSuitAndValue(card)
                            if suit and suit == missingSuit then
                                local mask = click:CreateTexture(nil, "OVERLAY")
                                mask:SetAllPoints(visual)
                                mask:SetColorTexture(MissingSuitMaskColor(suit))
                                click.MissingSuitMask = mask
                            end
                        end
                        local canPlay = (STATE.phase == "PLAYING"
                            and seat == STATE.localSeat
                            and STATE.turn == seat
                            and p.isHuman
                            and #p.hand % 3 == 2)
                        if canPlay then
                            click:SetScript("OnEnter", function()
                                click.Visual:SetPoint("BOTTOMLEFT", 0, 10)
                            end)
                            click:SetScript("OnLeave", function()
                                click.Visual:SetPoint("BOTTOMLEFT", 0, 0)
                            end)
                            click:SetScript("OnClick", function()
                                if STATE.mode == "BATTLE" and not STATE.host then
                                    if STATE.net.pendingActionToken then
                                        Whisper(STATE.room.hostName, "ACTION_REQ", {
                                            token = STATE.net.pendingActionToken,
                                            kind = "DISCARD",
                                            card = card,
                                        })
                                    end
                                else
                                    UI.SubmitLocalDiscard(card)
                                end
                            end)
                        else
                            click:SetAlpha(0.8)
                            click:EnableMouse(false)
                        end
                    elseif seat == 3 then
                        local hidden = not STATE.revealWinner[seat]
                        local tile = CreateTileFrame(area.Hand, 28, 40, card, hidden, isLastDraw, nil, HiddenBackTextureForSeat(seat), tableTileRoot)
                        tile:SetPoint("TOPRIGHT", -((idx - 1) * 30 + (isLastDraw and 10 or 0)), 0)
                    elseif seat == 2 then
                        local hidden = not STATE.revealWinner[seat]
                        local tile = CreateTileFrame(area.Hand, 40, 28, card, hidden, isLastDraw, nil, HiddenBackTextureForSeat(seat), tableTileRoot)
                        tile:SetPoint("BOTTOMLEFT", 0, ((idx - 1) * 30 + (isLastDraw and 10 or 0)))
                    else
                        local hidden = not STATE.revealWinner[seat]
                        local tile = CreateTileFrame(area.Hand, 40, 28, card, hidden, isLastDraw, nil, HiddenBackTextureForSeat(seat), tableTileRoot)
                        tile:SetPoint("TOPRIGHT", 0, -((idx - 1) * 30 + (isLastDraw and 10 or 0)))
                    end
                end

                ClearChildren(area.Discards)
                for idx, card in ipairs(p.discards) do
                    local row = math.floor((idx - 1) / 6)
                    local col = (idx - 1) % 6
                    local isLatest = (idx == #p.discards and card == STATE.lastDiscard)
                    local tile = CreateTileFrame(area.Discards, 30, 42, card, false, isLatest, { 1, 0.2, 0.2, 1 }, nil, IMG_ROOT)
                    tile:SetPoint("TOPLEFT", col * 32, -row * 44)
                end
            else
                area.RoleText:SetText("")
                area.NameText:SetText("")
                if area.ScoreText then
                    area.ScoreText:SetText("")
                end
                if area.TurnTimerText then
                    area.TurnTimerText:SetText("")
                end
                area.RoleIcon:SetTexture(nil)
                ClearChildren(area.Melds)
                ClearChildren(area.Hand)
                ClearChildren(area.Discards)
            end
        end
    end
end

local function ReturnToHomeScreen()
    StopBGM()
    ResetRoundCommon()
    STATE.mode = "NONE"
    STATE.phase = "IDLE"
    STATE.host = false
    STATE.ruleId = GetConfiguredRuleId()
    STATE.localSeat = 1
    STATE.room.id = nil
    STATE.room.gameId = nil
    STATE.room.ruleId = STATE.ruleId
    STATE.room.hostName = nil
    STATE.room.players = {}
    STATE.room.watchers = {}
    STATE.room.announced = nil
    if UI.SettingsPanel then
        UI.SettingsPanel:Hide()
    end
    if UI.RuleGuidePanel then
        UI.RuleGuidePanel:Hide()
    end
    CloseAllRuleSelectorLists(nil)
    UpdateStatusTimerText("")
    SetStatusText(T("请选择模式"))
    SetWallText("")
    ShowModePanel()
    RefreshTable()
end

local function ResolveRoundFinish(winSeat, discardSeat, selfDraw, ctx)
    STATE.phase = "FINISHED"
    ResetTimers()
    ClearActionPanel()
    local winner = GetPlayer(winSeat)
    if winner then
        STATE.revealWinner[winSeat] = true
        local evalCtx = CloneTable(ctx or {})
        evalCtx.ruleId = GetActiveRuleId()
        evalCtx.missingSuitCleared = IsMissingSuitCleared(GetActiveRuleId(), winner)
        local fanList = EvaluateFan(winner, evalCtx)
        local roundDelta, _, totalFan = ScoreWin(winSeat, discardSeat, selfDraw, fanList, {})
        local fanText = {}
        for _, item in ipairs(fanList) do
            fanText[#fanText + 1] = T(item.name) .. "+" .. item.fan
        end
        local methodText = selfDraw and T("自摸") or T("点炮")
        SetWallText("")
        if selfDraw then
            PlayActionVoice(totalFan >= 13 and "HU_DA" or "HU")
        else
            PlayActionVoice("HU_PAO")
        end
        local result = ResultOps.BuildRoundResult(winSeat, discardSeat, selfDraw, fanList, roundDelta, {
            winTile = selfDraw and winner.hand[#winner.hand] or STATE.lastDiscard,
            continueRound = false,
        })
        if result then
            ResultOps.SaveHistory(result)
            ResultOps.AnnounceToChat(result)
            ResultOps.ShowResultPanel(result)
        end
    end
    RefreshTable()
end

local function ResolveBloodRiverWin(winSeat, discardSeat, selfDraw, ctx)
    local winner = GetPlayer(winSeat)
    if not winner then
        return
    end
    local ruleId = GetActiveRuleId()
    local evalCtx = CloneTable(ctx or {})
    evalCtx.ruleId = ruleId
    evalCtx.missingSuitCleared = IsMissingSuitCleared(ruleId, winner)
    local fanList = EvaluateFan(winner, evalCtx)
    local paySeats = {}
    for seat = 1, 4 do
        if seat ~= winSeat then
            paySeats[#paySeats + 1] = seat
        end
    end
    local roundDelta = ScoreWin(winSeat, discardSeat, selfDraw, fanList, { paySeats = paySeats })
    winner.winCount = (winner.winCount or 0) + 1

    local totalFan = SumFan(fanList)
    local fanText = {}
    for _, item in ipairs(fanList) do
        fanText[#fanText + 1] = T(item.name) .. "+" .. item.fan
    end
    local methodText = selfDraw and T("自摸") or T("点炮")
    local eventText = T("%s %s %d番 (%s)", ShortName(winner.name), methodText, totalFan, Join(fanText, " "))
    STATE.roundLog[#STATE.roundLog + 1] = eventText
    if #STATE.roundLog > 4 then
        table.remove(STATE.roundLog, 1)
    end
    SetWallText(T("血流成河") .. "\n" .. Join(STATE.roundLog, "\n"))
    PlayActionVoice(totalFan >= 13 and "HU_DA" or (selfDraw and "HU" or "HU_PAO"))
    local result = ResultOps.BuildRoundResult(winSeat, discardSeat, selfDraw, fanList, roundDelta, {
        winTile = selfDraw and winner.hand[#winner.hand] or STATE.lastDiscard,
        continueRound = true,
    })
    if result then
        ResultOps.SaveHistory(result)
        ResultOps.AnnounceToChat(result)
    end
    RefreshTable()
end

local function NextSeat(seat)
    return (seat % 4) + 1
end

local function RemoveDiscardFromSeat(seat, card)
    local p = GetPlayer(seat)
    if not p or #p.discards == 0 then
        return
    end
    if p.discards[#p.discards] == card then
        table.remove(p.discards)
    else
        for i = #p.discards, 1, -1 do
            if p.discards[i] == card then
                table.remove(p.discards, i)
                break
            end
        end
    end
end

local function ApplyMeldFromDiscard(seat, discardSeat, action, data)
    local p = GetPlayer(seat)
    if not p then
        return
    end
    local card = STATE.lastDiscard
    RemoveDiscardFromSeat(discardSeat, card)
    if action == "PENG" then
        RemoveByValue(p.hand, card, 2)
        p.melds[#p.melds + 1] = { type = "peng", tiles = { card, card, card } }
        p.meldSetCount = p.meldSetCount + 1
        PlayActionVoice("PENG")
    elseif action == "GANG" then
        RemoveByValue(p.hand, card, 3)
        p.melds[#p.melds + 1] = { type = "minggang", tiles = { card, card, card, card } }
        p.meldSetCount = p.meldSetCount + 1
        PlayActionVoice("GANG")
    elseif action == "CHI" then
        if not AllowsChi(GetActiveRuleId()) then
            return
        end
        local combo = data and data.combo
        if combo then
            for _, t in ipairs(combo) do
                if t ~= card then
                    RemoveByValue(p.hand, t, 1)
                end
            end
            p.melds[#p.melds + 1] = { type = "chi", tiles = combo }
            p.meldSetCount = p.meldSetCount + 1
            PlayActionVoice("CHI")
        end
    end
    SortHand(p.hand, true)
end

local function DrawTileForSeat(seat)
    local p = GetPlayer(seat)
    if not p then
        return nil
    end
    if #STATE.deck == 0 then
        return nil
    end
    local tile = table.remove(STATE.deck, 1)
    p.hand[#p.hand + 1] = tile
    SortHand(p.hand, true)
    return tile
end

local function BuildPublicPlayerState()
    local out = {}
    for i = 1, 4 do
        local p = GetPlayer(i)
        out[#out + 1] = {
            name = p.name,
            hand = #p.hand,
            disc = Join(p.discards, "."),
            meld = #p.melds,
            miss = p.missingSuit or "",
            wins = p.winCount or 0,
        }
    end
    return out
end

local function SendRoundPublicState(msgType, payload)
    if STATE.mode ~= "BATTLE" or not STATE.host then
        return
    end
    payload = payload or {}
    payload.turn = STATE.turn
    payload.deck = #STATE.deck
    payload.last = STATE.lastDiscard
    payload.ruleId = GetActiveRuleId()
    payload.players = BuildPublicPlayerState()
    Broadcast(msgType, payload)
end

local function SendPrivateHandSync()
    if STATE.mode ~= "BATTLE" or not STATE.host then
        return
    end
    for seat = 1, 4 do
        local p = GetPlayer(seat)
        Whisper(p.name, "HAND_SYNC", {
            seat = seat,
            hand = Join(p.hand, "."),
            meldCount = p.meldSetCount,
            missingSuit = p.missingSuit or "",
            winCount = p.winCount or 0,
        })
    end
end

local function BeginDiscardTimer(seat, seconds, onTimeout)
    if STATE.discardTimer and STATE.discardTimer.ticker then
        STATE.discardTimer.ticker:Cancel()
    end
    local deadline = GetTimePreciseSec() + seconds
    local timerKey = tostring(STATE.net.pendingActionToken or "") .. ":" .. tostring(seat)
    STATE.discardTimer = { seat = seat, deadline = deadline, onTimeout = onTimeout, timerKey = timerKey }
    local timerRef = STATE.discardTimer
    if STATE.lastAlarmTimerKey ~= timerKey then
        STATE.lastAlarmSecond = nil
        STATE.lastAlarmTimerKey = timerKey
    end
    timerRef.ticker = C_Timer.NewTicker(0.1, function()
        if STATE.discardTimer ~= timerRef then
            return
        end
        local remain = timerRef.deadline - GetTimePreciseSec()
        if remain < 0 then
            remain = 0
        end
        UpdateStatusTimerText(string.format("%.1f", remain), seat)
        if MajongMastersDB.timer.alarmLast3Sec and seat == STATE.localSeat and remain > 0 and remain <= 3.05 then
            if STATE.lastAlarmSecond ~= 3 then
                STATE.lastAlarmSecond = 3
                PlayCountdownAlarm()
            end
        end
        if remain <= 0 then
            local cb = timerRef.onTimeout
            if timerRef.ticker then
                timerRef.ticker:Cancel()
            end
            if STATE.discardTimer == timerRef then
                STATE.discardTimer = nil
            end
            UpdateStatusTimerText("")
            local panelBlocking = UI.ActionPanel and UI.ActionPanel:IsShown() and not STATE.net.selfGangPromptToken
            if cb and not STATE.responseWindow and not STATE.actionTimer and not panelBlocking then
                cb()
            end
        end
    end)
end

local function EndDiscardTimer()
    if STATE.discardTimer and STATE.discardTimer.ticker then
        STATE.discardTimer.ticker:Cancel()
    end
    STATE.discardTimer = nil
    STATE.lastAlarmSecond = nil
    STATE.lastAlarmTimerKey = nil
    UpdateStatusTimerText("")
end

local function BeginActionTimer(seconds, onTimeout)
    seconds = math.max(1, tonumber(seconds) or DB_DEFAULTS.timer.actionSec)
    if STATE.actionTimer and STATE.actionTimer.ticker then
        STATE.actionTimer.ticker:Cancel()
    end
    local deadline = GetTimePreciseSec() + seconds
    local timerRef = { deadline = deadline, onTimeout = onTimeout }
    STATE.actionTimer = timerRef
    timerRef.ticker = C_Timer.NewTicker(0.1, function()
        if STATE.actionTimer ~= timerRef then
            return
        end
        local remain = timerRef.deadline - GetTimePreciseSec()
        if remain < 0 then
            remain = 0
        end
        UpdateActionPanelTimerText(T("动作倒计时: %.1fs", remain))
        if remain <= 0 then
            local cb = timerRef.onTimeout
            if timerRef.ticker then
                timerRef.ticker:Cancel()
            end
            if STATE.actionTimer == timerRef then
                STATE.actionTimer = nil
            end
            UpdateActionPanelTimerText("")
            if cb then
                cb()
            end
        end
    end)
end

local function EndActionTimer()
    if STATE.actionTimer and STATE.actionTimer.ticker then
        STATE.actionTimer.ticker:Cancel()
    end
    STATE.actionTimer = nil
    UpdateActionPanelTimerText("")
end

local function IsLocalTurnHuman()
    local p = GetPlayer(STATE.turn)
    return p and p.isHuman and STATE.turn == STATE.localSeat
end

local function SubmitDiscardLocal(card)
    local p = GetPlayer(STATE.turn)
    if not p or STATE.turn ~= STATE.localSeat then
        return
    end
    local ruleId = GetActiveRuleId()
    if not CanDiscardByRule(ruleId, p.hand, card, p.missingSuit) then
        PrintInfo(T("当前规则需先打缺门牌"))
        return
    end
    if STATE.mode == "BATTLE" and not STATE.host then
        if STATE.net.pendingActionToken then
            ClearActionPanel()
            Whisper(STATE.room.hostName, "ACTION_REQ", {
                token = STATE.net.pendingActionToken,
                kind = "DISCARD",
                card = card,
            })
            EndDiscardTimer()
        end
        return
    end
    if RemoveByValue(p.hand, card, 1) < 1 then
        return
    end
    ClearActionPanel()
    STATE.lastDiscard = card
    p.discards[#p.discards + 1] = card
    SortHand(p.hand, false)
    PlayDiscardVoice(card)
    SendRoundPublicState("DISCARD_APPLY", { seat = STATE.turn, card = card })
    SendPrivateHandSync()
    RefreshTable()
    EndActionTimer()
    UI.ScheduleResolveResponses(STATE.turn)
end

UI.SubmitLocalDiscard = SubmitDiscardLocal

local function ApplyGangInDrawPhase(seat, kongInfo)
    local p = GetPlayer(seat)
    if not p or not kongInfo then
        return false
    end
    if kongInfo.kind == "angang" then
        RemoveByValue(p.hand, kongInfo.tile, 4)
        p.melds[#p.melds + 1] = { type = "angang", tiles = { kongInfo.tile, kongInfo.tile, kongInfo.tile, kongInfo.tile } }
        p.meldSetCount = p.meldSetCount + 1
        PlayActionVoice("GANG")
        return true
    elseif kongInfo.kind == "bugang" then
        RemoveByValue(p.hand, kongInfo.tile, 1)
        for _, meld in ipairs(p.melds) do
            if meld.type == "peng" and meld.tiles[1] == kongInfo.tile then
                meld.type = "bugang"
                meld.tiles[#meld.tiles + 1] = kongInfo.tile
                break
            end
        end
        PlayActionVoice("GANG")
        return true
    end
    return false
end

local function CanSeatWinOnDiscard(seat, card)
    local p = GetPlayer(seat)
    if not p then
        return false
    end
    local ruleId = GetActiveRuleId()
    if HasIllegalHonors(ruleId, p, card) then
        return false
    end
    if RequiresMissingSuit(ruleId) then
        local testPlayer = {
            hand = CopyArray(p.hand),
            melds = p.melds,
            missingSuit = p.missingSuit,
        }
        testPlayer.hand[#testPlayer.hand + 1] = card
        if not IsMissingSuitCleared(ruleId, testPlayer) then
            return false
        end
    end
    local tmp = CopyArray(p.hand)
    tmp[#tmp + 1] = card
    return IsWinWithMelds(tmp, p.meldSetCount, BuildRuleWinCheckOptions())
end

local function GetLegalResponses(discardSeat, card)
    local legal = {}
    local nextSeat = NextSeat(discardSeat)
    local allowChi = AllowsChi(GetActiveRuleId())
    for seat = 1, 4 do
        if seat ~= discardSeat then
            local p = GetPlayer(seat)
            if p then
                local list = {}
                if CanSeatWinOnDiscard(seat, card) then
                    list[#list + 1] = { kind = "HU" }
                end
                local counts = CountMap(p.hand)
                if (counts[card] or 0) >= 3 then
                    list[#list + 1] = { kind = "GANG" }
                end
                if (counts[card] or 0) >= 2 then
                    list[#list + 1] = { kind = "PENG" }
                end
                if allowChi and seat == nextSeat then
                    local chow = GetChowCandidates(p.hand, card)
                    if #chow > 0 then
                        list[#list + 1] = { kind = "CHI", combos = chow }
                    end
                end
                if #list > 0 then
                    legal[seat] = list
                end
            end
        end
    end
    return legal
end

local function ResolveResponseWindow(discardSeat)
    local window = STATE.responseWindow
    if not window or window.discardSeat ~= discardSeat then
        return
    end
    EndActionTimer()
    local responses = window.responses
    local bestSeat, best
    local function priority(resp)
        if not resp or resp.kind == "PASS" then
            return 0
        end
        if resp.kind == "HU" then
            return 4
        elseif resp.kind == "GANG" or resp.kind == "PENG" then
            return 3
        elseif resp.kind == "CHI" then
            return 2
        end
        return 1
    end
    for seat, resp in pairs(responses) do
        local p = priority(resp)
        if p > 0 then
            if not best then
                bestSeat = seat
                best = resp
            else
                local bp = priority(best)
                if p > bp then
                    bestSeat = seat
                    best = resp
                elseif p == bp then
                    if SeatDistance(discardSeat, seat) < SeatDistance(discardSeat, bestSeat) then
                        bestSeat = seat
                        best = resp
                    end
                end
            end
        end
    end
    STATE.responseWindow = nil
    ClearActionPanel()
    if not best then
        UI.BeginTurn(NextSeat(discardSeat))
        return
    end
    if best.kind == "HU" then
        local ruleId = GetActiveRuleId()
        if IsBloodRiver(ruleId) then
            ResolveBloodRiverWin(bestSeat, discardSeat, false, {
                selfDraw = false,
                haiDi = (#STATE.deck == 0),
            })
            local nextSeat = NextSeat(discardSeat)
            SendRoundPublicState("ROUND_FINISH", {
                winSeat = bestSeat,
                discardSeat = discardSeat,
                selfDraw = false,
                continue = true,
                nextSeat = nextSeat,
                ruleId = ruleId,
            })
            C_Timer.After(0.35, function()
                BeginTurn(nextSeat)
            end)
        else
            ResolveRoundFinish(bestSeat, discardSeat, false, {
                selfDraw = false,
                haiDi = (#STATE.deck == 0),
            })
            SendRoundPublicState("ROUND_FINISH", {
                winSeat = bestSeat,
                discardSeat = discardSeat,
                selfDraw = false,
                ruleId = ruleId,
            })
        end
        return
    end
    ApplyMeldFromDiscard(bestSeat, discardSeat, best.kind, best.data)
    STATE.turn = bestSeat
    SendRoundPublicState("MELD_APPLY", {
        seat = bestSeat,
        kind = best.kind,
        discardSeat = discardSeat,
        combo = best.data and best.data.combo and Join(best.data.combo, ".") or "",
    })
    SendPrivateHandSync()
    RefreshTable()
    if best.kind == "GANG" then
        -- Ming-gang from discard needs a supplement draw before discard.
        UI.BeginTurn(bestSeat)
    else
        UI.BeginSeatDiscardPhase(bestSeat)
    end
end

local function SubmitResponse(seat, resp)
    local window = STATE.responseWindow
    if not window or not window.legal[seat] then
        return
    end
    if window.responses[seat] then
        return
    end
    window.responses[seat] = resp or { kind = "PASS" }
    local allDone = true
    for s in pairs(window.legal) do
        if not window.responses[s] then
            allDone = false
            break
        end
    end
    if allDone then
        ResolveResponseWindow(window.discardSeat)
    end
end

local function ShowActionChoicesForSeat(seat, legalActions, token)
    if seat ~= STATE.localSeat then
        return
    end
    if not UI.ActionPanel then
        return
    end
    EndDiscardTimer()
    UI.ActionPanel:Show()
    for _, child in ipairs({ UI.ActionPanel:GetChildren() }) do
        child:Hide()
    end
    local submitted = false
    local function submitChoice(kind, data)
        if submitted then
            return
        end
        submitted = true
        local currentToken = STATE.net.pendingActionToken
        if token and currentToken and token ~= currentToken then
            ClearActionPanel()
            return
        end
        if STATE.mode == "BATTLE" and not STATE.host then
            local payload = { token = token, kind = kind }
            if kind == "CHI" then
                payload.combo = (data and data.combo and Join(data.combo, ".")) or ""
            end
            Whisper(STATE.room.hostName, "ACTION_REQ", payload)
        elseif kind == "CHI" then
            SubmitResponse(seat, { kind = "CHI", data = data })
        else
            SubmitResponse(seat, { kind = kind })
        end
        ClearActionPanel()
    end
    local buttonDefs = {}
    local function formatChiComboLabel(combo)
        if type(combo) ~= "table" or #combo ~= 3 then
            return T("吃")
        end
        local nums = {}
        local suit, sameSuit = nil, true
        for _, tile in ipairs(combo) do
            local s, v = TileSuitAndValue(tile)
            if not s or not v then
                return T("吃") .. "(" .. Join(combo, "/") .. ")"
            end
            nums[#nums + 1] = tonumber(v)
            if not suit then
                suit = s
            elseif suit ~= s then
                sameSuit = false
            end
        end
        if not sameSuit then
            return T("吃") .. "(" .. Join(combo, "/") .. ")"
        end
        table.sort(nums)
        local suitText = (suit == "W" and "万") or (suit == "T" and "条") or (suit == "S" and "筒") or suit
        return T("吃") .. tostring(nums[1]) .. tostring(nums[2]) .. tostring(nums[3]) .. suitText
    end
    local function addBtn(label, onClick, isDanger)
        buttonDefs[#buttonDefs + 1] = {
            label = label,
            onClick = onClick,
            isDanger = isDanger,
        }
    end
    for _, action in ipairs(legalActions) do
        if action.kind == "HU" then
            addBtn(T("胡"), function()
                submitChoice("HU")
            end, true)
        elseif action.kind == "GANG" then
            addBtn(T("杠"), function()
                submitChoice("GANG")
            end, false)
        elseif action.kind == "PENG" then
            addBtn(T("碰"), function()
                submitChoice("PENG")
            end, false)
        elseif action.kind == "CHI" then
            local chiCombos = action.combos or {}
            if #chiCombos <= 1 then
                local combo = chiCombos[1]
                addBtn(formatChiComboLabel(combo), function()
                    submitChoice("CHI", { combo = combo })
                end, false)
            else
                for _, combo in ipairs(chiCombos) do
                    addBtn(formatChiComboLabel(combo), function()
                        submitChoice("CHI", { combo = combo })
                    end, false)
                end
            end
        end
    end
    addBtn(T("过"), function()
        submitChoice("PASS")
    end, false)

    local spacing = 68
    local xStart = -((#buttonDefs - 1) * spacing) / 2
    for idx, def in ipairs(buttonDefs) do
        local btn = CreateFrame("Button", nil, UI.ActionPanel, "UIPanelButtonTemplate")
        btn:SetSize(64, 34)
        btn:SetPoint("CENTER", xStart + (idx - 1) * spacing, 0)
        btn:SetText(def.isDanger and ("|cffff3333" .. def.label .. "|r") or def.label)
        btn:SetScript("OnClick", def.onClick)
    end
end

local function StartResponseWindow(discardSeat)
    EndDiscardTimer()
    local card = STATE.lastDiscard
    if not card then
        UI.BeginTurn(NextSeat(discardSeat))
        return
    end
    local legal = GetLegalResponses(discardSeat, card)
    local hasAny = false
    for _ in pairs(legal) do
        hasAny = true
        break
    end
    if not hasAny then
        UI.BeginTurn(NextSeat(discardSeat))
        return
    end

    local token = NewActionToken()
    STATE.net.pendingActionToken = token
    STATE.responseWindow = {
        token = token,
        discardSeat = discardSeat,
        legal = legal,
        responses = {},
    }

    if STATE.mode == "SINGLE" and not legal[STATE.localSeat] then
        for seat, actions in pairs(legal) do
            local aiPlayer = GetPlayer(seat)
            if aiPlayer and not aiPlayer.isHuman then
                local ok, resp = pcall(DecideAIResponse, aiPlayer.hand, aiPlayer.meldSetCount, actions, {
                    difficulty = GetConfiguredAIDifficulty(),
                    ruleId = GetActiveRuleId(),
                    missingSuit = aiPlayer.missingSuit,
                    players = STATE.players,
                    selfSeat = seat,
                    discardSeat = discardSeat,
                    discardCard = card,
                    stochastic = true,
                })
                if not ok then
                    resp = { kind = "PASS" }
                end
                SubmitResponse(seat, resp or { kind = "PASS" })
            else
                SubmitResponse(seat, { kind = "PASS" })
            end
        end
        local win = STATE.responseWindow
        if win and win.token == token and win.discardSeat == discardSeat then
            for seat in pairs(win.legal) do
                if not win.responses[seat] then
                    win.responses[seat] = { kind = "PASS" }
                end
            end
            ResolveResponseWindow(discardSeat)
        end
        return
    end

    local sec = math.max(1, tonumber(MajongMastersDB.timer.actionSec) or DB_DEFAULTS.timer.actionSec)
    BeginActionTimer(sec, function()
        local win = STATE.responseWindow
        if not win then
            return
        end
        for seat in pairs(win.legal) do
            if not win.responses[seat] then
                win.responses[seat] = { kind = "PASS" }
            end
        end
        ResolveResponseWindow(discardSeat)
    end)

    for seat, actions in pairs(legal) do
        if seat == STATE.localSeat then
            ShowActionChoicesForSeat(seat, actions, token)
        end
        if STATE.mode == "BATTLE" and STATE.host then
            local actionNames = {}
            for _, act in ipairs(actions) do
                actionNames[#actionNames + 1] = act.kind
            end
            local chiPayload = ""
            for _, act in ipairs(actions) do
                if act.kind == "CHI" then
                    local packed = {}
                    if type(act.combos) == "table" then
                        for _, combo in ipairs(act.combos) do
                            if type(combo) == "table" and #combo == 3 then
                                packed[#packed + 1] = Join(combo, ".")
                            end
                        end
                    end
                    chiPayload = Join(packed, "|")
                    break
                end
            end
            Whisper(GetPlayer(seat).name, "ACTION_PROMPT", {
                token = token,
                discardSeat = discardSeat,
                card = card,
                actions = Join(actionNames, "."),
                chi = chiPayload,
                sec = sec,
            })
        end
        if STATE.mode == "SINGLE" and seat ~= STATE.localSeat then
            local aiPlayer = GetPlayer(seat)
            if aiPlayer and not aiPlayer.isHuman then
                C_Timer.After(0.55 + SeatDistance(discardSeat, seat) * 0.12, function()
                    local win = STATE.responseWindow
                    if not win or win.token ~= token or win.discardSeat ~= discardSeat then
                        return
                    end
                    if win.responses[seat] then
                        return
                    end
                    local ok, resp = pcall(DecideAIResponse, aiPlayer.hand, aiPlayer.meldSetCount, actions, {
                        difficulty = GetConfiguredAIDifficulty(),
                        ruleId = GetActiveRuleId(),
                        missingSuit = aiPlayer.missingSuit,
                        players = STATE.players,
                        selfSeat = seat,
                        discardSeat = discardSeat,
                        discardCard = card,
                        stochastic = true,
                    })
                    if not ok then
                        resp = { kind = "PASS" }
                    end
                    SubmitResponse(seat, resp or { kind = "PASS" })
                end)
            end
        end
    end
end

UI.ScheduleResolveResponses = StartResponseWindow

local function PickRuleLegalFallbackDiscard(player)
    if not player or not player.hand or #player.hand == 0 then
        return nil
    end
    local ruleId = GetActiveRuleId()
    for i = #player.hand, 1, -1 do
        local card = player.hand[i]
        if CanDiscardByRule(ruleId, player.hand, card, player.missingSuit) then
            return card
        end
    end
    return player.hand[#player.hand]
end

local function SubmitAIDiscardNow(seat)
    if STATE.responseWindow or STATE.actionTimer or (UI.ActionPanel and UI.ActionPanel:IsShown()) then
        return false
    end
    if STATE.phase ~= "PLAYING" or STATE.turn ~= seat then
        return false
    end
    local p = GetPlayer(seat)
    if not p or p.isHuman or #p.hand == 0 then
        return false
    end
    if (#p.hand % 3) ~= 2 then
        return false
    end
    local ok, discard = pcall(ChooseAIDiscard, p.hand, p.meldSetCount, {
        difficulty = GetConfiguredAIDifficulty(),
        ruleId = GetActiveRuleId(),
        missingSuit = p.missingSuit,
        players = STATE.players,
        selfSeat = seat,
        stochastic = true,
    })
    if not ok or not discard then
        discard = PickRuleLegalFallbackDiscard(p)
    end
    if not discard then
        return false
    end
    if not CanDiscardByRule(GetActiveRuleId(), p.hand, discard, p.missingSuit) then
        discard = PickRuleLegalFallbackDiscard(p)
        if not discard then
            return false
        end
    end
    if RemoveByValue(p.hand, discard, 1) < 1 then
        discard = PickRuleLegalFallbackDiscard(p)
        if not discard or RemoveByValue(p.hand, discard, 1) < 1 then
            return false
        end
    end
    STATE.lastDiscard = discard
    p.discards[#p.discards + 1] = discard
    SortHand(p.hand, false)
    PlayDiscardVoice(discard)
    RefreshTable()
    EndActionTimer()
    StartResponseWindow(seat)
    return true
end

local function BeginSeatDiscardPhase(seat)
    if STATE.responseWindow or STATE.actionTimer or (UI.ActionPanel and UI.ActionPanel:IsShown()) then
        return
    end
    STATE.responseWindow = nil
    ClearActionPanel()
    EndActionTimer()
    STATE.turn = seat
    local p = GetPlayer(seat)
    if not p then
        return
    end
    STATE.net.pendingActionToken = NewActionToken()
    STATE.net.selfGangPromptDismissedToken = nil
    if STATE.mode == "BATTLE" and STATE.host then
        Broadcast("TURN_START", {
            seat = seat,
            sec = MajongMastersDB.timer.discardSec,
            token = STATE.net.pendingActionToken,
        })
    end
    local sec = MajongMastersDB.timer.discardSec
    BeginDiscardTimer(seat, sec, function()
        local panelBlocking = UI.ActionPanel and UI.ActionPanel:IsShown() and not STATE.net.selfGangPromptToken
        if STATE.responseWindow or STATE.actionTimer or panelBlocking then
            return
        end
        if STATE.phase ~= "PLAYING" or STATE.turn ~= seat then
            return
        end
        local player = GetPlayer(seat)
        if not player or #player.hand == 0 or (#player.hand % 3) ~= 2 then
            return
        end
        local autoCard = PickRuleLegalFallbackDiscard(player)
        SubmitDiscardLocal(autoCard)
    end)
    RefreshTable()
    if seat ~= STATE.localSeat then
        if STATE.mode == "SINGLE" and not p.isHuman then
            C_Timer.After(1.0, function()
                SubmitAIDiscardNow(seat)
            end)
            local fallbackDelay = math.min(2.2, math.max(1.2, sec * 0.35))
            C_Timer.After(fallbackDelay, function()
                SubmitAIDiscardNow(seat)
            end)
        end
    end
end

UI.BeginSeatDiscardPhase = BeginSeatDiscardPhase

UI.TryPromptLocalSelfGang = function()
    if STATE.phase ~= "PLAYING" or STATE.turn ~= STATE.localSeat then
        return false
    end
    if STATE.responseWindow or STATE.actionTimer then
        return false
    end
    if not UI.ActionPanel then
        return false
    end
    local p = GetPlayer(STATE.localSeat)
    if not p or not p.isHuman or (#p.hand % 3) ~= 2 then
        return false
    end
    local token = tostring(STATE.net.pendingActionToken or "")
    if token ~= "" and STATE.net.selfGangPromptDismissedToken == token then
        return false
    end
    local kongList = GetKongCandidates(p, nil, false)
    if #kongList == 0 then
        return false
    end
    if UI.ActionPanel:IsShown() and STATE.net.selfGangPromptToken == token then
        return true
    end
    UI.ActionPanel:Show()
    for _, child in ipairs({ UI.ActionPanel:GetChildren() }) do
        child:Hide()
    end
    STATE.net.selfGangPromptToken = token
    UpdateActionPanelTimerText(T("可选动作: 杠牌"))

    local submitted = false
    local function closePrompt(markDismissed)
        if markDismissed and token ~= "" then
            STATE.net.selfGangPromptDismissedToken = token
        end
        ClearActionPanel()
    end
    local function applyKong(info)
        if submitted or not info then
            return
        end
        submitted = true
        if STATE.mode == "BATTLE" and not STATE.host then
            EndDiscardTimer()
            Whisper(STATE.room.hostName, "ACTION_REQ", {
                token = STATE.net.pendingActionToken,
                kind = "GANG_SELF",
                tile = info.tile,
                gangKind = info.kind,
            })
            closePrompt(true)
            return
        end
        if not ApplyGangInDrawPhase(STATE.localSeat, info) then
            submitted = false
            closePrompt(false)
            return
        end
        SendRoundPublicState("MELD_APPLY", { seat = STATE.localSeat, kind = "GANG_SELF", tile = info.tile })
        SendPrivateHandSync()
        RefreshTable()
        EndDiscardTimer()
        closePrompt(true)
        C_Timer.After(0.35, function()
            if STATE.phase == "PLAYING" and STATE.turn == STATE.localSeat then
                BeginTurn(STATE.localSeat)
            end
        end)
    end

    local buttonDefs = {}
    for _, info in ipairs(kongList) do
        local kindText = (info.kind == "angang" and T("暗杠")) or (info.kind == "bugang" and T("补杠")) or T("杠")
        local tileText = ResultOps.TileToText(info.tile)
        buttonDefs[#buttonDefs + 1] = {
            label = kindText .. tileText,
            onClick = function()
                applyKong(info)
            end,
        }
    end
    buttonDefs[#buttonDefs + 1] = {
        label = T("过"),
        onClick = function()
            closePrompt(true)
        end,
    }

    local spacing = 86
    local xStart = -((#buttonDefs - 1) * spacing) / 2
    for idx, def in ipairs(buttonDefs) do
        local btn = CreateFrame("Button", nil, UI.ActionPanel, "UIPanelButtonTemplate")
        btn:SetSize(82, 34)
        btn:SetPoint("CENTER", xStart + (idx - 1) * spacing, 0)
        btn:SetText(def.label)
        btn:SetScript("OnClick", def.onClick)
    end
    return true
end

local function BeginTurn(seat)
    if STATE.phase ~= "PLAYING" then
        return
    end
    if STATE.responseWindow or STATE.actionTimer or (UI.ActionPanel and UI.ActionPanel:IsShown()) then
        return
    end
    if #STATE.deck == 0 then
        STATE.phase = "FINISHED"
        SetWallText(T("流局"))
        RefreshTable()
        if UI.StartSingleBtn and STATE.mode == "SINGLE" then
            UI.StartSingleBtn:Show()
        elseif UI.BattlePanel and STATE.mode == "BATTLE" then
            UI.BattlePanel:Show()
        end
        return
    end
    local tile = DrawTileForSeat(seat)
    if not tile then
        STATE.phase = "FINISHED"
        SetWallText(T("流局"))
        RefreshTable()
        return
    end
    SendRoundPublicState("DRAW_APPLY", { seat = seat })
    SendPrivateHandSync()
    local p = GetPlayer(seat)
    local tempHand = CopyArray(p.hand)
    local ruleId = GetActiveRuleId()
    local canHu = IsWinWithMelds(tempHand, p.meldSetCount, BuildRuleWinCheckOptions())
    if canHu and RequiresMissingSuit(ruleId) and not IsMissingSuitCleared(ruleId, p) then
        canHu = false
    end
    if canHu then
        if IsBloodRiver(ruleId) then
            ResolveBloodRiverWin(seat, nil, true, {
                selfDraw = true,
                haiDi = (#STATE.deck == 0),
            })
            SendRoundPublicState("ROUND_FINISH", {
                winSeat = seat,
                selfDraw = true,
                continue = true,
                nextSeat = NextSeat(seat),
                ruleId = ruleId,
            })
            C_Timer.After(0.5, function()
                BeginTurn(NextSeat(seat))
            end)
        else
            ResolveRoundFinish(seat, nil, true, {
                selfDraw = true,
                haiDi = (#STATE.deck == 0),
            })
            SendRoundPublicState("ROUND_FINISH", {
                winSeat = seat,
                selfDraw = true,
                ruleId = ruleId,
            })
        end
        return
    end
    local kongList = GetKongCandidates(p, nil, false)
    if #kongList > 0 and seat ~= STATE.localSeat and STATE.mode == "SINGLE" and not p.isHuman then
        local chosenKong = SelectKongInDraw(p, kongList, {
            difficulty = GetConfiguredAIDifficulty(),
            ruleId = GetActiveRuleId(),
            missingSuit = p.missingSuit,
            players = STATE.players,
            selfSeat = seat,
            stochastic = true,
        })
        if chosenKong and ApplyGangInDrawPhase(seat, chosenKong) then
            SendRoundPublicState("MELD_APPLY", { seat = seat, kind = "GANG_SELF", tile = chosenKong.tile })
            SendPrivateHandSync()
            RefreshTable()
            C_Timer.After(0.5, function()
                BeginTurn(seat)
            end)
            return
        end
    end
    RefreshTable()
    BeginSeatDiscardPhase(seat)
    if seat == STATE.localSeat then
        UI.TryPromptLocalSelfGang()
    end
end

UI.BeginTurn = BeginTurn

local function StartSingleGame()
    STATE.mode = "SINGLE"
    STATE.host = true
    STATE.localSeat = 1
    STATE.phase = "PLAYING"
    STATE.ruleId = NormalizeRuleId((UI.SingleRuleSelection and UI.SingleRuleSelection.ruleId) or GetConfiguredRuleId())
    STATE.room.ruleId = STATE.ruleId
    STATE.currentRound = STATE.currentRound + 1
    ResetRoundCommon()
    local names = {
        FullNameFromUnit("player") or T("我"),
        T("AI-下家"),
        T("AI-对家"),
        T("AI-上家"),
    }
    for seat = 1, 4 do
        STATE.players[seat] = BuildPlayer(names[seat], seat == 1)
    end
    STATE.scores = { 0, 0, 0, 0 }
    STATE.deck = BuildRuleDeck(STATE.ruleId)
    for seat = 1, 4 do
        for _ = 1, 13 do
            STATE.players[seat].hand[#STATE.players[seat].hand + 1] = table.remove(STATE.deck, 1)
        end
        SortHand(STATE.players[seat].hand, false)
        if RequiresMissingSuit(STATE.ruleId) then
            STATE.players[seat].missingSuit = ChooseMissingSuit(STATE.players[seat].hand)
        else
            STATE.players[seat].missingSuit = nil
        end
        STATE.players[seat].winCount = 0
    end
    StopBGM()
    PlayBGM()
    ClearActionPanel()
    HideStartButtons()
    if UI.HomeBtn then
        UI.HomeBtn:Show()
    end
    RefreshTable()
    BeginTurn(1)
end

local function EnterBattleLobby()
    STATE.mode = "BATTLE"
    STATE.phase = "LOBBY"
    STATE.host = false
    STATE.ruleId = GetConfiguredRuleId()
    STATE.room.id = nil
    STATE.room.gameId = nil
    STATE.room.ruleId = STATE.ruleId
    STATE.room.hostName = nil
    STATE.room.players = {}
    STATE.room.watchers = {}
    STATE.room.announced = nil
    STATE.scores = { 0, 0, 0, 0 }
    if UI.BattleRuleSelection and UI.BattleRuleSelection.SetRule then
        UI.BattleRuleSelection.SetRule(STATE.room.ruleId, true)
    end
    ClearActionPanel()
    ResetTimers()
    SetStatusText(T("对战大厅：可建房或加入"))
    SetWallText("")
    RefreshTable()
    ShowBattlePanel()
end

local function SyncLobbyText()
    if not UI.BattlePanel then
        return
    end
    local lines = {}
    lines[#lines + 1] = T("房间ID: %s", tostring(STATE.room.id or T("无")))
    lines[#lines + 1] = T("房主: %s", tostring(ShortName(STATE.room.hostName or T("无"))))
    lines[#lines + 1] = RuleInfoText(STATE.room.ruleId or STATE.ruleId)
    if #STATE.room.players > 0 then
        local list = {}
        for _, n in ipairs(STATE.room.players) do
            list[#list + 1] = ShortName(n)
        end
        lines[#lines + 1] = T("牌手: %s", Join(list, " / "))
    end
    if #STATE.room.watchers > 0 then
        local list = {}
        for _, n in ipairs(STATE.room.watchers) do
            list[#list + 1] = ShortName(n)
        end
        lines[#lines + 1] = T("旁观: %s", Join(list, " / "))
    end
    UI.BattlePanel.Status:SetText(Join(lines, "\n"))
end

local function RefreshBattlePanelAvailability()
    if not UI.BattlePanel then
        return
    end
    local blocked, reason = IsRestrictedByMapOrLockdown()
    local enabled = not blocked
    local function setButtonState(btn)
        if not btn then
            return
        end
        btn:SetEnabled(enabled)
        btn:SetAlpha(enabled and 1 or 0.55)
    end
    setButtonState(UI.BattlePanel.CreateBtn)
    setButtonState(UI.BattlePanel.JoinBtn)
    setButtonState(UI.BattlePanel.StartBtn)
    if blocked then
        UI.BattlePanel.Status:SetText(T("联机通信受限\n%s\n请离开副本、结束战斗后重试（或使用单人模式）", tostring(reason)))
    elseif STATE.phase == "LOBBY" then
        SyncLobbyText()
    end
end

local function HostCreateRoom()
    local allowed, reason = IsHomeGroupReadyForBattle()
    if not allowed then
        PrintInfo(reason)
        return
    end
    local blocked, breason = IsRestrictedByMapOrLockdown()
    if blocked then
        PrintInfo(breason)
        return
    end
    local ok, err = EnsurePrefixRegistered()
    if not ok then
        PrintInfo(err)
        return
    end
    STATE.host = true
    STATE.phase = "LOBBY"
    local me = FullNameFromUnit("player")
    STATE.room.hostName = me
    STATE.room.id = string.format("MM-%d", math.floor(GetServerTime() % 1000000))
    STATE.room.gameId = nil
    STATE.room.ruleId = NormalizeRuleId((UI.BattleRuleSelection and UI.BattleRuleSelection.ruleId) or STATE.room.ruleId or STATE.ruleId or GetConfiguredRuleId())
    STATE.ruleId = STATE.room.ruleId
    STATE.room.players = { me }
    STATE.room.watchers = {}
    STATE.scores = { 0, 0, 0, 0 }
    SyncLobbyText()
    Broadcast("ROOM_ANNOUNCE", {
        room = STATE.room.id,
        host = me,
        count = #STATE.room.players,
        ruleId = STATE.room.ruleId,
    })
    PrintInfo(T("已建房：%s", STATE.room.id))
end

local function JoinAnnouncedRoom()
    local blocked, breason = IsRestrictedByMapOrLockdown()
    if blocked then
        PrintInfo(breason)
        return
    end
    local ok, err = EnsurePrefixRegistered()
    if not ok then
        PrintInfo(err)
        return
    end
    if not STATE.room.announced or not STATE.room.announced.host then
        PrintInfo(T("当前没有可加入房间"))
        return
    end
    local host = STATE.room.announced.host
    STATE.room.hostName = CanonicalFullName(host)
    STATE.room.id = STATE.room.announced.room
    STATE.room.ruleId = NormalizeRuleId(STATE.room.announced.ruleId or STATE.room.ruleId or STATE.ruleId)
    STATE.ruleId = STATE.room.ruleId
    STATE.scores = { 0, 0, 0, 0 }
    Whisper(STATE.room.hostName, "JOIN_REQ", {
        room = STATE.room.id,
        player = FullNameFromUnit("player"),
    })
    PrintInfo(T("已发送加入请求 -> %s", ShortName(STATE.room.hostName)))
end

local function HostBroadcastLobby()
    Broadcast("LOBBY_SYNC", {
        room = STATE.room.id,
        gameId = STATE.room.gameId or "",
        ruleId = STATE.room.ruleId or STATE.ruleId,
        host = STATE.room.hostName,
        players = Join(STATE.room.players, "|"),
        watchers = Join(STATE.room.watchers, "|"),
    })
end

local function HostAssignJoin(playerName)
    if STATE.phase ~= "LOBBY" or not STATE.host then
        return
    end
    playerName = CanonicalFullName(playerName)
    if playerName == STATE.room.hostName then
        return
    end
    for _, n in ipairs(STATE.room.players) do
        if n == playerName then
            return
        end
    end
    for _, n in ipairs(STATE.room.watchers) do
        if n == playerName then
            return
        end
    end
    if #STATE.room.players < 4 then
        STATE.room.players[#STATE.room.players + 1] = playerName
        Whisper(playerName, "JOIN_ACK", {
            room = STATE.room.id,
            role = "player",
            index = #STATE.room.players,
        })
    else
        STATE.room.watchers[#STATE.room.watchers + 1] = playerName
        Whisper(playerName, "JOIN_ACK", {
            room = STATE.room.id,
            role = "watcher",
            index = #STATE.room.watchers,
        })
    end
    HostBroadcastLobby()
    SyncLobbyText()
end

local function ResetNextRoundState()
    STATE.nextRoundToken = nil
    STATE.nextRoundPrompted = false
    STATE.nextRoundJoinedBy = {}
end

local function HostTryStartNextRound()
    if not STATE.host or STATE.mode ~= "BATTLE" then
        return
    end
    if not STATE.nextRoundPrompted or not STATE.nextRoundToken then
        return
    end
    if #STATE.room.players ~= 4 then
        return
    end
    for _, playerName in ipairs(STATE.room.players) do
        local key = CanonicalFullName(playerName)
        if not STATE.nextRoundJoinedBy[key] then
            return
        end
    end
    STATE.phase = "LOBBY"
    if UI.StartBattleRoundAsHost then
        UI.StartBattleRoundAsHost()
    end
end

local function HostPromptNextRound()
    if STATE.mode ~= "BATTLE" or not STATE.host or STATE.phase ~= "FINISHED" then
        return
    end
    STATE.nextRoundToken = NewActionToken()
    STATE.nextRoundPrompted = true
    STATE.nextRoundJoinedBy = {}
    STATE.nextRoundJoinedBy[CanonicalFullName(STATE.room.hostName)] = true
    Broadcast("ROUND_NEXT_PROMPT", {
        token = STATE.nextRoundToken,
        room = STATE.room.id or "",
        gameId = STATE.room.gameId or "",
    })
    if STATE.lastRoundResult then
        ResultOps.ShowResultPanel(STATE.lastRoundResult)
    end
    HostTryStartNextRound()
end

UI.StartBattleRoundAsHost = function()
    if not STATE.host or (STATE.phase ~= "LOBBY" and STATE.phase ~= "FINISHED") then
        return
    end
    local blocked, breason = IsRestrictedByMapOrLockdown()
    if blocked then
        PrintInfo(breason)
        return
    end
    if #STATE.room.players ~= 4 then
        PrintInfo(T("需要 4 名牌手才能开始"))
        return
    end
    ResetNextRoundState()
    STATE.phase = "PLAYING"
    STATE.currentRound = STATE.currentRound + 1
    STATE.room.gameId = string.format("%s-G%d", STATE.room.id or "MM", STATE.currentRound)
    ResetRoundCommon()
    STATE.players = {}
    for seat = 1, 4 do
        local full = CanonicalFullName(STATE.room.players[seat]) or ("Seat" .. tostring(seat))
        STATE.players[seat] = BuildPlayer(full, true)
    end
    local me = FullNameFromUnit("player")
    STATE.localSeat = FindSeatByName(me) or 1
    STATE.dealerSeat = 1
    STATE.turn = STATE.dealerSeat
    STATE.scores = STATE.scores or { 0, 0, 0, 0 }
    STATE.ruleId = NormalizeRuleId(STATE.room.ruleId or STATE.ruleId or GetConfiguredRuleId())
    STATE.room.ruleId = STATE.ruleId
    STATE.deck = BuildRuleDeck(STATE.ruleId)
    for seat = 1, 4 do
        for _ = 1, 13 do
            STATE.players[seat].hand[#STATE.players[seat].hand + 1] = table.remove(STATE.deck, 1)
        end
        SortHand(STATE.players[seat].hand, false)
        if RequiresMissingSuit(STATE.ruleId) then
            STATE.players[seat].missingSuit = ChooseMissingSuit(STATE.players[seat].hand)
        else
            STATE.players[seat].missingSuit = nil
        end
        STATE.players[seat].winCount = 0
    end
    Broadcast("GAME_START", {
        room = STATE.room.id,
        gameId = STATE.room.gameId,
        ruleId = STATE.ruleId,
        p1 = STATE.players[1].name,
        p2 = STATE.players[2].name,
        p3 = STATE.players[3].name,
        p4 = STATE.players[4].name,
        m1 = STATE.players[1].missingSuit or "",
        m2 = STATE.players[2].missingSuit or "",
        m3 = STATE.players[3].missingSuit or "",
        m4 = STATE.players[4].missingSuit or "",
        dealer = STATE.dealerSeat,
    })
    SendPrivateHandSync()
    StopBGM()
    PlayBGM()
    if UI.ResultPanel then
        UI.ResultPanel:Hide()
    end
    RefreshTable()
    BeginTurn(STATE.dealerSeat)
end

local function BuildBattleClientPlayers(payload)
    STATE.room.id = payload.room or STATE.room.id
    STATE.room.gameId = payload.gameId or payload.g or STATE.room.gameId
    STATE.ruleId = NormalizeRuleId(payload.ruleId or payload.rule or STATE.room.ruleId or STATE.ruleId)
    STATE.room.ruleId = STATE.ruleId
    STATE.players = {
        BuildPlayer(CanonicalFullName(payload.p1), true),
        BuildPlayer(CanonicalFullName(payload.p2), true),
        BuildPlayer(CanonicalFullName(payload.p3), true),
        BuildPlayer(CanonicalFullName(payload.p4), true),
    }
    STATE.localSeat = FindSeatByName(FullNameFromUnit("player")) or 1
    STATE.dealerSeat = payload.dealer or 1
    STATE.turn = STATE.dealerSeat
    STATE.phase = "PLAYING"
    STATE.deck = {}
    local totalTiles = #BuildRuleDeck(STATE.ruleId)
    local drawAfterDeal = math.max(0, totalTiles - 52)
    for _ = 1, drawAfterDeal do
        STATE.deck[#STATE.deck + 1] = "X"
    end
    for seat = 1, 4 do
        STATE.players[seat].hand = {}
        STATE.players[seat].discards = {}
        STATE.players[seat].melds = {}
        STATE.players[seat].meldSetCount = 0
        STATE.players[seat].missingSuit = payload["m" .. tostring(seat)] ~= "" and payload["m" .. tostring(seat)] or nil
        STATE.players[seat].winCount = 0
    end
end

local function UpdateClientPublicFromPacket(playersInfo)
    if type(playersInfo) ~= "table" then
        return
    end
    for i = 1, 4 do
        local info = playersInfo[i]
        local p = STATE.players[i]
        if info and p then
            local handCount = tonumber(info.hand) or #p.hand
            if i ~= STATE.localSeat then
                while #p.hand < handCount do
                    p.hand[#p.hand + 1] = "0W"
                end
                while #p.hand > handCount do
                    table.remove(p.hand)
                end
            end
            p.discards = info.disc and Split(info.disc, ".") or p.discards
            if info.miss and info.miss ~= "" then
                p.missingSuit = info.miss
            end
            p.winCount = tonumber(info.wins) or p.winCount or 0
        end
    end
end

local function SetPlaceholderHandCount(player, count)
    if not player then
        return
    end
    count = math.max(0, tonumber(count) or 0)
    while #player.hand < count do
        player.hand[#player.hand + 1] = "0W"
    end
    while #player.hand > count do
        table.remove(player.hand)
    end
end

local function BuildSnapshotForTarget(targetName)
    local targetSeat = FindSeatByName(targetName) or 0
    local playerRows = {}
    for seat = 1, 4 do
        local p = STATE.players[seat]
        if p then
            playerRows[#playerRows + 1] = table.concat({
                tostring(seat),
                p.name or "",
                tostring(#p.hand),
                tostring(#p.discards),
                tostring(#p.melds),
                p.missingSuit or "",
                tostring(p.winCount or 0),
            }, ";")
        end
    end
    local localHand = ""
    if targetSeat >= 1 and targetSeat <= 4 and STATE.players[targetSeat] then
        localHand = Join(STATE.players[targetSeat].hand, ".")
    end
    return {
        room = STATE.room.id or "",
        gameId = STATE.room.gameId or "",
        ruleId = GetActiveRuleId(),
        round = STATE.currentRound or 0,
        phase = STATE.phase or "IDLE",
        turn = STATE.turn or 1,
        dealer = STATE.dealerSeat or 1,
        deck = #STATE.deck,
        last = STATE.lastDiscard or "",
        scores = Join(STATE.scores or {}, ","),
        token = STATE.net.pendingActionToken or "",
        hash = STATE.net.eventHash or "0",
        seat = targetSeat,
        hand = localHand,
        players = Join(playerRows, "|"),
    }
end

local function SendSnapshotTo(targetName, reason)
    local snap = BuildSnapshotForTarget(targetName)
    local body = EncodePacket(snap)
    if not body then
        return
    end
    local chunkSize = 110
    local total = math.max(1, math.ceil(#body / chunkSize))
    local sid = string.format("%d-%d", math.floor(GetTimePreciseSec() * 1000), math.random(1000, 9999))
    for idx = 1, total do
        local beginAt = (idx - 1) * chunkSize + 1
        local part = body:sub(beginAt, beginAt + chunkSize - 1)
        Whisper(targetName, "SNAPSHOT_PART", {
            sid = sid,
            idx = idx,
            total = total,
            data = part,
            reason = reason or "",
        })
    end
end

local function ApplySnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return
    end
    STATE.room.id = snapshot.room or STATE.room.id
    STATE.room.gameId = snapshot.gameId or STATE.room.gameId
    STATE.ruleId = NormalizeRuleId(snapshot.ruleId or STATE.ruleId)
    STATE.room.ruleId = STATE.ruleId
    STATE.currentRound = tonumber(snapshot.round) or STATE.currentRound
    STATE.phase = snapshot.phase or STATE.phase
    STATE.turn = tonumber(snapshot.turn) or STATE.turn
    STATE.dealerSeat = tonumber(snapshot.dealer) or STATE.dealerSeat
    STATE.net.pendingActionToken = snapshot.token or STATE.net.pendingActionToken
    STATE.net.eventHash = snapshot.hash or STATE.net.eventHash
    STATE.lastDiscard = snapshot.last or STATE.lastDiscard

    local deckCount = tonumber(snapshot.deck) or #STATE.deck
    STATE.deck = {}
    for _ = 1, math.max(0, deckCount) do
        STATE.deck[#STATE.deck + 1] = "X"
    end

    local scoreList = Split(snapshot.scores or "", ",")
    for i = 1, 4 do
        STATE.scores[i] = tonumber(scoreList[i]) or STATE.scores[i] or 0
    end

    local playerRows = Split(snapshot.players or "", "|")
    for _, row in ipairs(playerRows) do
        local cols = Split(row, ";")
        local seat = tonumber(cols[1])
        if seat and seat >= 1 and seat <= 4 and STATE.players[seat] then
            local p = STATE.players[seat]
            p.name = cols[2] or p.name
            p.discards = {}
            p.melds = {}
            local handCount = tonumber(cols[3]) or #p.hand
            if seat == STATE.localSeat then
                local hand = Split(snapshot.hand or "", ".")
                if #hand > 0 then
                    p.hand = hand
                    SortHand(p.hand, true)
                else
                    SetPlaceholderHandCount(p, handCount)
                end
            else
                SetPlaceholderHandCount(p, handCount)
            end
            local discCount = tonumber(cols[4]) or 0
            for _ = 1, math.max(0, discCount) do
                p.discards[#p.discards + 1] = "0W"
            end
            local meldCount = tonumber(cols[5]) or 0
            for _ = 1, math.max(0, meldCount) do
                p.melds[#p.melds + 1] = { type = "unknown", tiles = {} }
            end
            p.missingSuit = cols[6] ~= "" and cols[6] or p.missingSuit
            p.winCount = tonumber(cols[7]) or p.winCount or 0
        end
    end
    RefreshTable()
end

local function RequestSnapshot(reason)
    if STATE.host or STATE.mode ~= "BATTLE" then
        return
    end
    if not STATE.room.hostName then
        return
    end
    if STATE.net.resyncPending then
        return
    end
    STATE.net.resyncPending = true
    STATE.net.resyncAt = GetTimePreciseSec()
    Whisper(STATE.room.hostName, "SNAPSHOT_REQ", {
        reason = reason or "seq_gap",
        room = STATE.room.id or "",
        gameId = STATE.room.gameId or "",
    })
end

local function HandleHostActionRequest(sender, payload)
    if not STATE.host or STATE.phase ~= "PLAYING" then
        return
    end
    if payload.token ~= STATE.net.pendingActionToken then
        return
    end
    local seat = FindSeatByName(sender)
    if not seat then
        return
    end
    if payload.kind == "GANG_SELF" and seat == STATE.turn then
        local p = GetPlayer(seat)
        if not p then
            return
        end
        local chosen
        local wantTile = payload.tile
        local wantKind = payload.gangKind
        for _, info in ipairs(GetKongCandidates(p, nil, false)) do
            if info.tile == wantTile and (not wantKind or wantKind == "" or info.kind == wantKind) then
                chosen = info
                break
            end
        end
        if chosen and ApplyGangInDrawPhase(seat, chosen) then
            SendRoundPublicState("MELD_APPLY", { seat = seat, kind = "GANG_SELF", tile = chosen.tile })
            SendPrivateHandSync()
            RefreshTable()
            C_Timer.After(0.2, function()
                if STATE.phase == "PLAYING" and STATE.turn == seat then
                    BeginTurn(seat)
                end
            end)
        end
        return
    end
    if payload.kind == "DISCARD" and seat == STATE.turn then
        local p = GetPlayer(seat)
        if not p then
            return
        end
        if not CanDiscardByRule(GetActiveRuleId(), p.hand, payload.card, p.missingSuit) then
            return
        end
        local ok = false
        for _, c in ipairs(p.hand) do
            if c == payload.card then
                ok = true
                break
            end
        end
        if ok then
            RemoveByValue(p.hand, payload.card, 1)
            STATE.lastDiscard = payload.card
            p.discards[#p.discards + 1] = payload.card
            SortHand(p.hand, false)
            PlayDiscardVoice(payload.card)
            SendRoundPublicState("DISCARD_APPLY", { seat = seat, card = payload.card })
            SendPrivateHandSync()
            RefreshTable()
            StartResponseWindow(seat)
        end
        return
    end
    if STATE.responseWindow and STATE.responseWindow.token == payload.token then
        local legal = STATE.responseWindow.legal[seat]
        if not legal then
            return
        end
        local kind = payload.kind or "PASS"
        if kind == "PASS" then
            SubmitResponse(seat, { kind = "PASS" })
            return
        end
        for _, act in ipairs(legal) do
            if act.kind == kind then
                if kind == "CHI" then
                    local combo = Split(payload.combo or "", ".")
                    if #combo == 3 and act.combos and #act.combos > 0 then
                        local matched = false
                        for _, legalCombo in ipairs(act.combos) do
                            if legalCombo[1] == combo[1] and legalCombo[2] == combo[2] and legalCombo[3] == combo[3] then
                                matched = true
                                break
                            end
                        end
                        if matched then
                            SubmitResponse(seat, { kind = "CHI", data = { combo = combo } })
                        else
                            SubmitResponse(seat, { kind = "PASS" })
                        end
                    else
                        SubmitResponse(seat, { kind = "PASS" })
                    end
                else
                    SubmitResponse(seat, { kind = kind })
                end
                return
            end
        end
    end
end

local function HandleIncomingPacket(sender, packet)
    sender = CanonicalFullName(sender)
    packet = NormalizePacket(packet)
    if not packet then
        return
    end
    local valid, reason = ValidatePacket(packet)
    if not valid then
        if not STATE.host and reason == "crc_mismatch" then
            RequestSnapshot("crc_mismatch")
        end
        return
    end

    local t = packet.msgType
    local p = packet.payload or {}
    local selfName = CanonicalFullName(FullNameFromUnit("player"))

    if packet.ack and packet.ack > (STATE.net.maxAckSeq or 0) then
        STATE.net.maxAckSeq = packet.ack
    end

    if t == "ACK" then
        AckReliable(p.ackActionId, tonumber(p.ackSeq))
        return
    end

    local senderKey = packet.senderGuid ~= "" and packet.senderGuid or sender
    local lastSeq = STATE.net.recvSeqBySender[senderKey] or 0
    if not STATE.host and packet.seq > lastSeq + 1 then
        RequestSnapshot("seq_gap")
    end
    if packet.seq > lastSeq then
        STATE.net.recvSeqBySender[senderKey] = packet.seq
    end
    if packet.seq > (STATE.net.recvSeq or 0) then
        STATE.net.recvSeq = packet.seq
    end
    if packet.seq > (STATE.net.maxAckSeq or 0) then
        STATE.net.maxAckSeq = packet.seq
    end

    if packet.actionId ~= "" then
        if STATE.net.seenActionIds[packet.actionId] then
            if RELIABLE_MSG_TYPES[t] and sender ~= selfName then
                SendPacket("ACK", { ackActionId = packet.actionId, ackSeq = packet.seq }, "WHISPER", sender, { skipReliable = true })
            end
            return
        end
        STATE.net.seenActionIds[packet.actionId] = GetTimePreciseSec()
    end

    if RELIABLE_MSG_TYPES[t] and packet.actionId ~= "" and sender ~= selfName then
        SendPacket("ACK", { ackActionId = packet.actionId, ackSeq = packet.seq }, "WHISPER", sender, { skipReliable = true })
    end

    if HASH_CHAIN_MSG_TYPES[t] and not STATE.host then
        if STATE.net.eventHash and STATE.net.eventHash ~= "0" and packet.prevHash ~= "" and packet.prevHash ~= STATE.net.eventHash then
            RequestSnapshot("event_hash_mismatch")
        end
        if packet.eventHash and packet.eventHash ~= "" then
            STATE.net.eventHash = packet.eventHash
        end
    end

    if p.players then
        UpdateClientPublicFromPacket(p.players)
    end
    if p.ruleId or p.rule then
        STATE.ruleId = NormalizeRuleId(p.ruleId or p.rule)
        STATE.room.ruleId = STATE.ruleId
    end
    if p.last and p.last ~= "" then
        STATE.lastDiscard = p.last
    end
    if p.deck ~= nil and not STATE.host then
        local deckCount = tonumber(p.deck)
        if deckCount then
            while #STATE.deck > deckCount do
                table.remove(STATE.deck)
            end
            while #STATE.deck < deckCount do
                STATE.deck[#STATE.deck + 1] = "X"
            end
        end
    end

    if t == "SNAPSHOT_REQ" and STATE.host then
        SendSnapshotTo(sender, p.reason or "manual")
        return
    end

    if t == "SNAPSHOT_PART" and not STATE.host then
        local sid = p.sid
        local idx = tonumber(p.idx)
        local total = tonumber(p.total)
        local data = p.data
        if sid and idx and total and total > 0 and data then
            local box = STATE.net.snapshotInbox[sid]
            if not box then
                box = {
                    total = total,
                    parts = {},
                    count = 0,
                    at = GetTimePreciseSec(),
                }
                STATE.net.snapshotInbox[sid] = box
            end
            if not box.parts[idx] then
                box.parts[idx] = data
                box.count = box.count + 1
            end
            if box.count >= box.total then
                local merged = {}
                for i = 1, box.total do
                    merged[#merged + 1] = box.parts[i] or ""
                end
                STATE.net.snapshotInbox[sid] = nil
                local snapshot = DecodePacket(table.concat(merged))
                if snapshot then
                    ApplySnapshot(snapshot)
                    STATE.net.resyncPending = false
                    STATE.net.resyncAt = 0
                end
            end
        end
        return
    end

    if t == "ROOM_ANNOUNCE" then
        if STATE.host then
            return
        end
        STATE.room.announced = {
            room = p.room,
            host = CanonicalFullName(p.host),
            count = p.count,
            ruleId = NormalizeRuleId(p.ruleId or p.rule),
        }
        if UI.BattlePanel then
            UI.BattlePanel.JoinBtn:SetText(T("加入房间(%s/4)", tostring(p.count or 0)))
        end
        if UI.BattleRuleSelection and UI.BattleRuleSelection.SetRule and STATE.phase == "LOBBY" then
            UI.BattleRuleSelection.SetRule(STATE.room.announced.ruleId, true)
        end
        return
    end

    if t == "JOIN_REQ" and STATE.host then
        HostAssignJoin(p.player or sender)
        return
    end

    if t == "JOIN_ACK" then
        local roleText = tostring(p.role)
        if roleText == "player" then
            roleText = T("牌手")
        elseif roleText == "watcher" then
            roleText = T("旁观")
        end
        PrintInfo(T("加入成功，身份：%s", roleText))
        return
    end

    if t == "LOBBY_SYNC" then
        if STATE.host then
            return
        end
        STATE.room.id = p.room
        STATE.room.gameId = p.gameId ~= "" and p.gameId or STATE.room.gameId
        STATE.room.ruleId = NormalizeRuleId(p.ruleId or p.rule or STATE.room.ruleId)
        STATE.ruleId = STATE.room.ruleId
        STATE.room.hostName = CanonicalFullName(p.host)
        STATE.room.players = Split(p.players or "", "|")
        STATE.room.watchers = Split(p.watchers or "", "|")
        if UI.BattleRuleSelection and UI.BattleRuleSelection.SetRule then
            UI.BattleRuleSelection.SetRule(STATE.room.ruleId, true)
        end
        SyncLobbyText()
        return
    end

    if t == "GAME_START" then
        if STATE.host then
            return
        end
        STATE.mode = "BATTLE"
        STATE.host = false
        STATE.phase = "PLAYING"
        BuildBattleClientPlayers(p)
        if UI.BattleRuleSelection and UI.BattleRuleSelection.SetRule then
            UI.BattleRuleSelection.SetRule(STATE.ruleId, true)
        end
        STATE.net.resyncPending = false
        StopBGM()
        PlayBGM()
        RefreshTable()
        return
    end

    if t == "ACTION_REQ" and STATE.host then
        HandleHostActionRequest(sender, p)
        return
    end

    if t == "ROUND_NEXT_PROMPT" then
        if STATE.mode ~= "BATTLE" then
            return
        end
        if p.room and STATE.room.id and p.room ~= STATE.room.id then
            return
        end
        STATE.nextRoundToken = p.token
        STATE.nextRoundPrompted = true
        STATE.nextRoundJoinedBy = {}
        local hostName = CanonicalFullName(STATE.room.hostName or sender)
        if hostName then
            STATE.nextRoundJoinedBy[hostName] = true
        end
        if STATE.lastRoundResult then
            ResultOps.ShowResultPanel(STATE.lastRoundResult)
        end
        return
    end

    if t == "ROUND_NEXT_JOIN" then
        if STATE.mode ~= "BATTLE" then
            return
        end
        if p.room and STATE.room.id and p.room ~= STATE.room.id then
            return
        end
        if not p.token or p.token ~= STATE.nextRoundToken then
            return
        end
        local joinedName = CanonicalFullName(p.player or sender)
        if not joinedName or joinedName == "" then
            return
        end
        if STATE.host then
            if STATE.phase ~= "FINISHED" or not STATE.nextRoundPrompted then
                return
            end
            if not FindSeatByName(joinedName) then
                return
            end
            if not STATE.nextRoundJoinedBy[joinedName] then
                STATE.nextRoundJoinedBy[joinedName] = true
                Broadcast("ROUND_NEXT_JOIN", {
                    room = STATE.room.id or "",
                    gameId = STATE.room.gameId or "",
                    token = STATE.nextRoundToken,
                    player = joinedName,
                })
            end
            if STATE.lastRoundResult then
                ResultOps.ShowResultPanel(STATE.lastRoundResult)
            end
            HostTryStartNextRound()
        else
            STATE.nextRoundJoinedBy[joinedName] = true
            if STATE.lastRoundResult then
                ResultOps.ShowResultPanel(STATE.lastRoundResult)
            end
        end
        return
    end

    if t == "HAND_SYNC" then
        if STATE.phase ~= "PLAYING" and STATE.phase ~= "PAUSED" then
            return
        end
        local seat = tonumber(p.seat)
        local hand = Split(p.hand or "", ".")
        if seat and seat == STATE.localSeat and STATE.players[seat] then
            STATE.players[seat].hand = hand
            STATE.players[seat].meldSetCount = tonumber(p.meldCount) or STATE.players[seat].meldSetCount
            STATE.players[seat].missingSuit = p.missingSuit ~= "" and p.missingSuit or STATE.players[seat].missingSuit
            STATE.players[seat].winCount = tonumber(p.winCount) or STATE.players[seat].winCount or 0
            SortHand(STATE.players[seat].hand, true)
            RefreshTable()
            if STATE.turn == STATE.localSeat then
                UI.TryPromptLocalSelfGang()
            end
        end
        return
    end

    if t == "TURN_START" then
        if STATE.host then
            return
        end
        STATE.turn = tonumber(p.seat) or STATE.turn
        STATE.net.pendingActionToken = p.token
        STATE.net.selfGangPromptDismissedToken = nil
        local sec = tonumber(p.sec) or MajongMastersDB.timer.discardSec
        BeginDiscardTimer(STATE.turn, sec, function()
            local panelBlocking = UI.ActionPanel and UI.ActionPanel:IsShown() and not STATE.net.selfGangPromptToken
            if STATE.responseWindow or STATE.actionTimer or panelBlocking then
                return
            end
            if STATE.phase ~= "PLAYING" or STATE.turn ~= STATE.localSeat then
                return
            end
            local localPlayer = STATE.players[STATE.localSeat]
            if localPlayer and #localPlayer.hand > 0 and (#localPlayer.hand % 3) == 2 then
                local autoCard = PickRuleLegalFallbackDiscard(localPlayer)
                ClearActionPanel()
                Whisper(STATE.room.hostName, "ACTION_REQ", {
                    token = STATE.net.pendingActionToken,
                    kind = "DISCARD",
                    card = autoCard,
                })
            end
        end)
        RefreshTable()
        if STATE.turn == STATE.localSeat then
            UI.TryPromptLocalSelfGang()
        end
        return
    end

    if t == "DRAW_APPLY" then
        local seat = tonumber(p.seat)
        if seat and STATE.players[seat] then
            if seat ~= STATE.localSeat then
                STATE.players[seat].hand[#STATE.players[seat].hand + 1] = "0W"
            end
            if #STATE.deck > 0 then
                table.remove(STATE.deck, 1)
            end
            STATE.turn = seat
            RefreshTable()
        end
        return
    end

    if t == "DISCARD_APPLY" then
        local seat = tonumber(p.seat)
        local card = p.card
        if seat and card and STATE.players[seat] then
            local pl = STATE.players[seat]
            if seat ~= STATE.localSeat then
                if #pl.hand > 0 then
                    table.remove(pl.hand, #pl.hand)
                end
            else
                RemoveByValue(pl.hand, card, 1)
            end
            pl.discards[#pl.discards + 1] = card
            STATE.lastDiscard = card
            PlayDiscardVoice(card)
            RefreshTable()
        end
        return
    end

    if t == "MELD_APPLY" then
        local seat = tonumber(p.seat)
        local kind = p.kind
        local discardSeat = tonumber(p.discardSeat)
        local combo = Split(p.combo or "", ".")
        if seat and STATE.players[seat] then
            if kind == "PENG" then
                if seat ~= STATE.localSeat then
                    if #STATE.players[seat].hand >= 2 then
                        table.remove(STATE.players[seat].hand)
                        table.remove(STATE.players[seat].hand)
                    end
                end
                STATE.players[seat].melds[#STATE.players[seat].melds + 1] = { type = "peng", tiles = { STATE.lastDiscard, STATE.lastDiscard, STATE.lastDiscard } }
                STATE.players[seat].meldSetCount = (STATE.players[seat].meldSetCount or 0) + 1
                if discardSeat then RemoveDiscardFromSeat(discardSeat, STATE.lastDiscard) end
            elseif kind == "GANG" then
                if seat ~= STATE.localSeat then
                    for _ = 1, 3 do
                        if #STATE.players[seat].hand > 0 then
                            table.remove(STATE.players[seat].hand)
                        end
                    end
                end
                STATE.players[seat].melds[#STATE.players[seat].melds + 1] = { type = "minggang", tiles = { STATE.lastDiscard, STATE.lastDiscard, STATE.lastDiscard, STATE.lastDiscard } }
                STATE.players[seat].meldSetCount = (STATE.players[seat].meldSetCount or 0) + 1
                if discardSeat then RemoveDiscardFromSeat(discardSeat, STATE.lastDiscard) end
            elseif kind == "CHI" and #combo == 3 then
                if seat ~= STATE.localSeat then
                    if #STATE.players[seat].hand >= 2 then
                        table.remove(STATE.players[seat].hand)
                        table.remove(STATE.players[seat].hand)
                    end
                end
                STATE.players[seat].melds[#STATE.players[seat].melds + 1] = { type = "chi", tiles = combo }
                STATE.players[seat].meldSetCount = (STATE.players[seat].meldSetCount or 0) + 1
                if discardSeat then RemoveDiscardFromSeat(discardSeat, STATE.lastDiscard) end
            elseif kind == "GANG_SELF" then
                local tile = p.tile
                local pl = STATE.players[seat]
                local upgraded = false
                for _, meld in ipairs(pl.melds) do
                    if meld.type == "peng" and meld.tiles[1] == tile then
                        meld.type = "bugang"
                        meld.tiles[#meld.tiles + 1] = tile
                        upgraded = true
                        break
                    end
                end
                if upgraded then
                    if seat ~= STATE.localSeat and #pl.hand > 0 then
                        table.remove(pl.hand)
                    end
                else
                    if seat ~= STATE.localSeat then
                        for _ = 1, 4 do
                            if #pl.hand > 0 then
                                table.remove(pl.hand)
                            end
                        end
                    end
                    pl.melds[#pl.melds + 1] = { type = "angang", tiles = { tile, tile, tile, tile } }
                    pl.meldSetCount = (pl.meldSetCount or 0) + 1
                end
            end
            STATE.turn = seat
            RefreshTable()
        end
        return
    end

    if t == "ACTION_PROMPT" then
        if STATE.host then
            return
        end
        if STATE.localSeat < 1 then
            return
        end
        local token = p.token
        STATE.net.pendingActionToken = token
        local kinds = Split(p.actions or "", ".")
        local legal = {}
        for _, k in ipairs(kinds) do
            if k == "CHI" then
                local combos = {}
                local comboRows = Split(p.chi or "", "|")
                if #comboRows > 0 then
                    for _, row in ipairs(comboRows) do
                        local combo = Split(row, ".")
                        if #combo == 3 then
                            combos[#combos + 1] = combo
                        end
                    end
                else
                    -- backward compatibility with old one-combo payload
                    local combo = Split(p.chi or "", ".")
                    if #combo == 3 then
                        combos[#combos + 1] = combo
                    end
                end
                legal[#legal + 1] = { kind = "CHI", combos = (#combos > 0) and combos or nil }
            else
                legal[#legal + 1] = { kind = k }
            end
        end
        ShowActionChoicesForSeat(STATE.localSeat, legal, token)
        local sec = math.max(1, tonumber(p.sec) or tonumber(MajongMastersDB.timer.actionSec) or DB_DEFAULTS.timer.actionSec)
        BeginActionTimer(sec, function()
            Whisper(STATE.room.hostName, "ACTION_REQ", { token = token, kind = "PASS" })
            ClearActionPanel()
        end)
        return
    end

    if t == "ROUND_FINISH" then
        local winSeat = tonumber(p.winSeat)
        local discardSeat = tonumber(p.discardSeat)
        local selfDraw = p.selfDraw and true or false
        if p.ruleId then
            STATE.ruleId = NormalizeRuleId(p.ruleId)
            STATE.room.ruleId = STATE.ruleId
        end
        if winSeat then
            if p.continue then
                STATE.phase = "PLAYING"
                ResolveBloodRiverWin(winSeat, discardSeat, selfDraw, {
                    selfDraw = selfDraw,
                    haiDi = (#STATE.deck == 0),
                })
            else
                ResolveRoundFinish(winSeat, discardSeat, selfDraw, {
                    selfDraw = selfDraw,
                    haiDi = (#STATE.deck == 0),
                })
            end
        end
        return
    end
end

local function HandleAddonMessage(prefix, payload, channel, sender)
    if prefix ~= ADDON_PREFIX then
        return
    end
    local packet = DecodePacket(payload)
    if not packet then
        return
    end
    HandleIncomingPacket(sender, packet)
end

local ToggleRuleGuidePanel

local function BuildSettingsPanel()
    UI.SettingsPanel = CreateFrame("Frame", nil, UI.MainFrame, "BackdropTemplate")
    local sp = UI.SettingsPanel
    sp:SetSize(372, 488)
    sp:SetPoint("TOPRIGHT", -16, -60)
    sp:SetFrameStrata("TOOLTIP")
    sp:SetFrameLevel((UI.MainFrame and UI.MainFrame:GetFrameLevel() or 1) + 40)
    sp:SetToplevel(true)
    sp:EnableMouse(true)
    sp:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    sp:SetBackdropColor(0.02, 0.05, 0.08, 0.92)
    sp:SetBackdropBorderColor(0.86, 0.74, 0.28, 0.95)
    sp:Hide()

    local topBar = sp:CreateTexture(nil, "BACKGROUND")
    topBar:SetColorTexture(0.18, 0.09, 0.02, 0.92)
    topBar:SetPoint("TOPLEFT", 1, -1)
    topBar:SetPoint("TOPRIGHT", -1, -1)
    topBar:SetHeight(34)

    local topLine = sp:CreateTexture(nil, "BORDER")
    topLine:SetColorTexture(0.86, 0.74, 0.28, 0.9)
    topLine:SetPoint("TOPLEFT", 1, -35)
    topLine:SetPoint("TOPRIGHT", -1, -35)
    topLine:SetHeight(1)

    local closeBtn = CreateFrame("Button", nil, sp, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        sp:Hide()
    end)

    local title = sp:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -8)
    title:SetText(T("设置"))

    local audioTitle = sp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    audioTitle:SetPoint("TOPLEFT", 16, -48)
    audioTitle:SetText(T("音频开关"))

    local function makeCheck(label, y, getter, setter)
        local cb = CreateFrame("CheckButton", nil, sp, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 16, y)
        local textObj = cb.text or cb.Text
        if textObj then
            textObj:SetText(label)
            if textObj.SetTextColor then
                textObj:SetTextColor(1, 0.85, 0.18)
            end
        end
        cb:SetScript("OnClick", function(self)
            setter(self:GetChecked() and true or false)
        end)
        cb.Refresh = function()
            cb:SetChecked(getter())
        end
        return cb
    end

    local bgmCheck = makeCheck(T("背景音乐"), -72,
        function() return MajongMastersDB.audio.bgmEnabled end,
        function(v)
            MajongMastersDB.audio.bgmEnabled = v
            if v then
                PlayBGM()
            else
                StopBGM()
            end
        end)

    local sfxCheck = makeCheck(T("出牌声音 / 动作语音"), -104,
        function() return MajongMastersDB.audio.sfxEnabled end,
        function(v) MajongMastersDB.audio.sfxEnabled = v end)

    local voiceTitle = sp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    voiceTitle:SetPoint("TOPLEFT", 16, -138)
    voiceTitle:SetText(T("语音风格"))

    local womanBtn = CreateFrame("Button", nil, sp, "UIPanelButtonTemplate")
    womanBtn:SetSize(96, 28)
    womanBtn:SetPoint("TOPLEFT", 16, -164)
    womanBtn:SetText(T("女声"))
    womanBtn:SetScript("OnClick", function()
        MajongMastersDB.audio.voiceGender = "woman"
        sp:Refresh()
    end)

    local manBtn = CreateFrame("Button", nil, sp, "UIPanelButtonTemplate")
    manBtn:SetSize(96, 28)
    manBtn:SetPoint("LEFT", womanBtn, "RIGHT", 12, 0)
    manBtn:SetText(T("男声"))
    manBtn:SetScript("OnClick", function()
        MajongMastersDB.audio.voiceGender = "man"
        sp:Refresh()
    end)

    local aiTitle = sp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    aiTitle:SetPoint("TOPLEFT", 16, -204)
    aiTitle:SetText(T("AI 对手难度（默认：进阶）"))

    local difficultyOrder = AI.GetDifficultyKeys()
    local difficultyLabels = {
        beginner = T("新手"),
        advanced = T("进阶"),
        expert = T("专家"),
        master = T("大师"),
    }
    local difficultyButtons = {}
    for i, key in ipairs(difficultyOrder) do
        local btn = CreateFrame("Button", nil, sp, "UIPanelButtonTemplate")
        btn:SetSize(78, 26)
        btn:SetPoint("TOPLEFT", 16 + (i - 1) * 84, -230)
        btn:SetText(difficultyLabels[key] or key)
        btn:SetScript("OnClick", function()
            MajongMastersDB.ai.difficulty = NormalizeAIDifficulty(key)
            sp:Refresh()
        end)
        difficultyButtons[#difficultyButtons + 1] = {
            key = key,
            btn = btn,
        }
    end

    local ruleTitle = sp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ruleTitle:SetPoint("TOPLEFT", 16, -268)
    ruleTitle:SetText(T("默认玩法规则"))

    local defaultRuleSelector = CreateRuleListSelector(
        sp,
        326,
        "默认玩法规则（当前：%s）",
        GetConfiguredRuleId(),
        function(chosen)
            MajongMastersDB.rules.defaultRule = chosen
            if UI.SingleRuleSelection and UI.SingleRuleSelection.SetRule then
                UI.SingleRuleSelection.SetRule(chosen, true)
            end
            if UI.BattleRuleSelection and STATE.phase == "LOBBY" then
                if UI.BattleRuleSelection.SetRule then
                    UI.BattleRuleSelection.SetRule(chosen, true)
                end
                STATE.room.ruleId = chosen
                STATE.ruleId = chosen
                SyncLobbyText()
                if STATE.host and STATE.room.id then
                    Broadcast("ROOM_ANNOUNCE", {
                        room = STATE.room.id,
                        host = STATE.room.hostName,
                        count = #STATE.room.players,
                        ruleId = chosen,
                    })
                    HostBroadcastLobby()
                end
            end
            sp:Refresh()
        end
    )
    defaultRuleSelector.Btn:SetPoint("TOPLEFT", 16, -294)

    local ruleGuideBtn = CreateFrame("Button", nil, sp, "UIPanelButtonTemplate")
    ruleGuideBtn:SetSize(112, 24)
    ruleGuideBtn:SetPoint("TOPLEFT", 16, -326)
    ruleGuideBtn:SetText(T("规则说明"))
    ruleGuideBtn:SetScript("OnClick", function()
        ToggleRuleGuidePanel((defaultRuleSelector and defaultRuleSelector.ruleId) or GetConfiguredRuleId())
    end)

    local aboutTitle = sp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    aboutTitle:SetPoint("TOPLEFT", 16, -356)
    aboutTitle:SetText(T("关于"))

    local about = sp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    about:SetPoint("TOPLEFT", 16, -378)
    about:SetWidth(336)
    about:SetJustifyH("LEFT")
    about:SetText(T("作者：晓输童\n\n源代码参考：\nhttps://www.curseforge.com/wow/addons/majiang\n原作者：shenmidigua2 神秘地瓜"))

    local function RefreshVoiceButtons()
        local g = (MajongMastersDB.audio and MajongMastersDB.audio.voiceGender) or "woman"
        if g == "man" then
            womanBtn:SetAlpha(0.72)
            manBtn:SetAlpha(1)
        else
            womanBtn:SetAlpha(1)
            manBtn:SetAlpha(0.72)
        end
    end

    local function RefreshDifficultyButtons()
        local current = GetConfiguredAIDifficulty()
        for _, item in ipairs(difficultyButtons) do
            if item.key == current then
                item.btn:SetAlpha(1)
            else
                item.btn:SetAlpha(0.72)
            end
        end
        if aiTitle and aiTitle.SetText then
            aiTitle:SetText(T("AI 对手难度（默认：进阶，当前：%s）", T(GetAIDifficultyLabel(current))))
        end
    end

    local function RefreshRuleSelector()
        local current = GetConfiguredRuleId()
        ruleTitle:SetText(T("默认玩法规则"))
        if defaultRuleSelector and defaultRuleSelector.SetRule then
            defaultRuleSelector.SetRule(current, true)
        end
    end

    sp.Refresh = function()
        bgmCheck:Refresh()
        sfxCheck:Refresh()
        RefreshVoiceButtons()
        RefreshDifficultyButtons()
        RefreshRuleSelector()
        local ruleId = GetConfiguredRuleId()
        if UI.SingleRuleSelection and UI.SingleRuleSelection.SetRule then
            UI.SingleRuleSelection.SetRule(ruleId, true)
        end
        if UI.BattleRuleSelection and UI.BattleRuleSelection.SetRule and STATE.phase ~= "LOBBY" then
            UI.BattleRuleSelection.SetRule(ruleId, true)
        end
    end
end

local function ToggleSettingsPanel()
    if not UI.SettingsPanel then
        return
    end
    if UI.SettingsPanel:IsShown() then
        UI.SettingsPanel:Hide()
        CloseAllRuleSelectorLists(nil)
        return
    end
    UI.SettingsPanel:Refresh()
    UI.SettingsPanel:SetFrameLevel((UI.MainFrame and UI.MainFrame:GetFrameLevel() or 1) + 40)
    UI.SettingsPanel:Show()
    UI.SettingsPanel:Raise()
end

local function BuildRuleGuidePanel()
    UI.RuleGuidePanel = CreateFrame("Frame", nil, UI.MainFrame, "BackdropTemplate")
    local panel = UI.RuleGuidePanel
    panel:SetSize(446, 348)
    panel:SetPoint("CENTER", UI.MainFrame, "CENTER", 0, -8)
    panel:SetFrameStrata("TOOLTIP")
    panel:SetFrameLevel((UI.MainFrame and UI.MainFrame:GetFrameLevel() or 1) + 60)
    panel:SetToplevel(true)
    panel:EnableMouse(true)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(0.02, 0.05, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.86, 0.74, 0.28, 0.95)
    panel:Hide()

    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        panel:Hide()
        CloseAllRuleSelectorLists(nil)
    end)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText(T("规则说明"))

    panel.RuleSelector = CreateRuleListSelector(
        panel,
        250,
        "说明规则：%s",
        GetConfiguredRuleId(),
        function(ruleId)
            panel:SetRule(ruleId)
        end
    )
    panel.RuleSelector.Btn:SetPoint("TOPLEFT", 16, -42)

    panel.BodyText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.BodyText:SetPoint("TOPLEFT", 16, -102)
    panel.BodyText:SetWidth(410)
    panel.BodyText:SetJustifyH("LEFT")
    panel.BodyText:SetJustifyV("TOP")
    panel.BodyText:SetText("")

    panel.SetRule = function(_, ruleId)
        local normalized = NormalizeRuleId(ruleId)
        local styleBits = {}
        panel.ruleId = normalized
        if panel.RuleSelector and panel.RuleSelector.SetRule then
            panel.RuleSelector.SetRule(normalized, true)
        end
        styleBits[#styleBits + 1] = AllowsChi(normalized) and T("可吃牌") or T("不可吃牌")
        styleBits[#styleBits + 1] = RequiresMissingSuit(normalized) and T("需缺一门") or T("不需缺一门")
        styleBits[#styleBits + 1] = IsBloodRiver(normalized) and T("血战模式") or T("单胡即止")
        styleBits[#styleBits + 1] = RuleSet.AllowsHonors(normalized) and T("含字牌") or T("无字牌")
        panel.BodyText:SetText(
            T("玩法：%s", GetRuleName(normalized))
                .. "\n\n"
                .. T(RuleSet.GetRuleDescription(normalized) or "")
                .. "\n\n"
                .. T("当前插件实现：%s", table.concat(styleBits, "，"))
        )
    end
end

ToggleRuleGuidePanel = function(defaultRuleId)
    if not UI.RuleGuidePanel then
        return
    end
    if UI.RuleGuidePanel:IsShown() then
        UI.RuleGuidePanel:Hide()
        CloseAllRuleSelectorLists(nil)
        return
    end
    UI.RuleGuidePanel:SetRule(defaultRuleId or GetConfiguredRuleId())
    UI.RuleGuidePanel:SetFrameLevel((UI.MainFrame and UI.MainFrame:GetFrameLevel() or 1) + 60)
    UI.RuleGuidePanel:Show()
    UI.RuleGuidePanel:Raise()
end

local function BuildSettingsCategory()
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end
    local frame = CreateFrame("Frame")
    frame.name = UI_TITLE
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(UI_TITLE)
    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", 16, -50)
    body:SetJustifyH("LEFT")
    body:SetText(T("请使用 /mj 打开主界面，然后点击右上角“设置”按钮。\nAI 对手难度可选：新手 / 进阶 / 专家 / 大师（默认进阶）。\n玩法规则可选：27种。\n开始前规则选择已支持列表式选择，可打开“规则说明”查看通俗规则介绍。\n\n作者：晓输童\n\n源代码参考：https://www.curseforge.com/wow/addons/majiang\n原作者：shenmidigua2 神秘地瓜"))
    local category = Settings.RegisterCanvasLayoutCategory(frame, UI_TITLE, UI_TITLE)
    Settings.RegisterAddOnCategory(category)
    UI.SettingsCategory = category
end

local function BuildMainUI()
    UI.MainFrame = CreateFrame("Frame", "MajongMastersMainFrame", UIParent, "BackdropTemplate")
    local f = UI.MainFrame
    f:SetSize(1040, 860)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetBackdrop({
        bgFile = IMG_ROOT .. "bg.png",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(1, 1, 1, 1)
    f:SetBackdropBorderColor(0.78, 0.64, 0.18, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        if STATE.phase == "PLAYING" or STATE.phase == "PAUSED" or STATE.phase == "FINISHED" then
            PrintInfo(T("牌局进行中不可关闭"))
            return
        end
        f:Hide()
    end)
    UI.MainCloseBtn = close

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", 0, -16)
    title:SetText(UI_TITLE)

    local settingsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    settingsBtn:SetSize(88, 26)
    settingsBtn:SetPoint("TOPRIGHT", -36, -38)
    settingsBtn:SetText(T("设置"))
    settingsBtn:SetScript("OnClick", ToggleSettingsPanel)
    UI.SettingsBtn = settingsBtn

    UI.RuleGuideBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.RuleGuideBtn:SetSize(88, 26)
    UI.RuleGuideBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -8, 0)
    UI.RuleGuideBtn:SetText(T("规则说明"))
    UI.RuleGuideBtn:SetScript("OnClick", function()
        ToggleRuleGuidePanel(GetActiveRuleId())
    end)

    UI.HomeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.HomeBtn:SetSize(88, 26)
    UI.HomeBtn:SetPoint("RIGHT", UI.RuleGuideBtn, "LEFT", -8, 0)
    UI.HomeBtn:SetText(T("首页"))
    UI.HomeBtn:SetScript("OnClick", ReturnToHomeScreen)
    UI.HomeBtn:Hide()

    UI.HistoryBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.HistoryBtn:SetSize(88, 26)
    UI.HistoryBtn:SetPoint("RIGHT", UI.HomeBtn, "LEFT", -8, 0)
    UI.HistoryBtn:SetText(T("战绩"))
    UI.HistoryBtn:SetScript("OnClick", function()
        ResultOps.ToggleHistoryPanel()
    end)

    UI.StatusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.StatusText:SetPoint("TOP", 0, -58)
    UI.StatusText:SetText(T("请选择模式"))

    UI.TimerText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    UI.TimerText:SetPoint("TOP", 0, -84)

    UI.WallText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    UI.WallText:SetPoint("CENTER", 0, 0)
    UI.WallText:SetText("")

    UI.ModePanel = CreateFrame("Frame", nil, f)
    UI.ModePanel:SetSize(320, 80)
    UI.ModePanel:SetPoint("CENTER", 0, -36)

    local singleMode = CreateFrame("Button", nil, UI.ModePanel, "UIPanelButtonTemplate")
    singleMode:SetSize(130, 40)
    singleMode:SetPoint("LEFT", 0, 0)
    singleMode:SetText(T("单人模式"))
    singleMode:SetScript("OnClick", ShowSingleStart)

    local battleMode = CreateFrame("Button", nil, UI.ModePanel, "UIPanelButtonTemplate")
    battleMode:SetSize(130, 40)
    battleMode:SetPoint("RIGHT", 0, 0)
    battleMode:SetText(T("对战模式"))
    battleMode:SetScript("OnClick", function()
        EnterBattleLobby()
        ShowBattlePanel()
    end)

    UI.StartSingleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.StartSingleBtn:SetSize(160, 42)
    UI.StartSingleBtn:SetPoint("CENTER", 0, -36)
    UI.StartSingleBtn:SetText(T("开始单人牌局"))
    UI.StartSingleBtn:SetScript("OnClick", StartSingleGame)
    UI.StartSingleBtn:Hide()

    UI.SingleRuleSelection = CreateRuleListSelector(
        UI.StartSingleBtn,
        250,
        "单人规则：%s",
        GetConfiguredRuleId(),
        function(nextRule)
            MajongMastersDB.rules.defaultRule = nextRule
            if UI.SettingsPanel and UI.SettingsPanel.Refresh then
                UI.SettingsPanel:Refresh()
            end
        end
    )
    UI.SingleRuleSelection.Btn:SetPoint("BOTTOM", UI.StartSingleBtn, "TOP", 0, 8)

    UI.SingleRuleHelpBtn = CreateFrame("Button", nil, UI.StartSingleBtn, "UIPanelButtonTemplate")
    UI.SingleRuleHelpBtn:SetSize(92, 24)
    UI.SingleRuleHelpBtn:SetPoint("LEFT", UI.SingleRuleSelection.Btn, "RIGHT", 6, 0)
    UI.SingleRuleHelpBtn:SetText(T("规则说明"))
    UI.SingleRuleHelpBtn:SetScript("OnClick", function()
        ToggleRuleGuidePanel((UI.SingleRuleSelection and UI.SingleRuleSelection.ruleId) or GetConfiguredRuleId())
    end)

    UI.StartSingleBackBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.StartSingleBackBtn:SetSize(120, 30)
    UI.StartSingleBackBtn:SetPoint("TOP", UI.StartSingleBtn, "BOTTOM", 0, -10)
    UI.StartSingleBackBtn:SetText(T("返回首页"))
    UI.StartSingleBackBtn:SetScript("OnClick", ReturnToHomeScreen)
    UI.StartSingleBackBtn:Hide()

    UI.BattlePanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    UI.BattlePanel:SetSize(380, 252)
    UI.BattlePanel:SetPoint("CENTER", 0, -16)
    UI.BattlePanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    UI.BattlePanel:SetBackdropColor(0, 0, 0, 0.65)
    UI.BattlePanel:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    UI.BattlePanel:Hide()

    UI.BattlePanel.Title = UI.BattlePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.BattlePanel.Title:SetPoint("TOP", 0, -14)
    UI.BattlePanel.Title:SetText(T("对战大厅"))

    UI.BattleRuleSelection = CreateRuleListSelector(
        UI.BattlePanel,
        340,
        "房间规则：%s",
        GetConfiguredRuleId(),
        function(nextRule)
            STATE.room.ruleId = nextRule
            STATE.ruleId = nextRule
            MajongMastersDB.rules.defaultRule = nextRule
            SyncLobbyText()
            if STATE.host and STATE.room.id then
                Broadcast("ROOM_ANNOUNCE", {
                    room = STATE.room.id,
                    host = STATE.room.hostName,
                    count = #STATE.room.players,
                    ruleId = nextRule,
                })
                HostBroadcastLobby()
            end
            if UI.SettingsPanel and UI.SettingsPanel.Refresh then
                UI.SettingsPanel:Refresh()
            end
        end,
        function()
            if STATE.phase ~= "LOBBY" then
                return false
            end
            if (not STATE.host) and STATE.room.id then
                PrintInfo(T("仅房主可修改房间规则"))
                return false
            end
            return true
        end
    )
    UI.BattleRuleSelection.Btn:SetPoint("TOP", 0, -44)

    UI.BattlePanel.CreateBtn = CreateFrame("Button", nil, UI.BattlePanel, "UIPanelButtonTemplate")
    UI.BattlePanel.CreateBtn:SetSize(110, 34)
    UI.BattlePanel.CreateBtn:SetPoint("TOPLEFT", 20, -78)
    UI.BattlePanel.CreateBtn:SetText(T("建房"))
    UI.BattlePanel.CreateBtn:SetScript("OnClick", HostCreateRoom)

    UI.BattlePanel.JoinBtn = CreateFrame("Button", nil, UI.BattlePanel, "UIPanelButtonTemplate")
    UI.BattlePanel.JoinBtn:SetSize(110, 34)
    UI.BattlePanel.JoinBtn:SetPoint("LEFT", UI.BattlePanel.CreateBtn, "RIGHT", 10, 0)
    UI.BattlePanel.JoinBtn:SetText(T("加入游戏"))
    UI.BattlePanel.JoinBtn:SetScript("OnClick", JoinAnnouncedRoom)

    UI.BattlePanel.StartBtn = CreateFrame("Button", nil, UI.BattlePanel, "UIPanelButtonTemplate")
    UI.BattlePanel.StartBtn:SetSize(110, 34)
    UI.BattlePanel.StartBtn:SetPoint("LEFT", UI.BattlePanel.JoinBtn, "RIGHT", 10, 0)
    UI.BattlePanel.StartBtn:SetText(T("开始对局"))
    UI.BattlePanel.StartBtn:SetScript("OnClick", function()
        if UI.StartBattleRoundAsHost then
            UI.StartBattleRoundAsHost()
        end
    end)

    UI.BattlePanel.BackBtn = CreateFrame("Button", nil, UI.BattlePanel, "UIPanelButtonTemplate")
    UI.BattlePanel.BackBtn:SetSize(110, 30)
    UI.BattlePanel.BackBtn:SetPoint("BOTTOMLEFT", 20, 16)
    UI.BattlePanel.BackBtn:SetText(T("返回首页"))
    UI.BattlePanel.BackBtn:SetScript("OnClick", ReturnToHomeScreen)

    UI.BattlePanel.Status = UI.BattlePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.BattlePanel.Status:SetPoint("TOPLEFT", 20, -126)
    UI.BattlePanel.Status:SetWidth(340)
    UI.BattlePanel.Status:SetJustifyH("LEFT")
    UI.BattlePanel.Status:SetText(T("未加入房间"))
    UI.BattlePanel.RefreshAvailability = RefreshBattlePanelAvailability

    UI.ActionPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    UI.ActionPanel:SetSize(430, 88)
    UI.ActionPanel:SetPoint("BOTTOM", 0, 132)
    UI.ActionPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    UI.ActionPanel:SetBackdropColor(0, 0, 0, 0.7)
    UI.ActionPanel:SetBackdropBorderColor(0.75, 0.75, 0.75, 1)
    UI.ActionPanel:Hide()

    UI.ActionPanel.TimerText = UI.ActionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.ActionPanel.TimerText:SetPoint("BOTTOM", 0, 8)
    UI.ActionPanel.TimerText:SetText("")

    UI.ResultPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    UI.ResultPanel:SetSize(700, 420)
    UI.ResultPanel:SetPoint("CENTER", 0, -6)
    UI.ResultPanel:SetFrameStrata("TOOLTIP")
    UI.ResultPanel:SetFrameLevel((f:GetFrameLevel() or 1) + 70)
    UI.ResultPanel:SetToplevel(true)
    UI.ResultPanel:EnableMouse(true)
    UI.ResultPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    UI.ResultPanel:SetBackdropColor(0, 0, 0, 0.84)
    UI.ResultPanel:SetBackdropBorderColor(0.78, 0.64, 0.2, 0.96)
    UI.ResultPanel:Hide()

    UI.ResultPanel.CloseBtn = CreateFrame("Button", nil, UI.ResultPanel, "UIPanelCloseButton")
    UI.ResultPanel.CloseBtn:SetPoint("TOPRIGHT", 2, 2)
    UI.ResultPanel.CloseBtn:SetScript("OnClick", function()
        UI.ResultPanel:Hide()
    end)

    UI.ResultPanel.TitleText = UI.ResultPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.ResultPanel.TitleText:SetPoint("TOP", 0, -14)
    UI.ResultPanel.TitleText:SetText(T("本局结算"))

    UI.ResultPanel.WinnerText = UI.ResultPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    UI.ResultPanel.WinnerText:SetPoint("TOP", 0, -44)
    UI.ResultPanel.WinnerText:SetText("")

    UI.ResultPanel.ReadyText = UI.ResultPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.ResultPanel.ReadyText:SetPoint("TOP", UI.ResultPanel.WinnerText, "BOTTOM", 0, -2)
    UI.ResultPanel.ReadyText:SetText("")

    UI.ResultPanel.GroupTitle = UI.ResultPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.ResultPanel.GroupTitle:SetPoint("TOPLEFT", 16, -74)
    UI.ResultPanel.GroupTitle:SetText(T("胡牌牌组"))

    UI.ResultPanel.WinTileLabel = UI.ResultPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.ResultPanel.WinTileLabel:SetPoint("TOPLEFT", 16, -96)
    UI.ResultPanel.WinTileLabel:SetText(T("胡牌"))

    UI.ResultPanel.WinTileRow = CreateFrame("Frame", nil, UI.ResultPanel)
    UI.ResultPanel.WinTileRow:SetSize(330, 50)
    UI.ResultPanel.WinTileRow:SetPoint("TOPLEFT", 16, -114)

    UI.ResultPanel.HandTileLabel = UI.ResultPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.ResultPanel.HandTileLabel:SetPoint("TOPLEFT", 16, -170)
    UI.ResultPanel.HandTileLabel:SetText(T("手牌"))

    UI.ResultPanel.HandTilesRow = CreateFrame("Frame", nil, UI.ResultPanel)
    UI.ResultPanel.HandTilesRow:SetSize(330, 84)
    UI.ResultPanel.HandTilesRow:SetPoint("TOPLEFT", 16, -188)

    UI.ResultPanel.MeldTileLabel = UI.ResultPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.ResultPanel.MeldTileLabel:SetPoint("TOPLEFT", 16, -272)
    UI.ResultPanel.MeldTileLabel:SetText(T("碰/吃/杠"))

    UI.ResultPanel.MeldTilesRow = CreateFrame("Frame", nil, UI.ResultPanel)
    UI.ResultPanel.MeldTilesRow:SetSize(330, 78)
    UI.ResultPanel.MeldTilesRow:SetPoint("TOPLEFT", 16, -290)

    UI.ResultPanel.GroupText = UI.ResultPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.ResultPanel.GroupText:SetPoint("TOPLEFT", 16, -290)
    UI.ResultPanel.GroupText:SetWidth(330)
    UI.ResultPanel.GroupText:SetJustifyH("LEFT")
    UI.ResultPanel.GroupText:SetJustifyV("TOP")
    UI.ResultPanel.GroupText:SetText("")
    UI.ResultPanel.GroupText:Hide()

    UI.ResultPanel.FanTitle = UI.ResultPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.ResultPanel.FanTitle:SetPoint("TOPLEFT", 364, -74)
    UI.ResultPanel.FanTitle:SetText(T("牌组计分"))

    UI.ResultPanel.FanText = UI.ResultPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.ResultPanel.FanText:SetPoint("TOPLEFT", 364, -96)
    UI.ResultPanel.FanText:SetWidth(320)
    UI.ResultPanel.FanText:SetJustifyH("LEFT")
    UI.ResultPanel.FanText:SetJustifyV("TOP")
    UI.ResultPanel.FanText:SetText("")

    UI.ResultPanel.ScoreTitle = UI.ResultPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.ResultPanel.ScoreTitle:SetPoint("TOPLEFT", 364, -196)
    UI.ResultPanel.ScoreTitle:SetText(T("各家扣分 / 累计分值"))

    UI.ResultPanel.ScoreText = UI.ResultPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.ResultPanel.ScoreText:SetPoint("TOPLEFT", 364, -218)
    UI.ResultPanel.ScoreText:SetWidth(320)
    UI.ResultPanel.ScoreText:SetJustifyH("LEFT")
    UI.ResultPanel.ScoreText:SetJustifyV("TOP")
    UI.ResultPanel.ScoreText:SetText("")
    UI.ResultPanel.ScoreText:Hide()

    UI.ResultPanel.ScoreTable = CreateFrame("Frame", nil, UI.ResultPanel)
    UI.ResultPanel.ScoreTable:SetSize(320, 90)
    UI.ResultPanel.ScoreTable:SetPoint("TOPLEFT", 364, -218)

    UI.ResultPanel.ScoreHeaderName = UI.ResultPanel.ScoreTable:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    UI.ResultPanel.ScoreHeaderName:SetPoint("TOPLEFT", 2, 0)
    UI.ResultPanel.ScoreHeaderName:SetText(T("玩家"))
    UI.ResultPanel.ScoreHeaderDelta = UI.ResultPanel.ScoreTable:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    UI.ResultPanel.ScoreHeaderDelta:SetPoint("TOPLEFT", 138, 0)
    UI.ResultPanel.ScoreHeaderDelta:SetText(T("本局"))
    UI.ResultPanel.ScoreHeaderTotal = UI.ResultPanel.ScoreTable:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    UI.ResultPanel.ScoreHeaderTotal:SetPoint("TOPLEFT", 226, 0)
    UI.ResultPanel.ScoreHeaderTotal:SetText(T("累计"))

    UI.ResultPanel.ScoreRows = {}
    for seat = 1, 4 do
        local row = CreateFrame("Frame", nil, UI.ResultPanel.ScoreTable)
        row:SetSize(316, 16)
        row:SetPoint("TOPLEFT", 0, -6 - seat * 18)
        row.NameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.NameText:SetPoint("LEFT", 0, 0)
        row.NameText:SetWidth(132)
        row.NameText:SetJustifyH("LEFT")
        row.NameText:SetText("")
        row.DeltaText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.DeltaText:SetPoint("LEFT", 138, 0)
        row.DeltaText:SetWidth(84)
        row.DeltaText:SetJustifyH("LEFT")
        row.DeltaText:SetText("")
        row.TotalText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.TotalText:SetPoint("LEFT", 226, 0)
        row.TotalText:SetWidth(86)
        row.TotalText:SetJustifyH("LEFT")
        row.TotalText:SetText("")
        UI.ResultPanel.ScoreRows[seat] = row
    end

    UI.ResultPanel.SingleContinueBtn = CreateFrame("Button", nil, UI.ResultPanel, "UIPanelButtonTemplate")
    UI.ResultPanel.SingleContinueBtn:SetSize(138, 32)
    UI.ResultPanel.SingleContinueBtn:SetPoint("BOTTOMLEFT", 16, 8)
    UI.ResultPanel.SingleContinueBtn:SetText(T("继续单人牌局"))
    UI.ResultPanel.SingleContinueBtn:SetScript("OnClick", function()
        StartSingleGame()
    end)

    UI.ResultPanel.ModeBtn = CreateFrame("Button", nil, UI.ResultPanel, "UIPanelButtonTemplate")
    UI.ResultPanel.ModeBtn:SetSize(120, 32)
    UI.ResultPanel.ModeBtn:SetPoint("LEFT", UI.ResultPanel.SingleContinueBtn, "RIGHT", 8, 0)
    UI.ResultPanel.ModeBtn:SetText(T("模式选择"))
    UI.ResultPanel.ModeBtn:SetScript("OnClick", function()
        ReturnToHomeScreen()
    end)

    UI.ResultPanel.HostStartBtn = CreateFrame("Button", nil, UI.ResultPanel, "UIPanelButtonTemplate")
    UI.ResultPanel.HostStartBtn:SetSize(148, 32)
    UI.ResultPanel.HostStartBtn:SetPoint("BOTTOMRIGHT", -16, 8)
    UI.ResultPanel.HostStartBtn:SetText(T("开局"))
    UI.ResultPanel.HostStartBtn:SetScript("OnClick", function()
        HostPromptNextRound()
    end)

    UI.ResultPanel.GuestJoinBtn = CreateFrame("Button", nil, UI.ResultPanel, "UIPanelButtonTemplate")
    UI.ResultPanel.GuestJoinBtn:SetSize(148, 32)
    UI.ResultPanel.GuestJoinBtn:SetPoint("BOTTOMRIGHT", -16, 8)
    UI.ResultPanel.GuestJoinBtn:SetText(T("加入"))
    UI.ResultPanel.GuestJoinBtn:SetScript("OnClick", function()
        if STATE.mode ~= "BATTLE" or STATE.host then
            return
        end
        if not STATE.nextRoundPrompted or not STATE.nextRoundToken then
            return
        end
        local me = CanonicalFullName(FullNameFromUnit("player"))
        if not me or me == "" then
            return
        end
        STATE.nextRoundJoinedBy[me] = true
        Whisper(STATE.room.hostName, "ROUND_NEXT_JOIN", {
            room = STATE.room.id or "",
            gameId = STATE.room.gameId or "",
            token = STATE.nextRoundToken,
            player = me,
        })
        if STATE.lastRoundResult then
            ResultOps.ShowResultPanel(STATE.lastRoundResult)
        end
    end)

    UI.HistoryPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    UI.HistoryPanel:SetSize(760, 500)
    UI.HistoryPanel:SetPoint("CENTER", 0, -6)
    UI.HistoryPanel:SetFrameStrata("TOOLTIP")
    UI.HistoryPanel:SetFrameLevel((f:GetFrameLevel() or 1) + 65)
    UI.HistoryPanel:SetToplevel(true)
    UI.HistoryPanel:EnableMouse(true)
    UI.HistoryPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    UI.HistoryPanel:SetBackdropColor(0, 0, 0, 0.9)
    UI.HistoryPanel:SetBackdropBorderColor(0.72, 0.72, 0.72, 1)
    UI.HistoryPanel:Hide()

    UI.HistoryPanel.CloseBtn = CreateFrame("Button", nil, UI.HistoryPanel, "UIPanelCloseButton")
    UI.HistoryPanel.CloseBtn:SetPoint("TOPRIGHT", 2, 2)
    UI.HistoryPanel.CloseBtn:SetScript("OnClick", function()
        UI.HistoryPanel:Hide()
    end)

    UI.HistoryPanel.TitleText = UI.HistoryPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.HistoryPanel.TitleText:SetPoint("TOPLEFT", 14, -12)
    UI.HistoryPanel.TitleText:SetText(T("历史战绩"))

    UI.HistoryPanel.DetailTitleText = UI.HistoryPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.HistoryPanel.DetailTitleText:SetPoint("TOPLEFT", 330, -44)
    UI.HistoryPanel.DetailTitleText:SetText(T("记录详情"))

    UI.HistoryPanel.Rows = {}
    for i = 1, 12 do
        local row = CreateFrame("Button", nil, UI.HistoryPanel, "UIPanelButtonTemplate")
        row:SetSize(300, 28)
        row:SetPoint("TOPLEFT", 16, -52 - (i - 1) * 32)
        row:SetText("")
        row:SetScript("OnClick", function(self)
            ResultOps.ShowHistoryDetail(self.Record)
        end)
        if row.GetFontString and row:GetFontString() then
            row:GetFontString():SetJustifyH("LEFT")
            row:GetFontString():SetWidth(280)
        end
        UI.HistoryPanel.Rows[i] = row
    end

    UI.HistoryPanel.DetailScroll = CreateFrame("ScrollFrame", nil, UI.HistoryPanel, "UIPanelScrollFrameTemplate")
    UI.HistoryPanel.DetailScroll:SetPoint("TOPLEFT", 330, -66)
    UI.HistoryPanel.DetailScroll:SetPoint("BOTTOMRIGHT", -34, 18)

    UI.HistoryPanel.DetailContent = CreateFrame("Frame", nil, UI.HistoryPanel.DetailScroll)
    UI.HistoryPanel.DetailContent:SetSize(380, 360)
    UI.HistoryPanel.DetailScroll:SetScrollChild(UI.HistoryPanel.DetailContent)

    UI.HistoryPanel.DetailText = UI.HistoryPanel.DetailContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.HistoryPanel.DetailText:SetPoint("TOPLEFT", 0, 0)
    UI.HistoryPanel.DetailText:SetWidth(380)
    UI.HistoryPanel.DetailText:SetJustifyH("LEFT")
    UI.HistoryPanel.DetailText:SetJustifyV("TOP")
    UI.HistoryPanel.DetailText:SetText(T("暂无记录"))

    UI.HistoryPanel.DetailGroupTitle = UI.HistoryPanel.DetailContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.HistoryPanel.DetailGroupTitle:SetPoint("TOPLEFT", 0, -120)
    UI.HistoryPanel.DetailGroupTitle:SetText(T("胡牌牌组"))

    UI.HistoryPanel.DetailWinTileLabel = UI.HistoryPanel.DetailContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.HistoryPanel.DetailWinTileLabel:SetPoint("TOPLEFT", 0, -140)
    UI.HistoryPanel.DetailWinTileLabel:SetText(T("胡牌"))

    UI.HistoryPanel.DetailWinTileRow = CreateFrame("Frame", nil, UI.HistoryPanel.DetailContent)
    UI.HistoryPanel.DetailWinTileRow:SetSize(380, 44)
    UI.HistoryPanel.DetailWinTileRow:SetPoint("TOPLEFT", 0, -158)

    UI.HistoryPanel.DetailHandTileLabel = UI.HistoryPanel.DetailContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.HistoryPanel.DetailHandTileLabel:SetPoint("TOPLEFT", 0, -206)
    UI.HistoryPanel.DetailHandTileLabel:SetText(T("手牌"))

    UI.HistoryPanel.DetailHandTilesRow = CreateFrame("Frame", nil, UI.HistoryPanel.DetailContent)
    UI.HistoryPanel.DetailHandTilesRow:SetSize(380, 88)
    UI.HistoryPanel.DetailHandTilesRow:SetPoint("TOPLEFT", 0, -224)

    UI.HistoryPanel.DetailMeldTileLabel = UI.HistoryPanel.DetailContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.HistoryPanel.DetailMeldTileLabel:SetPoint("TOPLEFT", 0, -320)
    UI.HistoryPanel.DetailMeldTileLabel:SetText(T("碰/吃/杠"))

    UI.HistoryPanel.DetailMeldTilesRow = CreateFrame("Frame", nil, UI.HistoryPanel.DetailContent)
    UI.HistoryPanel.DetailMeldTilesRow:SetSize(380, 72)
    UI.HistoryPanel.DetailMeldTilesRow:SetPoint("TOPLEFT", 0, -338)

    UI.HistoryPanel.DetailMeldText = UI.HistoryPanel.DetailContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.HistoryPanel.DetailMeldText:SetPoint("TOPLEFT", 0, -338)
    UI.HistoryPanel.DetailMeldText:SetWidth(380)
    UI.HistoryPanel.DetailMeldText:SetJustifyH("LEFT")
    UI.HistoryPanel.DetailMeldText:SetJustifyV("TOP")
    UI.HistoryPanel.DetailMeldText:SetText("")
    UI.HistoryPanel.DetailMeldText:Hide()

    UI.HistoryPanel.DetailTailText = UI.HistoryPanel.DetailContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.HistoryPanel.DetailTailText:SetPoint("TOPLEFT", 0, -398)
    UI.HistoryPanel.DetailTailText:SetWidth(380)
    UI.HistoryPanel.DetailTailText:SetJustifyH("LEFT")
    UI.HistoryPanel.DetailTailText:SetJustifyV("TOP")
    UI.HistoryPanel.DetailTailText:SetText("")

    UI.PlayerAreas = {}
    local layouts = {
        [1] = { x = 0, y = 70, align = "BOTTOM", w = 620, h = 96, disc = { "BOTTOMLEFT", 220, 118 }, meld = { "BOTTOMLEFT", 520, 10 } },
        [2] = { x = -70, y = 20, align = "RIGHT", w = 116, h = 430, disc = { "TOPRIGHT", -140, -126 }, meld = { "TOPLEFT", 8, 76 } },
        [3] = { x = 0, y = -118, align = "TOP", w = 520, h = 76, disc = { "TOPLEFT", 170, -84 }, meld = { "TOPRIGHT", -460, -8 } },
        [4] = { x = 70, y = 20, align = "LEFT", w = 116, h = 430, disc = { "TOPLEFT", 162, -126 }, meld = { "BOTTOMLEFT", 8, 76 } },
    }
    for seat = 1, 4 do
        local conf = layouts[seat]
        local area = CreateFrame("Frame", nil, f)
        area:SetSize(conf.w, conf.h)
        area:SetPoint(conf.align, conf.x, conf.y)

        local roleText = area:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        roleText:SetPoint("TOP", 0, 2)
        roleText:SetText("")
        area.RoleText = roleText

        local nameIcon = area:CreateTexture(nil, "OVERLAY")
        nameIcon:SetSize(26, 26)
        nameIcon:SetPoint("TOPLEFT", 2, 26)
        area.RoleIcon = nameIcon

        local nameText = area:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", nameIcon, "RIGHT", 4, 0)
        nameText:SetText("")
        area.NameText = nameText

        local turnTimerText = area:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        turnTimerText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
        turnTimerText:SetText("")
        area.TurnTimerText = turnTimerText

        local scoreText = area:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        scoreText:SetPoint("TOPLEFT", turnTimerText, "BOTTOMLEFT", 0, -1)
        scoreText:SetText("")
        area.ScoreText = scoreText

        local disc = CreateFrame("Frame", nil, area)
        disc:SetSize(192, 168)
        disc:SetPoint(unpack(conf.disc))
        area.Discards = disc

        local hand = CreateFrame("Frame", nil, area)
        hand:SetSize(conf.w, conf.h)
        hand:SetPoint("CENTER")
        area.Hand = hand

        local meld = CreateFrame("Frame", nil, area)
        meld:SetSize(220, 300)
        meld:SetPoint(unpack(conf.meld))
        area.Melds = meld

        UI.PlayerAreas[seat] = area
    end

    BuildSettingsPanel()
    BuildRuleGuidePanel()
    BuildSettingsCategory()
end

local function ToggleMainFrameVisibility()
    if not UI.MainFrame then
        return
    end
    if UI.MainFrame:IsShown() then
        if STATE.phase == "PLAYING" or STATE.phase == "PAUSED" or STATE.phase == "FINISHED" then
            PrintInfo(T("牌局进行中不可关闭"))
            return
        end
        UI.MainFrame:Hide()
        return
    end
    UI.MainFrame:Show()
    if UI.MainCloseBtn then
        local locked = (STATE.phase == "PLAYING" or STATE.phase == "PAUSED" or STATE.phase == "FINISHED")
        UI.MainCloseBtn:SetShown(not locked)
    end
end

local function UpdateMinimapButtonPosition(btn)
    if not btn or not Minimap then
        return
    end
    local angle = tonumber(MajongMastersDB and MajongMastersDB.minimap and MajongMastersDB.minimap.angle) or 225
    local radians = math.rad(angle)
    local radius = (Minimap:GetWidth() * 0.5) + 6
    local x = math.cos(radians) * radius
    local y = math.sin(radians) * radius
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CreateMinimapButton()
    if UI.MinimapBtn or not Minimap then
        return
    end
    local btn = CreateFrame("Button", "MajongMastersMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(IMG_ROOT .. "mj.png")
    btn.Icon = icon

    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetPoint("TOPLEFT")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    btn.Overlay = overlay

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local hl = btn:GetHighlightTexture()
    if hl then
        hl:SetBlendMode("ADD")
    end

    btn:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            ToggleMainFrameVisibility()
        elseif mouseButton == "RightButton" then
            if UI.MainFrame and not UI.MainFrame:IsShown() then
                UI.MainFrame:Show()
            end
            ResultOps.ToggleHistoryPanel()
        end
    end)

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(frame)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx = cx / scale
            cy = cy / scale
            local angle = math.deg(Atan2(cy - my, cx - mx))
            if angle < 0 then
                angle = angle + 360
            end
            MajongMastersDB.minimap.angle = angle
            UpdateMinimapButtonPosition(frame)
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    UI.MinimapBtn = btn
    UpdateMinimapButtonPosition(btn)
    local hidden = MajongMastersDB and MajongMastersDB.minimap and MajongMastersDB.minimap.hide
    btn:SetShown(not hidden)
end

local function HandleRestrictionStateChanged(_, restrictionType, state)
    if state == 1 or state == 2 or state == "Activating" or state == "Active" then
        NotifyPause(T("限制态触发(%s)", tostring(restrictionType)))
    elseif state == 0 or state == "Inactive" then
        local resumed = ResumeIfPossible()
        if resumed then
            SetStatusText(T("限制态解除，已恢复"))
            RefreshTable()
        end
    end
end

local function HandleZoneOrGroupChanged()
    if STATE.mode ~= "BATTLE" then
        return
    end
    RefreshBattlePanelAvailability()
    local blocked, reason = IsRestrictedByMapOrLockdown()
    if blocked and STATE.phase == "PLAYING" then
        NotifyPause(reason)
    end
end

local function HandleEvent(_, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon ~= ADDON_NAME then
            return
        end
        InitDB()
        BuildMainUI()
        CreateMinimapButton()
        STATE.ruleId = GetConfiguredRuleId()
        STATE.room.ruleId = STATE.ruleId
        if UI.SingleRuleSelection and UI.SingleRuleSelection.SetRule then
            UI.SingleRuleSelection.SetRule(STATE.ruleId, true)
        end
        if UI.BattleRuleSelection and UI.BattleRuleSelection.SetRule then
            UI.BattleRuleSelection.SetRule(STATE.ruleId, true)
        end
        EnsureNetTicker()
        local ok, err = EnsurePrefixRegistered()
        if not ok then
            PrintInfo(err)
        end
        ShowModePanel()
        RefreshTable()
        PrintInfo(T("加载完成。/mj 打开主界面，/mjset 打开设置"))
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, payload, channel, sender = ...
        HandleAddonMessage(prefix, payload, channel, sender)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        HandleZoneOrGroupChanged()
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        HandleRestrictionStateChanged(nil, ...)
    end
end

EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("CHAT_MSG_ADDON")
EventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
EventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
EventFrame:SetScript("OnEvent", HandleEvent)

SLASH_Majong1 = "/mj"
SlashCmdList["Majong"] = function()
    ToggleMainFrameVisibility()
end

SLASH_MajongSET1 = "/mjset"
SlashCmdList["MajongSET"] = function()
    if UI.MainFrame and not UI.MainFrame:IsShown() then
        UI.MainFrame:Show()
    end
    if UI.SettingsPanel then
        UI.SettingsPanel:Refresh()
        UI.SettingsPanel:Show()
    end
    if UI.SettingsCategory and Settings and Settings.OpenToCategory then
        SafeCall(Settings.OpenToCategory, UI.SettingsCategory:GetID())
    end
end

SLASH_MajongHIS1 = "/mjhistory"
SlashCmdList["MajongHIS"] = function()
    if UI.MainFrame and not UI.MainFrame:IsShown() then
        UI.MainFrame:Show()
    end
    ResultOps.ToggleHistoryPanel()
end
