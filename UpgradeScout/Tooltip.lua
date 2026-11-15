local ADDON, ns = ...
local L = ns.L

-- Our lines in an item's tooltip: under the addon's name, how much better the item is than
-- what the character wears, on every profile of its class, the way Pawn shows its scales.
-- A player whose tooltips are long enough as it is can have one line in their place, for the
-- profile in use ("Only my spec" in the welcome window: ns.OwnTree), or none at all: the lines
-- written here are switched off there apart from those of our own tabs (ns.Shows "tooltip"
-- and "rowTooltip").
-- The Upgrades list writes them under its own rows (UI.lua), for the character the list is
-- for. Everywhere else in the game they come from here, for the character being played: the
-- bags, loot, quest rewards, links in the chat, the auction house's own lists.
local T = {}
ns.Tooltip = T

---------------------------------------------------------------------------
-- The lines
---------------------------------------------------------------------------
-- They start with the addon's icon and name, so that they are not taken for the lines another
-- addon puts there. `right`, when given, goes on the right of that line. The blue is the lens
-- of the logo.
local ICON = "|TInterface\\AddOns\\" .. ADDON .. "\\icon.tga:0|t "
local BRAND = ICON .. "Upgrade Scout"
local BRAND_R, BRAND_G, BRAND_B = 0.53, 0.78, 0.96

function T.AddHeader(tooltip, right)
    GameTooltip_AddBlankLineToTooltip(tooltip)
    if right then
        tooltip:AddDoubleLine(BRAND, right, BRAND_R, BRAND_G, BRAND_B, NORMAL_FONT_COLOR:GetRGB())
    else
        tooltip:AddLine(BRAND, BRAND_R, BRAND_G, BRAND_B)
    end
end

-- A gain as the list writes it (see InitItemRow in UI.lua), and the colour to write it in:
-- green for better, red for worse, grey for no change. With nothing to take a percent of (an
-- empty slot, or an item there that scores nothing), in points.
local function GainText(gain)
    if gain.percent then
        local shown = FormatPercentage(math.abs(gain.percent), true)
        if shown == FormatPercentage(0, true) then return shown, GRAY_FONT_COLOR end
        if gain.percent > 0 then return "+" .. shown, GREEN_FONT_COLOR end
        return "-" .. shown, RED_FONT_COLOR
    end
    return L.GAIN_POINTS:format(ns.Num(gain.delta)), gain.delta > 0 and GREEN_FONT_COLOR or GRAY_FONT_COLOR
end

-- The line of one profile: its name, in the colour of the class (`class`, as "MAGE") the way
-- Pawn colours its scales, and the gain (a placement, see Compare.Place).
function T.AddGain(tooltip, title, gain, class)
    local text, color = GainText(gain)
    local r, g, b = (RAID_CLASS_COLORS[class or ""] or HIGHLIGHT_FONT_COLOR):GetRGB()
    local rightR, rightG, rightB = color:GetRGB()
    tooltip:AddDoubleLine(title, text, r, g, b, rightR, rightG, rightB)
end

-- With the tree in use alone chosen (ns.OwnTree) the lines are one: the profile in use and
-- the gain on it. There is no heading over a single line; the addon's icon before the
-- profile's name says whose line it is, and a blank line sets it off as it does the heading.
function T.AddOwn(tooltip, title, gain, class)
    GameTooltip_AddBlankLineToTooltip(tooltip)
    T.AddGain(tooltip, ICON .. title, gain, class)
end

---------------------------------------------------------------------------
-- Any item, anywhere
---------------------------------------------------------------------------
-- What the character being played wears, scored on each of its profiles (see Score.Context),
-- and what that makes of the items whose tooltips were shown: the game draws a tooltip that
-- is up several times a second. Both are kept until the gear, the level or the spells (dual
-- wield) change. A snapshot that still waits for an item is not kept.
local contexts, answers = {}, {}

local function Forget()
    contexts, answers = {}, {}
end
ns.On("PLAYER_EQUIPMENT_CHANGED", Forget)
ns.On("SPELLS_CHANGED", Forget)
ns.On("PLAYER_LEVEL_UP", function()
    Forget()
    -- The game may tell the new level a moment after the event.
    C_Timer.After(1, Forget)
end)
-- Another one scores (the addon or Pawn), or Pawn's scales changed.
ns.Listen("SCORING_CHANGED", Forget)
-- With Pawn scoring an answer is about the scale in use alone (see Answer): another scale
-- chosen, and it is to be made again.
ns.Listen("PROFILE_CHANGED", function()
    if ns.Score.Engine() then answers = {} end
end)

-- Returns the snapshot, and whether it is whole.
local function Context(id)
    local ctx = contexts[id]
    if ctx then return ctx, true end
    ctx = ns.Score.Context(id)
    local whole = not ctx.pending and not ctx.unread
    if whole then contexts[id] = ctx end
    return ctx, whole
end

-- Is this item (variant and all) one the character has on? Its tooltip then has nothing to
-- be compared with.
local function Wears(link)
    local key = ns.ItemKey(link)
    for slot = 1, ns.Roster.LAST_SLOT do
        if ns.ItemKey(GetInventoryItemLink("player", slot)) == key then return true end
    end
    return false
end

-- Wears and wields what the class can, at any level: plate for a warrior of 20, who wears it
-- from 40, is something to save up for. The game's tooltip says in red what is not yet allowed.
local ANY_LEVEL = math.huge

-- The lines for an item link: { { name = profile id, title, gain }, ..., effects = bool },
-- false for an item that gets none (not gear, not for this class, worth nothing on any of
-- its profiles), nil while the game has not loaded it or the character. The second value is
-- whether that answer is final: false while the game still loads some of what is worn.
local function Answer(link)
    local known = answers[link]
    if known ~= nil then return known, true end
    local me = ns.Roster.Me()
    local scored = me and me.class and ns.Score.Item(link)
    if not scored then return nil end

    local whole, answer = true, false
    if ns.Compare.Handles(scored.invType)
        and ns.Roster.Wields({ class = me.class, level = ANY_LEVEL }, scored.classID, scored.subClassID) then
        local level = UnitLevel("player")
        local unique = C_Item.GetItemUniquenessByID(scored.itemID) == true
        local lines, worth = {}, false
        -- With Pawn scoring there are no lines to write (see OnItem), and the arrow in the
        -- bags asks about the scale in use alone.
        local profiles = ns.Score.Engine() and { (ns.Score.Current()) } or ns.Score.Profiles()
        for _, profile in ipairs(profiles) do
            local ctx, complete = Context(profile.name)
            whole = whole and complete
            local item = {
                link = link, itemID = scored.itemID, invType = scored.invType, unique = unique,
                value = ns.Score.Value(scored, profile.name, level),
            }
            if item.value > 0 then worth = true end
            -- Where it gains the most: a one-hander of a dual wielder goes in either hand.
            local best
            for _, placement in ipairs(ns.Compare.Gains(item, ctx)) do
                if not best or placement.delta > best.delta then best = placement end
            end
            if best then lines[#lines + 1] = { name = profile.name, title = profile.title, gain = best } end
        end
        if worth and #lines > 0 then
            lines.effects = ns.Score.HasUnscoredEffects(scored)
            answer = lines
        end
    end
    if whole then answers[link] = answer end
    return answer, whole
end

-- For the arrow on the icon of an item in the bags (Bags.lua): true when the item's line for
-- the profile in use reads as a gain, in green, false when it does not, nil while the game
-- has not loaded what it takes to tell.
function T.Upgrade(link)
    local _, _, _, invType = C_Item.GetItemInfoInstant(link)
    if not invType or not ns.Compare.Handles(invType) then return false end
    local answer, whole = Answer(link)
    if answer == nil or not whole then return nil end
    local current = answer and ns.Score.Current()
    if not current then return false end
    for _, line in ipairs(answer) do
        if line.name == current.name then
            local _, color = GainText(line.gain)
            return color == GREEN_FONT_COLOR
        end
    end
    return false
end

local NOTES = { OFFHAND_EMPTY = "TT_OFFHAND_EMPTY", BOTH_HANDS = "TT_BOTH_HANDS" }

-- Called by the game whenever a tooltip shows an item. Only the game's main tooltip and the one
-- for a link in the chat get our lines: the tooltips beside them show what is worn.
local function OnItem(tooltip)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    -- Switched off in the welcome window. (The rows of our own tabs have a switch of their
    -- own there, "rowTooltip".)
    if not ns.Shows("tooltip") then return end
    -- With Pawn scoring, the lines in a tooltip are Pawn's own, which say the same of its
    -- scales: ours would say it twice.
    if ns.Score.Engine() then return end
    -- A row of our own list writes its lines itself.
    local owner = tooltip:GetOwner()
    if owner and owner.upgradeScoutRow then return end
    local _, link = TooltipUtil.GetDisplayedItem(tooltip)
    if not link or Wears(link) then return end
    local answer = Answer(link)
    if not answer then return end

    local current = ns.Score.Current()
    local class = ns.Roster.Me().class
    local note
    -- The tree in use alone: the line of the profile in use, and no other.
    local own
    if ns.OwnTree() and current then
        for _, line in ipairs(answer) do
            if line.name == current.name then own = line end
        end
    end
    if own then
        note = own.gain.note
        T.AddOwn(tooltip, own.title, own.gain, class)
    else
        T.AddHeader(tooltip)
        for _, line in ipairs(answer) do
            local inUse = current ~= nil and line.name == current.name
            if inUse then note = line.gain.note end
            T.AddGain(tooltip, line.title, line.gain, class)
        end
    end
    if note and NOTES[note] then GameTooltip_AddNormalLine(tooltip, L[NOTES[note]]) end
    if answer.effects then GameTooltip_AddNormalLine(tooltip, L.TT_EFFECTS) end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
