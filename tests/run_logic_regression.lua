local ns = {}

assert(loadfile("modules/core_utils.lua"))("MaJiang", ns)
assert(loadfile("modules/ruleset.lua"))("MaJiang", ns)
assert(loadfile("modules/game_rules.lua"))("MaJiang", ns)
assert(loadfile("modules/ai_engine.lua"))("MaJiang", ns)
assert(loadfile("modules/scoring.lua"))("MaJiang", ns)

local Core = assert(ns.Core, "ns.Core missing")
local RuleSet = assert(ns.RuleSet, "ns.RuleSet missing")
local Rules = assert(ns.Rules, "ns.Rules missing")
local AI = assert(ns.AI, "ns.AI missing")
local Scoring = assert(ns.Scoring, "ns.Scoring missing")

local function fail(msg)
    io.stderr:write("FAIL: " .. msg .. "\n")
    os.exit(1)
end

local function assertEq(actual, expected, label)
    if actual ~= expected then
        fail(string.format("%s expected=%s actual=%s", label, tostring(expected), tostring(actual)))
    end
end

local function sortedCopy(list)
    local out = {}
    for i = 1, #list do
        out[i] = list[i]
    end
    table.sort(out)
    return out
end

local function assertArrayEq(actual, expected, label)
    if #actual ~= #expected then
        fail(string.format("%s len expected=%d actual=%d", label, #expected, #actual))
    end
    for i = 1, #expected do
        if actual[i] ~= expected[i] then
            fail(string.format("%s[%d] expected=%s actual=%s", label, i, tostring(expected[i]), tostring(actual[i])))
        end
    end
end

local handSeven = { "1W", "1W", "2W", "2W", "3W", "3W", "4T", "4T", "5T", "5T", "6S", "6S", "7F", "7F" }
local handKokushi = { "1W", "9W", "1T", "9T", "1S", "9S", "1F", "2F", "3F", "4F", "5F", "6F", "7F", "1W" }
local handWin = { "1W", "1W", "1W", "2W", "3W", "4W", "5W", "6W", "7W", "8W", "8W", "8W", "9W", "9W" }
local handWinMeld = { "1W", "1W", "2W", "3W", "4W", "5W", "6W", "7W", "8W", "8W", "8W" }
local handTing = { "1W", "1W", "1W", "2W", "3W", "4W", "5W", "6W", "7W", "8W", "8W", "8W", "9W" }
local handAI = { "1W", "1W", "1W", "2W", "3W", "4W", "5W", "6W", "7W", "2T", "3T", "4T", "9F", "9F" }
local handSichuan = { "1W", "1W", "2W", "2W", "3W", "3W", "4T", "4T", "5T", "5T", "6S", "6S", "7S", "7S" }

assertEq(Rules.IsSevenPairs(handSeven), true, "IsSevenPairs")
assertEq(Rules.IsKokushi(handKokushi), true, "IsKokushi")
assertEq(Rules.IsWinWithMelds(handWin, 0), true, "IsWinWithMelds basic")
assertEq(Rules.IsWinWithMelds(handWinMeld, 1), true, "IsWinWithMelds with meld")
assertEq(Rules.IsWinWithMelds(handKokushi, 0, { ruleId = "international" }), false, "IsWinWithMelds international no kokushi")
assertEq(Rules.IsWinWithMelds(handSichuan, 0, { ruleId = "sichuan_traditional" }), true, "IsWinWithMelds sichuan seven pairs")

local ting = sortedCopy(Rules.GetTingListWithMelds(handTing, 0))
assertArrayEq(ting, { "1W", "4W", "7W", "8W", "9W" }, "GetTingListWithMelds")
local tingSichuan = Rules.GetTingListWithMelds({ "1W", "1W", "2W", "3W", "4W", "5W", "6W", "7W", "8W", "9W", "9W", "2T", "3T" }, 0, { ruleId = "sichuan_traditional" })
for _, tile in ipairs(tingSichuan) do
    if tile:sub(2, 2) == "F" then
        fail("GetTingListWithMelds sichuan should not include honors")
    end
end

assertEq(AI.GetShanten(handTing), 0, "GetShanten")
assertEq(AI.ChooseAIDiscard(handAI, 0), "2W", "ChooseAIDiscard")
assertEq(RuleSet.NormalizeRuleId("四川麻将血流"), "sichuan_bloodriver", "NormalizeRuleId")
assertEq(RuleSet.CanDiscard("sichuan_traditional", { "1W", "2T", "3T" }, "2T", "W"), false, "CanDiscard missing suit lock")
assertEq(RuleSet.CanDiscard("sichuan_traditional", { "1W", "2T", "3T" }, "1W", "W"), true, "CanDiscard missing suit allowed")

local player = {
    hand = Core.CopyArray(handWin),
    melds = {},
}
Core.SortHand(player.hand, false)
local fan = Scoring.EvaluateFan(player, {
    selfDraw = true,
    gangWin = false,
    qiangGang = false,
    haiDi = false,
})

assertEq(Scoring.SumFan(fan), 6, "SumFan")

local fanNames = {}
for _, x in ipairs(fan) do
    fanNames[#fanNames + 1] = string.format("%s:%d", x.name, x.fan or 0)
end
table.sort(fanNames)
assertArrayEq(fanNames, { "清一色:4", "自摸:1", "门前清:1" }, "EvaluateFan names")

assertEq(Core.CardToImageKey("1W"), "1", "CardToImageKey")
assertEq(Core.CardToVoiceIndex("1F"), 27, "CardToVoiceIndex")
assertEq(AI.NormalizeDifficulty("进阶级"), "advanced", "NormalizeDifficulty zh")
assertEq(AI.NormalizeDifficulty("MASTER"), "master", "NormalizeDifficulty en")
local resp = AI.DecideResponse(handWinMeld, 1, { { kind = "HU" }, { kind = "PENG" } }, {
    difficulty = "beginner",
    players = {},
    selfSeat = 2,
    discardCard = "9W",
    stochastic = false,
})
assertEq(resp.kind, "HU", "DecideResponse HU priority")

print("OK: logic regression passed")
