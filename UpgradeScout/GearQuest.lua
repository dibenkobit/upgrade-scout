local _, ns = ...

-- GearQuest (the addon GearQuest Forever) as the one who scores, for a player who would
-- sooner go by that addon's stat weights than by this addon's own (Weights.lua). The choice
-- is made in the welcome window (Welcome.lua) and kept for the whole account; Score.lua,
-- which the rest of the addon asks, hands its questions on to this file while the choice
-- stands and GearQuest is there to be asked (Score.Engine). It is the fourth such addon,
-- after Pawn (Pawn.lua), Forever Companion (Companion.lua) and Forever Leveling BiS
-- (Leveling.lua), and answers the same questions.
--
-- Nothing of GearQuest is carried here: no weight, no item, no line of its code. It keeps no
-- table for other addons and describes none, so it is asked through the addon's own, which
-- it leaves in the open as the global GearQuest, each time. Written after its version 1.4.1:
--   * It has lists of gear for a class, a spec, a side and a level, one for every level, up
--     to two hundred pieces to a slot. A row of a list is an item with a score, made
--     before the addon was packed: each stat of the item times the spec's weight for it, a
--     weapon's damage per second times a weight of its own, and for some items what their
--     effect or their set is worth. As a rule an item has the same score at every level it
--     is listed. The lists of the class being played are loaded as the character logs in.
--   * Data:EntryForItemLink gives the row a link has at the level, the spec and the side of
--     the character being played: what its line in a tooltip is written from. A random
--     enchantment has a row by its name ("of the Tiger"), with the score of the best roll
--     that enchantment can come with. Data:EquippedPipelineScore gives the score of an item's
--     row at whatever level it has one, as GearQuest takes it for a piece that is worn.
--   * Spec:GetOptions lists the specs it has for a class, each with the name it shows it by,
--     and Custom:List the ones the player made there (kept for the account). The spec of
--     the character being played is the one picked in it; with none picked, the one for the
--     talents; otherwise the one it starts the class on. Spec:SetSelectedSpec picks one, as
--     its own window does. It keeps the pick with what it saves for that character alone.
--   * Custom:Weights gives the weights a spec scores with: under its own names for the
--     stats, a chance by the percent, with a weight for a weapon's damage per second, one
--     for a ranged weapon's and one for a weapon's speed.
--   * It writes into every item tooltip, about the character being played: for an item with
--     a row, its place in the list, a number from 0 to 100 for where its score stands
--     between the worst and the best of the slot, and how far that is from what is worn;
--     for any other, that it is not scoring the item. Each has a switch in its settings
--     (GearQuestForeverDB.settings). It draws no arrows in the bags.
--   * It can show its lists for another class and level than the character's ("simulation").
--     While that is on, everything it answers is about that other character.
--
-- So there are two ways to a score here.
--
-- Where GearQuest has a row for the item, the score is the row's: for the character being
-- played, on the spec in use there. That is the number its own line in a tooltip is made
-- from, and a list of ours that added the stats up its own way would now and then stand
-- over a line that says otherwise. A player who chose it to score is shown what it shows.
-- (The owner's rule for every addon that scores: see Companion.lua.) Its 0 to 100 is not
-- used: it says where an item stands among the others of its slot, not what it is worth,
-- and a tenth more of it is not a tenth more of anything. The score it is made from is a
-- sum of stats like any other, the same currency in every slot, and that is what a gain
-- here is a share of.
--
-- Everything else is scored here, from the weights Custom:Weights gives for the class and
-- the spec, the way its rows are made: each stat times its weight, a chance by the percent,
-- armor of a kind the spec would rather not wear for a share of that, a weapon by its
-- damage per second. So are the items it has no row for, which are many on an auction house;
-- the other specs of the character being played; and every other character of the account,
-- of whom it knows nothing. What an item's effect or its set is worth is not in that sum:
-- only its rows have it. Nor is the share it gives out for a kind of armor the one its rows
-- were made with for every spec (a paladin's Holy; and a rogue's cloth has none given out).
-- (Put to the copy of GearQuest 1.4.1 in the game folder, with the game's count of an
-- item's stats made from its own stat rows, for fourteen classes, specs and levels: of the
-- 114 to 506 items it lists for a character at its level, the score for the character
-- played was the row's for every one, and the sum was the row's score to the hundredth for
-- 88 to 100 in a hundred, but for that paladin, for whom it was for 53. See
-- scripts/check-gearquest.lua, which says of the others why not.)
--
-- It has a way of its own to score a link it has no row for (Compare:ScoreItemLinkStats),
-- which it uses for a worn piece it lists nowhere. That one is not asked: it goes by another
-- table of weights than its lists are made with, and for one made-up item its number was
-- from a third of the sum on those weights to seven times it, by the spec.
--
-- Where an item goes and what it would replace stays this addon's to say (Compare.lua), on
-- those numbers; a weapon has the one, whichever hand it is in, as its damage has one
-- weight there for either.
--
-- Throughout this file `who` is the character the question is about: a card from Roster for
-- one that is not being played, nil for the one that is.
local Q = {}
ns.GearQuest = Q

-- The addon by the name it goes by in the game: the heading of its own lines in a tooltip.
Q.NAME = "GearQuest"

-- The words of ours that are about this addon, by what they are for (Score.Text).
Q.TEXT = {
    SCORE = "TT_GEARQUEST_SCORE",
    TIP = "PROFILE_TIP_GEARQUEST",
    NO_SCALE = "ERR_NO_SCALE_GEARQUEST",
    ABSENT = "WELCOME_NO_GEARQUEST",
    ASK = "WELCOME_SCALE_GEARQUEST",
    NONE = "WELCOME_NO_SCALE_GEARQUEST",
    NEW = "WELCOME_GEARQUEST_NEW",
}
-- (And one more, which is ours to say only while it writes its own line: Q.Words.)
local SHARED = "WELCOME_TOOLTIP_GEARQUEST"
-- What the account remembers of having seen the choice of who scores with this addon there.
Q.OFFERED = "gearquestOffered"

local WEAPON_CLASS, ARMOR_CLASS = Enum.ItemClass.Weapon, Enum.ItemClass.Armor
local DAGGER = 15               -- the kind of weapon, as the game numbers it

---------------------------------------------------------------------------
-- Is it there
---------------------------------------------------------------------------
-- The addon's own table; nil where it is not installed or is switched off.
local function Addon()
    local addon = GearQuest
    return type(addon) == "table" and addon or nil
end

-- Its settings, for the whole account; nil where it has none yet.
local function Settings()
    local db = GearQuestForeverDB
    local settings = type(db) == "table" and db.settings or nil
    return type(settings) == "table" and settings or nil
end

-- Everything asked of it is one of these functions of its own, named here by the part of
-- the addon they are in, so that a version without one is taken for an addon that cannot be
-- asked, not for an error in the middle of a scan. (A few more are asked where they are
-- there: see Q.Choose, Row, Q.ShowsWeapons, Q.Refuses, Labels and Hook.)
local REQUIRED = {
    { nil, "GetEffectiveClass", "GetEffectiveSpec", "GetEffectiveLevel", "IsPreviewEnabled" },
    { "Spec", "GetOptions", "GetSpecLabel" },
    { "Custom", "Get", "List", "Weights" },
    { "Data", "EntryForItemLink" },
}

-- Has it all of that, and its lists ready? They are made as the character logs in (its
-- index of them, Data.byItemId), a moment after its files are read. Found so once, it is so
-- for the rest of the session.
local readyFor
local function Ready()
    local addon = Addon()
    if not addon then return false end
    if readyFor == addon then return true end
    for i = 1, #REQUIRED do
        local part = REQUIRED[i][1]
        local from = addon
        if part then from = addon[part] end
        if type(from) ~= "table" then return false end
        for at = 2, #REQUIRED[i] do
            if type(from[REQUIRED[i][at]]) ~= "function" then return false end
        end
    end
    if type(addon.Data.byItemId) ~= "table" then return false end
    readyFor = addon
    return true
end

---------------------------------------------------------------------------
-- The character being played, as GearQuest has it
---------------------------------------------------------------------------
-- A profile here is a spec of GearQuest, named by one text: the class and the spec's own
-- name there ("ROGUE:combat"; "ROGUE:c:1" for the first one the player made). The ones of
-- the character being played begin with a mark of their own ("@ROGUE:combat"): the one in
-- use there is scored by its rows, and the same spec may be an alt's at once, which has
-- none.
local MINE = "@"

local function Id(class, spec, mine)
    return (mine and MINE or "") .. class .. ":" .. spec
end

-- The class and the spec of a profile, and whether it is one of the character being played.
-- nil for what is not one of ours.
local function Parse(id)
    if type(id) ~= "string" then return nil end
    local mine, class, spec = id:match("^(@?)(%u+):(.+)$")
    if not class then return nil end
    return class, spec, mine == MINE
end

-- What it says of the character being played: { simulating = it shows another character's
-- lists; id, class, spec = the profile of the spec in use, where there is one; level }. The
-- question is asked many times a second (each time a tooltip is drawn), and answering it
-- reads its settings and the character's talents there, so the answer is kept for a moment.
-- It is asked again at once when GearQuest draws its own windows anew (see Hook below); and
-- an answer that turns out new without that is told the same way.
local ACTIVE_FOR = 2            -- seconds an answer is kept
local state, stateAt
local seen                      -- (see "When its answers change")
local simulated                 -- what its simulation was found at when last looked into
local Later                     -- (defined with Look)

local function State()
    local now = GetTime()
    if state == nil or now - stateAt > ACTIVE_FOR then
        local addon = GearQuest
        state = { simulating = addon:IsPreviewEnabled() and true or false }
        local class, spec = addon:GetEffectiveClass(), addon:GetEffectiveSpec()
        if not state.simulating and type(class) == "string" and type(spec) == "string" then
            state.id, state.class, state.spec = Id(class, spec, true), class, spec
            state.level = tonumber(addon:GetEffectiveLevel())
        end
        stateAt = now
        if simulated == nil then simulated = state.simulating end
        if simulated ~= state.simulating or (seen and (seen.mine ~= state.id or seen.level ~= state.level)) then Later() end
    end
    return state
end

-- Is GearQuest there to be asked? Not while it is not installed or is switched off, not in
-- a version without what is asked of it, not in the moments of logging in before its lists
-- are made; and not while it simulates another character: all it would say is about that
-- one. The choice stands meanwhile, and the addon scores by itself.
function Q.Usable()
    return Ready() and not State().simulating
end

---------------------------------------------------------------------------
-- Specs
---------------------------------------------------------------------------
-- The specs it has for a class, by their own names there: the ones that come with it, in
-- its order, then the ones the player made. (One it lists and does not offer yet is left out.)
local function Specs(class)
    local out = {}
    if type(class) ~= "string" then return out end
    local addon = GearQuest
    for _, option in ipairs(addon.Spec:GetOptions(class) or {}) do
        if type(option) == "table" and type(option.id) == "string" and not option.comingLater then out[#out + 1] = option.id end
    end
    for _, record in ipairs(addon.Custom:List(class) or {}) do
        if type(record) == "table" and type(record.id) == "string" then out[#out + 1] = record.id end
    end
    return out
end

-- The name a spec is shown by: GearQuest's own, in the language it speaks.
local function SpecTitle(class, spec)
    local label = GearQuest.Spec:GetSpecLabel(spec, class)
    if type(label) == "string" and label ~= "" then return label end
    return spec
end

function Q.Title(id)
    local class, spec = Parse(id)
    if not class then return tostring(id) end
    return SpecTitle(class, spec)
end

-- The specs to choose from for a character: { { name = the profile, title = the name it
-- is shown by, spec = its own name there }, ... }: every spec GearQuest has for the
-- character's class.
function Q.Scales(who)
    if who ~= nil and who == ns.Roster.Me() then who = nil end
    -- From here on there may be scores that rest on its answers as they are now.
    Q.Watch()
    local class = who and who.class or nil
    if not who then class = State().class end
    local out = {}
    for _, spec in ipairs(Specs(class)) do
        out[#out + 1] = { name = Id(class, spec, not who), title = SpecTitle(class, spec), spec = spec }
    end
    return out
end

-- The spec for the talent tree a character's talents are in. Its card names the profile
-- this addon has for the tree (Roster.Update): the class and the tree's name in English,
-- which in small letters is what GearQuest calls the spec, but for the few below.
local TREE = { DRUID_FERAL_CAT = "feral", DRUID_FERAL_BEAR = "bear", PRIEST_HEALER = "holy" }

local function ByTalents(who)
    local talents = who.talents
    if type(talents) ~= "string" or type(who.class) ~= "string" then return nil end
    if TREE[talents] then return TREE[talents] end
    if talents:sub(1, #who.class + 1) ~= who.class .. "_" then return nil end
    return talents:sub(#who.class + 2):lower()
end

-- The spec to score with for a character, and the specs it was chosen from, as
-- Score.Current. For the character being played it is the one in use in GearQuest: its own
-- line in a tooltip goes by that one, and a list on another would contradict it. For
-- another character: the one chosen for it in this addon's field; otherwise the one for
-- its talents; otherwise the one GearQuest starts a character of the class on; otherwise
-- the first. (What was picked in GearQuest for another character cannot be read: it keeps
-- that with what it saves for the character alone.)
function Q.Current(who)
    if who ~= nil and who == ns.Roster.Me() then who = nil end
    local list = Q.Scales(who)
    if #list == 0 then return nil, list end
    local function Find(spec)
        if spec == nil then return nil end
        for i = 1, #list do
            if list[i].spec == spec then return list[i] end
        end
    end
    if not who then return Find(State().spec) or list[1], list end
    local first = GearQuest.Spec.GetDefaultSpec
    return Find(who.gearquest) or Find(ByTalents(who))
        or Find(type(first) == "function" and first(GearQuest.Spec, who.class) or nil) or list[1], list
end

-- The spec chosen for a character (its card) in this addon's field or welcome window. For
-- the character being played that is a choice of the spec in use in GearQuest, and is made
-- there, by the function its own window picks one with: its lists and its lines in a
-- tooltip follow. For another character it is written on the card, by the spec's name there.
function Q.Choose(card, id)
    local class, spec = Parse(id)
    if not class then return end
    if card ~= ns.Roster.Me() then
        card.gearquest = spec
        return
    end
    card.gearquest = nil
    local pick = GearQuest.Spec.SetSelectedSpec
    if State().spec == spec or type(pick) ~= "function" then return end
    -- (Its function is called on its own: an error in it is reported and stops nothing here.)
    securecallfunction(pick, GearQuest.Spec, spec, class)
    -- What it says now is read anew; that the scores are another spec's is told as any
    -- change of it is (Look).
    state = nil
    Later()
end

-- The tooltip's block of the welcome window has a sentence of ours for as long as GearQuest
-- writes its own line: it writes one for the items it has a row for, and ours stand for the
-- rest (Q.WritesTooltip). Score.Text asks here for the words.
local Shows                     -- (defined with its own marks)

function Q.Words(what)
    if what == "SHARED" then return Shows() and SHARED or nil end
    return Q.TEXT[what]
end

---------------------------------------------------------------------------
-- Weights
---------------------------------------------------------------------------
-- The weights of a class's spec, as Custom:Weights gives them: { weights = { [its name for
-- a stat] = weight }, dps, ranged, speed = the weights of a weapon's damage per second, of
-- a ranged weapon's, and of a weapon's speed; kinds = { [a kind of armor, by its name
-- there] = the share of its worth a piece of that kind has for the spec }; text = all of
-- it as one text }. Each answer is new tables made over there, so it is kept, by what was
-- asked, until GearQuest's answers may have changed (Look), which also finds out by these
-- which of them did.
-- A spec the player made there is asked about by its record; one that comes with the addon
-- by a record made up here, of that spec with nothing changed.
-- The player can change a spec of their own at any time, and GearQuest says so for the one
-- in use alone. So an answer about a spec is asked for again once it is OTHERS_FOR seconds
-- old, and one found changed is told as any other change is (`stale`, see Look).
local asked = {}
local OTHERS_FOR = 10
local stale = false

local function Ask(key)
    local addon = GearQuest
    local record = addon.Custom:Get(key.class, key.spec)
    local base = key.spec
    if type(record) == "table" and type(record.base) == "string" then
        base = record.base
    else
        record = { base = key.spec }
    end
    local weights, dps, ranged, speed = addon.Custom:Weights(key.class, record, key.level)
    -- (For a spec it has not, it answers with no weights at all.)
    if type(weights) ~= "table" or next(weights) == nil then return nil end
    local kinds = type(addon.StatWeightsArmorClass) == "table" and addon.StatWeightsArmorClass[key.class] or nil
    kinds = type(kinds) == "table" and (kinds[base] or kinds.default) or nil
    local got = {
        weights = weights, dps = tonumber(dps) or 0, ranged = tonumber(ranged) or 0, speed = tonumber(speed) or 0,
        kinds = type(kinds) == "table" and kinds or nil, key = key, at = GetTime(),
    }
    local parts = { "dps=" .. got.dps, "ranged=" .. got.ranged, "speed=" .. got.speed }
    for name, weight in pairs(weights) do parts[#parts + 1] = tostring(name) .. "=" .. tostring(weight) end
    for kind, share in pairs(got.kinds or {}) do parts[#parts + 1] = "kind " .. tostring(kind) .. "=" .. tostring(share) end
    table.sort(parts)
    got.text = table.concat(parts, ",")
    return got
end

-- The weights a spec of a class scores with for a character of the level; nil for a spec
-- the addon has no weights for.
local function Weights(class, spec, level)
    level = tonumber(level) or 60
    local name = class .. ":" .. spec .. ":" .. level
    local got = asked[name]
    if got == nil then
        got = Ask({ class = class, spec = spec, level = level }) or false
        asked[name] = got
    elseif got and GetTime() - got.at > OTHERS_FOR then
        local again = Ask(got.key)
        if (again and again.text) ~= got.text then
            stale = true
            Later()
        end
        got = again or false
        asked[name] = got
    end
    return got or nil
end

---------------------------------------------------------------------------
-- A sum of stats
---------------------------------------------------------------------------
-- The game's name for a stat of gear -> the name GearQuest weighs it under. It weighs a
-- chance by the percent, and the game counts one in points of rating: `per` is how many of
-- those are a percent at level 60. It has one weight for attack power, with whatever weapon.
local function Mod(name)
    return "ITEM_MOD_" .. name .. "_SHORT"
end

local GEAR = {
    [Mod("STRENGTH")] = { to = "str" },
    [Mod("AGILITY")] = { to = "agi" },
    [Mod("STAMINA")] = { to = "sta" },
    [Mod("INTELLECT")] = { to = "int" },
    [Mod("SPIRIT")] = { to = "spi" },
    [Mod("ATTACK_POWER")] = { to = "ap" },
    [Mod("RANGED_ATTACK_POWER")] = { to = "ap" },
    [Mod("FERAL_ATTACK_POWER")] = { to = "feralAp" },
    -- (On gear this is the attack power a druid's weapon gives in its animal shapes: the
    -- game has no other name for it.)
    [Mod("MELEE_ATTACK_POWER")] = { to = "feralAp" },
    [Mod("ARCANE_DAMAGE_DONE")] = { to = "spArcane" },
    [Mod("FIRE_DAMAGE_DONE")] = { to = "spFire" },
    [Mod("FROST_DAMAGE_DONE")] = { to = "spFrost" },
    [Mod("HOLY_DAMAGE_DONE")] = { to = "spHoly" },
    [Mod("NATURE_DAMAGE_DONE")] = { to = "spNature" },
    [Mod("SHADOW_DAMAGE_DONE")] = { to = "spShadow" },
    [Mod("DEFENSE_SKILL_RATING")] = { to = "defense" },
    [Mod("BLOCK_VALUE")] = { to = "blockValue" },
    [Mod("MANA_REGENERATION")] = { to = "mp5" },
    [Mod("POWER_REGEN0")] = { to = "mp5" },
    [Mod("HEALTH_REGENERATION")] = { to = "hp5" },
    [Mod("HEALTH_REGEN")] = { to = "hp5" },
    [Mod("HEALTH")] = { to = "health" },
    [Mod("MANA")] = { to = "mana" },
    RESISTANCE0_NAME = { to = "armor" },
    [Mod("CRIT_RATING")] = { to = "crit", per = 14 },
    [Mod("HIT_RATING")] = { to = "hit", per = 10 },
    [Mod("HASTE_RATING")] = { to = "haste", per = 10 },
    [Mod("EXPERTISE_RATING")] = { to = "expertise", per = 10 },
    [Mod("DODGE_RATING")] = { to = "dodge", per = 12 },
    [Mod("PARRY_RATING")] = { to = "parry", per = 15 },
    [Mod("BLOCK_RATING")] = { to = "blockRating", per = 5 },
}

-- What a consumable adds is written down under the same names (SupplyData.lua), and a few
-- more that gear has no use for. A consumable can add a chance with weapons only or with
-- spells only (`with`), where GearQuest has one weight for a chance, whatever it is a
-- chance with: that counts on the weights of the kind that would use it (see Caster).
-- Attack power with weapons in hand is plain attack power there.
local SUPPLY = {}
for name, entry in pairs(GEAR) do SUPPLY[name] = entry end
SUPPLY[Mod("MELEE_ATTACK_POWER")] = { to = "ap" }
SUPPLY[Mod("CRIT_MELEE_RATING")] = { to = "crit", per = 14, with = "weapons" }
SUPPLY[Mod("CRIT_SPELL_RATING")] = { to = "crit", per = 14, with = "spells" }
SUPPLY[Mod("HIT_MELEE_RATING")] = { to = "hit", per = 10, with = "weapons" }
SUPPLY[Mod("HIT_SPELL_RATING")] = { to = "hit", per = 10, with = "spells" }
SUPPLY[Mod("HASTE_MELEE_RATING")] = { to = "haste", per = 10, with = "weapons" }
SUPPLY[Mod("HASTE_SPELL_RATING")] = { to = "haste", per = 10, with = "spells" }

-- What adds to spells is two stats there: to the damage they do ("spell power") and to
-- their healing. The game has three names: for both alike, for damage alone, for healing
-- alone. Healing that comes with nothing for damage counts for a third of itself as spell
-- power as well, under a weight of its own.
local SPELL_BOTH, SPELL_DAMAGE, SPELL_HEALING = Mod("SPELL_POWER"), Mod("SPELL_DAMAGE_DONE"), Mod("SPELL_HEALING_DONE")
local HEALING_AS_POWER = 3
-- Of an item's resistances it counts the greatest, not their sum.
local RESISTANCES = { "RESISTANCE1_NAME", "RESISTANCE2_NAME", "RESISTANCE3_NAME", "RESISTANCE4_NAME", "RESISTANCE5_NAME",
    "RESISTANCE6_NAME" }
local DPS = Mod("DAMAGE_PER_SECOND")
local BLOCK = Mod("BLOCK_VALUE")

-- Are the weights a spell caster's? They are when Intellect, Spirit and what adds to spells
-- together weigh more than Strength, Agility and attack power do.
local function Caster(weights)
    local function Sum(...)
        local total = 0
        for i = 1, select("#", ...) do
            local weight = weights[(select(i, ...))]
            if type(weight) == "number" and weight > 0 then total = total + weight end
        end
        return total
    end
    return Sum("int", "spi", "sp", "heal") > Sum("str", "agi", "ap")
end

-- A set of stats under the game's names, as GearQuest would count it: { [its name for a
-- stat] = amount }. names: GEAR or SUPPLY. weights: the weights it is for, which say which
-- kind of chance counts (asked about a consumable alone).
local function Counted(stats, names, weights)
    local set, caster = {}, nil
    for name, amount in pairs(stats) do
        local entry = names[name]
        local counts = entry ~= nil
        if counts and entry.with then
            if caster == nil then caster = Caster(weights) end
            counts = caster == (entry.with == "spells")
        end
        if counts then set[entry.to] = (set[entry.to] or 0) + amount / (entry.per or 1) end
    end
    local both = stats[SPELL_BOTH] or 0
    local damage, healing = both + (stats[SPELL_DAMAGE] or 0), both + (stats[SPELL_HEALING] or 0)
    if damage ~= 0 then set.sp = damage end
    if healing ~= 0 then
        set.heal = healing
        if damage == 0 then set.sp_from_heal = healing / HEALING_AS_POWER end
    end
    local resist = 0
    for i = 1, #RESISTANCES do resist = math.max(resist, stats[RESISTANCES[i]] or 0) end
    if resist ~= 0 then set.resist = resist end
    return set
end

-- The pieces of armor whose kind matters to a spec (cloth, leather, mail, plate): what is
-- worn on the body, not a cloak. And the kinds by the names GearQuest has for them.
local BODY = {
    INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true, INVTYPE_WRIST = true,
    INVTYPE_HAND = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true,
}
local KIND = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

-- A weapon's speed, which the game keeps in the words of its tooltip alone: on the right of
-- the line of its damage ("Speed 2.60"; a comma for the point in some languages). nil for
-- what has none.
local function Speed(link)
    local tip = C_TooltipInfo.GetHyperlink(link)
    for _, line in ipairs(tip and type(tip.lines) == "table" and tip.lines or {}) do
        local right = line.rightText
        if type(right) == "string" then
            local whole, part = right:match("(%d+)[%.,](%d+)%s*$")
            if whole then return tonumber(whole .. "." .. part) end
        end
    end
    return nil
end

-- The sum for an item read our way (`read`: see Q.Item), on a spec's weights (`got`: see
-- Weights): stat by stat, each for the share its kind of armor has, and the weapon. A
-- weapon is worth its damage per second times a weight, the same in either hand, with
-- another weight for a ranged one; and, for the few specs that weigh it, its speed, unless
-- it is one made for the off hand. `parts`, where given, is filled with the sum's lines for
-- Q.Parts.
local function ItemSum(item, read, got, parts)
    local share = 1
    if got.kinds and read.kind and BODY[item.invType] and type(got.kinds[read.kind]) == "number" then
        share = got.kinds[read.kind]
    end
    local total = 0
    for name, amount in pairs(Counted(read.stats, GEAR)) do
        local weight = got.weights[name]
        if type(weight) == "number" and weight ~= 0 then
            weight = weight * share
            total = total + amount * weight
            if parts then parts[#parts + 1] = { name = name, amount = amount, weight = weight, points = amount * weight } end
        end
    end
    local dps = read.stats[DPS]
    if dps and item.classID == WEAPON_CLASS then
        local ranged = RANGED[item.invType] == true
        local weight = ranged and got.ranged or got.dps
        total = total + dps * weight
        if parts then parts[#parts + 1] = { name = ranged and "dpsRanged" or "dps", stat = DPS, amount = dps, weight = weight, points = dps * weight } end
        if got.speed ~= 0 and not ranged and item.invType ~= "INVTYPE_WEAPONOFFHAND" then
            if read.speed == nil then read.speed = Speed(read.link) or false end
            if read.speed then
                total = total + read.speed * got.speed
                if parts then parts[#parts + 1] = { name = "speed", amount = read.speed, weight = got.speed, points = read.speed * got.speed } end
            end
        end
    end
    return total
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
-- What there is to score about an item link, in the shape Score.Item gives it, with what
-- either way to a score needs in place of the stats (`gearquest`): the link without its
-- enchantment, which is what GearQuest is asked about (the item as it would be for sale);
-- the item as this addon reads it (`stats`; its `kind` of armor; a weapon's `speed`, once
-- weights asked for it), for a sum on weights.
-- nil while there is no answer yet: the client has not loaded the item.
-- An item of a kind that is not gear (a shirt, a tabard) has nothing to read: `gearquest`
-- is false and the item scores nothing. That is an answer, and it stands: such an item is
-- often worn, and taken for one still to be read it would keep the gear from ever being
-- whole (Score.Context).
function Q.Item(link)
    local itemID, _, _, invType, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
    if not itemID then return nil end
    local read = false
    if ns.Compare.Handles(invType) then
        local bare = ns.Stats.Bare(link)
        if not C_Item.GetItemInfo(bare) then return nil end
        local own = ns.Score.Own(link)
        if not own then return nil end
        local stats = own.stats
        if own.tipBlock then
            -- A shield's own block, which this addon reads from its tooltip, is no stat to
            -- GearQuest: what it weighs as block value is the bonus to it that a few items
            -- have, which the game counts among an item's stats.
            stats = {}
            for name, amount in pairs(own.stats) do
                if name ~= BLOCK then stats[name] = amount end
            end
        end
        read = { link = bare, stats = stats, kind = classID == ARMOR_CLASS and KIND[subClassID] or nil }
    end
    return {
        link = link, itemID = itemID, invType = invType, classID = classID, subClassID = subClassID,
        scorer = Q, gearquest = read,
    }
end

-- The slot of its lists an item is listed in, by the way the item is worn: the name its
-- functions take for it.
local SLOT = {
    INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_CLOAK = "Back", INVTYPE_CHEST = "Chest",
    INVTYPE_ROBE = "Chest", INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands", INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs",
    INVTYPE_FEET = "Feet", INVTYPE_FINGER = "Finger", INVTYPE_TRINKET = "Trinket", INVTYPE_WEAPON = "MainHand",
    INVTYPE_2HWEAPON = "MainHand", INVTYPE_WEAPONMAINHAND = "MainHand", INVTYPE_WEAPONOFFHAND = "SecondaryHand",
    INVTYPE_SHIELD = "SecondaryHand", INVTYPE_HOLDABLE = "SecondaryHand", INVTYPE_RANGED = "Ranged",
    INVTYPE_RANGEDRIGHT = "Ranged", INVTYPE_THROWN = "Ranged", INVTYPE_RELIC = "Ranged",
}
-- (A weapon for one hand may be in the list of either hand, or of the off hand alone.)
local SECOND_SLOT = { INVTYPE_WEAPON = "SecondaryHand" }

-- Is the link a random enchantment of its item ("of the Tiger")? Such a link goes by another
-- name than the item does. (A name the game does not give yet: taken for one.)
local function Enchanted(itemID, link)
    local plain = C_Item.GetItemInfo(itemID)
    -- (The name as the link has it, to the bracket that closes it: a name may have its own.)
    local name = link:match("|h%[(.-)%]|h") or C_Item.GetItemInfo(link)
    return type(plain) ~= "string" or type(name) ~= "string" or name ~= plain
end

-- GearQuest's own score for an item, for the spec in use of the character being played:
-- { score, rolled = it is the score of the best roll of a random enchantment }; nil for an
-- item it has no row for. It is the row the item has at the character's level; where it has
-- none there, the row of another level, as GearQuest takes one for a piece that is worn
-- (most of what is worn is listed a few levels down). A random enchantment is not asked
-- about by the item alone: the row of another level may be another enchantment's.
-- Finding the rows of an item it was not asked about before takes it a millisecond and
-- more (it unpacks every row the item has, at every level), a scan asks about thousands of
-- items, and a rescan about the same ones: an answer is kept by the link, until its answers
-- change (Look), and for ROWS_KEPT links at most.
local ROWS_KEPT = 6000
local rows, rowsKept = {}, 0

local function ForgetRows()
    rows, rowsKept = {}, 0
end

local function Row(item)
    local link = item.gearquest.link
    local known = rows[link]
    if known ~= nil then return known or nil end
    local data = GearQuest.Data
    local row = false
    local entry = data:EntryForItemLink(link)
    if type(entry) == "table" and type(entry.pipelineScore) == "number" then
        row = { score = entry.pipelineScore, rolled = type(entry.suffix) == "string" and entry.suffix ~= "" }
    elseif type(data.EquippedPipelineScore) == "function" and SLOT[item.invType] and not Enchanted(item.itemID, link) then
        local score = data:EquippedPipelineScore(item.itemID, SLOT[item.invType])
        if type(score) ~= "number" and SECOND_SLOT[item.invType] then
            score = data:EquippedPipelineScore(item.itemID, SECOND_SLOT[item.invType])
        end
        if type(score) == "number" then row = { score = score, rolled = false } end
    end
    if rowsKept >= ROWS_KEPT then ForgetRows() end
    rows[link], rowsKept = row, rowsKept + 1
    return row or nil
end

-- Is the profile the one whose rows GearQuest has to give: the spec in use of the character
-- being played?
local function InUse(id)
    return id ~= nil and Ready() and State().id == id
end

-- An item's score on a profile, for a character of the level. 0 for a profile there is not.
-- A weapon has the one score, whichever hand it is in.
-- For the spec in use of the character being played it is GearQuest's own, where it has
-- one. Of a random enchantment that is the score of its best roll, and the piece at hand is
-- one roll, which may be a lesser: it scores what it adds up to, and no more than its row
-- says. (GearQuest does the same for one that is worn.)
function Q.Value(item, id, level)
    local read = item.gearquest
    if not read then return 0 end
    local class, spec = Parse(id)
    if not class then return 0 end
    local row = InUse(id) and Row(item) or nil
    if row and not row.rolled then return row.score end
    local got = Weights(class, spec, level)
    local sum = got and ItemSum(item, read, got) or 0
    if row then return got and math.min(row.score, sum) or row.score end
    return sum
end

-- Does GearQuest keep the item out of the hands of the character being played? One of its
-- specs fights with daggers alone, a rogue's, and it says which is in use; a weapon of
-- another kind then has no place in its lists, and none in ours. Of another character it is
-- not asked: it knows of none.
function Q.Refuses(item, who)
    if who ~= nil and who ~= ns.Roster.Me() then return false end
    if not item.gearquest or item.classID ~= WEAPON_CLASS or ns.Compare.Kind(item.invType) ~= "HANDS" then return false end
    local data = GearQuest.Data
    return type(data.AssassinationDaggerOnly) == "function" and data:AssassinationDaggerOnly() == true and item.subClassID ~= DAGGER
end

-- Its words for the stats, by its names for them, in the language it speaks: the ones its
-- own window lists a spec's weights by.
local function Labels()
    local addon = GearQuest
    local out = {}
    local words = type(addon.L) == "table" and addon.L or nil
    for name, label in pairs(type(addon.ScoringWeightLabels) == "table" and addon.ScoringWeightLabels or {}) do
        if type(label) == "string" then
            local worded = words and words[label]
            out[name] = type(worded) == "string" and worded or label
        end
    end
    return out
end

-- The sum stat by stat, for /upscout stats: { { name, label, amount, weight, points }, ... }
-- with the heaviest first, and the total. The lines are this addon's reading of the item on
-- the profile's weights. Where GearQuest has a row for the item the total is the row's
-- score, which is not always their sum: it counts more than stats.
function Q.Parts(item, id, level)
    local parts = {}
    local class, spec = Parse(id)
    local got = class and Weights(class, spec, level) or nil
    if item.gearquest and got then
        ItemSum(item, item.gearquest, got, parts)
        local labels = Labels()
        for i = 1, #parts do
            local part = parts[i]
            -- (A weapon's damage per second by the game's own word for it.)
            part.label = labels[part.name] or (part.stat and ns.Stats.Label(part.stat)) or part.name
        end
    end
    table.sort(parts, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        return a.name < b.name
    end)
    return parts, Q.Value(item, id, level)
end

-- Is this line of the item's tooltip one the score does not count? `text` is a line the
-- game gives the item for a spell of its own (Score.HasUnscoredEffects); `worn` says that
-- it is what the item does while worn, and not a use or a chance on hit. GearQuest's rows
-- have the worth of some items' effects, where it could make a number of their words, and
-- do not say which; a sum on its weights has none. So a use and a chance on hit count as
-- not scored. What an item does while worn is a stat where the game's tables say so
-- (GearData.extra).
function Q.Unread(item, _, worn)
    if not worn then return true end
    return ns.GearData.extra[item.itemID] == nil
end

---------------------------------------------------------------------------
-- A set of stats that is not an item
---------------------------------------------------------------------------
-- The score of a set of stats that is not an item: what an elixir adds, say. The same sum
-- on the profile's weights as for an item, so the number is in the points gear is scored
-- in. nil for a profile there is not.
function Q.StatsValue(stats, id, level)
    local class, spec = Parse(id)
    local got = class and Weights(class, spec, level) or nil
    if not got then return nil end
    local total = 0
    for name, amount in pairs(Counted(stats, SUPPLY, got.weights)) do
        local weight = got.weights[name]
        if type(weight) == "number" then total = total + amount * weight end
    end
    return total
end

---------------------------------------------------------------------------
-- A spec's say on weapons
---------------------------------------------------------------------------
-- Two of its specs fill their hands one way alone, and it says which is in use: one that
-- holds a weapon in both hands and nothing else (a shaman's), and one that holds a weapon
-- and a shield and never a two-hander (a paladin's). Its lists have nothing else for them,
-- and ours offer nothing else. Returns show1H, show2H as Pawn.ShowsWeapons does, for the
-- spec in use of the character being played; every other profile is offered every weapon.
function Q.ShowsWeapons(id)
    if not InUse(id) then return true, true end
    local data = GearQuest.Data
    local twoOnly = type(data.UsesTwoHandOnlyWeapons) == "function" and data:UsesTwoHandOnlyWeapons() == true
    local noTwo = type(data.UsesOneHandAndShield) == "function" and data:UsesOneHandAndShield() == true
    return not twoOnly, not noTwo
end

---------------------------------------------------------------------------
-- GearQuest's own lines
---------------------------------------------------------------------------
-- Its switch for its line of a score in item tooltips, as it stands: on until switched off
-- in its settings. It is switched with no word to other addons, so what it was found at is
-- kept (`seen`), and one found changed is told (Look).
Shows = function()
    local settings = Settings()
    return Ready() and (not settings or settings.showGearScore ~= false)
end

local function Noticed()
    if seen and seen.shows ~= Shows() then Later() end
end

-- Does it write the score into the item's tooltip itself, for the character being played?
-- It does for an item it has a row for at the character's level: where the item stands in
-- its list, and how it compares with what is worn. This addon then leaves its own lines
-- about the score out: they would say it twice (Score.Writes). For any other item it writes
-- that it is not scoring it, or nothing, and the lines are ours, on its weights; and so
-- they are for every item with its line switched off in its settings.
-- link: the item; nil when the question is whether it writes every item's, which it does not.
function Q.WritesTooltip(link)
    Noticed()
    if link == nil or not Shows() then return false end
    local entry = GearQuest.Data:EntryForItemLink(ns.Stats.Bare(link))
    return type(entry) == "table" and type(entry.pipelineScore) == "number"
end

-- GearQuest writes into every item tooltip, and means the character being played: it knows
-- of no other. Under an item picked for another character of the account (a row of a list
-- made for one) its lines read as if they were said of that character, which they are not.
-- Q.Hushed fills such a tooltip in with them left out: for the length of the call the
-- tooltip carries the mark GearQuest itself puts on a tooltip it wants none of its lines in
-- (gqSkipScoreHook), and it is taken off before anything else runs, whatever happens in the
-- call. This is asked whoever scores: the lines are its to write with the addon's own
-- weights chosen as well. Without GearQuest the tooltip is filled in and no more.
-- fill: what fills the tooltip in; it is called with the arguments that follow it, the
-- first of which is the tooltip.
function Q.Hushed(fill, ...)
    local tooltip = ...
    if not Addon() or type(tooltip) ~= "table" then
        fill(...)
        return
    end
    local before = rawget(tooltip, "gqSkipScoreHook")
    tooltip.gqSkipScoreHook = true
    local ok, problem = pcall(fill, ...)
    tooltip.gqSkipScoreHook = before
    if not ok then error(problem, 0) end
end

---------------------------------------------------------------------------
-- When its answers change
---------------------------------------------------------------------------
-- Another spec picked for the character, a weight changed in a spec of the player's own, a
-- level gained, the rows of such a spec made at last (it makes them a while after the spec
-- is picked): every score made on its answers is out of date. It tells no other addon. It
-- does draw its own windows anew then (RefreshUI), which is listened for (Hook); it does so
-- for other reasons too, which are nothing to the scores. So what the scores rest on is
-- kept (`seen`, and the weights that were asked for: `asked`), and only when that has
-- changed does the rest of the addon hear SCORING_CHANGED, while GearQuest scores: once for
-- a burst of changes.
-- Its line in a tooltip is nothing to the scores, and something to what this addon leaves
-- out for it: SETTING_CHANGED "gearquest" says so.
-- Its simulation of another character switched on or off is the addon itself going or
-- coming back (Q.Usable): told as a change of who scores, while it is the one chosen.
-- seen: { mine = the profile of the spec in use, level = the character's level there,
-- built = it has rows for that spec, shows = its line in a tooltip is on }. nil until its
-- specs are first asked for (Q.Scales), before which there are no such scores.

-- Has it rows for the spec? For one of the player's own it says so; one that comes with the
-- addon has them from the start.
local function Built(now)
    local custom = GearQuest.Custom
    if not now.id or type(custom.SpecIsIndexed) ~= "function" or not custom:Get(now.class, now.spec) then return true end
    return custom:SpecIsIndexed(now.class, now.spec) == true
end

-- Its specs are being read to score with, for the first time or again: what changes about
-- them from now on is to be told.
function Q.Watch()
    if seen then return end
    -- (Set before the spec in use is asked for: asking looks here.)
    seen = { shows = Shows() }
    local now = State()
    seen.mine, seen.level, seen.built = now.id, now.level, Built(now)
    -- (The weights of the spec in use are among what the scores rest on.)
    if now.id then Weights(now.class, now.spec, now.level) end
end

-- whole: GearQuest drew its windows anew, for whatever reason. Otherwise only what is found
-- out by asking is in question: its switch, its simulation, or an answer that has grown old.
local function Look(whole)
    if whole then state = nil end
    if not Ready() then return end
    local now = State()
    local chosen = ns.account.engine == "gearquest"
    if simulated ~= now.simulating then
        simulated = now.simulating
        if chosen then
            -- It scores no more, or again. What was kept of its answers is let go.
            seen, asked = nil, {}
            ForgetRows()
            ns.Fire("SCORING_CHANGED")
            ns.Fire("SETTING_CHANGED", "engine")
            return
        end
    end
    if not seen then return end
    if now.simulating or ns.Score.Engine() ~= "gearquest" then
        -- Nobody scores by it now. What was kept of its answers is let go, and they are
        -- read anew when it scores again (Q.Watch).
        seen, asked = nil, {}
        ForgetRows()
        return
    end
    local changed = false
    if whole then
        for name, got in pairs(asked) do
            local again = got and Ask(got.key) or nil
            if (again and again.text) ~= (got and got.text or nil) then changed = true end
            asked[name] = again or nil
        end
    end
    local shows = Shows()
    if shows ~= seen.shows then
        seen.shows = shows
        ns.Fire("SETTING_CHANGED", "gearquest")
    end
    local built = Built(now)
    if now.id ~= seen.mine or now.level ~= seen.level or built ~= seen.built then
        seen.mine, seen.level, seen.built, changed = now.id, now.level, built, true
    end
    if now.id then Weights(now.class, now.spec, now.level) end
    -- (Weights of a spec that were found changed when next asked for: Weights.)
    if stale then changed, stale = true, false end
    if changed then
        ForgetRows()
        ns.Fire("SCORING_CHANGED")
    end
end

local Changed = ns.Soon(0.2, function() Look(true) end)
Later = ns.Soon(0.2, function() Look(false) end)

-- A level gained: its lists are another level's now, and the game may give the new level
-- out a moment after it says so.
ns.On("PLAYER_LEVEL_UP", function()
    C_Timer.After(1.5, Changed)
end)

local told
local function Hook()
    local addon = Addon()
    if not addon or told == addon or type(addon.RefreshUI) ~= "function" then return end
    told = addon
    hooksecurefunc(addon, "RefreshUI", Changed)
end
Hook()
-- (GearQuest may be loaded after this addon.)
ns.On("PLAYER_LOGIN", Hook)
