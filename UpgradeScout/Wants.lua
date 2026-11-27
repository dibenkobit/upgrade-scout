local _, ns = ...

-- What a character wants of its gear: the filters of the Upgrades list that are about the
-- character the list is for, and not about the purchase. They are written on the character's
-- card (Roster.lua), which is kept for the whole account. So they go with the character the
-- list is for, and not with the one who shops: what is set while shopping for an alt is the
-- alt's, the alt finds it so when it is played and shops for itself, and what it changes then
-- is what the next one to shop for it finds.
--   armorOnly   true: only the best armor type for its class, which is the heaviest armor the
--               character has learned to wear. A hunter is then offered leather, and mail
--               once it has learned mail; cloth is left out.
--   minGain     the least an upgrade has to add, in percent of what it takes the place of;
--   minGainOn   true while that is asked for. The number stays when its box is unticked.
--   maxBelow    how many levels below the character's own gear may be made for and still be
--               offered: with 10, a character of level 30 is offered nothing that asks for
--               a level under 20. Gear that asks for no level is not made for a low one,
--               and is offered whatever the number;
--   maxBelowOn  true while that is asked for. The number stays when its box is unticked.
--               This one is also about the scan: gear that is not to be offered is not asked
--               of the auction house, and the scan is the shorter for it (see Scanner.lua).
--   byProfile   what it wants of its weapons, which goes with the way it is played: a warrior
--               wants a two-hander on Arms and a shield on Protection, a rogue swords on
--               Combat and daggers on Subtlety. So that is kept for each of its profiles by
--               itself, { [the profile's key, see Wants.ProfileKey] = { hands, kinds } }, and
--               what is asked of its gear is what is kept for the profile it is scored on:
--     hands     how it fills its hands: "TWO", with a two-hander, and then weapons for one
--               hand, shields and what is held in the off hand are left out; "ONE", with a
--               weapon for one hand and a shield, a held item or a second weapon beside it,
--               and then two-handers are left out; "ANY", either way. nil until the player
--               chooses: the profile then says (see Wants.Hands).
--     kinds     { [weapon subclass] = false } for the kinds of weapon it is not to be
--               offered: a rogue that fights with swords leaves the daggers and the maces out.
-- ("Only what I can afford", "Top N per slot" and "Hide worse deals" are about the buyer:
-- those are in ns.db.)
--
-- One more filter is kept on the card and is not one of the wants: "Buyout up to", the most to
-- pay for one item. It is about the purchase, as "Only what I can afford" is, and like that
-- one it has no say in the best set for a budget or in the arrows of the bags. But what is a
-- fair price for an item depends on whom the item is for (a rich character shops for an alt
-- of level 20), so the sum goes with the character, as the others do.
--   maxPrice    that sum, in copper;
--   maxPriceOn  true while it is asked for. The sum stays when its box is unticked.
--
-- What is asked of a character's gear right now is its "wants": { armor = the one kind of
-- armor to offer (an item subclass: 2 leather, 3 mail, 4 plate), gain = the least percent,
-- level = the lowest level gear may ask for, hands = "TWO" or "ONE", kinds = { [weapon
-- subclass] = true } for the kinds left out }, each of them nil when it is not asked for.
-- Nothing asked for is nil, and every function here takes that for wants that leave nothing
-- out.
local Wants = {}
ns.Wants = Wants

local ARMOR_CLASS = Enum.ItemClass.Armor
local WEAPON_CLASS = Enum.ItemClass.Weapon
local CLOTH, PLATE = 1, 4

Wants.DEFAULT_GAIN = 10         -- the percent in the field before one is typed
Wants.MAX_GAIN = 9999
Wants.DEFAULT_BELOW = 10        -- the levels in their field before a number is typed
Wants.MAX_BELOW = 59            -- from the last level down to the first: more leaves nothing out

-- Armor is of a kind where it covers the body. A cloak is cloth for every class, and a ring,
-- a shield or something held in the hand is of no kind there is a choice between.
local BODY = {
    INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
    INVTYPE_WRIST = true, INVTYPE_HAND = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true,
}

-- The kind of armor an item is (1 cloth, 2 leather, 3 mail, 4 plate), for the items a choice
-- of armor is about; nil for everything else.
function Wants.ArmorOf(invType, classID, subClassID)
    if classID == ARMOR_CLASS and BODY[invType or ""] and type(subClassID) == "number"
        and subClassID >= CLOTH and subClassID <= PLATE then
        return subClassID
    end
    return nil
end

-- The heaviest armor the character of a card wears now, which is what "Best armor type for
-- the class" keeps. nil for a character that wears nothing but cloth: there is nothing
-- lighter to leave out.
function Wants.Armor(card)
    if not card then return nil end
    for kind = PLATE, CLOTH + 1, -1 do
        if ns.Roster.Wields(card, ARMOR_CLASS, kind) then return kind end
    end
    return nil
end

-- The percent typed for a character, asked for or not. (A card comes out of a saved file.)
function Wants.Gain(card)
    local gain = card and card.minGain
    if type(gain) ~= "number" or gain < 1 then return Wants.DEFAULT_GAIN end
    return math.min(math.floor(gain), Wants.MAX_GAIN)
end

-- The number of levels typed for a character, asked for or not. (A card comes out of a saved
-- file: what is no number there, or none to go by, gives way to the first one.)
function Wants.Below(card)
    local below = card and card.maxBelow
    if type(below) ~= "number" or below ~= below or below < 1 then return Wants.DEFAULT_BELOW end
    return math.min(math.floor(below), Wants.MAX_BELOW)
end

-- The level of the character of a card, as the gear snapshot has it (Score.Context): the
-- game is asked about the one being played, whose card may be a moment behind it.
local function LevelOf(card)
    local level
    if card == ns.Roster.Me() then level = UnitLevel("player") else level = card.level end
    if type(level) ~= "number" or level ~= level or level < 1 then return 1 end
    return math.floor(level)
end

-- The lowest level gear may ask for by the number typed for a character, asked for or not:
-- the character's own level less that number. nil when the number reaches down to the first
-- level, which the least of gear is made for: nothing is left out then.
function Wants.LevelTyped(card)
    if not card then return nil end
    local from = LevelOf(card) - Wants.Below(card)
    if from <= 1 then return nil end
    return from
end

-- The lowest level gear may ask for and still be offered to the character of a card; nil
-- when nothing is left out for its level.
function Wants.FromLevel(card)
    if not card or card.maxBelowOn ~= true then return nil end
    return Wants.LevelTyped(card)
end

---------------------------------------------------------------------------
-- Weapons
---------------------------------------------------------------------------
-- The three ways to fill the hands, in the order the menu has them.
Wants.HANDS = { "ANY", "TWO", "ONE" }
local IS_HANDS = { ANY = true, TWO = true, ONE = true }

-- Which of the two ways an item for the hands goes with; nil for what is not held in them.
local HELD = {
    INVTYPE_2HWEAPON = "TWO",
    INVTYPE_WEAPON = "ONE", INVTYPE_WEAPONMAINHAND = "ONE", INVTYPE_WEAPONOFFHAND = "ONE",
    INVTYPE_SHIELD = "ONE", INVTYPE_HOLDABLE = "ONE",
}

-- The profiles of the addon's own whose weights come from a simulated tank behind a shield.
-- What a two-hander scores on them is no measure of it: the character they are for does not
-- hold one. So such a profile says "ONE" for a character that has not chosen.
local SHIELD_TANK = { WARRIOR_PROTECTION = true, PALADIN_PROTECTION = true }

-- The kind of weapon an item is (its subclass: 7 a one-handed sword, 10 a staff); nil for
-- what is no weapon.
function Wants.WeaponOf(classID, subClassID)
    if classID == WEAPON_CLASS and type(subClassID) == "number" then return subClassID end
    return nil
end

-- The profile the character of a card is scored on (Score.Current), as the key its choice of
-- weapons is kept under: who scores, and the profile's name there. "own:WARRIOR_PROTECTION"
-- is a profile of the addon's own, "pawn:..." a Pawn scale, "companion:..." a scale of Forever
-- Companion; so a scale that happens to be named as another addon's is still another key.
-- Forever Leveling BiS and GearQuest name a profile one way for the character being played
-- and another for the same character seen from an alt (Leveling.lua, GearQuest.lua), and the
-- choice is the character's whoever shops for it: theirs go by the spec, which is the same
-- from both sides ("leveling:fury", "gearquest:combat").
local BY_SPEC = { leveling = true, gearquest = true }

function Wants.ProfileKey(card)
    local engine = ns.Score.Engine()
    local profile = ns.Score.Current(card)
    local id = profile and profile.name
    if engine and BY_SPEC[engine] and profile and type(profile.spec) == "string" then id = profile.spec end
    -- (No profile to score on is a key like any other: a choice made then is kept, for then.)
    return (engine or "own") .. ":" .. (type(id) == "string" and id or "")
end

-- What is kept on a card for the profile it is scored on: { hands, kinds }; nil when nothing
-- is. (A card comes out of a saved file: what is no table there says nothing.)
function Wants.Kept(card)
    local all = card.byProfile
    if type(all) ~= "table" then return nil end
    local kept = all[Wants.ProfileKey(card)]
    return type(kept) == "table" and kept or nil
end

-- The same to write into: made where there is none, and over what is no table.
local function Keeping(card)
    if type(card.byProfile) ~= "table" then card.byProfile = {} end
    local key = Wants.ProfileKey(card)
    local kept = card.byProfile[key]
    if type(kept) ~= "table" then
        kept = {}
        card.byProfile[key] = kept
    end
    return kept
end

-- How the character of a card fills its hands: "ANY", "TWO" or "ONE". Its own choice for the
-- profile it is scored on, where it has made one, "ANY" among them: a choice stands whatever
-- the profile would say. Until then "ONE" on a profile of a shield tank, while the addon's own
-- weights score, and "ANY" otherwise: another addon that scores has its own say on the hands
-- (see Compare.Places), and this one adds none to it unasked. Also returns whether it is the
-- character's own choice.
-- (A card comes out of a saved file: what is none of the three is no choice.)
function Wants.Hands(card)
    if not card then return "ANY", false end
    local kept = Wants.Kept(card)
    if kept and IS_HANDS[kept.hands] then return kept.hands, true end
    if not ns.Score.Engine() then
        local profile = ns.Score.Current(card)
        if profile and SHIELD_TANK[profile.name] then return "ONE", false end
    end
    return "ANY", false
end

-- Is this kind of weapon one the character of a card is not to be offered, on the profile it
-- is scored on?
function Wants.KindOut(card, kind)
    local kept = Wants.Kept(card)
    return kept ~= nil and type(kept.kinds) == "table" and kept.kinds[kind] == false
end

-- The kinds its class can ever wield that it is not to be offered: { [weapon subclass] =
-- true }, and how many they are. What its card says of any other kind is passed over.
function Wants.KindsOut(card)
    local out, count = {}, 0
    local kept = Wants.Kept(card)
    local kinds = kept and kept.kinds
    if type(kinds) ~= "table" then return out, count end
    for _, weapon in ipairs(ns.Roster.WeaponKinds(card.class)) do
        if kinds[weapon.kind] == false then
            out[weapon.kind] = true
            count = count + 1
        end
    end
    return out, count
end

---------------------------------------------------------------------------
-- The wants
---------------------------------------------------------------------------
-- One table for each thing that can be asked, so that whoever keeps a result made for some
-- wants can tell by the table itself whether they are still the same.
local made = {}

-- The wants of the character of a card; nil when it asks for nothing.
function Wants.Of(card)
    if not card then return nil end
    local armor = card.armorOnly == true and Wants.Armor(card) or nil
    local gain = card.minGainOn == true and Wants.Gain(card) or nil
    local level = Wants.FromLevel(card)
    local hands = Wants.Hands(card)
    if hands == "ANY" then hands = nil end
    local kinds, count = Wants.KindsOut(card)
    if count == 0 then kinds = nil end
    if not armor and not gain and not level and not hands and not kinds then return nil end
    -- (The kinds left out, in the order of their numbers: the same ones are the same key.)
    local out = {}
    if kinds then
        for kind in pairs(kinds) do out[#out + 1] = kind end
    end
    table.sort(out)
    local key = (armor or 0) .. ":" .. (gain or 0) .. ":" .. (level or 0) .. ":" .. (hands or "")
        .. ":" .. table.concat(out, ",")
    local wants = made[key]
    if not wants then
        wants = { armor = armor, gain = gain, level = level, hands = hands, kinds = kinds }
        made[key] = wants
    end
    return wants
end

-- Would the character have the item at all? `item` is what the scanner knows of one (an
-- offer, or what EvalLink in Scanner.lua makes of a link): its `armor` is Wants.ArmorOf, its
-- `weapon` Wants.WeaponOf, `invType` the way it is worn, and its `reqLevel` the level it asks
-- for. Gear that asks for no level is 0 there: it is not made for a low level, and the
-- filter of levels leaves it alone, as it does an item that says nothing of its level. It
-- is judged like any other, and listed where it is an upgrade.
function Wants.Fits(wants, item)
    if not wants then return true end
    if wants.armor and item.armor and item.armor ~= wants.armor then return false end
    if wants.level and item.reqLevel and item.reqLevel > 0 and item.reqLevel < wants.level then return false end
    if wants.kinds and item.weapon and wants.kinds[item.weapon] then return false end
    local held = wants.hands and HELD[item.invType or ""]
    return not held or held == wants.hands
end

-- The same of an item known by its link alone: one in the bags (Bags.lua). Nothing is said of
-- the level it asks for: the arrows in the bags do not go by that (see Wants.SetBelow).
function Wants.FitsLink(wants, link)
    if not wants then return true end
    local _, _, _, invType, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
    return Wants.Fits(wants, {
        invType = invType,
        armor = Wants.ArmorOf(invType, classID, subClassID),
        weapon = Wants.WeaponOf(classID, subClassID),
    })
end

-- Is the gain of a placement (see Compare.Place) enough? The percent is held against the
-- number as the list writes it, rounded: a row that reads "+50%" passes "at least 50". A gain
-- with no percent to it (the slot is empty, or what is in it scores nothing) is more than any.
function Wants.Enough(wants, placement)
    if not wants or not wants.gain or not placement.percent then return true end
    return math.floor(placement.percent * 100 + 0.5) >= wants.gain
end

-- The placements of an item that the character would have: all of them, some or none.
local NONE = {}
function Wants.Keep(wants, item, placements)
    if not wants then return placements end
    if not Wants.Fits(wants, item) then return NONE end
    if not wants.gain then return placements end
    local kept
    for i = 1, #placements do
        if Wants.Enough(wants, placements[i]) then
            kept = kept or {}
            kept[#kept + 1] = placements[i]
        end
    end
    return kept or NONE
end

-- They are set in the menu of the Filters field (Filters.lua). Whoever shows what they
-- change hears WANTS_CHANGED with the card: the list, and the arrows in the bags.
function Wants.SetArmorOnly(card, on)
    card.armorOnly = on and true or nil
    ns.Fire("WANTS_CHANGED", card)
end

-- percent: the number that was typed; nil leaves the one there is.
function Wants.SetGain(card, on, percent)
    if percent then card.minGain = Clamp(math.floor(percent), 1, Wants.MAX_GAIN) end
    card.minGainOn = on and true or nil
    ns.Fire("WANTS_CHANGED", card)
end

-- levels: the number that was typed; nil leaves the one there is. Nobody but the list shows
-- what it changes, and the menu that sets it tells the list itself (Filters.lua). The arrows
-- in the bags do not go by it: the filter spares the scan what is not worth reading, and an
-- item that is in the bags already costs nothing to judge. Where an old piece still beats
-- what is worn, its arrow is the truth.
function Wants.SetBelow(card, on, levels)
    if levels then card.maxBelow = Clamp(math.floor(levels), 1, Wants.MAX_BELOW) end
    card.maxBelowOn = on and true or nil
end

-- The two about its weapons are written down for the profile the character is scored on, and
-- no other profile of its is any the different for them.
-- hands: one of Wants.HANDS. "ANY" is written down like the other two: it is a choice, and
-- holds where the profile would say otherwise.
function Wants.SetHands(card, hands)
    if not IS_HANDS[hands] then return end
    Keeping(card).hands = hands
    ns.Fire("WANTS_CHANGED", card)
end

-- kind: a weapon subclass; on: the character is to be offered it.
function Wants.SetKind(card, kind, on)
    local kept = Keeping(card)
    local kinds = type(kept.kinds) == "table" and kept.kinds or {}
    if on then kinds[kind] = nil else kinds[kind] = false end
    -- (No kind left out is no table: a card says nothing of what is as it was made.)
    kept.kinds = next(kinds) ~= nil and kinds or nil
    ns.Fire("WANTS_CHANGED", card)
end

---------------------------------------------------------------------------
-- "Buyout up to"
---------------------------------------------------------------------------
local SILVER, GOLD = 100, 10000

Wants.DEFAULT_PRICE = GOLD                          -- the sum in the fields before one is typed
Wants.MAX_PRICE = 99999 * GOLD + 99 * SILVER        -- what its two fields can hold

-- The sum typed for a character, asked for or not: whole silver, and no less than one.
function Wants.PriceTyped(card)
    local price = card and card.maxPrice
    if type(price) ~= "number" or price < SILVER then return Wants.DEFAULT_PRICE end
    return math.min(math.floor(price / SILVER) * SILVER, Wants.MAX_PRICE)
end

-- The most to pay for one item for the character of a card, in copper; nil when no sum is
-- asked for.
function Wants.Price(card)
    if not card or card.maxPriceOn ~= true then return nil end
    return Wants.PriceTyped(card)
end

-- copper: the sum that was typed; nil leaves the one there is. Nobody but the list shows
-- what the sum changes, and the menu that sets it tells the list itself (Filters.lua).
function Wants.SetPrice(card, on, copper)
    if copper then card.maxPrice = Clamp(math.floor(copper / SILVER) * SILVER, SILVER, Wants.MAX_PRICE) end
    card.maxPriceOn = on and true or nil
end
