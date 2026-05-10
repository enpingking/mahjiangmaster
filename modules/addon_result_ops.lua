local ADDON_NAME, NS = ...
ADDON_NAME = ADDON_NAME or "MaJiang"
if type(NS) ~= "table" then
    NS = _G.MaJiangNS or {}
    _G.MaJiangNS = NS
end

local ResultOpsModule = {}

function ResultOpsModule.New(env)
    assert(type(env) == "table", "ResultOpsModule.New requires env table")

    local UI = assert(env.UI, "ResultOpsModule.New missing env.UI")
    local STATE = assert(env.STATE, "ResultOpsModule.New missing env.STATE")
    local T = assert(env.T, "ResultOpsModule.New missing env.T")
    local Join = assert(env.Join, "ResultOpsModule.New missing env.Join")
    local TileSuitAndValue = assert(env.TileSuitAndValue, "ResultOpsModule.New missing env.TileSuitAndValue")
    local GetPlayer = assert(env.GetPlayer, "ResultOpsModule.New missing env.GetPlayer")
    local GetActiveRuleId = assert(env.GetActiveRuleId, "ResultOpsModule.New missing env.GetActiveRuleId")
    local GetRuleName = assert(env.GetRuleName, "ResultOpsModule.New missing env.GetRuleName")
    local CloneTable = assert(env.CloneTable, "ResultOpsModule.New missing env.CloneTable")
    local CopyArray = assert(env.CopyArray, "ResultOpsModule.New missing env.CopyArray")
    local GetDB = assert(env.GetDB, "ResultOpsModule.New missing env.GetDB")
    local ShortName = assert(env.ShortName, "ResultOpsModule.New missing env.ShortName")
    local SafeCall = assert(env.SafeCall, "ResultOpsModule.New missing env.SafeCall")
    local CanonicalFullName = assert(env.CanonicalFullName, "ResultOpsModule.New missing env.CanonicalFullName")
    local FullNameFromUnit = assert(env.FullNameFromUnit, "ResultOpsModule.New missing env.FullNameFromUnit")
    local GetClearChildren = assert(env.GetClearChildren, "ResultOpsModule.New missing env.GetClearChildren")
    local IMG_ROOT = assert(env.IMG_ROOT, "ResultOpsModule.New missing env.IMG_ROOT")

    local function ClearChildren(frame)
        local fn = GetClearChildren()
        if fn then
            fn(frame)
        end
    end

    local ResultOps = {}

    ResultOps.TileToText = function(tile)
        local suit, value = TileSuitAndValue(tile)
        if not suit or not value then
            return tostring(tile or "")
        end
        if suit == "W" then
            return tostring(value) .. "万"
        elseif suit == "T" then
            return tostring(value) .. "筒"
        elseif suit == "S" then
            return tostring(value) .. "索"
        elseif suit == "F" then
            local honors = { "东", "南", "西", "北", "中", "发", "白" }
            return honors[value] or tostring(tile)
        end
        return tostring(tile)
    end

    ResultOps.FormatTiles = function(tiles, sep)
        local out = {}
        for _, t in ipairs(tiles or {}) do
            out[#out + 1] = ResultOps.TileToText(t)
        end
        return Join(out, sep or " ")
    end

    ResultOps.MeldTypeText = function(meldType)
        if meldType == "chi" then return "吃" end
        if meldType == "peng" then return "碰" end
        if meldType == "minggang" then return "明杠" end
        if meldType == "angang" then return "暗杠" end
        if meldType == "bugang" then return "补杠" end
        return tostring(meldType or "副露")
    end

    ResultOps.MeldTypeIconPath = function(meldType)
        if meldType == "chi" then
            return IMG_ROOT .. "chi.png"
        end
        if meldType == "peng" then
            return IMG_ROOT .. "peng.png"
        end
        if meldType == "minggang" or meldType == "angang" or meldType == "bugang" then
            return IMG_ROOT .. "gang.png"
        end
        return nil
    end

    ResultOps.RenderMeldTiles = function(parent, melds, opts)
        if not parent then
            return 0, 0
        end
        opts = opts or {}
        local cols = math.max(6, tonumber(opts.cols) or 10)
        local slotW = math.max(14, tonumber(opts.slotW) or 20)
        local slotH = math.max(20, tonumber(opts.slotH) or 28)
        local gapX = math.max(0, tonumber(opts.gapX) or 2)
        local gapY = math.max(0, tonumber(opts.gapY) or 2)
        local tileW = math.max(12, tonumber(opts.tileW) or 18)
        local tileH = math.max(18, tonumber(opts.tileH) or 26)
        local iconW = math.max(12, tonumber(opts.iconW) or slotW)
        local iconH = math.max(18, tonumber(opts.iconH) or slotH)
        local groupGapX = math.max(0, tonumber(opts.groupGapX) or 0)
        local maxWidth = tonumber(opts.maxWidth)
        if not maxWidth or maxWidth <= 0 then
            maxWidth = cols * slotW + math.max(0, cols - 1) * gapX
        end
        local tileRoot = opts.tileRoot or IMG_ROOT

        ClearChildren(parent)
        local cursorX, cursorY = 0, 0
        local rowHeight = 0
        local maxRows = 1
        local hasAny = false
        local function NewRow()
            cursorX = 0
            cursorY = cursorY + rowHeight + gapY
            rowHeight = 0
            maxRows = maxRows + 1
        end
        local function PlaceFrame(frame, width, height)
            if cursorX > 0 and (cursorX + width) > maxWidth then
                NewRow()
            end
            frame:SetPoint("TOPLEFT", cursorX, -cursorY)
            cursorX = cursorX + width + gapX
            rowHeight = math.max(rowHeight, height)
            hasAny = true
        end

        for _, meld in ipairs(melds or {}) do
            local iconPath = ResultOps.MeldTypeIconPath(meld and meld.type)
            if iconPath then
                local icon = CreateFrame("Frame", nil, parent)
                icon:SetSize(iconW, iconH)
                local tex = icon:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints()
                tex:SetTexture(iconPath)
                PlaceFrame(icon, iconW, iconH)
            end
            for _, tile in ipairs((meld and meld.tiles) or {}) do
                local tileFrame = UI.CreateTileFrame(parent, tileW, tileH, tile, false, false, nil, nil, tileRoot)
                PlaceFrame(tileFrame, tileW, tileH)
            end
            if groupGapX > 0 and hasAny then
                cursorX = cursorX + groupGapX
            end
        end

        if not hasAny then
            return 0, 0
        end
        return maxRows, cursorY + rowHeight
    end

    ResultOps.BuildWinnerGroupText = function(result)
        local lines = {}
        local winTile = result and result.winTile
        if winTile then
            lines[#lines + 1] = T("胡牌: %s", ResultOps.TileToText(winTile))
        end
        local handText = ResultOps.FormatTiles(result and result.winnerHand or {}, " ")
        if handText ~= "" then
            lines[#lines + 1] = T("手牌: %s", handText)
        end
        for _, meld in ipairs(result and result.winnerMelds or {}) do
            local meldText = ResultOps.FormatTiles(meld.tiles or {}, " ")
            lines[#lines + 1] = T("%s: %s", ResultOps.MeldTypeText(meld.type), meldText)
        end
        return Join(lines, "\n")
    end

    ResultOps.BuildRoundResult = function(winSeat, discardSeat, selfDraw, fanList, roundDelta, opts)
        opts = opts or {}
        local winner = GetPlayer(winSeat)
        if not winner then
            return nil
        end
        local result = {
            ts = GetServerTime(),
            mode = STATE.mode,
            ruleId = GetActiveRuleId(),
            ruleName = GetRuleName(GetActiveRuleId()),
            winSeat = winSeat,
            winner = winner.name,
            discardSeat = discardSeat,
            selfDraw = selfDraw and true or false,
            round = STATE.currentRound or 0,
            gameId = STATE.room.gameId or "",
            roomId = STATE.room.id or "",
            fanList = CloneTable(fanList or {}),
            roundDelta = CloneTable(roundDelta or { 0, 0, 0, 0 }),
            scores = CloneTable(STATE.scores or { 0, 0, 0, 0 }),
            players = {},
            winnerHand = CopyArray(winner.hand or {}),
            winnerMelds = CloneTable(winner.melds or {}),
            continueRound = opts.continueRound and true or false,
        }
        for seat = 1, 4 do
            result.players[seat] = STATE.players[seat] and STATE.players[seat].name or ("Seat" .. tostring(seat))
        end
        if opts.winTile and opts.winTile ~= "" then
            result.winTile = opts.winTile
        elseif selfDraw then
            result.winTile = result.winnerHand[#result.winnerHand]
        else
            result.winTile = STATE.lastDiscard
        end
        result.winnerGroupText = ResultOps.BuildWinnerGroupText(result)
        return result
    end

    ResultOps.SaveHistory = function(result)
        local db = GetDB()
        if not result or not db or type(db.history) ~= "table" then
            return
        end
        local records = db.history.records
        if type(records) ~= "table" then
            records = {}
            db.history.records = records
        end
        table.insert(records, 1, CloneTable(result))
        local maxRecords = math.max(20, tonumber(db.history.maxRecords) or 200)
        while #records > maxRecords do
            table.remove(records)
        end
    end

    ResultOps.AnnounceToChat = function(result)
        if not result then
            return
        end
        if STATE.mode == "BATTLE" and not STATE.host then
            return
        end
        local cat = LE_PARTY_CATEGORY_HOME or 1
        if not IsInGroup(cat) then
            return
        end
        local channel = IsInRaid(cat) and "RAID" or "PARTY"
        local methodText = result.selfDraw and T("自摸") or T("点炮")
        local winnerText = ShortName(result.winner) .. " " .. methodText
        local ruleText = result.ruleName or GetRuleName(result.ruleId)
        local deltaParts = {}
        for seat = 1, 4 do
            local name = ShortName(result.players[seat] or ("Seat" .. tostring(seat)))
            local delta = tonumber((result.roundDelta or {})[seat]) or 0
            local total = tonumber((result.scores or {})[seat]) or 0
            local sign = (delta >= 0) and "+" or ""
            deltaParts[#deltaParts + 1] = string.format("%s %s%d(%d)", name, sign, delta, total)
        end
        local line1 = string.format("[麻将大师] %s | %s", winnerText, tostring(ruleText))
        local line2 = string.format("[麻将大师] %s", Join(deltaParts, " | "))
        SafeCall(SendChatMessage, line1, channel)
        SafeCall(SendChatMessage, line2, channel)
    end

    ResultOps.ResultTitleText = function(result)
        if not result then
            return ""
        end
        local methodText = result.selfDraw and T("自摸") or T("点炮")
        return T("%s %s", ShortName(result.winner), methodText)
    end

    ResultOps.ResultFanText = function(result)
        local out = {}
        for _, item in ipairs(result and result.fanList or {}) do
            out[#out + 1] = string.format("%s +%s", T(item.name), tostring(item.fan))
        end
        if #out == 0 then
            return T("番型: 无")
        end
        return T("番型: %s", Join(out, " | "))
    end

    ResultOps.ResultScoreText = function(result, opts)
        opts = opts or {}
        local lines = {}
        for seat = 1, 4 do
            local rawName = (result.players or {})[seat] or ("Seat" .. tostring(seat))
            local name = (opts.fullNames and rawName) or ShortName(rawName)
            local delta = tonumber((result.roundDelta or {})[seat]) or 0
            local total = tonumber((result.scores or {})[seat]) or 0
            local sign = delta >= 0 and "+" or ""
            lines[#lines + 1] = string.format("%s: %s%d  累计:%d", name, sign, delta, total)
        end
        return Join(lines, "\n")
    end

    ResultOps.ResultMeldText = function(result)
        local lines = {}
        for _, meld in ipairs(result and result.winnerMelds or {}) do
            local meldText = ResultOps.FormatTiles(meld.tiles or {}, " ")
            lines[#lines + 1] = T("%s: %s", ResultOps.MeldTypeText(meld.type), meldText)
        end
        if #lines == 0 then
            return ""
        end
        return Join(lines, "\n")
    end

    ResultOps.UpdateResultGroupTiles = function(result)
        local panel = UI.ResultPanel
        if not panel or not panel.WinTileRow or not panel.HandTilesRow then
            return
        end
        ClearChildren(panel.WinTileRow)
        ClearChildren(panel.HandTilesRow)
        if panel.MeldTilesRow then
            ClearChildren(panel.MeldTilesRow)
        end
        local tileRoot = IMG_ROOT
        if result and result.winTile then
            local winTile = UI.CreateTileFrame(panel.WinTileRow, 34, 48, result.winTile, false, true, { 1, 0.2, 0.2, 1 }, nil, tileRoot)
            winTile:SetPoint("TOPLEFT", 0, 0)
        end
        local hand = result and result.winnerHand or {}
        local cols = 10
        local tileW, tileH = 24, 34
        local gapX, gapY = 1, 2
        for idx, card in ipairs(hand) do
            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            local tile = UI.CreateTileFrame(panel.HandTilesRow, tileW, tileH, card, false, false, nil, nil, tileRoot)
            tile:SetPoint("TOPLEFT", col * (tileW + gapX), -row * (tileH + gapY))
        end
        local handRows = math.max(1, math.ceil(#hand / cols))
        local handHeight = handRows * (tileH + gapY)
        panel.HandTilesRow:SetHeight(handHeight)

        local melds = result and result.winnerMelds or {}
        if panel.MeldTileLabel and panel.MeldTilesRow then
            panel.MeldTileLabel:ClearAllPoints()
            panel.MeldTileLabel:SetPoint("TOPLEFT", panel.HandTilesRow, "BOTTOMLEFT", 0, -6)
            panel.MeldTilesRow:ClearAllPoints()
            panel.MeldTilesRow:SetPoint("TOPLEFT", panel.MeldTileLabel, "BOTTOMLEFT", 0, -3)
            if #melds > 0 then
                panel.MeldTileLabel:Show()
                panel.MeldTilesRow:Show()
                local _, meldHeight = ResultOps.RenderMeldTiles(panel.MeldTilesRow, melds, {
                    cols = 10,
                    slotW = 30,
                    slotH = 30,
                    gapX = 0,
                    gapY = 2,
                    tileW = 18,
                    tileH = 26,
                    iconW = 26,
                    iconH = 26,
                    tileRoot = tileRoot,
                })
                panel.MeldTilesRow:SetHeight(math.max(24, meldHeight))
            else
                panel.MeldTileLabel:Hide()
                panel.MeldTilesRow:Hide()
            end
        end
    end

    ResultOps.UpdateScoreRows = function(result, opts)
        opts = opts or {}
        local panel = UI.ResultPanel
        if not panel then
            return
        end
        if not panel.ScoreRows then
            if panel.ScoreText then
                panel.ScoreText:SetText(ResultOps.ResultScoreText(result, opts))
            end
            return
        end
        for seat = 1, 4 do
            local row = panel.ScoreRows[seat]
            if row then
                local rawName = (result and result.players or {})[seat] or ("Seat" .. tostring(seat))
                local name = (opts.fullNames and rawName) or ShortName(rawName)
                local delta = tonumber((result and result.roundDelta or {})[seat]) or 0
                local total = tonumber((result and result.scores or {})[seat]) or 0
                local sign = delta >= 0 and "+" or ""
                row.NameText:SetText(name)
                row.DeltaText:SetText(string.format("%s%d", sign, delta))
                row.TotalText:SetText(tostring(total))
            end
        end
    end

    ResultOps.ShowResultPanel = function(result)
        if not UI.ResultPanel then
            return
        end
        STATE.lastRoundResult = result
        if UI.HistoryPanel and UI.HistoryPanel:IsShown() then
            UI.HistoryPanel:Hide()
        end
        UI.ResultPanel:Show()
        UI.ResultPanel:Raise()
        if UI.ResultPanel.TitleText then
            local ruleName = result and result.ruleName or GetRuleName(GetActiveRuleId())
            UI.ResultPanel.TitleText:SetText(T("本局结算 - %s", ruleName))
        end
        if UI.ResultPanel.WinnerText then
            UI.ResultPanel.WinnerText:SetText(ResultOps.ResultTitleText(result))
        end
        ResultOps.UpdateResultGroupTiles(result)
        if UI.ResultPanel.GroupText then
            if UI.ResultPanel.MeldTilesRow then
                UI.ResultPanel.GroupText:SetText("")
                UI.ResultPanel.GroupText:Hide()
            else
                UI.ResultPanel.GroupText:SetText(ResultOps.ResultMeldText(result))
                UI.ResultPanel.GroupText:Show()
            end
        end
        if UI.ResultPanel.FanText then
            UI.ResultPanel.FanText:SetText(ResultOps.ResultFanText(result))
        end
        ResultOps.UpdateScoreRows(result)
        if UI.ResultPanel.ReadyText then
            local readyText = ""
            if STATE.mode == "BATTLE" and STATE.nextRoundPrompted then
                local readyCount = 0
                for _, playerName in ipairs(STATE.room.players or {}) do
                    if STATE.nextRoundJoinedBy[CanonicalFullName(playerName)] then
                        readyCount = readyCount + 1
                    end
                end
                readyText = T("下一局已加入: %d/4", readyCount)
            end
            UI.ResultPanel.ReadyText:SetText(readyText)
        end
        if UI.ResultPanel.HostStartBtn then
            local showHostStart = (STATE.mode == "BATTLE" and STATE.host)
            UI.ResultPanel.HostStartBtn:SetShown(showHostStart)
            UI.ResultPanel.HostStartBtn:SetEnabled(showHostStart and not STATE.nextRoundPrompted)
            UI.ResultPanel.HostStartBtn:SetAlpha((showHostStart and not STATE.nextRoundPrompted) and 1 or 0.65)
        end
        if UI.ResultPanel.GuestJoinBtn then
            local showGuestJoin = (STATE.mode == "BATTLE" and not STATE.host and STATE.nextRoundPrompted and STATE.nextRoundToken)
            local localKey = CanonicalFullName(FullNameFromUnit("player"))
            local alreadyJoined = localKey and STATE.nextRoundJoinedBy[localKey]
            UI.ResultPanel.GuestJoinBtn:SetShown(showGuestJoin)
            UI.ResultPanel.GuestJoinBtn:SetEnabled(showGuestJoin and not alreadyJoined)
            UI.ResultPanel.GuestJoinBtn:SetAlpha((showGuestJoin and not alreadyJoined) and 1 or 0.65)
        end
        if UI.ResultPanel.SingleContinueBtn then
            UI.ResultPanel.SingleContinueBtn:SetShown(STATE.mode == "SINGLE")
        end
        if UI.ResultPanel.ModeBtn then
            UI.ResultPanel.ModeBtn:SetShown(STATE.mode == "SINGLE")
        end
        if UI.StartSingleBtn then
            UI.StartSingleBtn:Hide()
        end
        if UI.BattlePanel then
            UI.BattlePanel:Hide()
        end
        if UI.HomeBtn then
            UI.HomeBtn:Hide()
        end
    end

    ResultOps.HistoryRecords = function()
        local db = GetDB()
        if not db or type(db.history) ~= "table" then
            return {}
        end
        if type(db.history.records) ~= "table" then
            db.history.records = {}
        end
        return db.history.records
    end

    ResultOps.FormatHistoryRow = function(record)
        local whenText = date("%m-%d %H:%M", tonumber(record.ts) or GetServerTime())
        local modeText = record.mode == "BATTLE" and T("对战") or T("单人")
        local winner = ShortName(record.winner or "")
        local methodText = record.selfDraw and T("自摸") or T("点炮")
        return string.format("%s [%s] %s %s", whenText, modeText, winner, methodText)
    end

    ResultOps.ShowHistoryDetail = function(record)
        if not UI.HistoryPanel then
            return
        end
        if not record then
            UI.HistoryPanel.DetailText:SetText(T("暂无记录"))
            if UI.HistoryPanel.DetailGroupTitle then UI.HistoryPanel.DetailGroupTitle:Hide() end
            if UI.HistoryPanel.DetailWinTileLabel then UI.HistoryPanel.DetailWinTileLabel:Hide() end
            if UI.HistoryPanel.DetailHandTileLabel then UI.HistoryPanel.DetailHandTileLabel:Hide() end
            if UI.HistoryPanel.DetailMeldTileLabel then UI.HistoryPanel.DetailMeldTileLabel:Hide() end
            if UI.HistoryPanel.DetailWinTileRow then UI.HistoryPanel.DetailWinTileRow:Hide() end
            if UI.HistoryPanel.DetailHandTilesRow then UI.HistoryPanel.DetailHandTilesRow:Hide() end
            if UI.HistoryPanel.DetailMeldTilesRow then UI.HistoryPanel.DetailMeldTilesRow:Hide() end
            if UI.HistoryPanel.DetailMeldText then
                UI.HistoryPanel.DetailMeldText:SetText("")
                UI.HistoryPanel.DetailMeldText:Hide()
            end
            if UI.HistoryPanel.DetailTailText then
                UI.HistoryPanel.DetailTailText:SetText("")
                UI.HistoryPanel.DetailTailText:Hide()
            end
            if UI.HistoryPanel.DetailWinTileRow then
                ClearChildren(UI.HistoryPanel.DetailWinTileRow)
            end
            if UI.HistoryPanel.DetailHandTilesRow then
                ClearChildren(UI.HistoryPanel.DetailHandTilesRow)
            end
            if UI.HistoryPanel.DetailMeldTilesRow then
                ClearChildren(UI.HistoryPanel.DetailMeldTilesRow)
            end
            if UI.HistoryPanel.DetailContent then
                UI.HistoryPanel.DetailContent:SetHeight(360)
            end
            return
        end
        UI.HistoryPanel.DetailGroupTitle:Show()
        UI.HistoryPanel.DetailWinTileLabel:Show()
        UI.HistoryPanel.DetailHandTileLabel:Show()
        if UI.HistoryPanel.DetailMeldTileLabel then
            UI.HistoryPanel.DetailMeldTileLabel:Show()
        end
        UI.HistoryPanel.DetailWinTileRow:Show()
        UI.HistoryPanel.DetailHandTilesRow:Show()
        if UI.HistoryPanel.DetailMeldTilesRow then
            UI.HistoryPanel.DetailMeldTilesRow:Show()
        end
        UI.HistoryPanel.DetailMeldText:Hide()
        UI.HistoryPanel.DetailTailText:Show()
        local metaLines = {}
        metaLines[#metaLines + 1] = T("时间: %s", date("%Y-%m-%d %H:%M:%S", tonumber(record.ts) or GetServerTime()))
        metaLines[#metaLines + 1] = T("模式: %s", record.mode == "BATTLE" and T("对战") or T("单人"))
        metaLines[#metaLines + 1] = T("规则: %s", record.ruleName or GetRuleName(record.ruleId))
        if record.mode == "BATTLE" then
            metaLines[#metaLines + 1] = T("牌手: %s", Join({
                tostring((record.players or {})[1] or ""),
                tostring((record.players or {})[2] or ""),
                tostring((record.players or {})[3] or ""),
                tostring((record.players or {})[4] or ""),
            }, " / "))
        end
        local winnerName = (record.mode == "BATTLE") and tostring(record.winner or "") or ShortName(record.winner or "")
        metaLines[#metaLines + 1] = T("赢家: %s", winnerName)
        metaLines[#metaLines + 1] = T("胡牌方式: %s", record.selfDraw and T("自摸") or T("点炮"))
        UI.HistoryPanel.DetailText:SetText(Join(metaLines, "\n"))

        local groupTop = -math.ceil(UI.HistoryPanel.DetailText:GetStringHeight() + 14)
        UI.HistoryPanel.DetailGroupTitle:SetPoint("TOPLEFT", 0, groupTop)
        UI.HistoryPanel.DetailWinTileLabel:SetPoint("TOPLEFT", 0, groupTop - 20)
        UI.HistoryPanel.DetailWinTileRow:SetPoint("TOPLEFT", 0, groupTop - 38)
        UI.HistoryPanel.DetailHandTileLabel:SetPoint("TOPLEFT", 0, groupTop - 86)
        UI.HistoryPanel.DetailHandTilesRow:SetPoint("TOPLEFT", 0, groupTop - 104)

        ClearChildren(UI.HistoryPanel.DetailWinTileRow)
        ClearChildren(UI.HistoryPanel.DetailHandTilesRow)
        if UI.HistoryPanel.DetailMeldTilesRow then
            ClearChildren(UI.HistoryPanel.DetailMeldTilesRow)
        end

        local tileRoot = IMG_ROOT
        if record.winTile then
            local winTile = UI.CreateTileFrame(UI.HistoryPanel.DetailWinTileRow, 30, 42, record.winTile, false, true, { 1, 0.2, 0.2, 1 }, nil, tileRoot)
            winTile:SetPoint("TOPLEFT", 0, 0)
        end

        local hand = record.winnerHand or {}
        local cols = 11
        local tileW, tileH = 22, 32
        local gapX, gapY = 1, 2
        for idx, card in ipairs(hand) do
            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            local tile = UI.CreateTileFrame(UI.HistoryPanel.DetailHandTilesRow, tileW, tileH, card, false, false, nil, nil, tileRoot)
            tile:SetPoint("TOPLEFT", col * (tileW + gapX), -row * (tileH + gapY))
        end

        local handRows = math.max(1, math.ceil(#hand / cols))
        local handHeight = handRows * (tileH + gapY)
        UI.HistoryPanel.DetailHandTilesRow:SetHeight(handHeight)

        local handBottomTop = groupTop - 104 - handHeight
        local tailTop
        local melds = record.winnerMelds or {}
        if UI.HistoryPanel.DetailMeldTileLabel and UI.HistoryPanel.DetailMeldTilesRow then
            if #melds > 0 then
                local meldLabelTop = handBottomTop - 8
                UI.HistoryPanel.DetailMeldTileLabel:Show()
                UI.HistoryPanel.DetailMeldTileLabel:SetPoint("TOPLEFT", 0, meldLabelTop)
                UI.HistoryPanel.DetailMeldTilesRow:Show()
                UI.HistoryPanel.DetailMeldTilesRow:SetPoint("TOPLEFT", 0, meldLabelTop - 18)
                local _, meldHeight = ResultOps.RenderMeldTiles(UI.HistoryPanel.DetailMeldTilesRow, melds, {
                    cols = 11,
                    slotW = 30,
                    slotH = 26,
                    gapX = 0,
                    gapY = 2,
                    tileW = 16,
                    tileH = 24,
                    iconW = 24,
                    iconH = 24,
                    tileRoot = tileRoot,
                })
                UI.HistoryPanel.DetailMeldTilesRow:SetHeight(math.max(26, meldHeight))
                tailTop = (meldLabelTop - 18) - math.max(26, meldHeight) - 8
            else
                UI.HistoryPanel.DetailMeldTileLabel:Hide()
                UI.HistoryPanel.DetailMeldTilesRow:Hide()
                tailTop = handBottomTop - 12
            end
            UI.HistoryPanel.DetailMeldText:SetText("")
        else
            local meldTop = handBottomTop - 12
            UI.HistoryPanel.DetailMeldText:Show()
            UI.HistoryPanel.DetailMeldText:SetPoint("TOPLEFT", 0, meldTop)
            UI.HistoryPanel.DetailMeldText:SetText(ResultOps.ResultMeldText(record))
            tailTop = meldTop - math.ceil(UI.HistoryPanel.DetailMeldText:GetStringHeight()) - 10
        end

        local tailLines = {}
        tailLines[#tailLines + 1] = ResultOps.ResultFanText(record)
        tailLines[#tailLines + 1] = " "
        tailLines[#tailLines + 1] = T("本局加减 / 累计:")
        tailLines[#tailLines + 1] = ResultOps.ResultScoreText(record, { fullNames = (record.mode == "BATTLE") })
        UI.HistoryPanel.DetailTailText:SetPoint("TOPLEFT", 0, tailTop)
        UI.HistoryPanel.DetailTailText:SetText(Join(tailLines, "\n"))

        if UI.HistoryPanel.DetailContent and UI.HistoryPanel.DetailTailText then
            local totalHeight = math.ceil(-tailTop + UI.HistoryPanel.DetailTailText:GetStringHeight() + 18)
            UI.HistoryPanel.DetailContent:SetHeight(math.max(360, totalHeight))
        end
    end

    ResultOps.RefreshHistoryPanel = function()
        if not UI.HistoryPanel then
            return
        end
        local records = ResultOps.HistoryRecords()
        for i, btn in ipairs(UI.HistoryPanel.Rows or {}) do
            local record = records[i]
            if record then
                btn.Record = record
                btn:SetText(ResultOps.FormatHistoryRow(record))
                btn:Show()
            else
                btn.Record = nil
                btn:Hide()
            end
        end
        ResultOps.ShowHistoryDetail(records[1])
    end

    ResultOps.ToggleHistoryPanel = function()
        if not UI.HistoryPanel then
            return
        end
        local showing = UI.HistoryPanel:IsShown()
        if showing then
            UI.HistoryPanel:Hide()
            return
        end
        ResultOps.RefreshHistoryPanel()
        UI.HistoryPanel:Show()
        UI.HistoryPanel:Raise()
    end

    return ResultOps
end

NS.AddonResultOps = ResultOpsModule
