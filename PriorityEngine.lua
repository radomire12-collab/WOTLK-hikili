local addonName, addon = ...

if type(addon) ~= "table" then
    addon = _G[addonName] or {}
end
_G[addonName] = addon

addon.Priorities = addon.Priorities or {}

local function hasTarget(state)
    return state.targetExists and state.targetAttackable and not state.targetDead
end

local function canCast(state, spell, opts)
    opts = opts or {}

    if not addon:GetSpellName(spell) then
        return false
    end
    if addon.IsSpellKnownLocal and not addon:IsSpellKnownLocal(spell) then
        return false
    end
    if opts.requireTarget and not hasTarget(state) then
        return false
    end
    if not opts.skipUsable and not addon:IsSpellUsable(spell) then
        return false
    end
    if opts.requireTarget and not opts.skipRange and not addon:IsSpellInRange(spell, "target") then
        return false
    end

    local cd = addon:SpellCooldownRemaining(spell)
    if cd > (state.gcd + (opts.cooldownLeeway or 0.1)) then
        return false
    end

    return true
end

local function push(queue, used, spell)
    if not spell or used[spell] then
        return
    end
    if addon.IsSpellKnownLocal and not addon:IsSpellKnownLocal(spell) then
        return
    end
    used[spell] = true
    queue[#queue + 1] = spell
end

local function pushIf(queue, used, state, spell, opts)
    if canCast(state, spell, opts) then
        push(queue, used, spell)
    end
end

local function makeQueue()
    return {}, {}
end

local function buff(spell)
    return addon:BuffRemaining("player", spell)
end

local function debuff(state, spell)
    if not hasTarget(state) then
        return 0
    end
    return addon:DebuffRemaining("target", spell)
end

local function choosePaladinJudgement(state)
    local list = { "Judgement of Wisdom", "Judgement of Light", "Judgement of Justice" }
    for _, spell in ipairs(list) do
        if canCast(state, spell, { requireTarget = true }) then
            return spell
        end
    end
    return nil
end

local function choosePaladinSeal(state, preferWisdom)
    if buff("Seal of Wisdom") > 0 or buff("Seal of Vengeance") > 0 or buff("Seal of Command") > 0 then
        return nil
    end

    if preferWisdom and canCast(state, "Seal of Wisdom") then
        return "Seal of Wisdom"
    end
    if canCast(state, "Seal of Vengeance") then
        return "Seal of Vengeance"
    end
    if canCast(state, "Seal of Command") then
        return "Seal of Command"
    end
    if canCast(state, "Seal of Wisdom") then
        return "Seal of Wisdom"
    end
    return nil
end

local function chooseWarlockCurse(state)
    if not hasTarget(state) then
        return nil
    end
    local doom = debuff(state, "Curse of Doom")
    local agony = debuff(state, "Curse of Agony")
    local targetLevel = UnitLevel("target")
    local classification = UnitClassification and UnitClassification("target")
    local isBoss = (targetLevel == -1) or (classification == "worldboss")

    if isBoss then
        local doomKnown = (not addon.IsSpellKnownLocal) or addon:IsSpellKnownLocal("Curse of Doom")
        -- On bosses, prefer Doom and do not overwrite it with Agony while it should be active.
        if doomKnown and state.targetHealthPct > 25 then
            if doom < 5 and canCast(state, "Curse of Doom", { requireTarget = true }) then
                return "Curse of Doom"
            end
            return nil
        end

        if agony < 3 and canCast(state, "Curse of Agony", { requireTarget = true }) then
            return "Curse of Agony"
        end
        return nil
    end

    if agony < 3 and canCast(state, "Curse of Agony", { requireTarget = true }) then
        return "Curse of Agony"
    end
    return nil
end

local function shouldLifeTapForGlyph(state)
    if not addon.HasGlyphLike or not addon:HasGlyphLike("life tap") then
        return false
    end

    local lifeTapBuff = buff("Life Tap")
    if lifeTapBuff >= 8 then
        return false
    end

    if not state.inCombat then
        return state.playerHealthPct > 45
    end

    -- During combat, keep uptime without over-tapping at very low health.
    return state.playerHealthPct > 55 and state.manaPct <= 75
end

local function pushWarlockLifeTap(queue, used, state)
    if shouldLifeTapForGlyph(state) then
        -- Some 3.3.5 cores report Life Tap as unusable at full mana; keep glyph upkeep priority.
        if canCast(state, "Life Tap", { skipUsable = true }) then
            push(queue, used, "Life Tap")
        end
        return
    end

    if state.manaPct <= 35 then
        pushIf(queue, used, state, "Life Tap")
    end
end

local function ensureHunterAspect(state, queue, used)
    if buff("Aspect of the Dragonhawk") < 60 then
        pushIf(queue, used, state, "Aspect of the Dragonhawk")
    end
end

addon.Priorities["DEATHKNIGHT:1"] = function(state, queueLength)
    local queue, used = makeQueue()

    if buff("Horn of Winter") < 6 then
        pushIf(queue, used, state, "Horn of Winter")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if debuff(state, "Frost Fever") < 3 then
        pushIf(queue, used, state, "Icy Touch", { requireTarget = true })
    end
    if debuff(state, "Blood Plague") < 3 then
        pushIf(queue, used, state, "Plague Strike", { requireTarget = true })
    end

    pushIf(queue, used, state, "Death Strike", { requireTarget = true })
    pushIf(queue, used, state, "Heart Strike", { requireTarget = true })

    if state.runicPower >= 40 then
        pushIf(queue, used, state, "Death Coil", { requireTarget = true })
    end

    pushIf(queue, used, state, "Blood Strike", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["DEATHKNIGHT:2"] = function(state, queueLength)
    local queue, used = makeQueue()

    if buff("Horn of Winter") < 6 then
        pushIf(queue, used, state, "Horn of Winter")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if debuff(state, "Frost Fever") < 3 then
        pushIf(queue, used, state, "Icy Touch", { requireTarget = true })
    end
    if debuff(state, "Blood Plague") < 3 then
        pushIf(queue, used, state, "Plague Strike", { requireTarget = true })
    end

    pushIf(queue, used, state, "Howling Blast", { requireTarget = true })
    pushIf(queue, used, state, "Obliterate", { requireTarget = true })

    if state.runicPower >= 40 then
        pushIf(queue, used, state, "Frost Strike", { requireTarget = true })
    end

    pushIf(queue, used, state, "Blood Strike", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["DEATHKNIGHT:3"] = function(state, queueLength)
    local queue, used = makeQueue()

    if buff("Horn of Winter") < 6 then
        pushIf(queue, used, state, "Horn of Winter")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if debuff(state, "Frost Fever") < 3 then
        pushIf(queue, used, state, "Icy Touch", { requireTarget = true })
    end
    if debuff(state, "Blood Plague") < 3 then
        pushIf(queue, used, state, "Plague Strike", { requireTarget = true })
    end

    pushIf(queue, used, state, "Scourge Strike", { requireTarget = true })
    pushIf(queue, used, state, "Blood Strike", { requireTarget = true })

    if state.runicPower >= 80 then
        pushIf(queue, used, state, "Death Coil", { requireTarget = true })
    end

    return queue, queueLength
end

addon.Priorities["DRUID:1"] = function(state, queueLength)
    local queue, used = makeQueue()
    if not hasTarget(state) then
        return queue, queueLength
    end

    if debuff(state, "Faerie Fire") < 25 then
        pushIf(queue, used, state, "Faerie Fire", { requireTarget = true })
    end
    pushIf(queue, used, state, "Starfall")

    if debuff(state, "Moonfire") < 2 then
        pushIf(queue, used, state, "Moonfire", { requireTarget = true })
    end
    if debuff(state, "Insect Swarm") < 2 then
        pushIf(queue, used, state, "Insect Swarm", { requireTarget = true })
    end

    if state.moving then
        pushIf(queue, used, state, "Moonfire", { requireTarget = true })
    end

    pushIf(queue, used, state, "Starfire", { requireTarget = true })
    pushIf(queue, used, state, "Wrath", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["DRUID:2"] = function(state, queueLength)
    local queue, used = makeQueue()
    local cp = state.comboPoints or 0

    if state.energy <= 35 then
        pushIf(queue, used, state, "Tiger's Fury")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if cp >= 1 and buff("Savage Roar") < 2 then
        pushIf(queue, used, state, "Savage Roar")
    end
    if debuff(state, "Mangle") < 8 then
        pushIf(queue, used, state, "Mangle (Cat)", { requireTarget = true })
    end
    if debuff(state, "Rake") < 2 then
        pushIf(queue, used, state, "Rake", { requireTarget = true })
    end
    if cp >= 5 and debuff(state, "Rip") < 3 then
        pushIf(queue, used, state, "Rip", { requireTarget = true })
    end
    if cp >= 5 and debuff(state, "Rip") > 4 then
        pushIf(queue, used, state, "Ferocious Bite", { requireTarget = true })
    end

    pushIf(queue, used, state, "Shred", { requireTarget = true })
    pushIf(queue, used, state, "Mangle (Cat)", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["DRUID:3"] = function(state, queueLength)
    local queue, used = makeQueue()

    if state.playerHealthPct < 55 then
        pushIf(queue, used, state, "Rejuvenation")
    end
    if state.playerHealthPct < 40 then
        pushIf(queue, used, state, "Healing Touch")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if debuff(state, "Moonfire") < 2 then
        pushIf(queue, used, state, "Moonfire", { requireTarget = true })
    end
    if debuff(state, "Insect Swarm") < 2 then
        pushIf(queue, used, state, "Insect Swarm", { requireTarget = true })
    end

    pushIf(queue, used, state, "Wrath", { requireTarget = true })
    pushIf(queue, used, state, "Starfire", { requireTarget = true })
    return queue, queueLength
end
addon.Priorities["HUNTER:1"] = function(state, queueLength)
    local queue, used = makeQueue()

    ensureHunterAspect(state, queue, used)
    if not hasTarget(state) then
        return queue, queueLength
    end

    if debuff(state, "Hunter's Mark") < 30 then
        pushIf(queue, used, state, "Hunter's Mark", { requireTarget = true })
    end
    if state.targetHealthPct <= 20 then
        pushIf(queue, used, state, "Kill Shot", { requireTarget = true })
    end
    if debuff(state, "Serpent Sting") < 3 then
        pushIf(queue, used, state, "Serpent Sting", { requireTarget = true })
    end

    pushIf(queue, used, state, "Bestial Wrath")
    pushIf(queue, used, state, "Kill Command", { requireTarget = true })
    pushIf(queue, used, state, "Arcane Shot", { requireTarget = true })
    pushIf(queue, used, state, "Steady Shot", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["HUNTER:2"] = function(state, queueLength)
    local queue, used = makeQueue()

    ensureHunterAspect(state, queue, used)
    if not hasTarget(state) then
        return queue, queueLength
    end

    if debuff(state, "Hunter's Mark") < 30 then
        pushIf(queue, used, state, "Hunter's Mark", { requireTarget = true })
    end
    if state.targetHealthPct <= 20 then
        pushIf(queue, used, state, "Kill Shot", { requireTarget = true })
    end
    if debuff(state, "Serpent Sting") < 3 then
        pushIf(queue, used, state, "Serpent Sting", { requireTarget = true })
    end

    pushIf(queue, used, state, "Chimera Shot", { requireTarget = true })
    pushIf(queue, used, state, "Aimed Shot", { requireTarget = true })
    pushIf(queue, used, state, "Arcane Shot", { requireTarget = true })
    pushIf(queue, used, state, "Steady Shot", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["HUNTER:3"] = function(state, queueLength)
    local queue, used = makeQueue()

    ensureHunterAspect(state, queue, used)
    if not hasTarget(state) then
        return queue, queueLength
    end

    if debuff(state, "Hunter's Mark") < 30 then
        pushIf(queue, used, state, "Hunter's Mark", { requireTarget = true })
    end
    if state.targetHealthPct <= 20 then
        pushIf(queue, used, state, "Kill Shot", { requireTarget = true })
    end
    if debuff(state, "Serpent Sting") < 3 then
        pushIf(queue, used, state, "Serpent Sting", { requireTarget = true })
    end

    pushIf(queue, used, state, "Explosive Shot", { requireTarget = true })
    pushIf(queue, used, state, "Black Arrow", { requireTarget = true })
    pushIf(queue, used, state, "Aimed Shot", { requireTarget = true })
    pushIf(queue, used, state, "Steady Shot", { requireTarget = true })
    pushIf(queue, used, state, "Arcane Shot", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["MAGE:1"] = function(state, queueLength)
    local queue, used = makeQueue()

    if state.manaPct <= 30 then
        pushIf(queue, used, state, "Evocation")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if state.moving then
        pushIf(queue, used, state, "Arcane Barrage", { requireTarget = true })
    end
    if buff("Missile Barrage") > 0 then
        pushIf(queue, used, state, "Arcane Missiles", { requireTarget = true })
    end

    pushIf(queue, used, state, "Arcane Blast", { requireTarget = true })
    pushIf(queue, used, state, "Arcane Missiles", { requireTarget = true })
    pushIf(queue, used, state, "Arcane Barrage", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["MAGE:2"] = function(state, queueLength)
    local queue, used = makeQueue()

    if state.manaPct <= 30 then
        pushIf(queue, used, state, "Evocation")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if buff("Hot Streak") > 0 then
        pushIf(queue, used, state, "Pyroblast", { requireTarget = true })
    end
    if debuff(state, "Living Bomb") < 2 then
        pushIf(queue, used, state, "Living Bomb", { requireTarget = true })
    end
    if state.moving then
        pushIf(queue, used, state, "Scorch", { requireTarget = true })
    end
    if buff("Clearcasting") > 0 then
        pushIf(queue, used, state, "Pyroblast", { requireTarget = true })
    end

    pushIf(queue, used, state, "Fireball", { requireTarget = true })
    pushIf(queue, used, state, "Scorch", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["MAGE:3"] = function(state, queueLength)
    local queue, used = makeQueue()

    if state.manaPct <= 30 then
        pushIf(queue, used, state, "Evocation")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if buff("Fingers of Frost") > 0 then
        pushIf(queue, used, state, "Deep Freeze", { requireTarget = true })
    end
    if buff("Brain Freeze") > 0 then
        pushIf(queue, used, state, "Frostfire Bolt", { requireTarget = true })
    end
    if state.moving then
        pushIf(queue, used, state, "Ice Lance", { requireTarget = true })
    end

    pushIf(queue, used, state, "Frostbolt", { requireTarget = true })
    pushIf(queue, used, state, "Ice Lance", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["PALADIN:1"] = function(state, queueLength)
    local queue, used = makeQueue()
    local seal = choosePaladinSeal(state, true)
    local judgement = choosePaladinJudgement(state)

    if seal then
        push(queue, used, seal)
    end
    if state.playerHealthPct < 45 then
        pushIf(queue, used, state, "Holy Light")
    end
    if state.playerHealthPct < 80 then
        pushIf(queue, used, state, "Flash of Light")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if judgement then
        push(queue, used, judgement)
    end
    pushIf(queue, used, state, "Holy Shock", { requireTarget = true })
    pushIf(queue, used, state, "Exorcism", { requireTarget = true })
    pushIf(queue, used, state, "Consecration")
    return queue, queueLength
end

addon.Priorities["PALADIN:2"] = function(state, queueLength)
    local queue, used = makeQueue()
    local seal = choosePaladinSeal(state, false)
    local judgement = choosePaladinJudgement(state)

    if buff("Righteous Fury") < 60 then
        pushIf(queue, used, state, "Righteous Fury")
    end
    if seal then
        push(queue, used, seal)
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    pushIf(queue, used, state, "Hammer of the Righteous", { requireTarget = true })
    pushIf(queue, used, state, "Shield of Righteousness", { requireTarget = true })
    if judgement then
        push(queue, used, judgement)
    end
    pushIf(queue, used, state, "Consecration")
    pushIf(queue, used, state, "Holy Shield")
    pushIf(queue, used, state, "Avenger's Shield", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["PALADIN:3"] = function(state, queueLength)
    local queue, used = makeQueue()
    local seal = choosePaladinSeal(state, false)
    local judgement = choosePaladinJudgement(state)

    if seal then
        push(queue, used, seal)
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if state.targetHealthPct <= 20 then
        pushIf(queue, used, state, "Hammer of Wrath", { requireTarget = true })
    end

    pushIf(queue, used, state, "Crusader Strike", { requireTarget = true })
    pushIf(queue, used, state, "Divine Storm", { requireTarget = true })
    if judgement then
        push(queue, used, judgement)
    end
    pushIf(queue, used, state, "Consecration")
    pushIf(queue, used, state, "Exorcism", { requireTarget = true })
    pushIf(queue, used, state, "Holy Wrath")
    return queue, queueLength
end
addon.Priorities["PRIEST:1"] = function(state, queueLength)
    local queue, used = makeQueue()

    if state.playerHealthPct < 65 then
        pushIf(queue, used, state, "Power Word: Shield")
    end
    if state.playerHealthPct < 45 then
        pushIf(queue, used, state, "Flash Heal")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if debuff(state, "Shadow Word: Pain") < 3 then
        pushIf(queue, used, state, "Shadow Word: Pain", { requireTarget = true })
    end

    pushIf(queue, used, state, "Penance", { requireTarget = true })
    pushIf(queue, used, state, "Mind Blast", { requireTarget = true })
    pushIf(queue, used, state, "Holy Fire", { requireTarget = true })
    pushIf(queue, used, state, "Smite", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["PRIEST:2"] = function(state, queueLength)
    local queue, used = makeQueue()

    if state.playerHealthPct < 65 then
        pushIf(queue, used, state, "Renew")
    end
    if state.playerHealthPct < 45 then
        pushIf(queue, used, state, "Flash Heal")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    pushIf(queue, used, state, "Holy Fire", { requireTarget = true })
    if debuff(state, "Shadow Word: Pain") < 3 then
        pushIf(queue, used, state, "Shadow Word: Pain", { requireTarget = true })
    end
    pushIf(queue, used, state, "Smite", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["PRIEST:3"] = function(state, queueLength)
    local queue, used = makeQueue()

    if state.manaPct <= 25 then
        pushIf(queue, used, state, "Dispersion")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if debuff(state, "Vampiric Touch") < 2 then
        pushIf(queue, used, state, "Vampiric Touch", { requireTarget = true })
    end
    if debuff(state, "Devouring Plague") < 2 then
        pushIf(queue, used, state, "Devouring Plague", { requireTarget = true })
    end
    if debuff(state, "Shadow Word: Pain") < 2 then
        pushIf(queue, used, state, "Shadow Word: Pain", { requireTarget = true })
    end
    if state.targetHealthPct <= 25 then
        pushIf(queue, used, state, "Shadow Word: Death", { requireTarget = true })
    end

    pushIf(queue, used, state, "Mind Blast", { requireTarget = true })
    pushIf(queue, used, state, "Mind Flay", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["ROGUE:1"] = function(state, queueLength)
    local queue, used = makeQueue()
    local cp = state.comboPoints or 0

    if buff("Hunger for Blood") < 6 then
        pushIf(queue, used, state, "Hunger for Blood")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if cp >= 1 and buff("Slice and Dice") < 2 then
        pushIf(queue, used, state, "Slice and Dice")
    end
    if cp >= 4 and debuff(state, "Rupture") < 2 then
        pushIf(queue, used, state, "Rupture", { requireTarget = true })
    end
    if cp >= 4 then
        pushIf(queue, used, state, "Envenom", { requireTarget = true })
    end

    pushIf(queue, used, state, "Mutilate", { requireTarget = true })
    pushIf(queue, used, state, "Backstab", { requireTarget = true })
    pushIf(queue, used, state, "Sinister Strike", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["ROGUE:2"] = function(state, queueLength)
    local queue, used = makeQueue()
    local cp = state.comboPoints or 0

    if state.energy <= 45 then
        pushIf(queue, used, state, "Adrenaline Rush")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    pushIf(queue, used, state, "Killing Spree", { requireTarget = true })

    if cp >= 1 and buff("Slice and Dice") < 2 then
        pushIf(queue, used, state, "Slice and Dice")
    end
    if cp >= 5 and debuff(state, "Rupture") < 2 then
        pushIf(queue, used, state, "Rupture", { requireTarget = true })
    end
    if cp >= 5 then
        pushIf(queue, used, state, "Eviscerate", { requireTarget = true })
    end

    pushIf(queue, used, state, "Sinister Strike", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["ROGUE:3"] = function(state, queueLength)
    local queue, used = makeQueue()
    local cp = state.comboPoints or 0

    pushIf(queue, used, state, "Shadow Dance")
    if not hasTarget(state) then
        return queue, queueLength
    end

    if cp >= 1 and buff("Slice and Dice") < 2 then
        pushIf(queue, used, state, "Slice and Dice")
    end
    if cp >= 5 then
        pushIf(queue, used, state, "Eviscerate", { requireTarget = true })
    end

    pushIf(queue, used, state, "Hemorrhage", { requireTarget = true })
    pushIf(queue, used, state, "Backstab", { requireTarget = true })
    pushIf(queue, used, state, "Sinister Strike", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["SHAMAN:1"] = function(state, queueLength)
    local queue, used = makeQueue()

    if state.manaPct <= 35 then
        pushIf(queue, used, state, "Thunderstorm")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if debuff(state, "Flame Shock") < 2 then
        pushIf(queue, used, state, "Flame Shock", { requireTarget = true })
    end

    pushIf(queue, used, state, "Lava Burst", { requireTarget = true })
    pushIf(queue, used, state, "Chain Lightning", { requireTarget = true })
    pushIf(queue, used, state, "Lightning Bolt", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["SHAMAN:2"] = function(state, queueLength)
    local queue, used = makeQueue()

    if buff("Lightning Shield") < 20 then
        pushIf(queue, used, state, "Lightning Shield")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    pushIf(queue, used, state, "Feral Spirit")
    pushIf(queue, used, state, "Stormstrike", { requireTarget = true })
    pushIf(queue, used, state, "Lava Lash", { requireTarget = true })

    if debuff(state, "Flame Shock") < 2 then
        pushIf(queue, used, state, "Flame Shock", { requireTarget = true })
    end

    pushIf(queue, used, state, "Earth Shock", { requireTarget = true })
    pushIf(queue, used, state, "Lightning Bolt", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["SHAMAN:3"] = function(state, queueLength)
    local queue, used = makeQueue()

    if buff("Earth Shield") < 10 then
        pushIf(queue, used, state, "Earth Shield")
    end
    if state.playerHealthPct < 65 then
        pushIf(queue, used, state, "Riptide")
    end
    if state.playerHealthPct < 45 then
        pushIf(queue, used, state, "Lesser Healing Wave")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    if debuff(state, "Flame Shock") < 2 then
        pushIf(queue, used, state, "Flame Shock", { requireTarget = true })
    end

    pushIf(queue, used, state, "Lava Burst", { requireTarget = true })
    pushIf(queue, used, state, "Lightning Bolt", { requireTarget = true })
    pushIf(queue, used, state, "Chain Lightning", { requireTarget = true })
    return queue, queueLength
end
addon.Priorities["WARLOCK:1"] = function(state, queueLength)
    local queue, used = makeQueue()

    pushWarlockLifeTap(queue, used, state)
    if buff("Fel Armor") < 60 then
        pushIf(queue, used, state, "Fel Armor")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    local curse = chooseWarlockCurse(state)
    if curse then
        push(queue, used, curse)
    end

    if debuff(state, "Corruption") < 3 then
        pushIf(queue, used, state, "Corruption", { requireTarget = true })
    end
    if debuff(state, "Unstable Affliction") < 3 then
        pushIf(queue, used, state, "Unstable Affliction", { requireTarget = true })
    end
    if debuff(state, "Haunt") < 2 then
        pushIf(queue, used, state, "Haunt", { requireTarget = true })
    end
    if state.targetHealthPct <= 25 then
        pushIf(queue, used, state, "Drain Soul", { requireTarget = true })
    end

    pushIf(queue, used, state, "Shadow Bolt", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["WARLOCK:2"] = function(state, queueLength)
    local queue, used = makeQueue()

    pushWarlockLifeTap(queue, used, state)
    if buff("Fel Armor") < 60 then
        pushIf(queue, used, state, "Fel Armor")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    local curse = chooseWarlockCurse(state)
    if curse then
        push(queue, used, curse)
    end

    if debuff(state, "Corruption") < 3 then
        pushIf(queue, used, state, "Corruption", { requireTarget = true })
    end
    if debuff(state, "Immolate") < 2 then
        pushIf(queue, used, state, "Immolate", { requireTarget = true })
    end

    pushIf(queue, used, state, "Metamorphosis")
    if buff("Metamorphosis") > 0 then
        pushIf(queue, used, state, "Immolation Aura")
    end
    if state.targetHealthPct <= 25 then
        pushIf(queue, used, state, "Drain Soul", { requireTarget = true })
    end

    pushIf(queue, used, state, "Incinerate", { requireTarget = true })
    pushIf(queue, used, state, "Shadow Bolt", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["WARLOCK:3"] = function(state, queueLength)
    local queue, used = makeQueue()

    pushWarlockLifeTap(queue, used, state)
    if buff("Fel Armor") < 60 then
        pushIf(queue, used, state, "Fel Armor")
    end
    if not hasTarget(state) then
        return queue, queueLength
    end

    local curse = chooseWarlockCurse(state)
    if curse then
        push(queue, used, curse)
    end

    local immolate = debuff(state, "Immolate")
    if immolate < 2 then
        pushIf(queue, used, state, "Immolate", { requireTarget = true })
    end
    if immolate > 2 then
        pushIf(queue, used, state, "Conflagrate", { requireTarget = true })
    end

    pushIf(queue, used, state, "Chaos Bolt", { requireTarget = true })
    if state.targetHealthPct <= 20 then
        pushIf(queue, used, state, "Shadowburn", { requireTarget = true })
    end

    pushIf(queue, used, state, "Incinerate", { requireTarget = true })
    pushIf(queue, used, state, "Shadow Bolt", { requireTarget = true })
    return queue, queueLength
end

addon.Priorities["WARRIOR:1"] = function(state, queueLength)
    local queue, used = makeQueue()
    if not hasTarget(state) then
        return queue, queueLength
    end

    if state.targetHealthPct <= 20 then
        pushIf(queue, used, state, "Execute", { requireTarget = true })
    end
    if debuff(state, "Rend") < 3 then
        pushIf(queue, used, state, "Rend", { requireTarget = true })
    end

    pushIf(queue, used, state, "Mortal Strike", { requireTarget = true })
    pushIf(queue, used, state, "Overpower", { requireTarget = true })
    pushIf(queue, used, state, "Slam", { requireTarget = true })

    if state.rage >= 60 then
        pushIf(queue, used, state, "Heroic Strike", { requireTarget = true })
    end

    return queue, queueLength
end

addon.Priorities["WARRIOR:2"] = function(state, queueLength)
    local queue, used = makeQueue()
    if not hasTarget(state) then
        return queue, queueLength
    end

    if state.targetHealthPct <= 20 then
        pushIf(queue, used, state, "Execute", { requireTarget = true })
    end

    pushIf(queue, used, state, "Bloodthirst", { requireTarget = true })
    pushIf(queue, used, state, "Whirlwind", { requireTarget = true })
    pushIf(queue, used, state, "Slam", { requireTarget = true })

    if state.rage >= 55 then
        pushIf(queue, used, state, "Heroic Strike", { requireTarget = true })
    end

    return queue, queueLength
end

addon.Priorities["WARRIOR:3"] = function(state, queueLength)
    local queue, used = makeQueue()
    if not hasTarget(state) then
        return queue, queueLength
    end

    pushIf(queue, used, state, "Shield Slam", { requireTarget = true })
    pushIf(queue, used, state, "Revenge", { requireTarget = true })
    pushIf(queue, used, state, "Shockwave", { requireTarget = true })
    pushIf(queue, used, state, "Thunder Clap", { requireTarget = true })
    pushIf(queue, used, state, "Devastate", { requireTarget = true })

    if state.rage >= 50 then
        pushIf(queue, used, state, "Heroic Strike", { requireTarget = true })
    end

    return queue, queueLength
end

local CLASS_FALLBACKS = {
    DEATHKNIGHT = { "Icy Touch", "Plague Strike", "Death Coil" },
    DRUID = { "Moonfire", "Wrath", "Starfire" },
    HUNTER = { "Serpent Sting", "Arcane Shot", "Steady Shot" },
    MAGE = { "Frostbolt", "Fireball", "Arcane Blast" },
    PALADIN = { "Crusader Strike", "Exorcism", "Consecration" },
    PRIEST = { "Shadow Word: Pain", "Mind Blast", "Smite" },
    ROGUE = { "Sinister Strike", "Eviscerate", "Rupture" },
    SHAMAN = { "Flame Shock", "Lava Burst", "Lightning Bolt" },
    WARLOCK = { "Corruption", "Shadow Bolt", "Immolate" },
    WARRIOR = { "Mortal Strike", "Bloodthirst", "Slam" },
}

local function genericFallback(state)
    local queue, used = makeQueue()

    if hasTarget(state) then
        local list = CLASS_FALLBACKS[state.class]
        if list then
            for _, spell in ipairs(list) do
                pushIf(queue, used, state, spell, { requireTarget = true })
            end
        end
    end

    if #queue == 0 and addon:IsSpellKnownLocal(6603) then
        push(queue, used, 6603)
    end

    return queue
end

function addon:GetPriorityQueue(state)
    local queueLength = (self.db and self.db.queueLength) or 1
    local key = state.specKey
    local handler = key and self.Priorities[key]

    if handler then
        local queue = handler(state, queueLength)
        if queue and #queue > 0 then
            while #queue > queueLength do
                table.remove(queue)
            end
            return queue, key
        end
    end

    return genericFallback(state), "fallback"
end
