local addonName, addon = ...

if type(addon) ~= "table" then
    addon = _G[addonName] or {}
end
_G[addonName] = addon

local max = math.max
local floor = math.floor
local UnitPowerSafe = UnitPower or UnitMana
local UnitPowerMaxSafe = UnitPowerMax or UnitManaMax
local BOOKTYPE_SPELL_SAFE = BOOKTYPE_SPELL or "spell"

local defaults = {
    enabled = true,
    locked = false,
    scale = 1,
    alpha = 1,
    iconSize = 52,
    spacing = 6,
    point = "CENTER",
    relPoint = "CENTER",
    x = 0,
    y = -120,
    queueLength = 1, -- next-action mode by default
    dbVersion = 2,
}

addon.state = {}
addon.knownSpellsByName = addon.knownSpellsByName or {}
addon.knownSpellsByID = addon.knownSpellsByID or {}
addon.knownSpellCount = addon.knownSpellCount or 0
addon.glyphNames = addon.glyphNames or {}

local function copyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            copyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function clamp(value, low, high)
    if value < low then
        return low
    end
    if value > high then
        return high
    end
    return value
end

local function safeNumber(v)
    if not v then
        return 0
    end
    return v
end

local function normalizeSpellKey(name)
    if type(name) ~= "string" then
        return nil
    end
    -- Strip rank suffix variants and normalize for matching.
    local clean = string.gsub(name, "%s*%b()", "")
    clean = string.gsub(clean, "%s+", " ")
    clean = string.lower(clean)
    return clean
end

function addon:GetSpellName(spell)
    if type(spell) == "number" then
        return GetSpellInfo(spell)
    end
    return spell
end

function addon:GetSpellTexture(spell)
    if type(spell) == "number" then
        return select(3, GetSpellInfo(spell))
    end
    local _, _, icon = GetSpellInfo(spell)
    return icon
end

function addon:RefreshGlyphs()
    local names = {}

    if GetGlyphSocketInfo and GetSpellInfo then
        for slot = 1, 6 do
            local a, b, c, d, e, f, g, h = GetGlyphSocketInfo(slot)
            local values = { a, b, c, d, e, f, g, h }
            for _, value in ipairs(values) do
                if type(value) == "number" and value > 0 then
                    local n = GetSpellInfo(value)
                    if n then
                        names[string.lower(n)] = true
                    end
                end
            end
        end
    end

    self.glyphNames = names
end

function addon:HasGlyphLike(text)
    if type(text) ~= "string" or text == "" then
        return false
    end
    local needle = string.lower(text)
    for glyphName in pairs(self.glyphNames or {}) do
        if string.find(glyphName, needle, 1, true) then
            return true
        end
    end
    return false
end

function addon:RefreshKnownSpells()
    local byName = {}
    local byID = {}
    local count = 0
    local hasSpellBookNameAPI = (type(GetSpellBookItemName) == "function") or (type(GetSpellName) == "function")
    local hasSpellBookInfoAPI = (type(GetSpellBookItemInfo) == "function")

    local function getSpellbookName(slot)
        if type(GetSpellBookItemName) == "function" then
            local n = GetSpellBookItemName(slot, BOOKTYPE_SPELL_SAFE)
            if n and n ~= "" then
                return n
            end
        end
        if type(GetSpellName) == "function" then
            local n = GetSpellName(slot, BOOKTYPE_SPELL_SAFE)
            if n and n ~= "" then
                return n
            end
        end
        return nil
    end

    local function getSpellbookInfo(slot)
        if hasSpellBookInfoAPI then
            return GetSpellBookItemInfo(slot, BOOKTYPE_SPELL_SAFE)
        end
        return nil, nil
    end

    local function addKnown(spellName, spellID)
        if not spellName or spellName == "" then
            return
        end
        if not byName[spellName] then
            count = count + 1
        end
        byName[spellName] = true
        local norm = normalizeSpellKey(spellName)
        if norm then
            byName[norm] = true
        end
        if spellID and type(spellID) == "number" and spellID > 0 then
            byID[spellID] = true
        end
    end

    if GetNumSpellTabs and GetSpellTabInfo and hasSpellBookNameAPI then
        local tabs = GetNumSpellTabs() or 0
        for tab = 1, tabs do
            local _, _, offset, numSlots = GetSpellTabInfo(tab)
            offset = offset or 0
            numSlots = numSlots or 0

            for slot = offset + 1, offset + numSlots do
                local spellType, spellID = getSpellbookInfo(slot)
                local spellName = getSpellbookName(slot)
                if spellName and spellName ~= "" and spellType ~= "FUTURESPELL" and spellType ~= "FLYOUT" then
                    addKnown(spellName, spellID)
                end
            end
        end
    end

    -- Fallback scan for private cores where tab metadata is broken.
    if count == 0 and hasSpellBookNameAPI then
        local empty = 0
        for slot = 1, 512 do
            local spellType, spellID = getSpellbookInfo(slot)
            local spellName = getSpellbookName(slot)
            if spellName and spellName ~= "" and spellType ~= "FUTURESPELL" and spellType ~= "FLYOUT" then
                addKnown(spellName, spellID)
                empty = 0
            else
                empty = empty + 1
                if empty >= 80 then
                    break
                end
            end
        end
    end

    self.knownSpellsByName = byName
    self.knownSpellsByID = byID
    self.knownSpellCount = count
end

function addon:IsSpellKnownLocal(spell)
    if type(spell) == "number" and spell == 6603 then
        return true
    end

    local spellName = self:GetSpellName(spell)
    if not spellName then
        return false
    end

    local spellID = type(spell) == "number" and spell or select(7, GetSpellInfo(spellName))
    if type(spellID) ~= "number" then
        spellID = nil
    end

    if IsSpellKnown and spellID and spellID > 0 then
        local ok, known = pcall(IsSpellKnown, spellID)
        if ok and known then
            return true
        end
    end
    if IsPlayerSpell and spellID and spellID > 0 then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and known then
            return true
        end
    end

    if (self.knownSpellCount or 0) > 0 then
        if self.knownSpellsByName and self.knownSpellsByName[spellName] then
            return true
        end
        local norm = normalizeSpellKey(spellName)
        if norm and self.knownSpellsByName and self.knownSpellsByName[norm] then
            return true
        end
        if self.knownSpellsByID and spellID and self.knownSpellsByID[spellID] then
            return true
        end
        return false
    end

    -- If spellbook scan is unavailable on this core, use weak heuristics.
    local usable, noMana = IsUsableSpell(spellName)
    if usable or noMana then
        return true
    end
    return false
end

function addon:SpellCooldownRemaining(spell)
    local spellName = self:GetSpellName(spell)
    if not spellName then
        return math.huge
    end

    local start, duration, enabled = GetSpellCooldown(spellName)
    if not start or not duration or enabled == 0 then
        return math.huge
    end
    if start == 0 then
        return 0
    end

    return max(0, (start + duration) - GetTime())
end

function addon:GCDRemaining()
    local start, duration = GetSpellCooldown(61304) -- global cooldown spell
    if not start or not duration or start == 0 then
        return 0
    end
    return max(0, (start + duration) - GetTime())
end

function addon:IsSpellUsable(spell)
    local spellName = self:GetSpellName(spell)
    if not spellName then
        return false
    end
    if not self:IsSpellKnownLocal(spell) then
        return false
    end
    local usable, noMana = IsUsableSpell(spellName)
    return usable == true or usable == 1 or noMana == true or noMana == 1
end

function addon:IsSpellInRange(spell, unit)
    unit = unit or "target"
    local spellName = self:GetSpellName(spell)
    if not spellName then
        return false
    end
    local inRange = IsSpellInRange(spellName, unit)
    if inRange == nil then
        return true
    end
    return inRange == 1
end

local function auraRemaining(duration, expirationTime)
    if expirationTime and expirationTime > 0 then
        return max(0, expirationTime - GetTime())
    end
    if duration and duration > 0 then
        return duration
    end
    -- Some 3.3.5/private cores do not expose duration/expiration for target auras.
    -- If the aura exists but has no timer data, treat it as active.
    return 9999
end

local function isMine(caster)
    return caster == "player" or caster == "pet" or caster == "vehicle"
end

function addon:FindAura(unit, spell, helpful, mineOnly)
    local auraFunc = helpful and UnitBuff or UnitDebuff
    local spellName = self:GetSpellName(spell)
    if not spellName then
        return false, 0, 0
    end

    -- Fast path: query by aura name when supported.
    do
        local name, _, _, count, _, duration, expirationTime, caster = auraFunc(unit, spellName)
        if name == spellName then
            if not mineOnly or isMine(caster) then
                return true, auraRemaining(duration, expirationTime), count or 0, caster
            end
        end
    end

    local i = 1
    while true do
        local name, _, _, count, _, duration, expirationTime, caster = auraFunc(unit, i)
        if not name then
            break
        end

        if name == spellName then
            if not mineOnly or isMine(caster) then
                return true, auraRemaining(duration, expirationTime), count or 0, caster
            end
        end

        i = i + 1
    end

    return false, 0, 0
end

function addon:BuffRemaining(unit, spell, mineOnly)
    local found, remaining = self:FindAura(unit, spell, true, mineOnly)
    if not found then
        return 0
    end
    return remaining
end

function addon:DebuffRemaining(unit, spell, mineOnly)
    if mineOnly == nil then
        mineOnly = true
    end
    local found, remaining = self:FindAura(unit, spell, false, mineOnly)
    if not found then
        return 0
    end
    return remaining
end

function addon:CountRunes()
    local ready = {
        blood = 0,
        frost = 0,
        unholy = 0,
        death = 0,
    }

    if not GetRuneType or not GetRuneCooldown then
        return ready
    end

    for i = 1, 6 do
        local _, _, runeReady = GetRuneCooldown(i)
        if runeReady then
            local runeType = GetRuneType(i)
            if runeType == 1 then
                ready.blood = ready.blood + 1
            elseif runeType == 2 then
                ready.unholy = ready.unholy + 1
            elseif runeType == 3 then
                ready.frost = ready.frost + 1
            elseif runeType == 4 then
                ready.death = ready.death + 1
            end
        end
    end

    return ready
end

function addon:HasRuneCost(runes, cost)
    local death = runes.death or 0
    local kinds = { "blood", "frost", "unholy" }

    for _, kind in ipairs(kinds) do
        local need = safeNumber(cost[kind])
        local have = safeNumber(runes[kind])
        if have < need then
            death = death - (need - have)
            if death < 0 then
                return false
            end
        end
    end

    return true
end

function addon:GetActiveSpec()
    local classTag = select(2, UnitClass("player"))
    local bestTab, bestPoints = 1, -1

    local tabs = GetNumTalentTabs and GetNumTalentTabs() or 0
    for tab = 1, tabs do
        local _, _, points = GetTalentTabInfo(tab)
        points = points or 0
        if points > bestPoints then
            bestPoints = points
            bestTab = tab
        end
    end

    return classTag, bestTab, bestPoints
end

function addon:GetSpecKey()
    local classTag, tab = self:GetActiveSpec()
    if not classTag then
        return nil
    end
    return classTag .. ":" .. tostring(tab)
end

function addon:BuildState()
    local s = self.state
    local now = GetTime()

    local targetExists = UnitExists("target") and not UnitIsDead("target")
    local canAttack = targetExists and not not UnitCanAttack("player", "target")
    local playerClass = select(2, UnitClass("player"))

    local hp = UnitHealth("player")
    local hpMax = UnitHealthMax("player")
    local targetHP = targetExists and UnitHealth("target") or 0
    local targetHPMax = targetExists and UnitHealthMax("target") or 1

    s.time = now
    s.class = playerClass
    s.specKey = self:GetSpecKey()
    s.gcd = self:GCDRemaining()
    s.targetExists = targetExists
    s.targetAttackable = canAttack
    s.targetDead = targetExists and UnitIsDead("target") or false
    s.playerHealth = hp
    s.playerHealthPct = hpMax > 0 and (hp / hpMax) * 100 or 100
    s.targetHealth = targetHP
    s.targetHealthPct = targetHPMax > 0 and (targetHP / targetHPMax) * 100 or 100
    s.comboPoints = GetComboPoints and GetComboPoints("player", "target") or 0
    s.moving = (GetUnitSpeed and GetUnitSpeed("player") or 0) > 0
    s.inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false

    s.mana = UnitPowerSafe("player", 0)
    s.manaMax = UnitPowerMaxSafe("player", 0)
    s.manaPct = s.manaMax > 0 and (s.mana / s.manaMax) * 100 or 0
    s.rage = UnitPowerSafe("player", 1)
    s.focus = UnitPowerSafe("player", 2)
    s.energy = UnitPowerSafe("player", 3)
    s.runicPower = UnitPowerSafe("player", 6)
    s.runes = self:CountRunes()

    return s
end

function addon:RecommendQueue()
    local state = self:BuildState()
    return self:GetPriorityQueue(state)
end

function addon:ApplySetting(name, value)
    if name == "scale" then
        self.db.scale = clamp(value, 0.5, 2)
    elseif name == "alpha" then
        self.db.alpha = clamp(value, 0.2, 1)
    elseif name == "iconSize" then
        self.db.iconSize = floor(clamp(value, 30, 96))
    elseif name == "spacing" then
        self.db.spacing = floor(clamp(value, 0, 20))
    elseif name == "queueLength" then
        self.db.queueLength = floor(clamp(value, 1, 3))
    end

    if self.RefreshLayout then
        self:RefreshLayout()
    end
end

function addon:ResetPosition()
    self.db.point = defaults.point
    self.db.relPoint = defaults.relPoint
    self.db.x = defaults.x
    self.db.y = defaults.y

    if self.ApplyPosition then
        self:ApplyPosition()
    end
end

function addon:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF88CCFFHikili|r: " .. tostring(msg))
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("LEARNED_SPELL_IN_TAB")
eventFrame:RegisterEvent("GLYPH_ADDED")
eventFrame:RegisterEvent("GLYPH_REMOVED")
eventFrame:RegisterEvent("GLYPH_UPDATED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName ~= addonName then
            return
        end

        HikiliDB = HikiliDB or {}
        local oldVersion = HikiliDB.dbVersion or 0
        copyDefaults(HikiliDB, defaults)

        if oldVersion < 2 then
            if HikiliDB.queueLength == nil or tonumber(HikiliDB.queueLength) == 3 then
                HikiliDB.queueLength = 1
            end
            HikiliDB.dbVersion = 2
        end

        HikiliDB.queueLength = floor(clamp(tonumber(HikiliDB.queueLength) or 1, 1, 3))
        HikiliDB.scale = clamp(tonumber(HikiliDB.scale) or 1, 0.5, 2)
        HikiliDB.alpha = clamp(tonumber(HikiliDB.alpha) or 1, 0.2, 1)
        HikiliDB.iconSize = floor(clamp(tonumber(HikiliDB.iconSize) or 52, 30, 96))
        HikiliDB.spacing = floor(clamp(tonumber(HikiliDB.spacing) or 6, 0, 20))

        addon.db = HikiliDB
    elseif event == "PLAYER_LOGIN" then
        addon:RefreshKnownSpells()
        addon:RefreshGlyphs()
        addon:InitializeUI()
        addon:Print("Loaded for WoTLK 3.3.5a.")
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "GLYPH_ADDED" or event == "GLYPH_REMOVED" or event == "GLYPH_UPDATED" or event == "PLAYER_TALENT_UPDATE" or event == "CHARACTER_POINTS_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        addon:RefreshKnownSpells()
        addon:RefreshGlyphs()
        if addon.RequestImmediateUpdate then
            addon:RequestImmediateUpdate()
        end
    end
end)
