local _, NS = ...
if type(NS) ~= "table" then
    NS = _G.MaJiangNS or {}
    _G.MaJiangNS = NS
end

local I18N = NS.I18N or {}
NS.I18N = I18N

I18N.tables = I18N.tables or {}
I18N.currentLocale = I18N.currentLocale or "zhCN"

local function NormalizeLocale(locale)
    if locale == "zhCN" then
        return "zhCN"
    end
    return "enUS"
end

function I18N.AddLocale(locale, dict)
    if type(locale) ~= "string" or type(dict) ~= "table" then
        return
    end
    I18N.tables[locale] = dict
end

function I18N.GetGameLocale()
    if type(GetLocale) == "function" then
        local ok, wowLocale = pcall(GetLocale)
        if ok and type(wowLocale) == "string" and wowLocale ~= "" then
            return NormalizeLocale(wowLocale)
        end
    end
    return "zhCN"
end

function I18N.RefreshLocale()
    I18N.currentLocale = I18N.GetGameLocale()
    return I18N.currentLocale
end

local function GetCurrentTable()
    local locale = I18N.currentLocale or I18N.RefreshLocale()
    return I18N.tables[locale] or I18N.tables.zhCN or {}
end

function I18N.Get(key)
    local current = GetCurrentTable()
    local value = current[key]
    if value ~= nil then
        return value
    end
    local zh = I18N.tables.zhCN or {}
    if zh[key] ~= nil then
        return zh[key]
    end
    return key
end

function I18N.T(key, ...)
    local template = I18N.Get(key)
    if select("#", ...) <= 0 then
        return template
    end
    local ok, out = pcall(string.format, template, ...)
    if ok then
        return out
    end
    return template
end

I18N.RefreshLocale()
