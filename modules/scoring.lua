local _, NS = ...
if type(NS) ~= "table" then
    NS = _G.MaJiangNS or {}
    _G.MaJiangNS = NS
end

local Core = NS.Core
local Rules = NS.Rules
local RuleSet = NS.RuleSet or {}
assert(type(Core) == "table", "MaJiang modules load order error: NS.Core missing")
assert(type(Rules) == "table", "MaJiang modules load order error: NS.Rules missing")

local Scoring = NS.Scoring or {}
NS.Scoring = Scoring

local CopyArray = Core.CopyArray
local SortHand = Core.SortHand

local function NormalizeRuleId(ctx)
    local raw = ctx and ctx.ruleId
    if type(RuleSet.NormalizeRuleId) == "function" then
        return RuleSet.NormalizeRuleId(raw)
    end
    return raw or "guangdong"
end

local function RequiresMissingSuitRule(ruleId)
    if type(RuleSet.RequiresMissingSuit) == "function" then
        return RuleSet.RequiresMissingSuit(ruleId)
    end
    return false
end

local function AllTilesFromPlayer(player)
    local tiles = CopyArray(player.hand)
    for _, meld in ipairs(player.melds) do
        for _, t in ipairs(meld.tiles) do
            tiles[#tiles + 1] = t
        end
    end
    return tiles
end

local function IsMenQian(player)
    for _, meld in ipairs(player.melds) do
        if meld.type == "chi" or meld.type == "peng" or meld.type == "minggang" or meld.type == "bugang" then
            return false
        end
    end
    return true
end

local function SuitSet(tiles)
    local hasW, hasT, hasS, hasF = false, false, false, false
    for _, card in ipairs(tiles) do
        local suit = card:sub(2, 2)
        if suit == "W" then hasW = true end
        if suit == "T" then hasT = true end
        if suit == "S" then hasS = true end
        if suit == "F" then hasF = true end
    end
    return hasW, hasT, hasS, hasF
end

function Scoring.EvaluateFan(player, ctx)
    local fanList = {}
    local fullTiles = AllTilesFromPlayer(player)
    local meldCount = #player.melds
    local hand = CopyArray(player.hand)
    local ruleId = NormalizeRuleId(ctx)
    SortHand(hand, false)

    local isSevenPairs = (meldCount == 0) and Rules.IsSevenPairs(hand)
    local isKokushi = (meldCount == 0) and Rules.IsKokushi(hand)

    if isKokushi and (ruleId == "guangdong" or ruleId == "japanese") then
        fanList[#fanList + 1] = { name = "国士无双", fan = 13 }
        return fanList
    end
    if isSevenPairs then
        local sevenFan = 4
        if ruleId == "international" then
            sevenFan = 3
        elseif ruleId == "japanese" then
            sevenFan = 2
        elseif RequiresMissingSuitRule(ruleId) then
            sevenFan = 2
        end
        fanList[#fanList + 1] = { name = "七对", fan = sevenFan }
    end

    if ctx.selfDraw then
        fanList[#fanList + 1] = { name = "自摸", fan = 1 }
    end
    if IsMenQian(player) then
        fanList[#fanList + 1] = { name = "门前清", fan = 1 }
    end
    local hasW, hasT, hasS, hasF = SuitSet(fullTiles)
    local suitCount = (hasW and 1 or 0) + (hasT and 1 or 0) + (hasS and 1 or 0)
    if suitCount == 1 and hasF then
        local fan = 2
        if ruleId == "international" then
            fan = 3
        end
        fanList[#fanList + 1] = { name = "混一色", fan = fan }
    elseif suitCount == 1 and not hasF then
        local fan = 4
        if ruleId == "international" then
            fan = 6
        elseif RequiresMissingSuitRule(ruleId) then
            fan = 2
        end
        fanList[#fanList + 1] = { name = "清一色", fan = fan }
    end
    if Rules.IsPengPengHu(hand, player.melds) then
        local fan = 2
        if ruleId == "international" then
            fan = 3
        end
        fanList[#fanList + 1] = { name = "碰碰胡", fan = fan }
    end
    if ctx.gangWin then
        fanList[#fanList + 1] = { name = "杠上开花", fan = 1 }
    end
    if ctx.qiangGang then
        fanList[#fanList + 1] = { name = "抢杠胡", fan = 1 }
    end
    if ctx.haiDi then
        fanList[#fanList + 1] = { name = "海底捞月", fan = 1 }
    end
    if #fanList == 0 then
        fanList[#fanList + 1] = { name = "平胡", fan = 1 }
    end
    if RequiresMissingSuitRule(ruleId) and type(ctx.missingSuitCleared) == "boolean" and not ctx.missingSuitCleared then
        return { { name = "未打缺（禁止胡牌）", fan = 0 } }
    end
    return fanList
end

function Scoring.SumFan(fanList)
    local total = 0
    for _, x in ipairs(fanList) do
        total = total + (x.fan or 0)
    end
    return total
end
