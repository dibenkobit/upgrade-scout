local _, ns = ...

-- Forever Leveling BiS as the one who scores, for a player who would sooner go by that
-- addon's stat weights than by this addon's own (Weights.lua). The choice is made in the
-- welcome window (Welcome.lua) and kept for the whole account; Score.lua, which the rest of
-- the addon asks, hands its questions on to this file while the choice stands and Forever
-- Leveling BiS is there to be asked (Score.Engine). It is the third such addon, after Pawn
-- (Pawn.lua) and Forever Companion (Companion.lua), and answers the same questions.
--
-- Nothing of Forever Leveling BiS is carried here: no weight, no item, no line of its code.
-- It is asked through the table it keeps for other addons, ForeverLevelingBiS_API, as its
-- own API.md describes it (version 2, with the addon's 1.3.5), each time:
--   * GetSpec: the "main spec" the player picked in it for the character being played, and
--     the way that spec fills its hands (its "weapon setup"). The game has no word on a
--     character's spec, so this is the one the addon scores for.
--   * GetSpecs: the specs it has for a class, in the order of the talent trees. A hunter
--     has two for Survival and a druid two for Feral Combat.
--   * GetWeights: the weights of a class's spec at a level, the player's own where they
--     made a set of them there. Its own change with the level.
--   * ScoreItem: an item's score for the main spec of the character being played, "the same
--     score its tooltip uses": its own reading of the item, what it knows of the item's
--     effect, the speed of a weapon, what the character's race adds.
--   * GetGain: what an item gains that spec over what is worn; no answer for what the
--     character cannot wear now.
--   * OnChanged: a function of ours to call whenever its answers may have changed.
-- It writes a block into every item tooltip (the main spec's score, the gain, where the
-- item stands among the best) and draws an arrow on an upgrade in the bags. Each has a
-- switch in its settings, kept with the rest of what it saves (ForeverLevelingBiSDB).
--
-- So there are two ways to a score here, and which one is taken depends on whom it is for.
--
-- The character being played is scored by ScoreItem, on the main spec chosen in Forever
-- Leveling BiS and on no other: that is the one score the addon itself shows, in its own
-- block of a tooltip, and a list of ours that went by another spec, or added the numbers up
-- its own way, would contradict it. A player who chose it to score is shown what it shows.
-- (The owner's rule for every addon that scores: see Companion.lua.) So the profile field
-- has one line for that character, and another spec is chosen where the addon has it
-- chosen: its API reads and does not write. Beside that one line stands the way there
-- (F.Open).
--
-- Another character of the account is out of ScoreItem's reach, which knows the one being
-- played alone. Its items are scored here, from the weights GetWeights gives for its class,
-- spec and level, the way API.md says a score is made: each stat times its weight, a chance
-- by the percent, a weapon by its damage per second for the hand it is in and by its speed,
-- the two together never below nothing. What an item's effect is worth and what a race
-- adds are not in that sum: the API does not give them. Nor is armor an item has as a bonus
-- told from its other armor: the game counts the two as one. The numbers are then the ones
-- the player would see on that character, or close to them. (Put to the copy of Forever
-- Leveling BiS 1.3.5 in the game folder, with the game's count of an item's stats made from
-- its own data: of its 7,557 items, scored for nine classes and specs, the sum agreed with
-- its own score for all but some 140 to 150 of them: the ones with an effect, with bonus
-- armor, or with a chance to hit with ranged weapons only, which it keeps as a stat of its
-- own.) Such a character can be scored on any spec of its class; the one in use is the one
-- chosen for it in our field, otherwise its main spec in Forever Leveling BiS as last saved
-- there, otherwise the one for its talents.
--
-- Where an item goes and what it would replace stays this addon's to say (Compare.lua), on
-- those numbers; a weapon for one hand has two of them, one for each hand (F.OffValue).
--
-- Throughout this file `who` is the character the question is about: a card from Roster for
-- one that is not being played, nil for the one that is.
local F = {}
ns.Leveling = F

-- The addon by its own name, as the welcome window and the tooltips write it.
F.NAME = "Forever Leveling BiS"

-- The words of ours that are about this addon, by what they are for (Score.Text).
F.TEXT = {
    SCORE = "TT_LEVELING_SCORE",
    TIP = "PROFILE_TIP_LEVELING",
    NO_SCALE = "ERR_NO_SCALE_LEVELING",
    ABSENT = "WELCOME_NO_LEVELING",
    ASK = "WELCOME_SCALE_LEVELING",
    NONE = "WELCOME_NO_SCALE_LEVELING",
    CHANGE = "CHANGE_LEVELING",
    WRITES = "WELCOME_TOOLTIP_LEVELING",
    WRITES_OTHERS = "WELCOME_TOOLTIP_LEVELING_OTHERS",
    NEW = "WELCOME_LEVELING_NEW",
    ARROWS = "WELCOME_ARROWS_LEVELING",
}
-- What the account remembers of having seen the choice of who scores with this addon there.
F.OFFERED = "levelingOffered"

local WEAPON_CLASS = Enum.ItemClass.Weapon

---------------------------------------------------------------------------
-- Is it there
---------------------------------------------------------------------------
-- The table it keeps for other addons; nil where it is not installed or is switched off.
local function Api()
    local api = ForeverLevelingBiS_API
    return type(api) == "table" and api or nil
end

-- What it saves, for the whole account: its switches, and under `chars` what each character
-- chose in it. nil where it is not installed.
local function Kept()
    local db = ForeverLevelingBiSDB
    return type(db) == "table" and db or nil
end

-- Everything asked of it is one of these functions of its API, named here, so that a
-- version without one is taken for an addon that cannot be asked, not for an error in the
-- middle of a scan. (GetGain and GetStatKeys are asked where they are there: see F.Refuses
-- and F.Parts.)
local REQUIRED = { "GetSpec", "GetSpecs", "GetWeights", "ScoreItem", "OnChanged" }
local VERSION = 2               -- of its API: the first to score

-- Is Forever Leveling BiS there to be asked? Not while it is not installed or is switched
-- off, not with an API older than the one that scores, and not in the moments of logging in
-- before it knows the character: its API then has no answers. Once it has had one it has
-- them for the rest of the session, and is not asked again each time.
local readyFor
function F.Usable()
    local api = Api()
    if not api or (tonumber(api.version) or 1) < VERSION then return false end
    for i = 1, #REQUIRED do
        if type(api[REQUIRED[i]]) ~= "function" then return false end
    end
    if readyFor ~= api then
        if api.GetSpec() == nil then return false end
        readyFor = api
    end
    return true
end

---------------------------------------------------------------------------
-- Specs
---------------------------------------------------------------------------
-- A profile here is a spec of Forever Leveling BiS, named by one text: the class, the
-- spec's key there, and the weapon setup where one is known ("SHAMAN:enhancement:shield":
-- one spec of its has weights for each way of filling the hands). The one of the character
-- being played begins with a mark of its own ("@WARRIOR:fury:dualwield"): that one is
-- scored by ScoreItem, the others from their weights, and the same spec may be both at
-- once, for a warrior played and another one on the account.
local MINE = "@"

local function Id(class, spec, setup, mine)
    return (mine and MINE or "") .. class .. ":" .. spec .. (setup and ":" .. setup or "")
end

-- The class, the spec and the weapon setup (nil where none is named) of a profile, and
-- whether it is the one of the character being played. nil for what is not one of ours.
local function Parse(id)
    if type(id) ~= "string" then return nil end
    local mine, class, spec, setup = id:match("^(@?)(%u+):([%w_]+):?([%w_]*)$")
    if not class then return nil end
    return class, spec, setup ~= "" and setup or nil, mine == MINE
end

-- The name a spec is shown by: its talent tree as the game names it, which this addon has
-- in every language for its own profiles (Weights.titles). A spec's key is the tree's name
-- in English without its spaces, and so the profile of ours for that tree is the class and
-- that key ("WARRIOR_ARMS"), but for the few below. `false`: no profile of ours is named
-- after that tree, and the name is among our own words (WORD).
local TREE = {
    HUNTER = { beastmastery = "HUNTER_BEAST_MASTERY", survivalmelee = "HUNTER_SURVIVAL" },
    -- (A priest's Holy is the word a paladin's is, in every language of the game.)
    PRIEST = { discipline = false, holy = "PALADIN_HOLY" },
    DRUID = { feral = "DRUID_FERAL_CAT", bear = "DRUID_FERAL_BEAR" },
}
local WORD = { PRIEST = { discipline = "TREE_DISCIPLINE" } }
-- Two specs of one tree are told apart after its name, in brackets: by the druid's shape,
-- in our words, or by the hunter's way of fighting, in the game's.
local VARIANT = {
    HUNTER = { survival = "RANGED", survivalmelee = "MELEE" },
    DRUID = { feral = "FORM_CAT", bear = "FORM_BEAR" },
}

local function TreeOf(class, spec)
    local named = TREE[class] and TREE[class][spec]
    if named ~= nil then return named or nil end
    return class .. "_" .. spec:upper()
end

local function SpecTitle(class, spec)
    local data = ns.Weights
    local tree = TreeOf(class, spec)
    local titles = data.titles[GetLocale()] or data.titles.enUS
    local title = tree and (titles[tree] or data.titles.enUS[tree]) or nil
    local word = WORD[class] and WORD[class][spec]
    if not title and word then title = ns.L[word] end
    -- A spec that came with a later version of the addon: by its key, as the addon itself
    -- makes a name of one.
    title = title or (spec:sub(1, 1):upper() .. spec:sub(2))
    local variant = VARIANT[class] and VARIANT[class][spec]
    if variant then
        local text = ns.L[variant]
        if text == nil or text == variant then text = _G[variant] end
        if type(text) == "string" and text ~= "" then title = title .. " (" .. text .. ")" end
    end
    return title
end

function F.Title(id)
    local class, spec = Parse(id)
    if not class then return tostring(id) end
    return SpecTitle(class, spec)
end

-- The main spec of the character being played, as Forever Leveling BiS says it: { id, class,
-- spec, setup }. The question is asked many times a second (each time a tooltip is drawn),
-- and answering it reads the character's skills there, so the answer is kept for a moment.
-- It is asked again at once when Forever Leveling BiS says something changed (see Look
-- below); and an answer that turns out new without that is told the same way.
local ACTIVE_FOR = 2            -- seconds an answer is kept
local mine, mineAt
local seen                      -- (see "When its answers change")
local Later                     -- (defined with Look)

local function Mine()
    local now = GetTime()
    if mine == nil or now - mineAt > ACTIVE_FOR then
        local spec, setup, class = ForeverLevelingBiS_API.GetSpec()
        mine = false
        if type(spec) == "string" and type(class) == "string" then
            setup = type(setup) == "string" and setup or nil
            mine = { id = Id(class, spec, setup, true), class = class, spec = spec, setup = setup }
        end
        mineAt = now
        if seen and seen.mine ~= nil and seen.mine ~= (mine and mine.id or nil) then Later() end
    end
    return mine or nil
end

-- What Forever Leveling BiS has saved for another character of the account, under the
-- character's full name and its realm: the main spec chosen there (`spec`) and the weapon
-- setup of each spec (`weapons`, by "CLASS:spec"). The full name is the first name and the
-- surname with the game's own sign between them. nil for a character it has not seen.
local function Saved(who)
    local kept = Kept()
    local chars = kept and kept.chars
    if type(chars) ~= "table" or type(who.name) ~= "string" or type(who.realm) ~= "string" then return nil end
    local name = who.name
    if type(who.last) == "string" and who.last ~= "" then
        local signs = Constants and Constants.CharacterNameSeparatorConsts
        local sign = type(signs) == "table" and signs.CHARACTERNAME_SURNAME_SEPARATOR or nil
        name = name .. (type(sign) == "string" and sign or " ") .. who.last
    end
    local theirs = chars[name .. "-" .. who.realm]
    return type(theirs) == "table" and theirs or nil
end

-- The weapon setup saved there for a spec of the character; nil where none is.
local function SavedSetup(saved, class, spec)
    local weapons = saved and saved.weapons
    local setup = type(weapons) == "table" and weapons[class .. ":" .. spec] or nil
    return type(setup) == "string" and setup:match("^[%w_]+$") and setup or nil
end

-- The specs to choose from for a character: { { name = the profile, title = the name it
-- is shown by, spec = its key }, ... }.
-- For the character being played, the one: its main spec in Forever Leveling BiS. For
-- another character, every spec the addon has for its class, in its order.
function F.Scales(who)
    if who ~= nil and who == ns.Roster.Me() then who = nil end
    -- From here on there may be scores that rest on its answers as they are now.
    F.Watch()
    if not who then
        local own = Mine()
        if not own then return {} end
        return { { name = own.id, title = SpecTitle(own.class, own.spec), spec = own.spec } }
    end
    local class = who.class
    local specs = type(class) == "string" and ForeverLevelingBiS_API.GetSpecs(class) or nil
    local out = {}
    if type(specs) ~= "table" then return out end
    local saved = Saved(who)
    for i = 1, #specs do
        local spec = specs[i]
        if type(spec) == "string" and spec:match("^[%w_]+$") then
            out[#out + 1] = { name = Id(class, spec, SavedSetup(saved, class, spec)), title = SpecTitle(class, spec), spec = spec }
        end
    end
    return out
end

-- The spec for the talent tree a character's talents are in. Its card names the profile
-- this addon has for the tree (Roster.Update), which is the tree itself but for a priest:
-- our one profile for healing stands for two trees, and Holy is taken for either.
local HEALS = { PRIEST_HEALER = "holy" }

local function ByTalents(who, list)
    local talents = who.talents
    if talents == nil then return nil end
    for i = 1, #list do
        if HEALS[talents] == list[i].spec or TreeOf(who.class, list[i].spec) == talents then return list[i] end
    end
    return nil
end

-- The spec to score with for a character, and the specs it was chosen from, as
-- Score.Current. For the character being played it is its main spec in Forever Leveling
-- BiS. For another character: the one chosen for it in this addon's field; otherwise its
-- main spec there as last saved; otherwise the one for its talents; otherwise the first.
function F.Current(who)
    if who ~= nil and who == ns.Roster.Me() then who = nil end
    local list = F.Scales(who)
    if #list == 0 then return nil, list end
    if not who then return list[1], list end
    local function Find(spec)
        if spec == nil then return nil end
        for i = 1, #list do
            if list[i].spec == spec then return list[i] end
        end
    end
    local saved = Saved(who)
    return Find(who.leveling) or Find(saved and saved.spec) or ByTalents(who, list) or list[1], list
end

-- The spec chosen for a character (its card) in this addon's field. For another character
-- of the account it is written on the card, by the spec's key. The character being played
-- has the one line, and nothing to choose here: its main spec is chosen in Forever Leveling
-- BiS, whose API has no way to choose it from outside.
function F.Choose(card, id)
    if card == ns.Roster.Me() then return end
    local _, spec = Parse(id)
    card.leveling = spec
end

-- Where that main spec is chosen: the Settings panel of its window, which its own command
-- opens (/bis settings, as its Commands.lua has it: what a player would type). A player
-- who sees one spec where the other scorers have a choice is shown the way there: a button
-- beside the spec in the welcome window, a line under it in the profile field's menu.
-- F.Opens: is there such a place to open; F.Open: opens it.
local COMMAND, PANEL = "FOREVERLEVELINGBIS", "settings"
local function Command()
    local run = type(SlashCmdList) == "table" and SlashCmdList[COMMAND] or nil
    return type(run) == "function" and run or nil
end

function F.Opens()
    return F.Usable() and Command() ~= nil
end

function F.Open()
    if F.Opens() then Command()(PANEL) end
end

---------------------------------------------------------------------------
-- Weights
---------------------------------------------------------------------------
-- The weights of a spec at a level, as GetWeights gives them: { weights = { [its key for a
-- stat] = weight }, text = the same as one text }. Each answer is a new table made over
-- there, so it is kept, by what was asked, until Forever Leveling BiS says its answers may
-- have changed (Look), which also finds out by these which of them did.
-- The character being played is asked about with nothing named: its own class, main spec,
-- level and weapon setup, whatever they are by now.
local asked = {}

local function Text(weights)
    local parts = {}
    for key, weight in pairs(weights) do parts[#parts + 1] = tostring(key) .. "=" .. tostring(weight) end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function Ask(key)
    local weights
    if key.mine then
        weights = ForeverLevelingBiS_API.GetWeights()
    else
        weights = ForeverLevelingBiS_API.GetWeights(key.class, key.spec, key.level, key.setup)
    end
    if type(weights) ~= "table" then return nil end
    return { weights = weights, text = Text(weights), key = key }
end

-- The weights a profile scores with for a character of the level; nil for what is not a
-- profile, or one the addon has no weights for.
local function Weights(id, level)
    local class, spec, setup, own = Parse(id)
    if not class then return nil end
    level = tonumber(level) or 60
    local name = own and MINE or (class .. ":" .. spec .. ":" .. tostring(setup) .. ":" .. level)
    local got = asked[name]
    if got == nil then
        got = Ask({ mine = own, class = class, spec = spec, setup = setup, level = level }) or false
        asked[name] = got
    end
    return got and got.weights or nil
end

---------------------------------------------------------------------------
-- A sum of stats
---------------------------------------------------------------------------
-- The game's name for a stat of gear -> the key Forever Leveling BiS weighs it under (the
-- table of "Stat keys" in its API.md). It weighs a chance by the percent, and the game
-- counts one in points of rating: `per` is how many of those are a percent at level 60.
local function Mod(name)
    return "ITEM_MOD_" .. name .. "_SHORT"
end

local GEAR = {
    [Mod("STRENGTH")] = { to = "str" },
    [Mod("AGILITY")] = { to = "agi" },
    [Mod("STAMINA")] = { to = "sta" },
    [Mod("INTELLECT")] = { to = "int" },
    [Mod("SPIRIT")] = { to = "spi" },
    [Mod("ATTACK_POWER")] = { to = "atkpwr" },
    [Mod("RANGED_ATTACK_POWER")] = { to = "rgdatkpwr" },
    [Mod("FERAL_ATTACK_POWER")] = { to = "feratkpwr" },
    -- (On gear this is the attack power a druid's weapon gives in its animal shapes: the
    -- game has no other name for it.)
    [Mod("MELEE_ATTACK_POWER")] = { to = "feratkpwr" },
    [Mod("SPELL_POWER")] = { to = "splpwr" },
    [Mod("SPELL_DAMAGE_DONE")] = { to = "spldmg" },
    [Mod("SPELL_HEALING_DONE")] = { to = "splheal" },
    [Mod("ARCANE_DAMAGE_DONE")] = { to = "arcsplpwr" },
    [Mod("FIRE_DAMAGE_DONE")] = { to = "firsplpwr" },
    [Mod("FROST_DAMAGE_DONE")] = { to = "frosplpwr" },
    [Mod("HOLY_DAMAGE_DONE")] = { to = "holsplpwr" },
    [Mod("NATURE_DAMAGE_DONE")] = { to = "natsplpwr" },
    [Mod("SHADOW_DAMAGE_DONE")] = { to = "shasplpwr" },
    [Mod("SPELL_PENETRATION")] = { to = "splpen" },
    [Mod("DEFENSE_SKILL_RATING")] = { to = "defrtng" },
    [Mod("BLOCK_VALUE")] = { to = "block" },
    [Mod("EXTRA_ARMOR")] = { to = "armorbonus" },
    [Mod("MANA_REGENERATION")] = { to = "manargn" },
    [Mod("POWER_REGEN0")] = { to = "manargn" },
    [Mod("HEALTH_REGENERATION")] = { to = "healthrgn" },
    [Mod("HEALTH_REGEN")] = { to = "healthrgn" },
    [Mod("HASTE_RATING")] = { to = "hastertng" },
    RESISTANCE0_NAME = { to = "armor" },
    [Mod("CRIT_RATING")] = { to = "critPct", per = 14 },
    [Mod("HIT_RATING")] = { to = "hitPct", per = 10 },
    [Mod("EXPERTISE_RATING")] = { to = "expPct", per = 10 },
    [Mod("DODGE_RATING")] = { to = "dodgePct", per = 12 },
    [Mod("PARRY_RATING")] = { to = "parryPct", per = 15 },
    [Mod("BLOCK_RATING")] = { to = "blockPct", per = 5 },
}

-- What a consumable adds is written down under the same names (SupplyData.lua), and a few
-- more that gear has no use for. A consumable can add a chance with weapons only or with
-- spells only (`with`), where Forever Leveling BiS has one weight for a chance, whatever it
-- is a chance with: that counts on the weights of the kind that would use it (see Caster).
-- Attack power with weapons in hand is plain attack power there.
local SUPPLY = {}
for name, entry in pairs(GEAR) do SUPPLY[name] = entry end
SUPPLY[Mod("MELEE_ATTACK_POWER")] = { to = "atkpwr" }
SUPPLY[Mod("CRIT_MELEE_RATING")] = { to = "critPct", per = 14, with = "weapons" }
SUPPLY[Mod("CRIT_SPELL_RATING")] = { to = "critPct", per = 14, with = "spells" }
SUPPLY[Mod("HIT_MELEE_RATING")] = { to = "hitPct", per = 10, with = "weapons" }
SUPPLY[Mod("HIT_SPELL_RATING")] = { to = "hitPct", per = 10, with = "spells" }
SUPPLY[Mod("HASTE_MELEE_RATING")] = { to = "hastertng", with = "weapons" }
SUPPLY[Mod("HASTE_SPELL_RATING")] = { to = "hastertng", with = "spells" }
-- What adds to spells is three stats there: to damage and healing alike (as the game's own
-- "spell power"), to damage alone, to healing alone. A consumable's two amounts are put
-- into those three (see F.StatsValue).
SUPPLY[Mod("SPELL_DAMAGE_DONE")], SUPPLY[Mod("SPELL_HEALING_DONE")] = nil, nil
local SPELL_DAMAGE, SPELL_HEALING = Mod("SPELL_DAMAGE_DONE"), Mod("SPELL_HEALING_DONE")
local HEALTH, MANA = Mod("HEALTH"), Mod("MANA")
local DPS = Mod("DAMAGE_PER_SECOND")

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
    return Sum("int", "spi", "splpwr", "spldmg", "splheal") > Sum("str", "agi", "atkpwr", "rgdatkpwr")
end

-- Forever Leveling BiS has no stat for these two. Health counts as the Stamina that gives
-- it, and mana as Intellect, at the game's own rates.
local HEALTH_PER_STAMINA = 10
local MANA_PER_INTELLECT = 15

-- A weapon is worth its damage per second times the weight of the hand it is in, and its
-- speed besides: a weight for each tenth of a second it is slower than a speed the weights
-- name (or, where they name none, than the usual one of its kind), the two together never
-- below nothing. An off hand's damage without a weight of its own counts for half of the
-- main hand's, as its blows do.
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
local USUAL_SPEED = { twoHand = 3.3, ranged = 2.8, other = 2.4 }

-- hand: "main", "off" or "ranged". Returns the weight of a point of damage per second
-- there, and the key of the hand's weight for speed.
local function HandWeights(weights, hand)
    if hand == "ranged" then return weights.rangedDps or 0, "rangedSpeed" end
    if hand == "off" then return weights.ohDps or 0.5 * (weights.dps or 0), "ohSpeed" end
    return weights.dps or 0, "speed"
end

local function HandOf(item, offHand)
    if RANGED[item.invType] then return "ranged" end
    if offHand or item.invType == "INVTYPE_WEAPONOFFHAND" then return "off" end
    return "main"
end

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

-- read: the item as F.Item read it; its speed is looked up when weights first ask for it.
local function WeaponScore(item, read, weights, dps, offHand)
    local hand = HandOf(item, offHand)
    local weight, speedKey = HandWeights(weights, hand)
    local points = dps * weight
    local faster = weights[speedKey]
    if type(faster) == "number" and faster ~= 0 then
        if read.speed == nil then read.speed = Speed(read.link) or false end
        if read.speed then
            local from = weights[speedKey .. "Ref"]
            if type(from) ~= "number" then
                from = (item.invType == "INVTYPE_2HWEAPON" and USUAL_SPEED.twoHand)
                    or (hand == "ranged" and USUAL_SPEED.ranged) or USUAL_SPEED.other
            end
            points = points + (read.speed - from) * 10 * faster
        end
    end
    return math.max(0, points), weight
end

-- The sum for an item read our way (`read`: see F.Item), on weights: stat by stat, and the
-- weapon. `parts`, where given, is filled with the sum's lines for F.Parts.
local function ItemSum(item, read, weights, offHand, parts)
    local total = 0
    for name, amount in pairs(read.stats) do
        local entry = GEAR[name]
        local weight = entry and weights[entry.to]
        if type(weight) == "number" then
            amount = amount / (entry.per or 1)
            total = total + amount * weight
            if parts then parts[#parts + 1] = { name = entry.to, amount = amount, weight = weight, points = amount * weight } end
        end
    end
    local dps = read.stats[DPS]
    if dps and item.classID == WEAPON_CLASS then
        local points, weight = WeaponScore(item, read, weights, dps, offHand)
        total = total + points
        if parts then
            local hand = HandOf(item, offHand)
            local key = hand == "ranged" and "rangedDps" or hand == "off" and "ohDps" or "dps"
            parts[#parts + 1] = { name = key, amount = dps, weight = weight, points = points }
        end
    end
    return total
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
-- What there is to score about an item link, in the shape Score.Item gives it, with what
-- either way to a score needs in place of the stats (`leveling`): the link without its
-- enchantment, which is what Forever Leveling BiS is asked about (it reads an item as it
-- would be for sale); the item as this addon reads it (`stats`; a weapon's `speed`, once
-- weights asked for it), for a sum on weights; and the scores ScoreItem gave, once it was
-- asked (`main`, `off`).
-- nil while there is no answer yet: the client has not loaded the item.
-- An item of a kind that is not gear (a shirt, a tabard) has nothing to read: `leveling`
-- is false and the item scores nothing. That is an answer, and it stands: such an item is
-- often worn, and taken for one still to be read it would keep the gear from ever being
-- whole (Score.Context).
function F.Item(link)
    local itemID, _, _, invType, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
    if not itemID then return nil end
    local read = false
    if ns.Compare.Handles(invType) then
        local bare = ns.Stats.Bare(link)
        if not C_Item.GetItemInfo(bare) then return nil end
        local own = ns.Score.Own(link)
        if not own then return nil end
        read = { link = bare, stats = own.stats }
    end
    return {
        link = link, itemID = itemID, invType = invType, classID = classID, subClassID = subClassID,
        scorer = F, leveling = read,
    }
end

-- The number ScoreItem gives for an item, in the main hand or the off hand; 0 for what it
-- has no score for. Asked once for an item and a hand, until its answers change.
local epoch = 0                 -- counts the times they did (Look)

local function Asked(item, offHand)
    local read = item.leveling
    if read.epoch ~= epoch then read.epoch, read.main, read.off = epoch, nil, nil end
    local hand = offHand and "off" or "main"
    if read[hand] == nil then
        local score = ForeverLevelingBiS_API.ScoreItem(read.link, offHand and true or nil)
        read[hand] = type(score) == "number" and score or 0
    end
    return read[hand]
end

-- Is the item one whose worth depends on the hand: a weapon that is not a ranged one?
local function Handed(item)
    return item.classID == WEAPON_CLASS and not RANGED[item.invType]
end

-- An item's score on a profile, for a character of the level. offHand: as it is worth in
-- the off hand (a weapon only made for that hand is always scored so). 0 for a profile
-- there is not.
function F.Value(item, id, level, offHand)
    if not item.leveling then return 0 end
    local class, _, _, own = Parse(id)
    if not class then return 0 end
    offHand = Handed(item) and (offHand or item.invType == "INVTYPE_WEAPONOFFHAND") or false
    if own then return Asked(item, offHand) end
    local weights = Weights(id, level)
    if not weights then return 0 end
    return ItemSum(item, item.leveling, weights, offHand)
end

-- What a weapon for one hand is worth in the off hand, where that is another number than
-- F.Value's, which is for the main hand: Compare.lua offers the off hand by this one. nil
-- for everything else.
function F.OffValue(item, id, level)
    if not item.leveling or item.invType ~= "INVTYPE_WEAPON" then return nil end
    return F.Value(item, id, level, true)
end

-- Does Forever Leveling BiS say that the character being played cannot wear the item now?
-- Asked of what goes into the hands, where it has rules this addon has not: the kind of
-- weapon a spec's abilities call for (a rogue's daggers). Its own tooltip then says "Not
-- for" the spec, and a row of ours that offered the item would stand over those words.
-- GetGain has no answer for such an item; no answer, with a second value of true, is an
-- item it cannot tell of yet, and that one is not refused. Of another character it is not
-- asked: it knows of none.
function F.Refuses(item, who)
    if who ~= nil and who ~= ns.Roster.Me() then return false end
    if not item.leveling or ns.Compare.Kind(item.invType) ~= "HANDS" then return false end
    local read = item.leveling
    if read.epoch ~= epoch then read.epoch, read.main, read.off, read.refused = epoch, nil, nil, nil end
    if read.refused == nil then
        local gain = ForeverLevelingBiS_API.GetGain
        read.refused = false
        if type(gain) == "function" then
            local got, wait = gain(read.link)
            read.refused = got == nil and not wait
        end
    end
    return read.refused
end

-- Its words for the stats, by their keys, in the player's language (GetStatKeys); our own
-- for the three of a weapon's damage, which it words for a window of its own.
local function Labels()
    local out = {}
    local keys = ForeverLevelingBiS_API.GetStatKeys
    local list = type(keys) == "function" and keys() or nil
    for _, stat in ipairs(type(list) == "table" and list or {}) do
        if type(stat) == "table" and type(stat.key) == "string" and type(stat.label) == "string" then
            out[stat.key] = stat.label
        end
    end
    return out
end

-- The sum stat by stat, for /upscout stats: { { name, label, amount, weight, points }, ... }
-- with the heaviest first, and the total. The lines are this addon's reading of the item on
-- the profile's weights. For the character being played the total is ScoreItem's own, which
-- is not always their sum: it reads the item its own way, and counts more than stats.
function F.Parts(item, id, level, offHand)
    local parts = {}
    local weights = Weights(id, level)
    if item.leveling and weights then
        offHand = Handed(item) and (offHand or item.invType == "INVTYPE_WEAPONOFFHAND") or false
        ItemSum(item, item.leveling, weights, offHand, parts)
        local labels = Labels()
        for i = 1, #parts do parts[i].label = labels[parts[i].name] or parts[i].name end
    end
    table.sort(parts, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        return a.name < b.name
    end)
    return parts, F.Value(item, id, level, offHand)
end

-- Is this line of the item's tooltip one the score does not count? `text` is a line the
-- game gives the item for a spell of its own (Score.HasUnscoredEffects); `worn` says that
-- it is what the item does while worn, and not a use or a chance on hit. Forever Leveling
-- BiS has the worth of a few items' effects, and does not say which; so a use and a chance
-- on hit count as not scored. What an item does while worn is a stat where the game's
-- tables say so (GearData.extra), which is how it reads the item too.
function F.Unread(item, _, worn)
    if not worn then return true end
    return ns.GearData.extra[item.itemID] == nil
end

---------------------------------------------------------------------------
-- A set of stats that is not an item
---------------------------------------------------------------------------
-- The score of a set of stats that is not an item: what an elixir adds, say. The same sum
-- on the profile's weights as for an item, so the number is in the points gear is scored
-- in. nil for a profile there is not.
function F.StatsValue(stats, id, level)
    local weights = Weights(id, level)
    if not weights then return nil end

    local set, caster = {}, nil
    local function Add(name, amount)
        if amount ~= 0 then set[name] = (set[name] or 0) + amount end
    end
    for name, amount in pairs(stats) do
        local entry = SUPPLY[name]
        local counts = entry ~= nil
        if counts and entry.with then
            if caster == nil then caster = Caster(weights) end
            counts = caster == (entry.with == "spells")
        end
        if counts then Add(entry.to, amount / (entry.per or 1)) end
    end
    local damage, healing = stats[SPELL_DAMAGE] or 0, stats[SPELL_HEALING] or 0
    local both = math.min(damage, healing)
    Add("splpwr", both)
    Add("spldmg", damage - both)
    Add("splheal", healing - both)
    Add("sta", (stats[HEALTH] or 0) / HEALTH_PER_STAMINA)
    Add("int", (stats[MANA] or 0) / MANA_PER_INTELLECT)

    local total = 0
    for name, amount in pairs(set) do
        local weight = weights[name]
        if type(weight) == "number" then total = total + amount * weight end
    end
    return total
end

---------------------------------------------------------------------------
-- A spec's say on weapons
---------------------------------------------------------------------------
-- None that rules a weapon out of a list: a spec is offered every weapon (see
-- Pawn.ShowsWeapons, whose scales have a say). What its abilities cannot use is told item
-- by item (F.Refuses).
function F.ShowsWeapons()
    return true, true
end

---------------------------------------------------------------------------
-- Forever Leveling BiS's own marks
---------------------------------------------------------------------------
-- Its two switches as they stand: its block in item tooltips, and its arrows in the bags.
-- Each is on until switched off in its settings. They are switched with no word to other
-- addons, so what they were found at is kept (`seen`), and one found changed is told (Look).
local hushed = false            -- its block is switched off by us, for the length of a call

local function Shows()
    local kept = Kept()
    if not kept then return false, false end
    local block = kept.tooltip ~= false
    if hushed then block = hushed.block end
    return block, kept.bagMarks ~= false
end

local function ShowsText()
    local block, arrows = Shows()
    return tostring(block) .. tostring(arrows)
end

local function Noticed()
    if seen and seen.shows ~= ShowsText() then Later() end
end

-- Does it write its block into item tooltips: the score of the item for the main spec, and
-- how much better it is than what is worn? While it does, this addon leaves its own lines
-- about the score out, as with Pawn: they would say it twice (Score.Writes). Switched off
-- in its settings, ours are written, on its score.
function F.WritesTooltip()
    Noticed()
    return (Shows())
end

-- Does it draw its own arrow on an upgrade there? In the bags it does, while its switch is
-- on, and this addon then draws none of its own (Bags.lua): two arrows on one icon, by the
-- same score, would say one thing twice. It draws none in the bank, where ours stay.
-- where: "bank" for a slot of the bank; anything else is the bags.
function F.DrawsArrows(where)
    Noticed()
    local _, arrows = Shows()
    return arrows and where ~= "bank"
end

-- Forever Leveling BiS writes into every item tooltip, and means the character being
-- played: it knows of no other. Under an item picked for another character of the account
-- (a row of a list made for one) its block reads as if it were said of that character,
-- which it is not. F.Hushed fills such a tooltip in with the block left out: for the length
-- of the call its switch for it is off, and it is put back before anything else runs,
-- whatever happens in the call. This is asked whoever scores: the block is its to write
-- with the addon's own weights chosen as well. Without Forever Leveling BiS the tooltip is
-- filled in and no more.
-- fill: what fills the tooltip in; it is called with the arguments that follow it.
function F.Hushed(fill, ...)
    local kept = Kept()
    if not kept or hushed then
        fill(...)
        return
    end
    -- (As it is written down, not as it reads: a switch never touched is to be left so.)
    local before = rawget(kept, "tooltip")
    hushed = { block = before ~= false }
    kept.tooltip = false
    local ok, problem = pcall(fill, ...)
    rawset(kept, "tooltip", before)
    hushed = false
    if not ok then error(problem, 0) end
end

---------------------------------------------------------------------------
-- When its answers change
---------------------------------------------------------------------------
-- Another main spec chosen for the character, another way to fill its hands, a weight
-- changed, a level gained: every score made on its answers is out of date. It then calls
-- the functions other addons gave it (OnChanged), which is how one can tell; it calls them
-- for other reasons too (the gear changed, an item was loaded), which are nothing to the
-- scores. So what the scores rest on is kept (`seen`, and the weights that were asked for:
-- `asked`), and only when that has changed does the rest of the addon hear SCORING_CHANGED,
-- while Forever Leveling BiS scores: once for a burst of changes.
-- What it draws itself, the block in a tooltip and the arrows, is nothing to the scores,
-- and something to what this addon leaves out for it: SETTING_CHANGED "leveling" says so.
-- seen: { mine = the profile of the character being played; shows = what Forever Leveling
-- BiS draws itself }. nil until its specs are first asked for (F.Scales), before which
-- there are no such scores.

-- Its specs are being read to score with, for the first time or again: what changes about
-- them from now on is to be told.
function F.Watch()
    if seen then return end
    -- (Set before the main spec is asked for: asking looks here.)
    seen = { shows = ShowsText() }
    local own = Mine()
    seen.mine = own and own.id or nil
    -- (The weights of the character being played are among what the scores rest on, whether
    -- or not a sum was made of them here: ScoreItem goes by them. So they are asked for.)
    if own then Weights(own.id) end
end

-- whole: Forever Leveling BiS said that something changed, which may be anything.
-- Otherwise only what it is not heard about is in question: its two switches, or an answer
-- about the main spec that has grown old.
local function Look(whole)
    if whole then mine = nil end
    if not seen then return end
    if not F.Usable() or ns.Score.Engine() ~= "leveling" then
        -- Nobody scores by it now. What was kept of its answers is let go, and they are
        -- read anew when it scores again (F.Watch).
        if whole then
            seen, asked = nil, {}
            epoch = epoch + 1
        end
        return
    end
    local changed = false
    if whole then
        for name, got in pairs(asked) do
            local now = got and Ask(got.key) or nil
            if (now and now.text) ~= (got and got.text or nil) then changed = true end
            asked[name] = now or nil
        end
    end
    local shows = ShowsText()
    if shows ~= seen.shows then
        seen.shows = shows
        ns.Fire("SETTING_CHANGED", "leveling")
    end
    local own = Mine()
    local id = own and own.id or nil
    if id ~= seen.mine then
        seen.mine, changed = id, true
        -- (Its weights are another spec's now, whoever said so.)
        asked[MINE] = nil
    end
    if id then Weights(id) end
    if changed then
        epoch = epoch + 1
        ns.Fire("SCORING_CHANGED")
    end
end

local Changed = ns.Soon(0.2, function() Look(true) end)
Later = ns.Soon(0.2, function() Look(false) end)

-- A level gained: its weights are another level's now, and it may say so a moment before
-- the game gives the new level out.
ns.On("PLAYER_LEVEL_UP", function()
    C_Timer.After(1.5, Changed)
end)

local told
local function Hook()
    local api = Api()
    if not api or told == api or type(api.OnChanged) ~= "function" then return end
    told = api
    api.OnChanged(Changed)
end
Hook()
-- (Forever Leveling BiS may be loaded after this addon, when the player has it load on demand.)
ns.On("PLAYER_LOGIN", Hook)
