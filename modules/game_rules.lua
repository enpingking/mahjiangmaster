local _, NS = ...
if type(NS) ~= "table" then
    NS = _G.MaJiangNS or {}
    _G.MaJiangNS = NS
end

local Core = NS.Core
assert(type(Core) == "table", "MaJiang modules load order error: NS.Core missing")
local RuleSet = NS.RuleSet or {}

local Rules = NS.Rules or {}
NS.Rules = Rules

local CountMap = Core.CountMap
local CopyArray = Core.CopyArray
local TileSuitAndValue = Core.TileSuitAndValue
local TileLess = Core.TileLess

local function BuildDefaultCandidateTiles()
    local allTiles = {}
    for _, suit in ipairs({ "W", "T", "S" }) do
        for value = 1, 9 do
            allTiles[#allTiles + 1] = tostring(value) .. suit
        end
    end
    for value = 1, 7 do
        allTiles[#allTiles + 1] = tostring(value) .. "F"
    end
    return allTiles
end

local function NormalizeWinOptions(opts)
    local out = {
        allowKokushi = true,
        allowSevenPairs = true,
        allowHonors = true,
        candidateTiles = BuildDefaultCandidateTiles(),
    }
    if type(opts) ~= "table" then
        return out
    end
    if type(opts.ruleId) == "string" and type(RuleSet.GetWinOptions) == "function" then
        local fromRule = RuleSet.GetWinOptions(opts.ruleId)
        if type(fromRule) == "table" then
            if fromRule.allowKokushi ~= nil then
                out.allowKokushi = fromRule.allowKokushi and true or false
            end
            if fromRule.allowSevenPairs ~= nil then
                out.allowSevenPairs = fromRule.allowSevenPairs and true or false
            end
            if fromRule.allowHonors ~= nil then
                out.allowHonors = fromRule.allowHonors and true or false
            end
        end
        if type(RuleSet.GetCandidateTiles) == "function" then
            local cands = RuleSet.GetCandidateTiles(opts.ruleId)
            if type(cands) == "table" and #cands > 0 then
                out.candidateTiles = cands
            end
        end
    end
    if opts.allowKokushi ~= nil then
        out.allowKokushi = opts.allowKokushi and true or false
    end
    if opts.allowSevenPairs ~= nil then
        out.allowSevenPairs = opts.allowSevenPairs and true or false
    end
    if opts.allowHonors ~= nil then
        out.allowHonors = opts.allowHonors and true or false
    end
    if type(opts.candidateTiles) == "table" and #opts.candidateTiles > 0 then
        out.candidateTiles = opts.candidateTiles
    end
    return out
end

local function HasHonorTile(hand)
    for _, card in ipairs(hand or {}) do
        local suit = card:sub(2, 2)
        if suit == "F" then
            return true
        end
    end
    return false
end

function Rules.IsSevenPairs(hand)
    if #hand ~= 14 then
        return false
    end
    local counts = CountMap(hand)
    local pairCount = 0
    for _, c in pairs(counts) do
        if c == 2 or c == 4 then
            pairCount = pairCount + (c / 2)
        else
            return false
        end
    end
    return pairCount == 7
end

function Rules.IsKokushi(hand)
    if #hand ~= 14 then
        return false
    end
    local required = {
        ["1W"] = true, ["9W"] = true,
        ["1T"] = true, ["9T"] = true,
        ["1S"] = true, ["9S"] = true,
        ["1F"] = true, ["2F"] = true, ["3F"] = true,
        ["4F"] = true, ["5F"] = true, ["6F"] = true, ["7F"] = true,
    }
    local counts = {}
    for _, card in ipairs(hand) do
        if not required[card] then
            return false
        end
        counts[card] = (counts[card] or 0) + 1
        if counts[card] > 2 then
            return false
        end
    end
    local hasPair = false
    for tile in pairs(required) do
        local c = counts[tile] or 0
        if c == 0 then
            return false
        end
        if c == 2 then
            if hasPair then
                return false
            end
            hasPair = true
        end
    end
    return hasPair
end

local function CanFormSets(sortedTiles, needSets)
    if needSets == 0 then
        return #sortedTiles == 0
    end
    if #sortedTiles ~= needSets * 3 then
        return false
    end
    local first = sortedTiles[1]
    local success = false
    if sortedTiles[2] == first and sortedTiles[3] == first then
        local rest = {}
        for i = 4, #sortedTiles do
            rest[#rest + 1] = sortedTiles[i]
        end
        if CanFormSets(rest, needSets - 1) then
            return true
        end
    end
    local suit, value = TileSuitAndValue(first)
    if suit ~= "F" then
        local target2 = tostring(value + 1) .. suit
        local target3 = tostring(value + 2) .. suit
        local idx2, idx3
        for i = 2, #sortedTiles do
            if not idx2 and sortedTiles[i] == target2 then
                idx2 = i
            elseif not idx3 and sortedTiles[i] == target3 then
                idx3 = i
            end
        end
        if idx2 and idx3 then
            local rest = {}
            for i = 2, #sortedTiles do
                if i ~= idx2 and i ~= idx3 then
                    rest[#rest + 1] = sortedTiles[i]
                end
            end
            success = CanFormSets(rest, needSets - 1)
        end
    end
    return success
end

local function CanFormAllTriplets(sortedTiles, needSets)
    if needSets == 0 then
        return #sortedTiles == 0
    end
    if #sortedTiles ~= needSets * 3 then
        return false
    end
    local first = sortedTiles[1]
    if sortedTiles[2] ~= first or sortedTiles[3] ~= first then
        return false
    end
    local rest = {}
    for i = 4, #sortedTiles do
        rest[#rest + 1] = sortedTiles[i]
    end
    return CanFormAllTriplets(rest, needSets - 1)
end

function Rules.IsWinWithMelds(hand, meldSetCount, opts)
    if #hand == 0 then
        return false
    end
    local winOpts = NormalizeWinOptions(opts)
    if not winOpts.allowHonors and HasHonorTile(hand) then
        return false
    end
    local needSets = 4 - (meldSetCount or 0)
    if needSets < 0 then
        return false
    end
    if (meldSetCount or 0) == 0 then
        if winOpts.allowSevenPairs and Rules.IsSevenPairs(hand) then
            return true
        end
        if winOpts.allowKokushi and winOpts.allowHonors and Rules.IsKokushi(hand) then
            return true
        end
    end
    local sorted = CopyArray(hand)
    table.sort(sorted, TileLess)
    if #sorted ~= needSets * 3 + 2 then
        return false
    end
    for i = 1, #sorted - 1 do
        if sorted[i] == sorted[i + 1] then
            local rest = {}
            for j = 1, #sorted do
                if j ~= i and j ~= i + 1 then
                    rest[#rest + 1] = sorted[j]
                end
            end
            if CanFormSets(rest, needSets) then
                return true
            end
        end
    end
    return false
end

function Rules.IsPengPengHu(hand, melds)
    local needSets = 4 - #melds
    for _, meld in ipairs(melds) do
        if meld.type == "chi" then
            return false
        end
    end
    local sorted = CopyArray(hand)
    table.sort(sorted, TileLess)
    if #sorted ~= needSets * 3 + 2 then
        return false
    end
    for i = 1, #sorted - 1 do
        if sorted[i] == sorted[i + 1] then
            local rest = {}
            for j = 1, #sorted do
                if j ~= i and j ~= i + 1 then
                    rest[#rest + 1] = sorted[j]
                end
            end
            if CanFormAllTriplets(rest, needSets) then
                return true
            end
        end
    end
    return false
end

function Rules.GetTingListWithMelds(hand, meldSetCount, opts)
    local ting = {}
    local winOpts = NormalizeWinOptions(opts)
    for _, tile in ipairs(winOpts.candidateTiles) do
        local tmp = CopyArray(hand)
        tmp[#tmp + 1] = tile
        if Rules.IsWinWithMelds(tmp, meldSetCount, winOpts) then
            ting[#ting + 1] = tile
        end
    end
    return ting
end
