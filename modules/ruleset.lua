local _, NS = ...
if type(NS) ~= "table" then
    NS = _G.MaJiangNS or {}
    _G.MaJiangNS = NS
end

local Core = NS.Core
assert(type(Core) == "table", "MaJiang modules load order error: NS.Core missing")

local RuleSet = NS.RuleSet or {}
NS.RuleSet = RuleSet

local CopyArray = Core.CopyArray

local RULE_ORDER = {
    "international",
    "japanese",
    "guangdong",
    "wuhan",
    "shanghai",
    "taiwan",
    "beijing",
    "dongbei",
    "changsha",
    "hangzhou",
    "nanjing",
    "chaoshan",
    "tianjin",
    "chongqing",
    "kunming",
    "guiyang",
    "fuzhou",
    "nanchang",
    "guangxi",
    "xinjiang",
    "sichuan",
    "zhengzhou",
    "xian",
    "kejia",
    "hainan",
    "anhui",
    "suzhou",
}

local RULE_DEFS = {
    international = {
        id = "international",
        name = "国际麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "国际通行的麻将简化规则，易上手，适合通用对局。\n插件按基础番型实现，作为跨地区通用玩法。",
    },
    japanese = {
        id = "japanese",
        name = "日本麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = true,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "日本立直麻将（Riichi）风格：门清、立直、役种要求是核心。\n插件使用简化实现：支持基础和牌形态，立直棒、宝牌、振听等细则仅作说明不完整结算。",
    },
    guangdong = {
        id = "guangdong",
        name = "广东麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = true,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "广式常见玩法，可吃碰杠、可点炮，番型多。\n插件按基础番型做简化，买马等扩展不单独结算。",
    },
    wuhan = {
        id = "wuhan",
        name = "武汉麻将",
        allowChi = false,
        allowHonors = false,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = true,
        description = "红中赖子杠风格，强调赖子与持续对局。\n插件简化为不可吃、无字牌、血战继续；赖子细则不单独实现。",
    },
    shanghai = {
        id = "shanghai",
        name = "上海麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = true,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "沪麻强调门清、花牌与承包思路。\n插件保留基础胡牌/番型，花牌与承包按说明理解为简化版。",
    },
    taiwan = {
        id = "taiwan",
        name = "台湾麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "台麻常见为16张起手、台数计分。\n插件采用13张基础引擎游玩，保留台麻风格说明，16张与补花为简化。",
    },
    beijing = {
        id = "beijing",
        name = "北京麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "北京玩法常见门清、点炮与自摸并存。\n插件按基础番型实现，地方番种作为说明参考。",
    },
    dongbei = {
        id = "dongbei",
        name = "东北麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "东北玩法节奏快，可吃碰杠，也可点炮。\n插件提供通用胡牌流程，地方封顶/翻倍细则做简化。",
    },
    changsha = {
        id = "changsha",
        name = "长沙麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = true,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = true,
        description = "长沙玩法强调将牌（2/5/8）和自摸思路。\n插件采用自摸+血战风格，地方将牌细算按说明理解。",
    },
    hangzhou = {
        id = "hangzhou",
        name = "杭州麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "杭州常见“财神/百搭”玩法，胡牌路线更灵活。\n插件不单独结算财神牌，按基础牌型简化游玩。",
    },
    nanjing = {
        id = "nanjing",
        name = "南京麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = true,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "南京玩法讲究“成牌”门槛，通常偏自摸体系。\n插件采用基础成和判断，成牌细目与大车小车按说明简化。",
    },
    chaoshan = {
        id = "chaoshan",
        name = "潮汕麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "潮汕玩法可吃碰杠，番型朴实但节奏快。\n插件按通用牌型实现，地方彩番作为说明参考。",
    },
    tianjin = {
        id = "tianjin",
        name = "天津麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = true,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "天津玩法特色是“混儿（百搭）”，常见自摸优先。\n插件保留基础流程，混儿替牌和专属番型按说明简化。",
    },
    chongqing = {
        id = "chongqing",
        name = "重庆麻将",
        allowChi = false,
        allowHonors = false,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = true,
        bloodRiver = true,
        description = "重庆玩法与川麻接近：缺一门、只能自摸、血战到底。\n插件完整支持缺一门与血战流程，是当前最贴近的地区规则之一。",
    },
    kunming = {
        id = "kunming",
        name = "昆明麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "昆明玩法兼顾自摸与点炮，强调清一色等番型。\n插件采用通用番型评分，地方加番规则按说明简化。",
    },
    guiyang = {
        id = "guiyang",
        name = "贵阳麻将",
        allowChi = false,
        allowHonors = false,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = true,
        bloodRiver = false,
        description = "贵阳玩法常见108张、缺一门、偏自摸，重杠牌收益。\n插件支持缺一门流程，杠后高阶计番按说明简化。",
    },
    fuzhou = {
        id = "fuzhou",
        name = "福州麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "福州玩法含花牌补牌与花番概念。\n插件按无花牌基础引擎运行，花牌相关做说明化处理。",
    },
    nanchang = {
        id = "nanchang",
        name = "南昌麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "南昌玩法常见“冲”规则，点炮权重较高。\n插件保留标准点炮/自摸流程，冲番细则按说明简化。",
    },
    guangxi = {
        id = "guangxi",
        name = "广西麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "广西地区常见转转类玩法，局势变化快。\n插件按通用四人麻将流程实现，转转附加规则按说明简化。",
    },
    xinjiang = {
        id = "xinjiang",
        name = "新疆麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "新疆玩法常把七对等对子牌型放在核心位置。\n插件保留七对判定，地方封顶与加倍按说明简化。",
    },
    sichuan = {
        id = "sichuan",
        name = "四川麻将",
        allowChi = false,
        allowHonors = false,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = true,
        bloodRiver = true,
        description = "四川血战到底：108张、缺一门、只能自摸、胡后不停牌。\n插件完整支持缺一门和血战，是当前支持最完整的地区规则。",
    },
    zhengzhou = {
        id = "zhengzhou",
        name = "郑州麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "郑州玩法偏通用麻将体系，可点炮可自摸。\n插件按标准番型判定，地方补充番做简化说明。",
    },
    xian = {
        id = "xian",
        name = "西安麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "西安玩法结构清晰，吃碰杠与点炮都常见。\n插件提供通用流程，地方特色加码按说明简化。",
    },
    kejia = {
        id = "kejia",
        name = "客家麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "客家麻将偏传统，番型稳定，重实战节奏。\n插件按基础牌型支持，地方特番按说明简化。",
    },
    hainan = {
        id = "hainan",
        name = "海南麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "海南玩法常见点炮与自摸并行，牌局节奏均衡。\n插件采用通用番型体系，地方扩展做简化。",
    },
    anhui = {
        id = "anhui",
        name = "安徽麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "安徽玩法整体接近通用国标思路，易上手。\n插件保留核心胡牌判定，地方番型按说明简化。",
    },
    suzhou = {
        id = "suzhou",
        name = "苏州麻将",
        allowChi = true,
        allowHonors = true,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = false,
        bloodRiver = false,
        description = "苏州玩法重门清与细节番，攻守平衡。\n插件按基础番型实现，门清与地方附加番按说明简化。",
    },
    -- 兼容旧版本保留，不在可选列表中展示
    sichuan_traditional = {
        id = "sichuan_traditional",
        name = "四川麻将（传统）",
        allowChi = false,
        allowHonors = false,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = true,
        bloodRiver = false,
        description = "旧版兼容：四川传统规则（缺一门、可持续打缺）。",
    },
    sichuan_bloodriver = {
        id = "sichuan_bloodriver",
        name = "四川麻将（血流成河）",
        allowChi = false,
        allowHonors = false,
        allowKokushi = false,
        allowSevenPairs = true,
        requireMissingSuit = true,
        bloodRiver = true,
        description = "旧版兼容：四川血流成河规则。",
    },
}

local RULE_ALIAS = {
    international = "international",
    intl = "international",
    ["国际"] = "international",
    ["国际麻将"] = "international",

    japanese = "japanese",
    riichi = "japanese",
    jp = "japanese",
    ["日本"] = "japanese",
    ["日本麻将"] = "japanese",
    ["立直"] = "japanese",
    ["立直麻将"] = "japanese",
    ["日麻"] = "japanese",

    guangdong = "guangdong",
    gd = "guangdong",
    ["广东"] = "guangdong",
    ["广东麻将"] = "guangdong",

    wuhan = "wuhan",
    ["武汉"] = "wuhan",
    ["武汉麻将"] = "wuhan",

    shanghai = "shanghai",
    ["上海"] = "shanghai",
    ["上海麻将"] = "shanghai",

    taiwan = "taiwan",
    ["台湾"] = "taiwan",
    ["台湾麻将"] = "taiwan",

    beijing = "beijing",
    ["北京"] = "beijing",
    ["北京麻将"] = "beijing",

    dongbei = "dongbei",
    ["东北"] = "dongbei",
    ["东北麻将"] = "dongbei",

    changsha = "changsha",
    ["长沙"] = "changsha",
    ["长沙麻将"] = "changsha",

    hangzhou = "hangzhou",
    ["杭州"] = "hangzhou",
    ["杭州麻将"] = "hangzhou",

    nanjing = "nanjing",
    ["南京"] = "nanjing",
    ["南京麻将"] = "nanjing",

    chaoshan = "chaoshan",
    ["潮汕"] = "chaoshan",
    ["潮汕麻将"] = "chaoshan",

    tianjin = "tianjin",
    ["天津"] = "tianjin",
    ["天津麻将"] = "tianjin",

    chongqing = "chongqing",
    ["重庆"] = "chongqing",
    ["重庆麻将"] = "chongqing",

    kunming = "kunming",
    ["昆明"] = "kunming",
    ["昆明麻将"] = "kunming",

    guiyang = "guiyang",
    ["贵阳"] = "guiyang",
    ["贵阳麻将"] = "guiyang",

    fuzhou = "fuzhou",
    ["福州"] = "fuzhou",
    ["福州麻将"] = "fuzhou",

    nanchang = "nanchang",
    ["南昌"] = "nanchang",
    ["南昌麻将"] = "nanchang",

    guangxi = "guangxi",
    ["广西"] = "guangxi",
    ["广西麻将"] = "guangxi",

    xinjiang = "xinjiang",
    ["新疆"] = "xinjiang",
    ["新疆麻将"] = "xinjiang",

    sichuan = "sichuan",
    sc = "sichuan_traditional",
    ["四川"] = "sichuan_traditional",
    ["四川麻将"] = "sichuan_traditional",
    ["四川麻将传统"] = "sichuan_traditional",
    ["四川传统"] = "sichuan_traditional",
    sichuan_traditional = "sichuan_traditional",
    bloodriver = "sichuan_bloodriver",
    xlc = "sichuan_bloodriver",
    ["血流"] = "sichuan_bloodriver",
    ["血流成河"] = "sichuan_bloodriver",
    ["四川血流"] = "sichuan_bloodriver",
    ["四川麻将血流"] = "sichuan_bloodriver",
    sichuan_bloodriver = "sichuan_bloodriver",

    zhengzhou = "zhengzhou",
    ["郑州"] = "zhengzhou",
    ["郑州麻将"] = "zhengzhou",

    xian = "xian",
    ["西安"] = "xian",
    ["西安麻将"] = "xian",

    kejia = "kejia",
    ["客家"] = "kejia",
    ["客家麻将"] = "kejia",

    hainan = "hainan",
    ["海南"] = "hainan",
    ["海南麻将"] = "hainan",

    anhui = "anhui",
    ["安徽"] = "anhui",
    ["安徽麻将"] = "anhui",

    suzhou = "suzhou",
    ["苏州"] = "suzhou",
    ["苏州麻将"] = "suzhou",
}

for id, def in pairs(RULE_DEFS) do
    RULE_ALIAS[id] = id
    RULE_ALIAS[string.lower(id)] = id
    if type(def.name) == "string" and def.name ~= "" then
        RULE_ALIAS[def.name] = id
    end
end

local function FallbackRuleId()
    return "guangdong"
end

function RuleSet.NormalizeRuleId(value)
    if type(value) ~= "string" then
        return FallbackRuleId()
    end
    local direct = RULE_ALIAS[value]
    if direct and RULE_DEFS[direct] then
        return direct
    end
    local lower = string.lower(value)
    direct = RULE_ALIAS[lower]
    if direct and RULE_DEFS[direct] then
        return direct
    end
    if RULE_DEFS[value] then
        return value
    end
    if RULE_DEFS[lower] then
        return lower
    end
    if string.find(value, "血流", 1, true) then
        return "sichuan_bloodriver"
    end
    if string.find(value, "日本", 1, true) or string.find(value, "立直", 1, true) or string.find(value, "日麻", 1, true) then
        return "japanese"
    end
    if string.find(value, "四川", 1, true) then
        return "sichuan_traditional"
    end
    if string.find(value, "武汉", 1, true) then
        return "wuhan"
    end
    if string.find(value, "重庆", 1, true) then
        return "chongqing"
    end
    if string.find(value, "贵阳", 1, true) then
        return "guiyang"
    end
    if string.find(value, "广东", 1, true) then
        return "guangdong"
    end
    return FallbackRuleId()
end

function RuleSet.GetRuleDef(ruleId)
    local id = RuleSet.NormalizeRuleId(ruleId)
    return RULE_DEFS[id] or RULE_DEFS[FallbackRuleId()]
end

function RuleSet.GetRuleName(ruleId)
    return RuleSet.GetRuleDef(ruleId).name
end

function RuleSet.GetRuleDescription(ruleId)
    local def = RuleSet.GetRuleDef(ruleId)
    return def.description or ""
end

function RuleSet.GetRuleOptions()
    local out = {}
    for _, id in ipairs(RULE_ORDER) do
        local def = RULE_DEFS[id]
        out[#out + 1] = { id = def.id, name = def.name, description = def.description }
    end
    return out
end

function RuleSet.AllowsChi(ruleId)
    return RuleSet.GetRuleDef(ruleId).allowChi
end

function RuleSet.AllowsHonors(ruleId)
    return RuleSet.GetRuleDef(ruleId).allowHonors
end

function RuleSet.IsBloodRiver(ruleId)
    return RuleSet.GetRuleDef(ruleId).bloodRiver
end

function RuleSet.RequiresMissingSuit(ruleId)
    return RuleSet.GetRuleDef(ruleId).requireMissingSuit
end

function RuleSet.GetWinOptions(ruleId)
    local def = RuleSet.GetRuleDef(ruleId)
    return {
        allowKokushi = def.allowKokushi,
        allowSevenPairs = def.allowSevenPairs,
        allowHonors = def.allowHonors,
    }
end

function RuleSet.BuildDeck(ruleId)
    local def = RuleSet.GetRuleDef(ruleId)
    local deck = {}
    for _, suit in ipairs({ "W", "T", "S" }) do
        for value = 1, 9 do
            for _ = 1, 4 do
                deck[#deck + 1] = tostring(value) .. suit
            end
        end
    end
    if def.allowHonors then
        for value = 1, 7 do
            for _ = 1, 4 do
                deck[#deck + 1] = tostring(value) .. "F"
            end
        end
    end
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end

function RuleSet.GetCandidateTiles(ruleId)
    local def = RuleSet.GetRuleDef(ruleId)
    local allTiles = {}
    for _, suit in ipairs({ "W", "T", "S" }) do
        for value = 1, 9 do
            allTiles[#allTiles + 1] = tostring(value) .. suit
        end
    end
    if def.allowHonors then
        for value = 1, 7 do
            allTiles[#allTiles + 1] = tostring(value) .. "F"
        end
    end
    return allTiles
end

function RuleSet.CardSuit(card)
    if type(card) ~= "string" or #card < 2 then
        return nil
    end
    return card:sub(2, 2)
end

function RuleSet.ChooseMissingSuit(hand)
    local cnt = { W = 0, T = 0, S = 0 }
    for _, card in ipairs(hand or {}) do
        local suit = RuleSet.CardSuit(card)
        if cnt[suit] ~= nil then
            cnt[suit] = cnt[suit] + 1
        end
    end
    local best = "W"
    if cnt.T < cnt[best] then
        best = "T"
    end
    if cnt.S < cnt[best] then
        best = "S"
    end
    return best
end

function RuleSet.HasSuitInHand(hand, suit)
    if not suit then
        return false
    end
    for _, card in ipairs(hand or {}) do
        if RuleSet.CardSuit(card) == suit then
            return true
        end
    end
    return false
end

function RuleSet.CanDiscard(ruleId, hand, card, missingSuit)
    if not RuleSet.RequiresMissingSuit(ruleId) then
        return true
    end
    if not missingSuit or missingSuit == "" then
        return true
    end
    if not RuleSet.HasSuitInHand(hand, missingSuit) then
        return true
    end
    return RuleSet.CardSuit(card) == missingSuit
end

function RuleSet.IsMissingSuitCleared(ruleId, player)
    if not RuleSet.RequiresMissingSuit(ruleId) then
        return true
    end
    if not player or not player.missingSuit then
        return false
    end
    if RuleSet.HasSuitInHand(player.hand, player.missingSuit) then
        return false
    end
    for _, meld in ipairs(player.melds or {}) do
        for _, card in ipairs((meld and meld.tiles) or {}) do
            if RuleSet.CardSuit(card) == player.missingSuit then
                return false
            end
        end
    end
    return true
end

function RuleSet.HasIllegalHonors(ruleId, player, newTile)
    if RuleSet.AllowsHonors(ruleId) then
        return false
    end
    local function checkCard(card)
        return RuleSet.CardSuit(card) == "F"
    end
    if newTile and checkCard(newTile) then
        return true
    end
    for _, card in ipairs((player and player.hand) or {}) do
        if checkCard(card) then
            return true
        end
    end
    for _, meld in ipairs((player and player.melds) or {}) do
        for _, card in ipairs((meld and meld.tiles) or {}) do
            if checkCard(card) then
                return true
            end
        end
    end
    return false
end

function RuleSet.ShouldContinueAfterWin(ruleId)
    return RuleSet.IsBloodRiver(ruleId)
end

function RuleSet.FilterHandByRule(ruleId, hand)
    local def = RuleSet.GetRuleDef(ruleId)
    if def.allowHonors then
        return CopyArray(hand)
    end
    local out = {}
    for _, card in ipairs(hand) do
        if RuleSet.CardSuit(card) ~= "F" then
            out[#out + 1] = card
        end
    end
    return out
end

function RuleSet.BuildVisibleCountsByRule(ruleId, players)
    local counts = {}
    for _, p in ipairs(players or {}) do
        if p then
            for _, c in ipairs(p.hand or {}) do
                counts[c] = (counts[c] or 0) + 1
            end
            for _, c in ipairs(p.discards or {}) do
                if c ~= "0W" then
                    counts[c] = (counts[c] or 0) + 1
                end
            end
            for _, m in ipairs(p.melds or {}) do
                for _, c in ipairs((m and m.tiles) or {}) do
                    counts[c] = (counts[c] or 0) + 1
                end
            end
        end
    end
    if not RuleSet.AllowsHonors(ruleId) then
        for _, card in ipairs({ "1F", "2F", "3F", "4F", "5F", "6F", "7F" }) do
            counts[card] = nil
        end
    end
    return counts
end
