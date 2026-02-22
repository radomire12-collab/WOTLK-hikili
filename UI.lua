local addonName, addon = ...

if type(addon) ~= "table" then
    addon = _G[addonName] or {}
end
_G[addonName] = addon

local updateFrame
local root
local icons = {}
local elapsedSinceUpdate = 0
local updateInterval = 0.10
local forceUpdate = false
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local glowPulseTime = 0
local floor = math.floor
local min = math.min
local max = math.max
local MIN_QUEUE = 1
local MAX_QUEUE = 3

local function clampQueueLength(value)
    return floor(max(MIN_QUEUE, min(MAX_QUEUE, tonumber(value) or MIN_QUEUE)))
end

local function createIcon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)

    f.texture = f:CreateTexture(nil, "ARTWORK")
    f.texture:SetAllPoints(f)
    f.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.border:SetBlendMode("ADD")
    f.border:SetAlpha(0.65)
    f.border:SetPoint("TOPLEFT", -12, 12)
    f.border:SetPoint("BOTTOMRIGHT", 12, -12)
    f.border:Hide()

    f.glow = f:CreateTexture(nil, "OVERLAY")
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("TOPLEFT", -16, 16)
    f.glow:SetPoint("BOTTOMRIGHT", 16, -16)
    f.glow:SetVertexColor(1.00, 0.85, 0.20)
    f.glow:SetAlpha(0)
    f.glow:Hide()

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    if f.cd.SetReverse then
        f.cd:SetReverse(true)
    end

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0, 0, 0, 0.35)
    f:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.9)

    f:Hide()
    return f
end

local function ensureIconCount(count)
    for i = #icons + 1, count do
        icons[i] = createIcon(root, addon.db.iconSize)
    end
end

local function setMovableState()
    if not root then
        return
    end

    if addon.db.locked then
        root:EnableMouse(false)
        root:RegisterForDrag()
    else
        root:EnableMouse(true)
        root:RegisterForDrag("LeftButton")
    end
end

local function savePosition()
    if not root then
        return
    end
    local point, _, relPoint, x, y = root:GetPoint(1)
    addon.db.point = point
    addon.db.relPoint = relPoint
    addon.db.x = x
    addon.db.y = y
end

local function setCooldown(icon, spell)
    local spellName = addon:GetSpellName(spell)
    if not spellName then
        icon.cd:Hide()
        return
    end

    local start, duration, enabled = GetSpellCooldown(spellName)
    if start and duration and enabled == 1 and duration > 1.5 and start > 0 then
        CooldownFrame_SetTimer(icon.cd, start, duration, 1)
        icon.cd:Show()
    else
        icon.cd:Hide()
    end
end

local function updateIcon(icon, spell)
    if not spell then
        icon.texture:SetTexture(QUESTION_MARK)
        if icon.texture.SetDesaturated then
            icon.texture:SetDesaturated(true)
        end
        icon:SetAlpha(0.35)
        icon.cd:Hide()
        icon:Show()
        return
    end

    local tex = addon:GetSpellTexture(spell)
    if not tex then
        icon.texture:SetTexture(QUESTION_MARK)
        if icon.texture.SetDesaturated then
            icon.texture:SetDesaturated(true)
        end
        icon:SetAlpha(0.35)
        icon.cd:Hide()
        icon:Show()
        return
    end

    icon.texture:SetTexture(tex)
    if icon.texture.SetDesaturated then
        icon.texture:SetDesaturated(false)
    end
    icon:SetAlpha(1)
    setCooldown(icon, spell)
    icon:Show()
end

local function updateRecommendations()
    if not addon.db.enabled or not root then
        return
    end

    local queue, specKey = addon:RecommendQueue()
    local queueLength = clampQueueLength(addon.db.queueLength or 1)

    for i = 1, queueLength do
        local spell = queue and queue[i] or nil
        updateIcon(icons[i], spell)

        if i == 1 and spell then
            icons[i].border:Show()
            icons[i].glow:Show()
        else
            icons[i].border:Hide()
            icons[i].glow:Hide()
            icons[i]:SetAlpha(icons[i]:GetAlpha() * 0.8)
        end
    end

    for i = queueLength + 1, #icons do
        icons[i]:Hide()
        icons[i].glow:Hide()
    end

    -- unsupported specs keep frame at lower alpha for visual feedback
    if specKey == "fallback" then
        root:SetAlpha((addon.db.alpha or 1) * 0.65)
    else
        root:SetAlpha(addon.db.alpha or 1)
    end
end

function addon:ApplyPosition()
    if not root then
        return
    end
    root:ClearAllPoints()
    root:SetPoint(
        addon.db.point or "CENTER",
        UIParent,
        addon.db.relPoint or "CENTER",
        addon.db.x or 0,
        addon.db.y or 0
    )
end

function addon:RefreshLayout()
    if not root then
        return
    end

    local size = addon.db.iconSize or 52
    local spacing = addon.db.spacing or 6
    local queueLength = clampQueueLength(addon.db.queueLength or 1)

    addon.db.queueLength = queueLength
    ensureIconCount(queueLength)

    root:SetScale(addon.db.scale or 1)
    root:SetAlpha(addon.db.alpha or 1)
    root:SetSize((size * queueLength) + (spacing * (queueLength - 1)), size)

    for i = 1, queueLength do
        local icon = icons[i]
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        if i == 1 then
            icon:SetPoint("LEFT", root, "LEFT", 0, 0)
        else
            icon:SetPoint("LEFT", icons[i - 1], "RIGHT", spacing, 0)
        end
    end

    for i = queueLength + 1, #icons do
        icons[i]:Hide()
    end
end

function addon:RequestImmediateUpdate()
    forceUpdate = true
end

local function parseSlash(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    if not cmd then
        return "", ""
    end
    return string.lower(cmd), rest
end

local function help()
    addon:Print("Commands:")
    addon:Print("/hikili lock | unlock")
    addon:Print("/hikili show | hide | toggle")
    addon:Print("/hikili scale <0.5-2>")
    addon:Print("/hikili alpha <0.2-1>")
    addon:Print("/hikili size <30-96>")
    addon:Print("/hikili spacing <0-20>")
    addon:Print("/hikili queue <1-3>")
    addon:Print("/hikili rescan")
    addon:Print("/hikili reset")
    addon:Print("/hikili debug")
end

local function formatRemaining(remains)
    if not remains or remains <= 0 then
        return "0.0"
    end
    if remains >= 9000 then
        return "up"
    end
    return string.format("%.1f", remains)
end

function addon:InitializeUI()
    root = CreateFrame("Frame", "HikiliFrame", UIParent)
    root:SetClampedToScreen(true)
    root:SetMovable(true)
    root:SetUserPlaced(true)
    root:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    root:SetBackdropColor(0, 0, 0, 0.20)
    root:SetBackdropBorderColor(0.20, 0.20, 0.20, 0.65)
    root:SetScript("OnDragStart", function(self)
        if addon.db.locked then
            return
        end
        self:StartMoving()
    end)
    root:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)

    addon.db.queueLength = clampQueueLength(addon.db.queueLength or 1)
    ensureIconCount(addon.db.queueLength)

    self:ApplyPosition()
    self:RefreshLayout()
    setMovableState()

    updateFrame = CreateFrame("Frame")
    updateFrame:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceUpdate = elapsedSinceUpdate + elapsed
        glowPulseTime = glowPulseTime + elapsed

        if forceUpdate or elapsedSinceUpdate >= updateInterval then
            forceUpdate = false
            elapsedSinceUpdate = 0
            updateRecommendations()
        end

        local icon = icons[1]
        if icon and icon.glow and icon.glow:IsShown() then
            local alpha = 0.45 + (0.35 * math.abs(math.sin(glowPulseTime * 4.5)))
            icon.glow:SetAlpha(alpha)
        end
    end)

    SLASH_HIKILI1 = "/hikili"
    SLASH_HIKILI2 = "/hk"
    SlashCmdList.HIKILI = function(msg)
        local cmd, rest = parseSlash(msg or "")
        if cmd == "" then
            help()
            return
        end

        if cmd == "lock" then
            addon.db.locked = true
            setMovableState()
            addon:Print("Frame locked.")
        elseif cmd == "unlock" then
            addon.db.locked = false
            setMovableState()
            addon:Print("Frame unlocked.")
        elseif cmd == "show" then
            addon.db.enabled = true
            root:Show()
            addon:Print("Enabled.")
        elseif cmd == "hide" then
            addon.db.enabled = false
            root:Hide()
            addon:Print("Hidden.")
        elseif cmd == "toggle" then
            addon.db.enabled = not addon.db.enabled
            if addon.db.enabled then
                root:Show()
                addon:Print("Enabled.")
            else
                root:Hide()
                addon:Print("Hidden.")
            end
        elseif cmd == "scale" then
            local n = tonumber(rest)
            if n then
                addon:ApplySetting("scale", n)
                addon:Print("Scale set to " .. string.format("%.2f", addon.db.scale))
            else
                addon:Print("Usage: /hikili scale 1.2")
            end
        elseif cmd == "alpha" then
            local n = tonumber(rest)
            if n then
                addon:ApplySetting("alpha", n)
                addon:Print("Alpha set to " .. string.format("%.2f", addon.db.alpha))
            else
                addon:Print("Usage: /hikili alpha 0.9")
            end
        elseif cmd == "size" then
            local n = tonumber(rest)
            if n then
                addon:ApplySetting("iconSize", n)
                addon:Print("Icon size set to " .. addon.db.iconSize)
            else
                addon:Print("Usage: /hikili size 56")
            end
        elseif cmd == "spacing" then
            local n = tonumber(rest)
            if n then
                addon:ApplySetting("spacing", n)
                addon:Print("Spacing set to " .. addon.db.spacing)
            else
                addon:Print("Usage: /hikili spacing 6")
            end
        elseif cmd == "queue" then
            local n = tonumber(rest)
            if n then
                addon:ApplySetting("queueLength", n)
                if addon.db.queueLength == 1 then
                    addon:Print("Queue set to 1 (next action only).")
                else
                    addon:Print("Queue set to " .. addon.db.queueLength .. " (next + preview).")
                end
            else
                addon:Print("Usage: /hikili queue 1")
            end
        elseif cmd == "rescan" then
            if addon.RefreshKnownSpells then
                addon:RefreshKnownSpells()
            end
            if addon.RefreshGlyphs then
                addon:RefreshGlyphs()
            end
            addon:Print("Spellbook rescanned. knownCount=" .. tostring(addon.knownSpellCount or 0))
            if addon.HasGlyphLike then
                addon:Print("Glyph Life Tap detected=" .. tostring(addon:HasGlyphLike("life tap")))
            end
        elseif cmd == "reset" then
            addon:ResetPosition()
            addon:Print("Position reset.")
        elseif cmd == "debug" then
            local state = addon:BuildState()
            local queue, key = addon:GetPriorityQueue(state)
            local handler = addon.Priorities and state.specKey and addon.Priorities[state.specKey]
            local s1 = queue and queue[1] and addon:GetSpellName(queue[1]) or "-"
            local s2 = queue and queue[2] and addon:GetSpellName(queue[2]) or "-"
            local s3 = queue and queue[3] and addon:GetSpellName(queue[3]) or "-"
            local k1 = queue and queue[1] and addon:IsSpellKnownLocal(queue[1]) or false
            local k2 = queue and queue[2] and addon:IsSpellKnownLocal(queue[2]) or false
            local k3 = queue and queue[3] and addon:IsSpellKnownLocal(queue[3]) or false
            addon:Print("enabled=" .. tostring(addon.db.enabled) .. ", locked=" .. tostring(addon.db.locked))
            addon:Print("spec=" .. tostring(state.specKey) .. ", handler=" .. tostring(handler ~= nil) .. ", profile=" .. tostring(key) .. ", queue=" .. tostring(queue and #queue or 0))
            addon:Print("queueLength=" .. tostring(addon.db.queueLength))
            addon:Print("target exists=" .. tostring(state.targetExists) .. " dead=" .. tostring(state.targetDead) .. " attackable=" .. tostring(state.targetAttackable))
            addon:Print("next=" .. tostring(s1) .. " | " .. tostring(s2) .. " | " .. tostring(s3))
            addon:Print("known=" .. tostring(k1) .. " | " .. tostring(k2) .. " | " .. tostring(k3))
            addon:Print("knownCount=" .. tostring(addon.knownSpellCount or 0))
            local hasSBN = type(GetSpellBookItemName) == "function"
            local hasGSN = type(GetSpellName) == "function"
            local hasSBI = type(GetSpellBookItemInfo) == "function"
            local sample = "-"
            if hasSBN then
                sample = tostring(GetSpellBookItemName(1, BOOKTYPE_SPELL or "spell") or "-")
            elseif hasGSN then
                sample = tostring(GetSpellName(1, BOOKTYPE_SPELL or "spell") or "-")
            end
            addon:Print("api sbn=" .. tostring(hasSBN) .. " gsn=" .. tostring(hasGSN) .. " sbi=" .. tostring(hasSBI) .. " sample1=" .. tostring(sample))
            if state.specKey and string.find(state.specKey, "WARLOCK:", 1, true) == 1 then
                local corr = addon:DebuffRemaining("target", "Corruption", true)
                local ua = addon:DebuffRemaining("target", "Unstable Affliction", true)
                local haunt = addon:DebuffRemaining("target", "Haunt", true)
                local kc = addon:IsSpellKnownLocal("Corruption")
                local kua = addon:IsSpellKnownLocal("Unstable Affliction")
                local kh = addon:IsSpellKnownLocal("Haunt")
                local u1, m1 = IsUsableSpell("Corruption")
                local u2, m2 = IsUsableSpell("Unstable Affliction")
                local lifeTapBuff = addon:BuffRemaining("player", "Life Tap")
                local hasGlyphLT = addon.HasGlyphLike and addon:HasGlyphLike("life tap")
                local tl = UnitLevel("target")
                local tc = UnitClassification and UnitClassification("target") or "-"
                addon:Print("dots corr=" .. formatRemaining(corr) .. " ua=" .. formatRemaining(ua) .. " haunt=" .. formatRemaining(haunt))
                addon:Print("known dots corr=" .. tostring(kc) .. " ua=" .. tostring(kua) .. " haunt=" .. tostring(kh))
                addon:Print("usable corr=" .. tostring(u1) .. "/" .. tostring(m1) .. " ua=" .. tostring(u2) .. "/" .. tostring(m2))
                addon:Print("glyphLT=" .. tostring(hasGlyphLT) .. " lifeTapBuff=" .. formatRemaining(lifeTapBuff))
                addon:Print("target lvl=" .. tostring(tl) .. " classif=" .. tostring(tc))
            end
            addon:Print("frameShown=" .. tostring(root:IsShown()) .. ", point=" .. tostring(addon.db.point) .. " x=" .. tostring(addon.db.x) .. " y=" .. tostring(addon.db.y))
        else
            help()
        end

        addon:RequestImmediateUpdate()
    end

    if not addon.db.enabled then
        root:Hide()
    end

    addon:RequestImmediateUpdate()
end
