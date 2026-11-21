local _, ns = ...

-- Forever Companion as the one who scores, for a player who would sooner go by the gear
-- scales of that addon than by this addon's own weights (Weights.lua). The choice is made in
-- the welcome window (Welcome.lua) and kept for the whole account; Score.lua, which the rest
-- of the addon asks, hands its questions on to this file while the choice stands and Forever
-- Companion is there to be asked (Score.Engine). It is the second such addon, after Pawn
-- (Pawn.lua), and answers the same questions in the same form.
--
-- Nothing of Forever Companion is carried here: its scales and its reading of an item are
-- asked for as they are in the player's own copy, each time. Written after its version
-- 0.5.1, where gear is scored in its Scales.lua:
--   * A scale is a set of weights under Pawn's names for the stats, with a key ("wh:18" for
--     one that comes with the addon, "my:3" for one the player made), the name it is shown
--     by, and the talent tree it is for, by the tree's place among its class's. The ones the
--     player made are kept for the whole account.
--   * A character has one scale in use: the one chosen for it in Forever Companion's options,
--     or, with none chosen, the one for the tree its talents are in.
--   * An item's value is the sum of its stats times the weights. The stats are Forever
--     Companion's own reading of the item: a chance to hit or to crit as percent, where the
--     game counts rating.
--   * It writes one line into an item's tooltip, for the scale in use, and draws an arrow of
--     its own on an upgrade: on quest rewards and loot, and in the bags, the bank and a
--     merchant's window. Each of those has a switch in its options.
--   * It writes its lists of the best gear into an item's tooltip as well: where the item
--     stands in them for each talent tree the player follows there. That has a switch too.
--
-- Its reading of an item is scored as it stands, also where it is known to be off. It reads
-- a chance as percent from the words of the tooltip, which it knows in English and in
-- French; in the other languages of the game it takes the game's count of rating in their
-- place and scores that as percent, fourteen times too much for a chance to crit. (Seen in
-- the game in Russian, with 0.5.1: gloves with 1% to crit at 406 points on a scale that
-- gives a percent 29.) That is not put right here, on purpose. A player who chose Forever
-- Companion to score sees its number in its own line of a tooltip, and a list of this addon
-- that said another for the same item would not be trusted: they are shown what it shows.
-- It is Forever Companion's to put right. (The owner's decision, 2026-11-16; a correction
-- was written and taken back, commits 7183c4e and its revert.)
--
-- What Forever Companion is asked: which scales a class has, which one the character being
-- played has in use, and what it reads of an item. Where an item goes and what it would
-- replace stays this addon's to say (Compare.lua), and so does whether a class can wear it
-- (Roster.Wields): Forever Companion tells an upgrade for the character being played alone.
--
-- Throughout this file `who` is the character the question is about: a card from Roster for
-- one that is not being played, nil for the one that is.
local C = {}
ns.Companion = C

-- The addon by its own name, as the welcome window and the tooltips write it.
C.NAME = "Forever Companion"

-- The words of ours that are about this addon, by what they are for (Score.Text).
C.TEXT = {
    SCORE = "TT_COMPANION_SCORE",
    TIP = "PROFILE_TIP_COMPANION",
    NO_SCALE = "ERR_NO_SCALE_COMPANION",
    ABSENT = "WELCOME_NO_COMPANION",
    ASK = "WELCOME_SCALE_COMPANION",
    NONE = "WELCOME_NO_SCALE_COMPANION",
    WRITES = "WELCOME_TOOLTIP_COMPANION",
    WRITES_OTHERS = "WELCOME_TOOLTIP_COMPANION_OTHERS",
    NEW = "WELCOME_COMPANION_NEW",
    ARROWS = "WELCOME_ARROWS_COMPANION",
}
-- What the account remembers of having seen the choice of who scores with this addon there.
C.OFFERED = "companionOffered"

-- Everything asked of Forever Companion is one of the functions of its Scales, named here,
-- so that a version that renames one is taken for an addon that cannot be asked, not for an
-- error in the middle of a scan.
local REQUIRED = { "ForClass", "Active", "ReadItem", "Score" }

-- Is Forever Companion there to be asked? Not while it is not installed or is switched off,
-- and not before it has opened what it keeps (its `db`, made as it loads).
function C.Usable()
    local addon = ForeverCompanion
    if type(addon) ~= "table" or type(addon.Scales) ~= "table" then return false end
    for i = 1, #REQUIRED do
        if type(addon.Scales[REQUIRED[i]]) ~= "function" then return false end
    end
    local db = addon.db
    return type(db) == "table" and type(db.char) == "table" and type(db.global) == "table"
end

-- Its options for the whole account, where it is installed; nil where it is not.
local function Options()
    local addon = ForeverCompanion
    local db = type(addon) == "table" and addon.db or nil
    local global = type(db) == "table" and db.global or nil
    return type(global) == "table" and global or nil
end

---------------------------------------------------------------------------
-- Scales
---------------------------------------------------------------------------
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- The scales of a class as Forever Companion lists them: the ones that come with it, then
-- the player's own (one made for no class is listed for every class).
local function Listed(class)
    local list = ForeverCompanion.Scales.ForClass(class)
    return type(list) == "table" and list or {}
end

-- What is kept of a scale, by its key, whatever class it is for: { title, tab, weights,
-- own = the player made it }. The weights are the scale's own table, so a weight changed in
-- Forever Companion's window is the weight here. Made when first asked for and again when
-- the scales have changed (see "When Forever Companion's scales change").
local byKey

local function Keep(scale)
    if type(scale) ~= "table" or scale.key == nil or type(scale.w) ~= "table" then return nil end
    local record = {
        title = tostring(scale.label or scale.key),
        tab = type(scale.tab) == "number" and scale.tab or nil,
        weights = scale.w,
        own = not scale.wowhead,
    }
    byKey[scale.key] = record
    return record
end

local function Record(key)
    if key == nil then return nil end
    if not byKey then
        byKey = {}
        for i = 1, #CLASSES do
            for _, scale in ipairs(Listed(CLASSES[i])) do Keep(scale) end
        end
    end
    return byKey[key]
end

-- The name a scale is shown by: Forever Companion's own.
function C.Title(key)
    local record = Record(key)
    return record and record.title or tostring(key)
end

-- The scales to choose from for a character: { { name = the scale's key, title = the name
-- it is shown by }, ... }, in Forever Companion's own order. They are the scales of the
-- character's class, the same whoever is being played.
function C.Scales(who)
    local owner = who or ns.Roster.Me()
    if not owner or not owner.class then return {} end
    -- From here on there may be scores that rest on the scales as they are now.
    C.Watch()
    if not byKey then Record("") end
    local out = {}
    for _, scale in ipairs(Listed(owner.class)) do
        local record = Keep(scale)
        if record then out[#out + 1] = { name = scale.key, title = record.title } end
    end
    return out
end

-- The key of the scale the character being played has in use, as Forever Companion says it:
-- the one chosen in its options, or the one for its talents. Working that out reads every
-- talent of the character, and the question is asked many times a second (each time a
-- tooltip is drawn), so the answer is kept for a moment. It is asked again at once when
-- Forever Companion says something changed, or the talents did (see Look below); and an
-- answer that turns out new without either is told the same way.
local ACTIVE_FOR = 2            -- seconds an answer is kept
local active, activeAt
local seen                      -- (see "When Forever Companion's scales change")
local Later                     -- (defined with Look)

local function ActiveKey()
    local now = GetTime()
    if active == nil or now - activeAt > ACTIVE_FOR then
        local scale = ForeverCompanion.Scales.Active()
        active, activeAt = type(scale) == "table" and scale.key or false, now
        if seen and seen.active ~= nil and seen.active ~= (active or nil) then Later() end
    end
    return active or nil
end

-- The scale chosen in Forever Companion's own options for another character of the account,
-- which it keeps under the character's name and the kind of realm it is on. That kind is
-- known for the character being played alone, so it is taken to be the same for a character
-- of the same realm. nil where nothing was chosen, or nothing can be told.
local function Saved(who)
    local db = ForeverCompanion.db
    local saved, keys = db.sv, db.keys
    if type(saved) ~= "table" or type(saved.char) ~= "table" or type(keys) ~= "table" then return nil end
    local me = ns.Roster.Me()
    if not me or type(who.name) ~= "string" or not ns.Roster.SameRealm(who, me) then return nil end
    local theirs = saved.char[who.name .. " - " .. tostring(keys.realm)]
    return type(theirs) == "table" and theirs.scale or nil
end

-- The talent tree a character's talents are in, by its place among its class's from the
-- left: what a scale's `tab` is. A card names the profile this addon has for the tree
-- (Roster.Update), whose place among its class's profiles is the tree's, but for the two
-- classes with other profiles than trees: a priest's two for three trees, a druid's four.
local TREE = { PRIEST_HEALER = 2, PRIEST_SHADOW = 3, DRUID_FERAL_BEAR = 2, DRUID_RESTORATION = 3 }

local function TreeOf(card)
    local talents = card.talents
    if talents == nil then return nil end
    if TREE[talents] then return TREE[talents] end
    local ids = ns.Weights.classes[card.class or ""]
    for i = 1, #(ids or {}) do
        if ids[i] == talents then return i end
    end
    return nil
end

-- The scale Forever Companion would pick by itself for a character with these talents: the
-- first that comes with it for the tree; where the tree has none (a priest's Discipline),
-- the first for healing or for damage, as it does itself; the first of them all otherwise.
local HEALS = { PRIEST = { [1] = true } }

local function ByTalents(who, list)
    local tree = TreeOf(who)
    local first, sameRole
    local heals = tree ~= nil and HEALS[who.class or ""] ~= nil and HEALS[who.class][tree] == true
    for i = 1, #list do
        local record = Record(list[i].name)
        if record and not record.own then
            if tree and record.tab == tree then return list[i] end
            first = first or list[i]
            local label = record.title:lower()
            local healer, tank = label:find("heal", 1, true) ~= nil, label:find("tank", 1, true) ~= nil
            if not sameRole and not tank and healer == heals then sameRole = list[i] end
        end
    end
    return sameRole or first
end

-- The scale to score with for a character, and the scales it was chosen from, as
-- Score.Current. For the character being played it is the one Forever Companion has in use:
-- its own line in a tooltip and its own arrows go by that one, and a list on another would
-- contradict them. For another character: the one chosen for it in this addon's field, if
-- it is still among its scales; otherwise the one chosen for it in Forever Companion;
-- otherwise the one for its talents.
function C.Current(who)
    if who ~= nil and who == ns.Roster.Me() then who = nil end
    local list = C.Scales(who)
    if #list == 0 then return nil, list end
    local function Find(key)
        if key == nil then return nil end
        for i = 1, #list do
            if list[i].name == key then return list[i] end
        end
    end
    if not who then return Find(ActiveKey()) or list[1], list end
    return Find(who.companion) or Find(Saved(who)) or ByTalents(who, list) or list[1], list
end

-- The scale chosen for a character (its card) in this addon's field or welcome window. For
-- the character being played that is a choice of the scale Forever Companion has in use,
-- and is made there: its options say so afterwards, and its own arrows are drawn again.
-- For another character it is written on the card.
function C.Choose(card, key)
    if card ~= ns.Roster.Me() then
        card.companion = key
        return
    end
    card.companion = nil
    local addon = ForeverCompanion
    addon.db.char.scale = key
    active, activeAt = key, GetTime()
    -- Forever Companion is told to draw its marks again, which this file hears as well (see
    -- Hook): what it would find new is what was just chosen, and is no news. (Its function
    -- is called on its own: an error in it is reported and does not undo the choice.)
    if seen then seen.active = key end
    if type(addon.RefreshScaleOverlays) == "function" then securecallfunction(addon.RefreshScaleOverlays, addon) end
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
-- What there is to score about an item link, in the shape Score.Item gives it, with Forever
-- Companion's reading of the item (`companion`: { stats = { [its name for a stat] = amount } })
-- in place of the stats. The item is read as it would be for sale, without an enchantment.
-- nil while there is no answer yet: the client has not loaded the item.
-- An item of a kind that is not gear (a shirt, a tabard) has nothing to read: `companion`
-- is false and the item scores nothing. That is an answer, and it stands: such an item is
-- often worn, and taken for one still to be read it would keep the gear from ever being
-- whole (Score.Context).
function C.Item(link)
    local itemID, _, _, invType, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
    if not itemID then return nil end
    local read = false
    if ns.Compare.Handles(invType) then
        local bare = ns.Stats.Bare(link)
        if not C_Item.GetItemInfo(bare) then return nil end
        -- Forever Companion reads the lines of the item's tooltip. From a tooltip the game
        -- has not filled in yet it makes what it can, without saying that it is a part: so
        -- the tooltip is waited for here.
        local tip = C_TooltipInfo.GetHyperlink(bare)
        local lines = tip and tip.lines
        if type(lines) ~= "table" or #lines < 2 then return nil end
        local got, wait = ForeverCompanion.Scales.ReadItem(bare)
        if type(got) == "table" and type(got.stats) == "table" then
            read = got
        elseif wait then
            return nil
        end
    end
    return {
        link = link, itemID = itemID, invType = invType, classID = classID, subClassID = subClassID,
        scorer = C, companion = read,
    }
end

-- An item's score on a scale: Forever Companion's own sum. 0 for a scale there is not.
function C.Value(item, key)
    local record = Record(key)
    if not item.companion or not record then return 0 end
    local value = ForeverCompanion.Scales.Score(item.companion.stats, record.weights)
    return type(value) == "number" and value or 0
end

-- The sum stat by stat, for /upscout stats: { { name, label, amount, weight, points }, ... }
-- with the heaviest first, and the total. A stat goes by Forever Companion's word for it.
function C.Parts(item, key)
    local record = Record(key)
    local parts = {}
    local labels = ForeverCompanion.Scales.LABEL
    if record and item.companion then
        for name, amount in pairs(item.companion.stats) do
            local weight = record.weights[name]
            if type(amount) == "number" and type(weight) == "number" then
                local label = type(labels) == "table" and labels[name] or name
                parts[#parts + 1] = { name = name, label = label, amount = amount, weight = weight, points = amount * weight }
            end
        end
    end
    table.sort(parts, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        return a.name < b.name
    end)
    return parts, C.Value(item, key)
end

-- A line of a tooltip as Forever Companion compares them: in small letters, without colour,
-- and without the accents of French, by its own function for that where it has one.
local function Plain(text)
    local api = ForeverCompanionAPI
    if type(api) == "table" and type(api.SearchNorm) == "function" then
        text = api.SearchNorm(text)
    else
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
    end
    return (text:gsub("\194\160", " "))
end

-- Is this line of the item's tooltip one the score does not count? `text` is a line the
-- game gives the item for a spell of its own (Score.HasUnscoredEffects); `worn` says that
-- it is what the item does while worn, and not a use or a chance on hit, of which Forever
-- Companion reads none. A line of what the item does while worn it reads where it knows the
-- words (attack power, spell damage and the like, in English and in French), and is asked
-- about by its own function for that. Where it has none, no such line counts.
function C.Unread(_, text, worn)
    if not worn or type(text) ~= "string" then return true end
    local parse = ForeverCompanion.Scales.ParseEquip
    local prefix = ITEM_SPELL_TRIGGER_ONEQUIP
    if type(parse) ~= "function" or type(prefix) ~= "string" or prefix == "" then return true end
    local line = Plain(text)
    prefix = Plain(prefix)
    if line:sub(1, #prefix) ~= prefix then return true end
    return parse((line:sub(#prefix + 1):gsub("^%s+", ""))) == nil
end

---------------------------------------------------------------------------
-- A set of stats that is not an item
---------------------------------------------------------------------------
-- What a consumable adds is written down under the game's names for the stats of gear, a
-- chance as the rating that gives it at level 60 (SupplyData.lua). Forever Companion has
-- Pawn's names, and reads a chance as a percentage. Below: the game's name -> its name, and
-- for a chance the points of rating in one percent.
--
-- The scales that come with Forever Companion have one weight for a chance, whatever it is
-- a chance with. A consumable can add a chance with weapons only or with spells only
-- (`with`): that counts on a scale of the kind that would use it (see Caster). A chance
-- with spells has a name of its own as well (`own`), which a scale the player made may
-- weigh: on such a scale it counts under that name.
local function Mod(name)
    return "ITEM_MOD_" .. name .. "_SHORT"
end

local NAMES = {
    [Mod("STRENGTH")] = { to = "Strength" },
    [Mod("AGILITY")] = { to = "Agility" },
    [Mod("STAMINA")] = { to = "Stamina" },
    [Mod("INTELLECT")] = { to = "Intellect" },
    [Mod("SPIRIT")] = { to = "Spirit" },
    [Mod("HEALTH_REGENERATION")] = { to = "Hp5" },
    [Mod("MANA_REGENERATION")] = { to = "Mp5" },
    [Mod("ATTACK_POWER")] = { to = "Ap" },
    [Mod("MELEE_ATTACK_POWER")] = { to = "Ap" },
    [Mod("RANGED_ATTACK_POWER")] = { to = "Rap" },
    [Mod("HOLY_DAMAGE_DONE")] = { to = "HolySpellDamage" },
    [Mod("FIRE_DAMAGE_DONE")] = { to = "FireSpellDamage" },
    [Mod("NATURE_DAMAGE_DONE")] = { to = "NatureSpellDamage" },
    [Mod("FROST_DAMAGE_DONE")] = { to = "FrostSpellDamage" },
    [Mod("SHADOW_DAMAGE_DONE")] = { to = "ShadowSpellDamage" },
    [Mod("ARCANE_DAMAGE_DONE")] = { to = "ArcaneSpellDamage" },
    [Mod("SPELL_PENETRATION")] = { to = "SpellPenetration" },
    RESISTANCE0_NAME = { to = "Armor" },
    [Mod("CRIT_RATING")] = { to = "CritRating", per = 14 },
    [Mod("CRIT_MELEE_RATING")] = { to = "CritRating", per = 14, with = "weapons" },
    [Mod("CRIT_SPELL_RATING")] = { to = "CritRating", per = 14, with = "spells", own = "SpellCritRating" },
    [Mod("HIT_RATING")] = { to = "HitRating", per = 10 },
    [Mod("HIT_MELEE_RATING")] = { to = "HitRating", per = 10, with = "weapons" },
    [Mod("HIT_SPELL_RATING")] = { to = "HitRating", per = 10, with = "spells", own = "SpellHitRating" },
    [Mod("DODGE_RATING")] = { to = "DodgeRating", per = 12 },
    [Mod("PARRY_RATING")] = { to = "ParryRating", per = 15 },
    [Mod("BLOCK_RATING")] = { to = "BlockRating", per = 5 },
}
local SPELL_DAMAGE, SPELL_HEALING = Mod("SPELL_DAMAGE_DONE"), Mod("SPELL_HEALING_DONE")
local HEALTH, MANA = Mod("HEALTH"), Mod("MANA")

-- Is the scale a spell caster's? It is when Intellect, Spirit and what adds to spells
-- together weigh more on it than Strength, Agility and attack power do. (That sorts every
-- scale Forever Companion 0.5.1 comes with the way its name says.)
local function Caster(weights)
    local function Sum(...)
        local total = 0
        for i = 1, select("#", ...) do
            local weight = weights[(select(i, ...))]
            if type(weight) == "number" and weight > 0 then total = total + weight end
        end
        return total
    end
    return Sum("Intellect", "Spirit", "SpellPower", "SpellDamage", "Healing") > Sum("Strength", "Agility", "Ap", "Rap")
end

-- Forever Companion has no stat for these two. Health counts as the Stamina that gives it,
-- and mana as Intellect, at the game's own rates.
local HEALTH_PER_STAMINA = 10
local MANA_PER_INTELLECT = 15

-- The score of a set of stats that is not an item: what an elixir adds, say. The same sum
-- Forever Companion makes for an item, so the number is in the points gear is scored in.
-- nil for a scale there is not.
function C.StatsValue(stats, key)
    local record = Record(key)
    if not record then return nil end
    local weights = record.weights

    local set, caster = {}, nil
    local function Add(name, amount)
        if amount ~= 0 then set[name] = (set[name] or 0) + amount end
    end
    for name, amount in pairs(stats) do
        local entry = NAMES[name]
        if entry then
            local to = entry.to
            if entry.own and weights[entry.own] then
                to = entry.own
            elseif entry.with then
                if caster == nil then caster = Caster(weights) end
                if caster ~= (entry.with == "spells") then to = nil end
            end
            if to then Add(to, amount / (entry.per or 1)) end
        end
    end
    -- What adds to spells. Forever Companion has "spell power" for what adds to damage and
    -- to healing alike, as most gear does, and names of their own for what adds to the one
    -- only. A caster's scale of its weighs spell power and no spell damage: the damage is
    -- what the spell power is for. So damage alone counts as spell power on a scale that
    -- has no weight for it and none for healing (a healer's has one, and no use for damage).
    local damage, healing = stats[SPELL_DAMAGE] or 0, stats[SPELL_HEALING] or 0
    local both = math.min(damage, healing)
    Add("SpellPower", both)
    Add("Healing", healing - both)
    if weights.SpellDamage or weights.Healing then
        Add("SpellDamage", damage - both)
    else
        Add("SpellPower", damage - both)
    end
    Add("Stamina", (stats[HEALTH] or 0) / HEALTH_PER_STAMINA)
    Add("Intellect", (stats[MANA] or 0) / MANA_PER_INTELLECT)

    local value = ForeverCompanion.Scales.Score(set, weights)
    return type(value) == "number" and value or nil
end

---------------------------------------------------------------------------
-- A scale's say on weapons
---------------------------------------------------------------------------
-- A scale of Forever Companion's has none: it is offered every weapon (see Pawn.ShowsWeapons,
-- whose scales have).
function C.ShowsWeapons()
    return true, true
end

---------------------------------------------------------------------------
-- Forever Companion's own marks
---------------------------------------------------------------------------
-- Does it write its line into item tooltips: the value of the item on the scale in use, and
-- how much better it is than what is worn? While it does, this addon leaves its own lines
-- about the score out, as with Pawn: they would say it twice (Score.Writes). Switched off
-- in its options, ours are written, on its scales.
function C.WritesTooltip()
    local options = Options()
    return options ~= nil and options.scales_enabled ~= false and options.scale_tooltip ~= false
end

-- Does it draw its own arrow on an upgrade in the bags and the bank? While it does, this
-- addon draws none of its own (Bags.lua): two arrows on one icon, by the same scale, would
-- say one thing twice, and where the two addons draw the line differently, two things.
-- Switched off in its options, ours are drawn, on its scales.
function C.DrawsArrows()
    local options = Options()
    return options ~= nil and options.scales_enabled ~= false and options.scale_arrows ~= false
        and options.scale_badges_more ~= false
end

-- Forever Companion writes into every item tooltip, and means the character being played:
-- it knows of no other. Its line of the scale says what the item is worth to that one and
-- how much better it is than what that one wears; its lists of the best gear say where the
-- item stands for the talent trees that one's player follows. Under an item picked for
-- another character of the account (a row of a list made for one, and what that one wears
-- beside it) both read as if they were said of that character, which they are not.
-- C.Hushed fills such a tooltip in with both left out: for the length of the call its two
-- options for them are off, and they are put back before anything else runs, whatever
-- happens in the call. What it writes of the item itself stays: its price at the auction
-- house, how many of it the player's characters have. This is asked whoever scores: the
-- lines are Forever Companion's to write with the addon's own weights chosen as well.
-- Without Forever Companion the tooltip is filled in and no more.
-- fill: what fills the tooltip in; it is called with the arguments that follow it.
local ABOUT_ME = { "scale_tooltip", "bis_tooltip" }

function C.Hushed(fill, ...)
    local options = Options()
    if not options then
        fill(...)
        return
    end
    -- (As they are written down, not as they read: an option that was never set reads as
    -- its default, and is to be left unset.)
    local kept = {}
    for i = 1, #ABOUT_ME do
        kept[i] = rawget(options, ABOUT_ME[i])
        options[ABOUT_ME[i]] = false
    end
    local ok, problem = pcall(fill, ...)
    for i = 1, #ABOUT_ME do rawset(options, ABOUT_ME[i], kept[i]) end
    if not ok then error(problem, 0) end
end

---------------------------------------------------------------------------
-- When Forever Companion's scales change
---------------------------------------------------------------------------
-- Another scale chosen for the character, a weight changed, a scale made or taken away, in
-- Forever Companion's own window: every score made on its scales is out of date, and so may
-- be the list of them. It then draws its marks again (RefreshScaleOverlays), which is how
-- an addon can tell; it does that for other reasons too (the gear changed), which are
-- nothing to the scores. So what the scores rest on is kept (`seen`), and only when that
-- has changed does the rest of the addon hear SCORING_CHANGED, while Forever Companion
-- scores: once for a burst of changes.
-- What it draws itself, the line in a tooltip and the arrows, is switched in the same
-- window. That is nothing to the scores, and something to what this addon leaves out for
-- it: SETTING_CHANGED "companion" says so.
-- seen: { scales = every scale with its weights, as one text; active = the key of the scale
-- the character being played has in use; shows = what Forever Companion draws itself }.
-- nil until its scales are first asked for (C.Scales), before which there are no such scores.

local function ScalesText()
    local parts = {}
    for i = 1, #CLASSES do
        for _, scale in ipairs(Listed(CLASSES[i])) do
            local weights = {}
            for stat, weight in pairs(type(scale.w) == "table" and scale.w or {}) do
                weights[#weights + 1] = tostring(stat) .. "=" .. tostring(weight)
            end
            table.sort(weights)
            parts[#parts + 1] = table.concat({
                CLASSES[i], tostring(scale.key), tostring(scale.label), tostring(scale.tab), table.concat(weights, ","),
            }, "\t")
        end
    end
    return table.concat(parts, "\n")
end

local function ShowsText()
    return tostring(C.WritesTooltip()) .. tostring(C.DrawsArrows())
end

-- The scales are being read to score with, for the first time or again: what changes about
-- them from now on is to be told.
function C.Watch()
    if seen then return end
    -- (Set before the scale in use is asked for: asking looks here.)
    seen = { scales = ScalesText(), shows = ShowsText() }
    seen.active = ActiveKey()
end

-- whole: Forever Companion said that something changed, which may be anything. Otherwise
-- only the scale it picks by itself is in question: the talents changed, or its answer of a
-- moment ago has grown old.
local function Look(whole)
    -- (What is kept of its scales is made anew whether or not anybody is to be told.)
    if whole then byKey, active = nil, nil end
    if not seen or not C.Usable() then return end
    local scoring = ns.Score.Engine() == "companion"
    local changed = false
    if whole then
        local scales = ScalesText()
        if scales ~= seen.scales then
            seen.scales, changed = scales, true
        end
        local shows = ShowsText()
        if shows ~= seen.shows then
            seen.shows = shows
            if scoring then ns.Fire("SETTING_CHANGED", "companion") end
        end
    end
    local key = ActiveKey()
    if key ~= seen.active then
        seen.active, changed = key, true
    end
    if changed and scoring then ns.Fire("SCORING_CHANGED") end
end

local Changed = ns.Soon(0.2, function() Look(true) end)
Later = ns.Soon(0.2, function() Look(false) end)

-- The talents changed, or may have: what Forever Companion picks by itself is asked anew.
local function Talents()
    active = nil
    Later()
end
ns.On("PLAYER_ENTERING_WORLD", Talents)
ns.On("TRAIT_CONFIG_UPDATED", Talents)
ns.On("PLAYER_LEVEL_UP", Talents)

local hooked = false
local function Hook()
    local addon = ForeverCompanion
    if hooked or type(addon) ~= "table" or type(addon.RefreshScaleOverlays) ~= "function" then return end
    hooked = true
    hooksecurefunc(addon, "RefreshScaleOverlays", Changed)
end
Hook()
-- (Forever Companion may be loaded after this addon, when the player has it load on demand.)
ns.On("PLAYER_LOGIN", Hook)
