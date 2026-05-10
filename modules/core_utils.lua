local _, NS = ...
if type(NS) ~= "table" then
    NS = _G.MaJiangNS or {}
    _G.MaJiangNS = NS
end

local Core = NS.Core or {}
NS.Core = Core

function Core.CloneTable(t)
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            out[k] = Core.CloneTable(v)
        else
            out[k] = v
        end
    end
    return out
end

function Core.MergeDefaults(dst, defs)
    for k, v in pairs(defs) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            Core.MergeDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function Core.Split(str, sep)
    local out = {}
    if str == nil or str == "" then
        return out
    end
    sep = sep or ","
    local pattern = "([^" .. sep .. "]+)"
    for s in string.gmatch(str, pattern) do
        out[#out + 1] = s
    end
    return out
end

function Core.Join(list, sep)
    return table.concat(list, sep or ",")
end

function Core.RemoveByValue(list, value, count)
    local removed = 0
    count = count or 1
    for i = #list, 1, -1 do
        if list[i] == value then
            table.remove(list, i)
            removed = removed + 1
            if removed >= count then
                break
            end
        end
    end
    return removed
end

function Core.CountMap(list)
    local m = {}
    for _, v in ipairs(list) do
        m[v] = (m[v] or 0) + 1
    end
    return m
end

function Core.CopyArray(list)
    local out = {}
    for i = 1, #list do
        out[i] = list[i]
    end
    return out
end

function Core.TileSuitAndValue(card)
    if type(card) ~= "string" or #card < 2 then
        return nil, nil
    end
    return card:sub(2, 2), tonumber(card:sub(1, 1))
end

function Core.TileLess(a, b)
    local order = { W = 1, T = 2, S = 3, F = 4 }
    local sa, va = Core.TileSuitAndValue(a)
    local sb, vb = Core.TileSuitAndValue(b)
    if sa ~= sb then
        return (order[sa] or 99) < (order[sb] or 99)
    end
    return (va or 0) < (vb or 0)
end

function Core.SortHand(hand, keepLastDraw)
    local lastTile
    if keepLastDraw and #hand % 3 == 2 then
        lastTile = table.remove(hand)
    end
    table.sort(hand, Core.TileLess)
    if lastTile then
        table.insert(hand, lastTile)
    end
end

function Core.BuildDeck()
    local deck = {}
    for _, suit in ipairs({ "W", "T", "S" }) do
        for value = 1, 9 do
            for _ = 1, 4 do
                deck[#deck + 1] = tostring(value) .. suit
            end
        end
    end
    for value = 1, 7 do
        for _ = 1, 4 do
            deck[#deck + 1] = tostring(value) .. "F"
        end
    end
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end

function Core.CardToImageKey(card)
    local suit, value = Core.TileSuitAndValue(card)
    if not suit or not value then
        return nil
    end
    if suit == "W" then
        return tostring(value)
    elseif suit == "T" then
        return tostring(10 + value)
    elseif suit == "S" then
        return tostring(20 + value)
    else
        return tostring(30 + value)
    end
end

function Core.CardToVoiceIndex(card)
    local suit, value = Core.TileSuitAndValue(card)
    if not suit or not value then
        return nil
    end
    if suit == "T" then
        return value - 1
    elseif suit == "S" then
        return 8 + value
    elseif suit == "W" then
        return 17 + value
    else
        return 26 + value
    end
end
