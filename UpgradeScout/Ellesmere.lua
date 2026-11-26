local _, ns = ...

-- EllesmereUI's Bags module shows the bags, the reagent bag and the bank in windows of its
-- own, on buttons of its own, and puts the game's bag windows out of sight: the arrows of
-- Bags.lua are then drawn where nobody sees them. Here its slots get the same arrows, by the
-- same rule (Bags.Arrow).
--
-- Nothing of EllesmereUI is carried here, and nothing of it is reached into. It keeps a
-- place for addons that draw on its slots, and that alone is used (written after EllesmereUI
-- Bags 9.9.5: its EUI_Bags_Slots.lua, "Third-party item overlay icons"):
--   * EUI_Bags, its bag window, is a global, and has RegisterItemOverlayIcon(name, func)
--     once the module's files have run.
--   * It calls func(button, data) for every slot it draws, of the bags, the reagent bag and
--     the bank, laid out as a grid or as a list, each time it draws the slot. data is
--     { bag, slot, info, itemLink } and good for the length of the call only (the bank fills
--     one table for all its slots); a slot with no item has no info.
--   * The button is a secure item button of the game's. Nothing is to be kept on it, and
--     what is drawn goes on button._textOverlay, a frame of its own that covers the item's
--     icon.
--   * An error in func is reported and does not stop its drawing.
--
-- It is never asked to draw a window again for an arrow's sake. Its own bridge to Pawn does
-- ask (EUI_Bags:RefreshInventory), which sorts and lays out every slot anew; and it first
-- says that the pass may keep the layout as it is (ns.Hold.events), for the player who has
-- it hold the items in place while some are taken out. That word is kept in a table of the
-- module's own, which is not another addon's to write in, and a pass without it lets the
-- held layout go. Its own passes are few besides: one a little after the bags change, for a
-- whole burst of changes. So Bags.lua keeps what each slot was last drawn with and puts the
-- arrows right itself, whenever the answers change and while the game still loads an item
-- (Bags.Other): on the slots in sight, as EllesmereUI draws nothing in a window that is
-- closed and every slot of one that opens.
--
-- Whether ours are drawn at all is for the one who scores to say here as in the game's
-- windows (Score.DrawsArrows, which is told whose windows these are): Forever Leveling BiS
-- draws its own arrows on these slots through the same place, on those of the bank too.
local ADDON = "ellesmere"       -- whose windows these are, as Bags.Arrow is asked
local NAME = "UpgradeScout"     -- what EllesmereUI has our function under

-- Where the arrow goes on a slot of theirs: the top right quarter of the icon. The game has
-- it in the top left corner, and there EllesmereUI writes the item's level on every piece of
-- gear, unless told not to. The bottom left is where it writes "BoE", the bottom right has
-- the count, the rank of an upgrade track and, with Pawn installed, Pawn's own arrow. The
-- top right it leaves to marks: its own (the spell of its Quick Actions) is anchored as this
-- one is, which makes the arrow 16 pixels on a slot of the grid, the size it gives Pawn's,
-- and smaller on a row of the list, whose icon a whole one would cover. (Forever Leveling
-- BiS has its arrow in the same quarter. Where both addons draw, which is where it is
-- installed and does not score, its arrow lies over ours.)
local function Place(arrow, host)
    arrow:SetPoint("TOPRIGHT", host, "TOPRIGHT", -1, -1)
    arrow:SetPoint("BOTTOMLEFT", host, "CENTER", 0, 0)
end

-- Is the slot one of the bank? Its bag window lists the bags the character carries, the
-- backpack to the reagent bag; any other bag it draws a slot of is a tab of the bank. (Its
-- own Quick Actions tell the two apart the same way.)
local function Where(bag)
    if bag and (bag < 0 or bag > NUM_TOTAL_EQUIPPED_BAG_SLOTS) then return "bank" end
end

local Drawn = ns.Bags.Other(ADDON, Place)

-- EllesmereUI has drawn a slot. What is needed of `data` is taken out of it here: the table
-- is not ours to keep.
local function Slot(button, data)
    local host = button._textOverlay
    if not host then return end
    Drawn(button, host, data.info and data.itemLink or nil, Where(data.bag))
end

-- The function is given to EllesmereUI as soon as it can take one: now, if its Bags module
-- has loaded, and otherwise when it has. The game loads the addons one after another, each
-- after the ones it names as its dependencies, optional ones too, and "EllesmereUIBags" is
-- named in our .toc: installed and switched on, it has loaded by now. That order is not
-- leaned on, though. The module may come under another folder's name, or be loaded only when
-- called for, as other parts of EllesmereUI are: then it is found when the game says that
-- it, or any addon after it, has loaded. Where there is no EllesmereUI, or one too old to
-- have the place, nothing is ever found and nothing is done.
local listed = false

local function List()
    if listed then return end
    local bags = EUI_Bags
    if type(bags) ~= "table" or type(bags.RegisterItemOverlayIcon) ~= "function" then return end
    listed = true
    bags.RegisterItemOverlayIcon(NAME, Slot)
end
List()
if not listed then ns.On("ADDON_LOADED", List) end
