local _, ns = ...

-- What a character wants of its gear: the two filters of the Upgrades list that are about the
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
-- ("Only what I can afford" and "Top N per slot" are about the buyer: those are in ns.db.)
--
-- What is asked of a character's gear right now is its "wants": { armor = the one kind of
-- armor to offer (an item subclass: 2 leather, 3 mail, 4 plate), gain = the least percent },
-- either of them nil when it is not asked for. Nothing asked for is nil, and every function
-- here takes that for wants that leave nothing out.
local Wants = {}
ns.Wants = Wants

local ARMOR_CLASS = Enum.ItemClass.Armor
local CLOTH, PLATE = 1, 4

Wants.DEFAULT_GAIN = 10         -- the percent in the field before one is typed
Wants.MAX_GAIN = 9999

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

-- One table for each thing that can be asked, so that whoever keeps a result made for some
-- wants can tell by the table itself whether they are still the same.
local made = {}

-- The wants of the character of a card; nil when it asks for nothing.
function Wants.Of(card)
    if not card then return nil end
    local armor = card.armorOnly == true and Wants.Armor(card) or nil
    local gain = card.minGainOn == true and Wants.Gain(card) or nil
    if not armor and not gain then return nil end
    local key = (armor or 0) .. ":" .. (gain or 0)
    local wants = made[key]
    if not wants then
        wants = { armor = armor, gain = gain }
        made[key] = wants
    end
    return wants
end

-- Would the character have the item at all? `item` is what the scanner knows of one (an
-- offer, or what EvalLink in Scanner.lua makes of a link): its `armor` is Wants.ArmorOf.
function Wants.Fits(wants, item)
    return not wants or not wants.armor or not item.armor or item.armor == wants.armor
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

-- The two are set in the menu of the Filters field (Filters.lua). Whoever shows what they
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
