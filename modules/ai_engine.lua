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

local AI = NS.AI or {}
NS.AI = AI

local CloneTable = Core.CloneTable
local CountMap = Core.CountMap
local CopyArray = Core.CopyArray
local TileSuitAndValue = Core.TileSuitAndValue
local RemoveByValue = Core.RemoveByValue

local function BuildWinRuleOptions(context)
    local opts = {}
    local ruleId = context and context.ruleId
    if type(ruleId) == "string" and type(RuleSet.GetWinOptions) == "function" then
        local ruleOpts = RuleSet.GetWinOptions(ruleId)
        if type(ruleOpts) == "table" then
            opts.allowKokushi = ruleOpts.allowKokushi
            opts.allowSevenPairs = ruleOpts.allowSevenPairs
            opts.allowHonors = ruleOpts.allowHonors
        end
    end
    if type(ruleId) == "string" and type(RuleSet.GetCandidateTiles) == "function" then
        opts.candidateTiles = RuleSet.GetCandidateTiles(ruleId)
    end
    if type(ruleId) == "string" then
        opts.ruleId = ruleId
    end
    return opts
end

local DIFFICULTY_CONFIG = {
    beginner = {
        key = "beginner",
        label = "新手",
        wShanten = 230,
        wTingType = 8,
        wTingRemain = 3,
        wKeep = 0.34,
        wDanger = 1.0,
        responseThreshold = 26,
        kongThreshold = 30,
        aggression = 0.25,
        bluff = 0.0,
        noise = 0.0,
    },
    advanced = {
        key = "advanced",
        label = "进阶",
        wShanten = 260,
        wTingType = 13,
        wTingRemain = 6,
        wKeep = 0.42,
        wDanger = 4.5,
        responseThreshold = 10,
        kongThreshold = 12,
        aggression = 0.45,
        bluff = 0.0,
        noise = 0.0,
    },
    expert = {
        key = "expert",
        label = "专家",
        wShanten = 290,
        wTingType = 17,
        wTingRemain = 9,
        wKeep = 0.50,
        wDanger = 7.5,
        responseThreshold = 3,
        kongThreshold = 4,
        aggression = 0.62,
        bluff = 2.2,
        noise = 0.0,
    },
    master = {
        key = "master",
        label = "大师",
        wShanten = 315,
        wTingType = 19,
        wTingRemain = 12,
        wKeep = 0.55,
        wDanger = 10.0,
        responseThreshold = -2,
        kongThreshold = -1,
        aggression = 0.74,
        bluff = 5.0,
        noise = 2.5,
    },
}

local DIFFICULTY_ALIASES = {
    beginner = "beginner",
    newbie = "beginner",
    novice = "beginner",
    ["新手"] = "beginner",
    ["新手级"] = "beginner",
    ["新手级别"] = "beginner",
    advanced = "advanced",
    intermediate = "advanced",
    ["进阶"] = "advanced",
    ["进阶级"] = "advanced",
    ["进阶级别"] = "advanced",
    expert = "expert",
    ["专家"] = "expert",
    ["专家级"] = "expert",
    ["专家级别"] = "expert",
    master = "master",
    ["大师"] = "master",
    ["大师级"] = "master",
    ["大师级别"] = "master",
}

local function GetConfig(difficulty)
    local key = AI.NormalizeDifficulty(difficulty)
    return DIFFICULTY_CONFIG[key]
end

function AI.NormalizeDifficulty(value)
    if type(value) ~= "string" then
        return "advanced"
    end
    local raw = value
    local lower = string.lower(raw)
    if DIFFICULTY_ALIASES[raw] then
        return DIFFICULTY_ALIASES[raw]
    end
    if DIFFICULTY_ALIASES[lower] then
        return DIFFICULTY_ALIASES[lower]
    end
    if string.find(raw, "新手", 1, true) then
        return "beginner"
    end
    if string.find(raw, "进阶", 1, true) then
        return "advanced"
    end
    if string.find(raw, "专家", 1, true) then
        return "expert"
    end
    if string.find(raw, "大师", 1, true) then
        return "master"
    end
    return "advanced"
end

function AI.GetDifficultyLabel(value)
    return GetConfig(value).label
end

function AI.GetDifficultyKeys()
    return { "beginner", "advanced", "expert", "master" }
end

local function Roll(context)
    if context and context.stochastic then
        if type(context.rngRoll) == "function" then
            local v = tonumber(context.rngRoll())
            if v then
                if v < 0 then v = 0 end
                if v > 1 then v = 1 end
                return v
            end
        end
        if type(math.random) == "function" then
            return math.random()
        end
    end
    return 0.5
end

local function BuildVisibleCounts(hand, context)
    local counts = CountMap(hand or {})
    if not context or type(context.players) ~= "table" then
        return counts
    end
    for _, player in ipairs(context.players) do
        if player then
            for _, card in ipairs(player.discards or {}) do
                if type(card) == "string" and #card >= 2 and card ~= "0W" then
                    counts[card] = (counts[card] or 0) + 1
                end
            end
            for _, meld in ipairs(player.melds or {}) do
                for _, card in ipairs((meld and meld.tiles) or {}) do
                    if type(card) == "string" and #card >= 2 then
                        counts[card] = (counts[card] or 0) + 1
                    end
                end
            end
        end
    end
    return counts
end

local function RemainingCount(card, visibleCounts)
    return math.max(0, 4 - (visibleCounts[card] or 0))
end

local function SumRemaining(tiles, visibleCounts)
    local total = 0
    local seen = {}
    for _, tile in ipairs(tiles) do
        if not seen[tile] then
            total = total + RemainingCount(tile, visibleCounts)
            seen[tile] = true
        end
    end
    return total
end

local function IsDiscardedByPlayer(player, card)
    for _, c in ipairs((player and player.discards) or {}) do
        if c == card then
            return true
        end
    end
    return false
end

local function EstimateTileDanger(card, context, visibleCounts)
    if not context or type(context.players) ~= "table" then
        return 0
    end
    local suit, value = TileSuitAndValue(card)
    if not suit or not value then
        return 0
    end
    local risk = 0
    local selfSeat = tonumber(context.selfSeat) or 0
    for seat = 1, 4 do
        local p = context.players[seat]
        if p and seat ~= selfSeat then
            if IsDiscardedByPlayer(p, card) then
                risk = risk + 0.2
            else
                local base
                if suit == "F" then
                    base = 1.35
                elseif value == 1 or value == 9 then
                    base = 1.05
                elseif value == 2 or value == 8 then
                    base = 1.22
                else
                    base = 1.48
                end
                local remain = RemainingCount(card, visibleCounts)
                if remain <= 1 then
                    base = base * 0.58
                elseif remain == 2 then
                    base = base * 0.78
                end
                if suit ~= "F" then
                    local left = tostring(value - 1) .. suit
                    local right = tostring(value + 1) .. suit
                    local nearDropped = IsDiscardedByPlayer(p, left) or IsDiscardedByPlayer(p, right)
                    if nearDropped then
                        base = base * 0.86
                    end
                end
                risk = risk + base
            end
        end
    end
    return risk
end

local function EstimateBluffValue(card, handAfterDiscard, context)
    if not context then
        return 0
    end
    local suit, value = TileSuitAndValue(card)
    if not suit or not value then
        return 0
    end
    if suit == "F" then
        return 0
    end
    local suits = { W = 0, T = 0, S = 0 }
    for _, t in ipairs(handAfterDiscard) do
        local s = t:sub(2, 2)
        if suits[s] ~= nil then
            suits[s] = suits[s] + 1
        end
    end
    local dominantSuit = "W"
    local dominantCount = suits.W
    if suits.T > dominantCount then
        dominantSuit = "T"
        dominantCount = suits.T
    end
    if suits.S > dominantCount then
        dominantSuit = "S"
        dominantCount = suits.S
    end
    if dominantCount < 5 then
        return 0
    end
    if suit ~= dominantSuit then
        return 1.0
    end
    return 0.2
end

local function GetTileKeepValue(card, hand)
    local counts = CountMap(hand)
    local suit, value = TileSuitAndValue(card)
    if suit == "F" then
        local c = counts[card] or 0
        if c == 1 then
            return 10
        elseif c == 2 then
            return 70
        else
            return 90
        end
    end
    local same = counts[card] or 0
    local left2 = counts[tostring(value - 2) .. suit] or 0
    local left1 = counts[tostring(value - 1) .. suit] or 0
    local right1 = counts[tostring(value + 1) .. suit] or 0
    local right2 = counts[tostring(value + 2) .. suit] or 0

    local score = 50
    if same >= 2 then
        score = score + 30
    end
    if left1 > 0 then score = score + 10 end
    if right1 > 0 then score = score + 10 end
    if left2 > 0 then score = score + 5 end
    if right2 > 0 then score = score + 5 end

    if (value >= 3 and left2 > 0 and left1 > 0)
        or (value >= 2 and value <= 8 and left1 > 0 and right1 > 0)
        or (value <= 7 and right1 > 0 and right2 > 0) then
        score = score + 30
    end
    if value == 1 or value == 9 then
        score = score - 20
    elseif value == 2 or value == 8 then
        score = score - 10
    end
    return score
end

local function CalculateSuitSetsTatsu(counts)
    local best = 0
    local function dfs(i, value)
        while i <= 9 and counts[i] == 0 do
            i = i + 1
        end
        if i > 9 then
            if value > best then
                best = value
            end
            return
        end
        if counts[i] >= 3 then
            counts[i] = counts[i] - 3
            dfs(i, value + 2)
            counts[i] = counts[i] + 3
        end
        if i <= 7 and counts[i] > 0 and counts[i + 1] > 0 and counts[i + 2] > 0 then
            counts[i], counts[i + 1], counts[i + 2] = counts[i] - 1, counts[i + 1] - 1, counts[i + 2] - 1
            dfs(i, value + 2)
            counts[i], counts[i + 1], counts[i + 2] = counts[i] + 1, counts[i + 1] + 1, counts[i + 2] + 1
        end
        if counts[i] >= 2 then
            counts[i] = counts[i] - 2
            dfs(i, value + 1)
            counts[i] = counts[i] + 2
        end
        if i <= 8 and counts[i] > 0 and counts[i + 1] > 0 then
            counts[i], counts[i + 1] = counts[i] - 1, counts[i + 1] - 1
            dfs(i, value + 1)
            counts[i], counts[i + 1] = counts[i] + 1, counts[i + 1] + 1
        end
        if i <= 7 and counts[i] > 0 and counts[i + 2] > 0 then
            counts[i], counts[i + 2] = counts[i] - 1, counts[i + 2] - 1
            dfs(i, value + 1)
            counts[i], counts[i + 2] = counts[i] + 1, counts[i + 2] + 1
        end
        local c = counts[i]
        counts[i] = 0
        dfs(i + 1, value)
        counts[i] = c
    end
    dfs(1, 0)
    return best
end

local function CalculateMaxSets(counts)
    local total = 0
    for _, suit in ipairs({ "W", "T", "S" }) do
        local suitCounts = {}
        for value = 1, 9 do
            suitCounts[value] = counts[tostring(value) .. suit] or 0
        end
        total = total + CalculateSuitSetsTatsu(suitCounts)
    end
    for value = 1, 7 do
        local card = tostring(value) .. "F"
        local c = counts[card] or 0
        if c >= 3 then
            total = total + 2 * math.floor(c / 3)
            c = c % 3
        end
        if c >= 2 then
            total = total + 1
        end
    end
    return total
end

function AI.GetShanten(hand)
    local counts = CountMap(hand)
    local minShanten = 8
    for card, c in pairs(counts) do
        if c >= 2 then
            counts[card] = c - 2
            local temp = CloneTable(counts)
            local val = 7 - CalculateMaxSets(temp)
            if val < minShanten then
                minShanten = val
            end
            counts[card] = c
        end
    end
    local temp = CloneTable(counts)
    local val = 8 - CalculateMaxSets(temp)
    if val < minShanten then
        minShanten = val
    end
    return minShanten
end

local function EvaluateHandPotential(hand, meldSetCount, context, visibleCounts)
    local shanten = AI.GetShanten(hand)
    local ting = Rules.GetTingListWithMelds(hand, meldSetCount or 0, BuildWinRuleOptions(context))
    local remain = SumRemaining(ting, visibleCounts or CountMap(hand))
    local cfg = GetConfig(context and context.difficulty)
    return (-shanten * cfg.wShanten) + (#ting * cfg.wTingType) + (remain * cfg.wTingRemain)
end

local function BuildDiscardCandidates(hand, meldSetCount, context)
    local cfg = GetConfig(context and context.difficulty)
    local visible = BuildVisibleCounts(hand, context)
    local list = {}
    local ruleOpts = BuildWinRuleOptions(context)
    local ruleId = context and context.ruleId
    local missingSuit = context and context.missingSuit
    for idx, card in ipairs(hand) do
        if type(RuleSet.CanDiscard) ~= "function" or RuleSet.CanDiscard(ruleId, hand, card, missingSuit) then
            local tmp = CopyArray(hand)
            table.remove(tmp, idx)
            local shanten = AI.GetShanten(tmp)
            local tingList = Rules.GetTingListWithMelds(tmp, meldSetCount, ruleOpts)
            local tingRemain = SumRemaining(tingList, visible)
            local keepValue = GetTileKeepValue(card, hand)
            local danger = EstimateTileDanger(card, context, visible)
            local bluff = EstimateBluffValue(card, tmp, context)
            local score = (-shanten * cfg.wShanten)
                + (#tingList * cfg.wTingType)
                + (tingRemain * cfg.wTingRemain)
                - (keepValue * cfg.wKeep)
                - (danger * cfg.wDanger)
                + (bluff * cfg.bluff)
                + ((Roll(context) - 0.5) * cfg.noise)
            list[#list + 1] = {
                card = card,
                score = score,
                shanten = shanten,
                tingCount = #tingList,
                tingRemain = tingRemain,
                danger = danger,
                keepValue = keepValue,
            }
        end
    end
    if #list == 0 then
        for _, card in ipairs(hand) do
            if type(RuleSet.CanDiscard) ~= "function" or RuleSet.CanDiscard(ruleId, hand, card, missingSuit) then
                list[#list + 1] = {
                    card = card,
                    score = 0,
                    shanten = 99,
                    tingCount = 0,
                    tingRemain = 0,
                    danger = 0,
                    keepValue = 0,
                }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        if a.shanten ~= b.shanten then
            return a.shanten < b.shanten
        end
        if a.tingCount ~= b.tingCount then
            return a.tingCount > b.tingCount
        end
        return a.keepValue < b.keepValue
    end)
    return list
end

local function PickByDifficulty(list, context)
    if #list == 0 then
        return nil
    end
    local level = AI.NormalizeDifficulty(context and context.difficulty)
    local best = list[1]
    local second = list[2]
    local third = list[3]
    local r = Roll(context)
    if level == "beginner" then
        if third and r > 0.70 then
            return third
        elseif second and r > 0.45 then
            return second
        end
        return best
    end
    if level == "advanced" then
        if second and (best.score - second.score) <= 5 and r > 0.80 then
            return second
        end
        return best
    end
    if level == "expert" then
        if second and (best.score - second.score) <= 3 and r > 0.88 then
            return second
        end
        return best
    end
    if level == "master" then
        if third and (best.score - third.score) <= 7 and r > 0.82 then
            return third
        end
        if second and (best.score - second.score) <= 4 and r > 0.60 then
            return second
        end
    end
    return best
end

function AI.ChooseAIDiscard(hand, meldSetCount, context)
    local candidates = BuildDiscardCandidates(hand, meldSetCount or 0, context or {})
    local pick = PickByDifficulty(candidates, context or {})
    if pick and pick.card then
        return pick.card
    end
    local ctx = context or {}
    if type(RuleSet.CanDiscard) == "function" then
        for _, card in ipairs(hand) do
            if RuleSet.CanDiscard(ctx.ruleId, hand, card, ctx.missingSuit) then
                return card
            end
        end
    end
    return hand[#hand]
end

function AI.GetKongCandidates(player, lastDiscard, fromDiscard)
    local out = {}
    local counts = CountMap(player.hand)
    if fromDiscard and lastDiscard then
        if (counts[lastDiscard] or 0) >= 3 then
            out[#out + 1] = { kind = "minggang", tile = lastDiscard }
        end
        return out
    end
    for tile, c in pairs(counts) do
        if c >= 4 then
            out[#out + 1] = { kind = "angang", tile = tile }
        end
    end
    for _, meld in ipairs(player.melds) do
        if meld.type == "peng" then
            local tile = meld.tiles[1]
            if (counts[tile] or 0) >= 1 then
                out[#out + 1] = { kind = "bugang", tile = tile }
            end
        end
    end
    return out
end

function AI.GetChowCandidates(hand, card)
    local valSuit, valNum = TileSuitAndValue(card)
    if valSuit == "F" or not valNum then
        return {}
    end
    local counts = CountMap(hand)
    local function has(tile)
        return (counts[tile] or 0) > 0
    end
    local cands = {}
    if valNum >= 3 then
        local a, b = tostring(valNum - 2) .. valSuit, tostring(valNum - 1) .. valSuit
        if has(a) and has(b) then
            cands[#cands + 1] = { a, b, card }
        end
    end
    if valNum >= 2 and valNum <= 8 then
        local a, b = tostring(valNum - 1) .. valSuit, tostring(valNum + 1) .. valSuit
        if has(a) and has(b) then
            cands[#cands + 1] = { a, b, card }
        end
    end
    if valNum <= 7 then
        local a, b = tostring(valNum + 1) .. valSuit, tostring(valNum + 2) .. valSuit
        if has(a) and has(b) then
            cands[#cands + 1] = { a, b, card }
        end
    end
    return cands
end

local function SimulateResponse(hand, meldSetCount, actionKind, discardCard, combo)
    local tmp = CopyArray(hand)
    local newMeldSet = meldSetCount or 0
    if actionKind == "PENG" then
        if RemoveByValue(tmp, discardCard, 2) < 2 then
            return nil, nil
        end
        newMeldSet = newMeldSet + 1
    elseif actionKind == "GANG" then
        if RemoveByValue(tmp, discardCard, 3) < 3 then
            return nil, nil
        end
        newMeldSet = newMeldSet + 1
    elseif actionKind == "CHI" then
        if type(combo) ~= "table" or #combo < 3 then
            return nil, nil
        end
        local a = combo[1]
        local b = combo[2]
        if RemoveByValue(tmp, a, 1) < 1 then
            return nil, nil
        end
        if RemoveByValue(tmp, b, 1) < 1 then
            return nil, nil
        end
        newMeldSet = newMeldSet + 1
    else
        return tmp, newMeldSet
    end
    return tmp, newMeldSet
end

local function EvaluateActionAfterClaim(hand, meldSetCount, actionKind, discardCard, combo, context)
    local tmp, newMeldSet = SimulateResponse(hand, meldSetCount, actionKind, discardCard, combo)
    if not tmp then
        return -math.huge
    end
    local visible = BuildVisibleCounts(hand, context)
    local postClaim = EvaluateHandPotential(tmp, newMeldSet, context, visible)
    if #tmp > 0 then
        local discard = AI.ChooseAIDiscard(tmp, newMeldSet, {
            difficulty = context and context.difficulty,
            players = context and context.players,
            selfSeat = context and context.selfSeat,
            stochastic = false,
        })
        local afterDiscard = CopyArray(tmp)
        RemoveByValue(afterDiscard, discard, 1)
        local postDiscard = EvaluateHandPotential(afterDiscard, newMeldSet, context, visible)
        postClaim = postClaim + (postDiscard * 0.7)
    end
    if actionKind == "GANG" then
        postClaim = postClaim + 10
    elseif actionKind == "PENG" then
        postClaim = postClaim + 6
    elseif actionKind == "CHI" then
        postClaim = postClaim + 4
    end
    return postClaim
end

function AI.DecideResponse(hand, meldSetCount, legalActions, context)
    if type(legalActions) ~= "table" or #legalActions == 0 then
        return { kind = "PASS" }
    end
    for _, act in ipairs(legalActions) do
        if act.kind == "HU" then
            return { kind = "HU" }
        end
    end
    local cfg = GetConfig(context and context.difficulty)
    local base = EvaluateHandPotential(hand, meldSetCount or 0, context or {}, BuildVisibleCounts(hand, context))
    local best = { kind = "PASS" }
    local bestGain = -math.huge

    for _, act in ipairs(legalActions) do
        if act.kind == "CHI" then
            for _, combo in ipairs(act.combos or {}) do
                local score = EvaluateActionAfterClaim(hand, meldSetCount, "CHI", context and context.discardCard, combo, context or {})
                local gain = score - base
                if gain > bestGain then
                    bestGain = gain
                    best = { kind = "CHI", data = { combo = combo } }
                end
            end
        elseif act.kind == "PENG" or act.kind == "GANG" then
            local score = EvaluateActionAfterClaim(hand, meldSetCount, act.kind, context and context.discardCard, nil, context or {})
            local gain = score - base
            if gain > bestGain then
                bestGain = gain
                best = { kind = act.kind }
            end
        end
    end

    local threshold = cfg.responseThreshold
    if best.kind == "GANG" then
        threshold = threshold + 5
    end
    if bestGain < threshold then
        return { kind = "PASS" }
    end

    if AI.NormalizeDifficulty(context and context.difficulty) == "master" and context and context.stochastic then
        local r = Roll(context)
        if best.kind ~= "PASS" and r > (0.94 + (1.0 - cfg.aggression) * 0.03) then
            return { kind = "PASS" }
        end
    end
    return best
end

function AI.SelectKongInDraw(player, kongList, context)
    if type(kongList) ~= "table" or #kongList == 0 or not player then
        return nil
    end
    local cfg = GetConfig(context and context.difficulty)
    local visible = BuildVisibleCounts(player.hand, context)
    local baseScore = EvaluateHandPotential(player.hand, player.meldSetCount or 0, context or {}, visible)
    local baseShanten = AI.GetShanten(player.hand)
    local best, bestGain = nil, -math.huge

    for _, info in ipairs(kongList) do
        local tmp = CopyArray(player.hand)
        local valid = true
        if info.kind == "angang" then
            if RemoveByValue(tmp, info.tile, 4) < 4 then
                valid = false
            end
        elseif info.kind == "bugang" then
            if RemoveByValue(tmp, info.tile, 1) < 1 then
                valid = false
            end
        else
            valid = false
        end
        if valid then
            local newMeldSet = (player.meldSetCount or 0) + 1
            local shanten = AI.GetShanten(tmp)
            local score = EvaluateHandPotential(tmp, newMeldSet, context or {}, visible)
            if shanten > baseShanten then
                score = score - 30
            end
            local gain = score - baseScore
            if gain > bestGain then
                bestGain = gain
                best = info
            end
        end
    end
    if not best then
        return nil
    end
    if bestGain < cfg.kongThreshold then
        return nil
    end
    if AI.NormalizeDifficulty(context and context.difficulty) == "beginner" and best.kind == "bugang" then
        return nil
    end
    return best
end
