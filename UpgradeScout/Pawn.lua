local _, ns = ...

-- Pawn as the one who scores, for a player who would sooner go by their Pawn scales than by
-- this addon's own weights (Weights.lua). The choice is made in the welcome window
-- (Welcome.lua) and kept for the whole account; Score.lua, which the rest of the addon asks,
-- hands its questions on to this file while the choice stands and Pawn is there to be asked
-- (Score.Engine). Nothing of Pawn is carried here: its scales and its reading of an item are
-- asked for as they are in the player's own Pawn, each time.
--
-- What Pawn is asked: which scales a character has, what an item is worth on one of them,
-- and which lines of the item it could not turn into a number. Where an item goes and what
-- it would replace stays this addon's to say (Compare.lua), and so does whether a class can
-- wear it (Roster.Wields).
--
-- Throughout this file `who` is the character the question is about: a card from Roster for
-- one that is not being played, nil for the one that is.
local P = {}
ns.Pawn = P

-- Everything asked of Pawn is one of its own functions, named here, so that a Pawn that
-- renames one is taken for a Pawn that cannot be asked, not for an error in the middle of
-- a scan.
local REQUIRED = {
    "PawnIsReady",
    "PawnGetItemData",
    "PawnGetSingleValueFromItem",
    "PawnGetAllScalesEx",
    "PawnGetItemValue",
    "PawnGetAllStatValues",
}

-- Is Pawn there to be asked? Not while it is not installed or is switched off, and not in
-- the moments of logging in before it has read its scales.
function P.Usable()
    for i = 1, #REQUIRED do
        if type(_G[REQUIRED[i]]) ~= "function" then return false end
    end
    if type(PawnCommon) ~= "table" or type(PawnCommon.Scales) ~= "table" then return false end
    return PawnIsReady() and true or false
end

-- What Pawn keeps of a scale, for the whole account: its weights (Values), the characters
-- that have it switched on (PerCharacterOptions), and for one made from a class's template
-- the class and the talent tree (ClassID, SpecID). nil for a scale there is not: Pawn
-- answers a question about one of those with an error line in the chat, so none is asked.
local function Record(scale)
    local record = scale ~= nil and PawnCommon.Scales[scale] or nil
    if type(record) ~= "table" or type(record.Values) ~= "table" or type(record.PerCharacterOptions) ~= "table" then
        return nil
    end
    return record
end

---------------------------------------------------------------------------
-- Scales
---------------------------------------------------------------------------
-- The number Pawn knows each class by, and the class by its number.
local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
local CLASS_OF = {}
for class, id in pairs(CLASS_ID) do CLASS_OF[id] = class end

-- The name Pawn shows a scale by, and the same without the class it begins with ("Druid:
-- Balance", a scale Pawn made for a talent tree): the lists name the character, whose class
-- every such scale of its is for.
local function Long(scale)
    local record = Record(scale)
    local title = record and record.LocalizedName
    return type(title) == "string" and title ~= "" and title or tostring(scale)
end

function P.Title(scale)
    local title = Long(scale)
    local record = Record(scale)
    local class = record and CLASS_OF[record.ClassID or 0]
    if not class then return title end
    for _, name in ipairs({ LOCALIZED_CLASS_NAMES_MALE[class] or "", LOCALIZED_CLASS_NAMES_FEMALE[class] or "" }) do
        local prefix = name .. ": "
        if name ~= "" and #title > #prefix and title:sub(1, #prefix) == prefix then return title:sub(#prefix + 1) end
    end
    return title
end

-- The scales to choose from for a character: { { name = Pawn's name for the scale, title =
-- the name it is shown by }, ... }, in Pawn's own order.
-- For the character being played, the scales Pawn shows for it. For another one Pawn's notes
-- are read: it keeps, for the whole account, which scales each character has switched on,
-- and it carries the scales of every class. A character Pawn has no notes about gets the
-- scales of its class.
function P.Scales(who)
    local me = ns.Roster.Me()
    if who == me then who = nil end
    local owner = who or me
    local all = owner and PawnGetAllScalesEx() or nil
    if type(all) ~= "table" then return {} end
    -- From here on there may be scores that rest on the scales as they are now.
    P.Watch()

    local shown, ofClass = {}, {}
    local classID = CLASS_ID[owner.class or ""]
    for i = 1, #all do
        local scale = all[i]
        local record = Record(scale.Name)
        if record then
            local entry = { name = scale.Name, title = P.Title(scale.Name) }
            local visible
            if who then
                local notes = record.PerCharacterOptions[who.key]
                visible = type(notes) == "table" and notes.Visible
            else
                visible = scale.IsVisible
            end
            if visible then shown[#shown + 1] = entry end
            if classID ~= nil and record.ClassID == classID then ofClass[#ofClass + 1] = entry end
        end
    end
    if who and #shown == 0 then shown = ofClass end

    -- Two that would read the same without their class keep it.
    local count = {}
    for i = 1, #shown do count[shown[i].title] = (count[shown[i].title] or 0) + 1 end
    for i = 1, #shown do
        if count[shown[i].title] > 1 then shown[i].title = Long(shown[i].name) end
    end
    return shown
end

-- The talent tree a scale of Pawn's own is for, by the profile this addon has for the tree
-- (Weights.classes; a character's card names the profile for its talents): the place of the
-- tree among the class's, as Pawn numbers them. That is the profile's place among its
-- class's here too (a druid has four of both: its Feral tree for a cat and for a bear),
-- except for a priest, who has three trees in Pawn and two profiles here.
local SPEC = { PRIEST_HEALER = 2, PRIEST_SHADOW = 3 }

local function SpecOf(card)
    local talents = card.talents
    if talents == nil then return nil end
    if SPEC[talents] then return SPEC[talents] end
    local ids = ns.Weights.classes[card.class or ""]
    for i = 1, #(ids or {}) do
        if ids[i] == talents then return i end
    end
    return nil
end

-- The scale to score with for a character: the one chosen for it, if it is still among its
-- scales; otherwise the one Pawn has for the talent tree it had the most points in when it
-- was last played; otherwise the first of them. Returns it and the list, as Score.Current.
function P.Current(who)
    local list = P.Scales(who)
    local owner = who or ns.Roster.Me()
    if not owner then return nil, list end
    local chosen = owner.scale
    local classID, specID = CLASS_ID[owner.class or ""], SpecOf(owner)
    local byTalents
    for i = 1, #list do
        if list[i].name == chosen then return list[i], list end
        local record = Record(list[i].name)
        if not byTalents and specID and record.ClassID == classID and record.SpecID == specID then
            byTalents = list[i]
        end
    end
    return byTalents or list[1], list
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
-- Does the item add anything, by the game's own count: its stats, and what it gives through
-- a spell it keeps on its wearer (as Score.Item reads it for the addon's own weights)? True
-- as well while the game has no answer.
local function AddsAnything(itemID, bare)
    local stats = ns.Stats.Read(bare)
    if not stats then return true end
    return next(stats) ~= nil or ns.GearData.extra[itemID] ~= nil
end

-- What there is to score about an item link, in the shape Score.Item gives it, with Pawn's
-- own record of the item in place of the stats: { link, itemID, invType, classID,
-- subClassID, pawn }. The item is read as it would be for sale, without an enchantment, as
-- Pawn's own upgrade arrows read it. nil while there is no answer yet: the client has not
-- loaded the item, or Pawn could not read it this time.
-- Pawn keeps no record of an item that adds nothing (a trinket that is only used), nor of a
-- kind it never reads (a shirt, a tabard). That is its answer, and it stands: `pawn` is
-- false and the item scores nothing. Such an item is often worn, and taken for one still to
-- be read it would keep the gear from ever being whole (Score.Context), and with it every
-- arrow out of the bags.
function P.Item(link)
    local itemID, _, _, invType, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
    if not itemID then return nil end
    local bare = ns.Stats.Bare(link)
    if not C_Item.GetItemInfo(bare) then return nil end
    local record = PawnGetItemData(bare)
    if type(record) ~= "table" then
        local reads = type(PawnCanItemHaveStats) ~= "function" or PawnCanItemHaveStats(bare)
        if reads and AddsAnything(itemID, bare) then return nil end
        record = false
    end
    return {
        link = link, itemID = itemID, invType = invType, classID = classID, subClassID = subClassID,
        pawn = record,
    }
end

-- An item's score on a scale: Pawn's number for the item without enchantments. 0 for a
-- scale there is not.
function P.Value(item, scale)
    if not item.pawn or not Record(scale) then return 0 end
    local value, base = PawnGetSingleValueFromItem(item.pawn, scale)
    return base or value or 0
end

-- A line of a tooltip as two of them are compared: Pawn takes the colour off some lines
-- before it reads them, and in French puts plain spaces for the ones that do not break.
local function Plain(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\194\160", " ")
    return (text:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", ""))
end

-- Is this line of the item's tooltip one Pawn could not turn into a number? `text` is a line
-- the game gives the item for a spell of its own: a use, a chance on hit, what it does while
-- worn (Score.HasUnscoredEffects). Pawn keeps what it did not understand: the line, or the
-- piece it stumbled on where it took the line apart at its commas.
-- That list alone does not tell an effect. Pawn reads a tooltip of its own, and the game
-- lets every addon write in it as in any other: one that puts an item's number under each
-- item (EllesmereUI's "ItemID" and "IconID") leaves lines there that Pawn cannot read, and by
-- the list every item would have an effect. So the question is asked of the game's lines.
function P.Unread(item, text)
    local unknown = item.pawn and item.pawn.UnknownLines
    if type(unknown) ~= "table" or type(text) ~= "string" then return false end
    local line = Plain(text)
    for part in pairs(unknown) do
        if type(part) == "string" then
            part = Plain(part)
            if part ~= "" and line:find(part, 1, true) then return true end
        end
    end
    return false
end

-- The sum stat by stat, for /upscout stats: { { name, amount, weight, points }, ... } with
-- the heaviest first, and Pawn's own total, which is not always their sum (a scale may be
-- set to bring its numbers to a common size, and a stat it rules out makes the item worth
-- nothing). The stats go by Pawn's names for them.
function P.Parts(item, scale)
    local record = Record(scale)
    local parts = {}
    local stats = item.pawn and (item.pawn.UnenchantedStats or item.pawn.Stats)
    if record and type(stats) == "table" then
        for name, amount in pairs(stats) do
            local weight = record.Values[name]
            if type(amount) == "number" and type(weight) == "number" then
                parts[#parts + 1] = { name = name, label = name, amount = amount, weight = weight, points = amount * weight }
            end
        end
    end
    table.sort(parts, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        return a.name < b.name
    end)
    return parts, P.Value(item, scale)
end

---------------------------------------------------------------------------
-- A set of stats that is not an item
---------------------------------------------------------------------------
-- What a consumable adds is written down under the game's names for the stats of gear, a
-- chance as the rating that gives it at level 60 (SupplyData.lua). Pawn has names of its
-- own, and in this game reads a chance as a percentage. Below: the game's name -> Pawn's
-- name, and for a chance the points of rating in one percent.
--
-- In this game a scale of Pawn's has one weight for a chance, whatever it is a chance with,
-- as a piece of gear has one rating for it. A consumable can add a chance with weapons only
-- or with spells only (`with`): that counts on a scale of the kind that would use it (see
-- Caster). Attack power goes under the name gear's has in Pawn, which a hunter's scale
-- weighs as well.
local function Mod(name)
    return "ITEM_MOD_" .. name .. "_SHORT"
end

local NAMES = {
    [Mod("STRENGTH")] = { to = "Strength" },
    [Mod("AGILITY")] = { to = "Agility" },
    [Mod("STAMINA")] = { to = "Stamina" },
    [Mod("INTELLECT")] = { to = "Intellect" },
    [Mod("SPIRIT")] = { to = "Spirit" },
    [Mod("HEALTH")] = { to = "Health" },
    [Mod("MANA")] = { to = "Mana" },
    [Mod("HEALTH_REGENERATION")] = { to = "Hp5" },
    [Mod("MANA_REGENERATION")] = { to = "Mp5" },
    [Mod("ATTACK_POWER")] = { to = "Ap" },
    [Mod("MELEE_ATTACK_POWER")] = { to = "Ap" },
    [Mod("RANGED_ATTACK_POWER")] = { to = "Rap" },
    [Mod("SPELL_DAMAGE_DONE")] = { to = "SpellDamage" },
    [Mod("SPELL_HEALING_DONE")] = { to = "Healing" },
    [Mod("HOLY_DAMAGE_DONE")] = { to = "HolySpellDamage" },
    [Mod("FIRE_DAMAGE_DONE")] = { to = "FireSpellDamage" },
    [Mod("NATURE_DAMAGE_DONE")] = { to = "NatureSpellDamage" },
    [Mod("FROST_DAMAGE_DONE")] = { to = "FrostSpellDamage" },
    [Mod("SHADOW_DAMAGE_DONE")] = { to = "ShadowSpellDamage" },
    [Mod("ARCANE_DAMAGE_DONE")] = { to = "ArcaneSpellDamage" },
    RESISTANCE0_NAME = { to = "Armor" },
    RESISTANCE2_NAME = { to = "FireResist" },
    RESISTANCE3_NAME = { to = "NatureResist" },
    RESISTANCE4_NAME = { to = "FrostResist" },
    RESISTANCE5_NAME = { to = "ShadowResist" },
    RESISTANCE6_NAME = { to = "ArcaneResist" },
    [Mod("CRIT_RATING")] = { to = "CritRating", per = 14 },
    [Mod("CRIT_MELEE_RATING")] = { to = "CritRating", per = 14, with = "weapons" },
    [Mod("CRIT_SPELL_RATING")] = { to = "CritRating", per = 14, with = "spells" },
    [Mod("HIT_RATING")] = { to = "HitRating", per = 10 },
    [Mod("HIT_MELEE_RATING")] = { to = "HitRating", per = 10, with = "weapons" },
    [Mod("HIT_SPELL_RATING")] = { to = "HitRating", per = 10, with = "spells" },
    [Mod("HASTE_RATING")] = { to = "HasteRating", per = 10 },
    [Mod("HASTE_MELEE_RATING")] = { to = "HasteRating", per = 10, with = "weapons" },
    [Mod("HASTE_SPELL_RATING")] = { to = "HasteRating", per = 10, with = "spells" },
    [Mod("DODGE_RATING")] = { to = "DodgeRating", per = 12 },
    [Mod("PARRY_RATING")] = { to = "ParryRating", per = 15 },
    [Mod("BLOCK_RATING")] = { to = "BlockRating", per = 5 },
}

-- Is the scale a spell caster's? It is when Intellect, Spirit, spell damage and healing
-- together weigh more on it than Strength, Agility and attack power do. (That sorts every
-- scale Pawn 2.14.3 comes with for this game the way its name says.)
local function Caster(weights)
    local function Sum(...)
        local total = 0
        for i = 1, select("#", ...) do
            local weight = weights[(select(i, ...))]
            if type(weight) == "number" and weight > 0 then total = total + weight end
        end
        return total
    end
    return Sum("Intellect", "Spirit", "SpellDamage", "Healing") > Sum("Strength", "Agility", "Ap", "Rap")
end

-- Pawn has no weight for these two on any scale in this game. Health counts as the Stamina
-- that gives it, at the rate Pawn itself takes for "+100 health" on gear, and mana as
-- Intellect.
local HEALTH_PER_STAMINA = 12.5
local MANA_PER_INTELLECT = 15

-- Pawn's score for a set of stats that is not an item: what an elixir adds, say. The same
-- sum Pawn makes for an item, so the number is in the points gear is scored in. nil for a
-- scale there is not.
function P.StatsValue(stats, scale)
    local record = Record(scale)
    if not record then return nil end
    local weights = record.Values

    local set, caster = {}, nil
    for name, amount in pairs(stats) do
        local entry = NAMES[name]
        local counts = entry ~= nil
        if counts and entry.with then
            if caster == nil then caster = Caster(weights) end
            counts = caster == (entry.with == "spells")
        end
        if counts then set[entry.to] = (set[entry.to] or 0) + amount / (entry.per or 1) end
    end
    if set.Health and not weights.Health then
        set.Stamina = (set.Stamina or 0) + set.Health / HEALTH_PER_STAMINA
        set.Health = nil
    end
    if set.Mana and not weights.Mana then
        set.Intellect = (set.Intellect or 0) + set.Mana / MANA_PER_INTELLECT
        set.Mana = nil
    end
    -- The arguments Pawn itself passes for an item on a scale it does not show.
    local value = PawnGetItemValue(set, nil, nil, scale, false, false, true)
    return type(value) == "number" and value or nil
end

---------------------------------------------------------------------------
-- A scale's say on weapons
---------------------------------------------------------------------------
-- A scale of Pawn's can be told not to show upgrades for one-handed weapons (and what goes
-- with them: a shield, something held in the off hand), or for two-handed ones: a tank's
-- scale is not to offer a two-hander. Compare.lua keeps to it (ctx.show1H, ctx.show2H).
function P.ShowsWeapons(scale)
    local record = Record(scale)
    if not record then return true, true end
    return not record.DoNotShow1HUpgrades, not record.DoNotShow2HUpgrades
end

---------------------------------------------------------------------------
-- Pawn's own lines in a tooltip
---------------------------------------------------------------------------
-- Pawn writes into every item tooltip how much of an upgrade the item is, and means the
-- character being played: it knows of no other. Under an item picked for another character
-- of the account (a row of a list made for one, and what that one wears beside it) that
-- reads as if it were said of that character, which it is not.
-- P.Hushed fills such a tooltip in with Pawn left nothing to say: for the length of the call
-- Pawn's own two options for its lines stand at "no upgrades" and "a scale's value only with
-- an upgrade", and they are put back before anything else runs, whatever happens in the
-- call. The rest of what Pawn does about a tooltip goes on: it takes back a border it had
-- coloured, and keeps track of the item under the mouse. This is asked whoever scores: the
-- lines are Pawn's to write with the addon's own weights chosen as well. Without Pawn the
-- tooltip is filled in and no more.
-- fill: what fills the tooltip in; it is called with the arguments that follow it.
function P.Hushed(fill, ...)
    local options = PawnCommon
    if type(options) ~= "table" then
        fill(...)
        return
    end
    local upgrades, sparing = options.ShowUpgradesOnTooltips, options.ShowValuesForUpgradesOnly
    options.ShowUpgradesOnTooltips, options.ShowValuesForUpgradesOnly = false, true
    local ok, problem = pcall(fill, ...)
    options.ShowUpgradesOnTooltips, options.ShowValuesForUpgradesOnly = upgrades, sparing
    if not ok then error(problem, 0) end
end

---------------------------------------------------------------------------
-- When Pawn's scales change
---------------------------------------------------------------------------
-- A scale switched on or off, made, taken away or given other weights, in Pawn's own
-- window: every score made on its scales is out of date, and so may be the list of them.
-- Pawn calls PawnResetTooltips whenever any of that happens, and also when the player
-- changes how its tooltips look, which is nothing to the scores. So what the scores rest on
-- is kept as one text (Snapshot), and only when that has changed does the rest of the addon
-- hear SCORING_CHANGED, while Pawn scores: once for a burst of changes.
local seen      -- the snapshot the scores made so far rest on; nil until Pawn is first asked
                -- for a character's scales (P.Scales), before which there are no such scores

-- Every scale by name, in order, with its weights, the characters it is switched on for and
-- its say on weapons.
local function Snapshot()
    local scales = {}
    for name, record in pairs(PawnCommon.Scales) do
        if type(record) == "table" then
            local parts = {}
            for stat, weight in pairs(type(record.Values) == "table" and record.Values or {}) do
                parts[#parts + 1] = tostring(stat) .. "=" .. tostring(weight)
            end
            for who, notes in pairs(type(record.PerCharacterOptions) == "table" and record.PerCharacterOptions or {}) do
                if type(notes) == "table" and notes.Visible then parts[#parts + 1] = "@" .. tostring(who) end
            end
            table.sort(parts)
            scales[#scales + 1] = table.concat({
                tostring(name), tostring(record.LocalizedName), tostring(record.NormalizationFactor),
                tostring(record.DoNotShow1HUpgrades), tostring(record.DoNotShow2HUpgrades), table.concat(parts, ","),
            }, "\t")
        end
    end
    table.sort(scales)
    return table.concat(scales, "\n")
end

-- The scales are being read to score with, for the first time or again: what changes about
-- them from now on is to be told.
function P.Watch()
    if seen == nil then seen = Snapshot() end
end

local Changed = ns.Soon(0.2, function()
    if seen == nil or not P.Usable() then return end
    local now = Snapshot()
    if now == seen then return end
    seen = now
    if ns.Score.Engine() then ns.Fire("SCORING_CHANGED") end
end)

local hooked = false
local function Hook()
    if hooked or type(PawnResetTooltips) ~= "function" then return end
    hooked = true
    hooksecurefunc("PawnResetTooltips", Changed)
end
Hook()
-- (Pawn may be loaded after this addon, when the player has it load on demand.)
ns.On("PLAYER_LOGIN", Hook)
