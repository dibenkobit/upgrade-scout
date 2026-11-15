local _, ns = ...
local L = ns.L

-- The Filters field of the addon's two tabs: one of the game's dropdowns, like the profile
-- field, whose menu has a tick box for every filter of the list in view. (The tick boxes once
-- stood in a row above the list, and three of them filled it.)
--   Upgrades      Only what I can afford, Top N per slot, Only leather (or mail, or plate),
--                 Upgrade at least N %; and under a rule Net cost, which leaves nothing out:
--                 it is a way to read the prices
--   Consumables   Only what I can afford, Best for me
-- The menu stays open while its boxes are ticked, as the game's own menu of auction filters
-- does. Beside the field stand the names of the filters that are on, so that it is plain
-- without a click why the list is what it is; where they do not fit, how many are on.
--
-- Two of the filters of gear are about the character the list is for, and every character
-- has its own: see Wants.lua. The others are the player's (ns.db).
local Filters = {}
ns.Filters = Filters

local Widgets = ns.Widgets
local NewSlices, NewText = Widgets.NewSlices, Widgets.NewText
local CREAM, SOFT, MUTED = Widgets.CREAM, Widgets.SOFT, Widgets.MUTED

local FIELD_HEIGHT, FIELD_MIN = 24, 86
local NUMBER_WIDTH, NUMBER_HEIGHT = 46, 18      -- the field for a percent: four digits and air
local BOX_WIDTH, LINE_HEIGHT = 16, 20           -- a line's tick box, and how tall a line is
local GAP = 8                                   -- between the field and the names beside it
local SEPARATOR = " \194\183 "                  -- a dot at mid height between two names

local field, names          -- the dropdown, and the text beside it
local tab                   -- what the tab tells the field: see Filters.Build
local room = 0              -- how wide the text beside the field may be

-- The card of the character the lists are for (Roster.lua).
local function Owner()
    return ns.Roster.Target() or ns.Roster.Me()
end

---------------------------------------------------------------------------
-- What is on
---------------------------------------------------------------------------
-- The filters of the view that are on, in the order of the menu: { { short, full }, ... },
-- `short` as it is named beside the field and `full` as the menu has it. Net cost is not one
-- of them: the title of the price column says when the prices are net.
local function Active()
    local out = {}
    local function Add(short, full)
        out[#out + 1] = { short = short, full = full or short }
    end
    local gear = tab.View() == "gear"
    -- With the best set for a budget shown, the list is that set: these two have no say.
    local planned = gear and tab.Planned()
    if ns.db.affordableOnly and not planned then Add(L.AFFORD_SHORT, L.AFFORD) end
    if not gear then
        if ns.db.bestOnly then Add(L.SUP_BEST) end
        return out
    end
    if ns.db.topOnly and not planned then Add(L.TOP:format(ns.Results.TOP_COUNT)) end
    local wants = ns.Wants.Of(Owner())
    if wants and wants.armor then Add(L["ARMOR_ONLY_" .. wants.armor]) end
    if wants and wants.gain then Add(L.GAIN_MIN_SHORT:format(wants.gain), L.GAIN_MIN_FULL:format(wants.gain)) end
    return out
end

-- Writes beside the field which filters are on: their names; how many they are, where the
-- names take more room than there is; nothing, where not even that fits or none is on.
function Filters.Paint()
    if not field then return end
    local active = Active()
    local short = {}
    for i = 1, #active do short[i] = active[i].short end
    names:SetText(table.concat(short, SEPARATOR))
    if names:GetUnboundedStringWidth() <= room then return end
    names:SetText(L.FILTERS_COUNT:format(#active))
    if names:GetUnboundedStringWidth() > room then names:SetText("") end
end

-- How wide the text beside the field may be: the tab says when it has laid out its strip.
function Filters.SetRoom(width)
    room = math.max(width, 0)
    Filters.Paint()
end

-- The field's own tooltip: the filters that are on, by their full names.
local function FieldTooltip(tooltip)
    GameTooltip_SetTitle(tooltip, L.FILTERS)
    local active = Active()
    if #active == 0 then
        GameTooltip_AddNormalLine(tooltip, L.FILTERS_NONE)
        return
    end
    for i = 1, #active do GameTooltip_AddHighlightLine(tooltip, active[i].full) end
end

---------------------------------------------------------------------------
-- The menu
---------------------------------------------------------------------------
-- A line with a tick box. `isOn(data)` says whether it is ticked, `flip(data)` is a click on
-- it; `tip` is what its tooltip says under its name. A line that is not `enabled` is grey and
-- takes no click.
local function AddCheck(root, text, isOn, flip, data, tip, enabled)
    local line = root:CreateCheckbox(text, isOn, flip, data)
    line:AddInitializer(Widgets.SkinMenuCheck)
    if tip then
        line:SetTooltip(function(tooltip)
            GameTooltip_SetTitle(tooltip, text)
            GameTooltip_AddNormalLine(tooltip, tip)
        end)
    end
    if enabled == false then line:SetEnabled(false) end
    return line
end

-- The player's own filters: `key` is the setting in ns.db.
local function IsSet(key)
    return ns.db[key] and true or false
end

local function Flip(key)
    ns.db[key] = not ns.db[key]
    -- "Net cost" changes how the prices are read, not what is listed.
    tab.Changed(key == "net")
end

-- The two that are the character's.
local function ArmorOnly()
    local card = Owner()
    return card ~= nil and card.armorOnly == true
end

local function FlipArmor()
    local card = Owner()
    if not card then return end
    ns.Wants.SetArmorOnly(card, not card.armorOnly)
    tab.Changed()
end

local function GainOn()
    local card = Owner()
    return card ~= nil and card.minGainOn == true
end

local function FlipGain()
    local card = Owner()
    if not card then return end
    ns.Wants.SetGain(card, not card.minGainOn)
    tab.Changed()
end

-- The line "Upgrade at least [ 50 ] %": after the words of its tick box, a field for the
-- number and a percent sign.
--   * A number typed is asked for at once, and ticks the box.
--   * Unticked, the box leaves the number in the field, in a dimmer ink.
--   * An empty field asks for nothing. Left empty, it unticks the box and shows the last
--     number again.
-- The game makes the lines of a menu anew whenever it draws the menu, so the field is attached
-- to the line here, each time (the game's own menu of auction filters has its level fields
-- the same way), and not made once and kept. Ticking a line by typing must not draw the menu
-- again, which would take the field from under the keys: the tick is switched on the line
-- itself (see Widgets.SkinMenuCheck).
-- Returns the size of the line, which the game would otherwise have to measure.
local function AddNumber(button)
    local card = Owner()
    local words = button.fontString
    local box = button:AttachFrame("EditBox")
    -- The game hands a frame over reset to nothing: in no layer of the menu's, so that it is
    -- drawn under the menu's plate and nothing of it is seen, and with the rest of what it was
    -- made with wiped as well. (Its own menus say as much where they attach a button, and set
    -- these by hand: MenuTemplates.AttachBasicButton.) So the field is put in the menu's layer,
    -- above its line, in view and in reach of the mouse.
    box:SetFrameStrata(button:GetFrameStrata())
    box:SetFrameLevel(button:GetFrameLevel() + 1)
    box:Show()
    box:EnableMouse(true)
    box:SetSize(NUMBER_WIDTH, NUMBER_HEIGHT)
    box:SetPoint("LEFT", words, "RIGHT", 6, -1)
    NewSlices(box, "Inset", 0.25, 6, "BACKGROUND", 0, 0, function() return box:AttachTexture() end)
    box:SetFont(Widgets.NumberFont(), 12, "")
    box:SetJustifyH("CENTER")
    -- A field the game has just made takes the keys as soon as it is in view, and the game
    -- shows this one before it hands it over: the keys are given back, so that opening the
    -- menu does not stop the character walking.
    box:SetAutoFocus(false)
    box:ClearFocus()
    box:SetNumeric(true)
    box:SetMaxLetters(4)

    local function Ink()
        local ink = card and card.minGainOn and CREAM or MUTED
        box:SetTextColor(ink[1], ink[2], ink[3])
    end
    local function Tick(shown)
        if button.Tick then button.Tick:SetShown(shown) end
    end
    box:SetText(tostring(ns.Wants.Gain(card)))
    Ink()

    box:SetScript("OnTextChanged", function(self, userInput)
        if not userInput or not card then return end
        local number = self:GetNumber()
        if number < 1 then return end
        ns.Wants.SetGain(card, true, number)
        Tick(true)
        Ink()
        tab.Changed()
    end)
    -- The field is left: by Enter or Escape, by a click elsewhere.
    local function Settle(self)
        if not card or self:GetNumber() >= 1 then return end
        if card.minGainOn then
            ns.Wants.SetGain(card, false)
            Tick(false)
            tab.Changed()
        end
        self:SetText(tostring(ns.Wants.Gain(card)))
        Ink()
    end
    local function Leave(self)
        Settle(self)
        self:ClearFocus()
    end
    box:SetScript("OnEditFocusLost", Settle)
    box:SetScript("OnEnterPressed", Leave)
    box:SetScript("OnEscapePressed", Leave)
    button.Number = box

    local sign = button:AttachFontString()
    sign:SetPoint("LEFT", box, "RIGHT", 4, 1)
    sign:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    sign:SetTextToFit("%")
    -- The tick box, the words (which the game puts 7 after it), the field and the sign.
    return BOX_WIDTH + 7 + words:GetStringWidth() + 6 + NUMBER_WIDTH + 4 + sign:GetStringWidth(), LINE_HEIGHT
end

-- The game calls this each time the menu opens.
local function Menu(_, root)
    local gear = tab.View() == "gear"
    -- What the best set for a budget holds is not for the price filter or for "Top N" to
    -- say: while the list shows that set, their lines are grey.
    local free = not (gear and tab.Planned())
    AddCheck(root, L.AFFORD, IsSet, Flip, "affordableOnly", nil, free)
    if not gear then
        AddCheck(root, L.SUP_BEST, IsSet, Flip, "bestOnly", L.SUP_BEST_TIP)
        return
    end
    local top = ns.Results.TOP_COUNT
    AddCheck(root, L.TOP:format(top), IsSet, Flip, "topOnly", L.TOP_TIP:format(top), free)
    -- "Only leather", "Only mail" or "Only plate": the line names the heaviest armor the
    -- character wears. One that wears cloth alone has nothing to leave out, and no line.
    local armor = ns.Wants.Armor(Owner())
    if armor then AddCheck(root, L["ARMOR_ONLY_" .. armor], ArmorOnly, FlipArmor, nil, L.ARMOR_ONLY_TIP) end
    AddCheck(root, L.GAIN_MIN, GainOn, FlipGain, nil, L.GAIN_MIN_TIP):AddInitializer(AddNumber)
    root:CreateDivider():AddInitializer(Widgets.SkinMenuDivider)
    AddCheck(root, L.NET, IsSet, Flip, "net", L.NET_TIP)
end

---------------------------------------------------------------------------
-- The field
---------------------------------------------------------------------------
-- Makes the field on a tab's frame. Returns it, and the text that stands beside it.
--   hooks   what the tab tells the field, and hears from it:
--             View()       "gear" or "supplies": the view the frame shows
--             Planned()    the list of gear shows the best set for a budget
--             Changed(sameOffers)   a box was ticked or a number typed. `sameOffers`: what
--                          changed is how prices are read (Net cost), not what is listed
function Filters.Build(frame, hooks)
    tab = hooks
    field = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    field:SetHeight(FIELD_HEIGHT)
    Widgets.SkinDropdown(field)
    -- The field reads "Filters" whatever is ticked. What is ticked stands beside it.
    field:OverrideText(L.FILTERS)
    field:SetWidth(math.max(FIELD_MIN, field.Text:GetUnboundedStringWidth() + 44))
    -- The field stands at the window's edge: its menu hangs from its right end.
    field:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPRIGHT", field, "BOTTOMRIGHT", 0, 0))
    field:SetupMenu(Menu)
    field:SetTooltip(FieldTooltip)

    names = NewText(frame, 10.5, SOFT, "RIGHT")
    names:SetPoint("RIGHT", field, "LEFT", -GAP, 0)
    return field, names
end
