local ADDON_NAME, NS = ...
ADDON_NAME = ADDON_NAME or "MaJiang"
if type(NS) ~= "table" then
    NS = _G.MaJiangNS or {}
    _G.MaJiangNS = NS
end

local UIUtilsModule = {}

function UIUtilsModule.New(env)
    assert(type(env) == "table", "UIUtilsModule.New requires env table")

    local UI = assert(env.UI, "UIUtilsModule.New missing env.UI")
    local T = assert(env.T, "UIUtilsModule.New missing env.T")
    local NormalizeRuleId = assert(env.NormalizeRuleId, "UIUtilsModule.New missing env.NormalizeRuleId")
    local GetRuleOptions = assert(env.GetRuleOptions, "UIUtilsModule.New missing env.GetRuleOptions")
    local GetRuleName = assert(env.GetRuleName, "UIUtilsModule.New missing env.GetRuleName")
    local CardToImageKey = assert(env.CardToImageKey, "UIUtilsModule.New missing env.CardToImageKey")
    local IMG_ROOT = assert(env.IMG_ROOT, "UIUtilsModule.New missing env.IMG_ROOT")

    local function CloseAllRuleSelectorLists(except)
        if not UI.RuleSelectors then
            return
        end
        for _, selector in ipairs(UI.RuleSelectors) do
            if selector ~= except and selector.ListFrame then
                selector.ListFrame:Hide()
            end
        end
    end

    local function CreateRuleListSelector(parent, width, textKey, initialRuleId, onRulePicked, canOpen)
        local selector = {
            textKey = textKey,
            ruleId = NormalizeRuleId(initialRuleId),
            options = GetRuleOptions(),
        }
        UI.RuleSelectors = UI.RuleSelectors or {}
        UI.RuleSelectors[#UI.RuleSelectors + 1] = selector

        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetSize(width, 28)
        selector.Btn = btn

        local listFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        listFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        listFrame:SetBackdropColor(0, 0, 0, 0.92)
        listFrame:SetBackdropBorderColor(0.86, 0.74, 0.28, 0.95)
        listFrame:SetFrameStrata("TOOLTIP")
        listFrame:SetFrameLevel((parent:GetFrameLevel() or 1) + 32)
        listFrame:SetSize(width + 32, 246)
        listFrame:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        listFrame:Hide()
        selector.ListFrame = listFrame

        local scroll = CreateFrame("ScrollFrame", nil, listFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 8, -8)
        scroll:SetPoint("BOTTOMRIGHT", -28, 8)
        selector.Scroll = scroll

        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(width, 1)
        scroll:SetScrollChild(content)
        selector.Content = content

        local optionButtons = {}
        selector.OptionButtons = optionButtons

        local function RefreshOptionStyles()
            for _, item in ipairs(optionButtons) do
                if item.id == selector.ruleId then
                    item.btn:SetAlpha(1)
                else
                    item.btn:SetAlpha(0.72)
                end
            end
        end

        local function RefreshButtonText()
            btn:SetText(T(selector.textKey, GetRuleName(selector.ruleId)))
            RefreshOptionStyles()
        end

        selector.SetRule = function(newRuleId, silent)
            local normalized = NormalizeRuleId(newRuleId)
            selector.ruleId = normalized
            RefreshButtonText()
            if not silent and onRulePicked then
                onRulePicked(normalized)
            end
        end

        for i, opt in ipairs(selector.options) do
            local row = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            row:SetSize(width - 6, 22)
            row:SetPoint("TOPLEFT", 2, -((i - 1) * 24))
            row:SetText(GetRuleName(opt.id))
            row:SetScript("OnClick", function()
                selector.SetRule(opt.id, false)
                listFrame:Hide()
            end)
            optionButtons[#optionButtons + 1] = {
                id = opt.id,
                btn = row,
            }
        end
        content:SetHeight(#selector.options * 24)

        btn:SetScript("OnClick", function()
            if canOpen and not canOpen() then
                return
            end
            local showing = listFrame:IsShown()
            CloseAllRuleSelectorLists(selector)
            if showing then
                listFrame:Hide()
                return
            end
            listFrame:Show()
            RefreshOptionStyles()
        end)

        RefreshButtonText()
        return selector
    end

    local function CreateTileFrame(parent, w, h, card, hidden, highlight, highlightColor, hiddenBackTexture, tileRoot)
        local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        frame:SetSize(w, h)
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = highlight and 2 or 1,
        })
        frame:SetBackdropColor(1, 1, 1, 1)
        frame:SetBackdropBorderColor(unpack(highlight and (highlightColor or { 1, 0.82, 0, 1 }) or { 0, 0, 0, 1 }))
        local tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        if hidden then
            tex:SetTexture(hiddenBackTexture or (IMG_ROOT .. "ce_an.png"))
        else
            local key = CardToImageKey(card)
            if key then
                tex:SetTexture((tileRoot or IMG_ROOT) .. key .. ".png")
            else
                tex:SetColorTexture(0.2, 0.2, 0.2, 1)
            end
        end
        frame.Texture = tex
        return frame
    end

    local function ClearChildren(frame)
        for _, child in ipairs({ frame:GetChildren() }) do
            child:Hide()
        end
    end

    return {
        CloseAllRuleSelectorLists = CloseAllRuleSelectorLists,
        CreateRuleListSelector = CreateRuleListSelector,
        CreateTileFrame = CreateTileFrame,
        ClearChildren = ClearChildren,
    }
end

NS.AddonUIUtils = UIUtilsModule

