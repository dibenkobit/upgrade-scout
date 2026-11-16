local _, ns = ...
local L = ns.L

-- The Filters field of the addon's two tabs: one of the game's dropdowns, like the profile
-- field, whose menu has a tick box for every filter of the list in view. (The tick boxes once
-- stood in a row above the list, and three of them filled it.)
--   Upgrades      Only what I can afford, Buyout up to (a sum), Top N per slot, Best armor
--                 type for the class, Upgrade at least N %; and under a rule Value by net
--                 cost, which is no filter: it says which of a row's two prices the best
--                 value is judged by
--   Consumables   Only what I can afford, Best for me
-- The menu stays open while its boxes are ticked, as the game's own menu of auction filters
-- does. Beside the field stand the names of the filters that are on, so that it is plain
-- without a click why the list is what it is; where they do not fit, how many are on.
--
-- Three of the filters of gear are kept with the character the list is for: every character
-- has its own, whichever character of the account shops for it (see Wants.lua). Two of them
-- are about that character, the armor and the least gain; the third is the most to pay for
-- one item for it. The others are the player's (ns.db).
local Filters = {}
ns.Filters = Filters

local Widgets = ns.Widgets
local NewSlices, NewText = Widgets.NewSlices, Widgets.NewText
local CREAM, SOFT, MUTED = Widgets.CREAM, Widgets.SOFT, Widgets.MUTED

local FIELD_HEIGHT, FIELD_MIN = 24, 86
local NUMBER_WIDTH, NUMBER_HEIGHT = 46, 18      -- the field for a percent: four digits and air
local GOLD_WIDTH, SILVER_WIDTH = 46, 30         -- the fields of a sum: five digits of gold, two of silver
local COIN_SIZE, COIN_GAP = 13, 3               -- the coin after a field of a sum, and the room before it
local BOX_WIDTH, LINE_HEIGHT = 16, 20           -- a line's tick box, and how tall a line is
-- What a field of the menu is told to do, by one line or another (see NewField).
local FIELD_SCRIPTS = { "OnTextChanged", "OnEditFocusGained", "OnEditFocusLost", "OnEnterPressed", "OnEscapePressed", "OnTabPressed" }
local GAP = 8                                   -- between the field and the names beside it
-- Between two names stands a dot at mid height. The game's Russian font (FRIZQT___CYR.TTF)
-- has no such sign and draws a square in its place, so the Russian client gets a bullet,
-- which that font has. A bullet for every language would not do: the game's Chinese font
-- (ARKai_T.ttf) has an empty place for it.
local SEPARATOR = GetLocale() == "ruRU" and " \226\128\162 " or " \194\183 "

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
-- `short` as it is named beside the field and `full` as the menu has it. "Value by net cost"
-- is not one of them: the list says it itself, the price the best value goes by standing in
-- white and the other in grey.
local function Active()
    local out = {}
    local function Add(short, full)
        out[#out + 1] = { short = short, full = full or short }
    end
    local gear = tab.View() == "gear"
    -- With the best set for a budget shown, the list is that set: the two price filters and
    -- "Top N" have no say.
    local planned = gear and tab.Planned()
    if ns.db.affordableOnly and not planned then Add(L.AFFORD_SHORT, L.AFFORD) end
    if not gear then
        if ns.db.bestOnly then Add(L.SUP_BEST) end
        return out
    end
    local cap = not planned and ns.Wants.Price(Owner())
    if cap then Add(L.PRICE_MAX_SHORT:format(ns.Money(cap)), L.PRICE_MAX_FULL:format(ns.Money(cap))) end
    if ns.db.topOnly and not planned then Add(L.TOP:format(ns.Results.TOP_COUNT)) end
    local wants = ns.Wants.Of(Owner())
    if wants and wants.armor then Add(L.ARMOR_BEST_SHORT, L.ARMOR_BEST) end
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
-- it; `tip` is what its tooltip says under its name, and `note` a line of its own after that.
-- A line that is not `enabled` is grey and takes no click.
local function AddCheck(root, text, isOn, flip, data, tip, enabled, note)
    local line = root:CreateCheckbox(text, isOn, flip, data)
    line:AddInitializer(Widgets.SkinMenuCheck)
    if tip then
        line:SetTooltip(function(tooltip)
            GameTooltip_SetTitle(tooltip, text)
            GameTooltip_AddNormalLine(tooltip, tip)
            if note then GameTooltip_AddHighlightLine(tooltip, note) end
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
    -- "Value by net cost" changes how the offers are judged, not which offers there are.
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

-- And the third that is kept with the character: the most to pay for one item.
local function PriceOn()
    local card = Owner()
    return card ~= nil and card.maxPriceOn == true
end

local function FlipPrice()
    local card = Owner()
    if not card then return end
    ns.Wants.SetPrice(card, not card.maxPriceOn)
    tab.Changed()
end

-- "Best armor type for the class" reads the same for every class, so the line's tooltip says
-- which type that is for the character the list is for, in the game's own word for it:
-- "Diluna: Leather". `armor` is that type (Wants.Armor).
local function ArmorNote(card, armor)
    local word = C_Item.GetItemSubClassInfo(Enum.ItemClass.Armor, armor)
    if not word or word == "" then return nil end
    if not card.name then return word end
    return ns.Roster.Colored(card, card.name) .. ": " .. word
end

-- A field for a number on a line of the menu, `width` wide, for `letters` digits. One that is
-- not `open` is to be read and not typed into: the mouse does not reach it.
-- The game makes the lines of a menu anew whenever it draws the menu, so a field is attached
-- to its line each time the line is drawn (the game's own menu of auction filters has its
-- level fields the same way), and not made once and kept.
local function NewField(button, width, letters, open)
    local box = button:AttachFrame("EditBox")
    -- The game hands a frame over reset to nothing: in no layer of the menu's, so that it is
    -- drawn under the menu's plate and nothing of it is seen, and with the rest of what it was
    -- made with wiped as well. (Its own menus say as much where they attach a button, and set
    -- these by hand: MenuTemplates.AttachBasicButton.) So the field is put in the menu's layer,
    -- above its line, in view and in reach of the mouse.
    box:SetFrameStrata(button:GetFrameStrata())
    box:SetFrameLevel(button:GetFrameLevel() + 1)
    box:Show()
    box:EnableMouse(open ~= false)
    box:SetSize(width, NUMBER_HEIGHT)
    NewSlices(box, "Inset", 0.25, 6, "BACKGROUND", 0, 0, function() return box:AttachTexture() end)
    box:SetFont(Widgets.NumberFont(), 12, "")
    box:SetJustifyH("CENTER")
    -- A field the game has just made takes the keys as soon as it is in view, and the game
    -- shows this one before it hands it over: the keys are given back, so that opening the
    -- menu does not stop the character walking.
    box:SetAutoFocus(false)
    box:ClearFocus()
    box:SetNumeric(true)
    box:SetMaxLetters(letters)
    -- The game takes a field back when the menu closes and may hand the same one to another
    -- line the next time. Whatever a line had it do goes first: the line it is on now says
    -- what it is to do.
    for i = 1, #FIELD_SCRIPTS do box:SetScript(FIELD_SCRIPTS[i], nil) end
    return box
end

-- The line "Upgrade at least [ 50 ] %": after the words of its tick box, a field for the
-- number and a percent sign.
--   * A number typed is asked for at once, and ticks the box.
--   * Unticked, the box leaves the number in the field, in a dimmer ink.
--   * An empty field asks for nothing. Left empty, it unticks the box and shows the last
--     number again.
-- Ticking a line by typing must not draw the menu again, which would take the field from
-- under the keys: the tick is switched on the line itself (see Widgets.SkinMenuCheck).
-- Returns the size of the line, which the game would otherwise have to measure.
local function AddNumber(button)
    local card = Owner()
    local words = button.fontString
    local box = NewField(button, NUMBER_WIDTH, 4)
    box:SetPoint("LEFT", words, "RIGHT", 6, -1)

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

-- The line "Buyout up to [ 5 ] (gold) [ 00 ] (silver)": after the words of its tick box, a
-- field for the gold and one for the silver with a coin after each, as the strip of the best
-- set has its budget. The sum is the most to pay for one item, kept with the character the
-- list is for (Wants.lua). The line goes by the rules of the one with the percent:
--   * A sum typed is asked for at once, and ticks the box.
--   * Unticked, the box leaves the sum in the fields, in a dimmer ink.
--   * No sum (both fields empty, or nought) asks for nothing. Enter or Escape on it unticks
--     the box and shows the last sum again. Leaving one field for the other does neither:
--     the gold is emptied on the way to a sum in silver alone.
-- A field that takes the keys has its number marked, so that the next digit replaces it:
-- the silver is two digits in a field for two.
-- While the list shows the best set for a budget the line is grey, as the other price
-- filter's is, and its fields are only read.
-- Returns the size of the line.
local function AddSum(button)
    local card = Owner()
    local words = button.fontString
    local open = not tab.Planned()
    local gold = NewField(button, GOLD_WIDTH, 5, open)
    gold:SetPoint("LEFT", words, "RIGHT", 6, -1)
    local silver = NewField(button, SILVER_WIDTH, 2, open)

    -- A coin after each field, the game's own.
    local function Coin(box, name)
        local coin = button:AttachTexture()
        coin:SetTexture("Interface\\MoneyFrame\\UI-" .. name .. "Icon")
        coin:SetTexCoord(0, 1, 0, 1)
        coin:SetDrawLayer("ARTWORK")
        coin:SetSize(COIN_SIZE, COIN_SIZE)
        coin:SetPoint("LEFT", box, "RIGHT", COIN_GAP, 0)
        return coin
    end
    gold.Coin = Coin(gold, "Gold")
    silver:SetPoint("LEFT", gold.Coin, "RIGHT", 6, 0)
    silver.Coin = Coin(silver, "Silver")

    -- What the two fields hold, in copper.
    local function Typed()
        return gold:GetNumber() * 10000 + silver:GetNumber() * 100
    end
    local function Ink()
        local ink = open and card and card.maxPriceOn and CREAM or MUTED
        gold:SetTextColor(ink[1], ink[2], ink[3])
        silver:SetTextColor(ink[1], ink[2], ink[3])
    end
    -- The sum of the card in the two fields.
    local function Paint()
        local copper = ns.Wants.PriceTyped(card)
        gold:SetText(tostring(math.floor(copper / 10000)))
        silver:SetText(("%02d"):format(math.floor(copper / 100) % 100))
        Ink()
    end
    local function Tick(shown)
        if button.Tick then button.Tick:SetShown(shown) end
    end
    Paint()

    local function Changed(_, userInput)
        if not userInput or not card then return end
        local copper = Typed()
        if copper < 100 then return end
        ns.Wants.SetPrice(card, true, copper)
        Tick(true)
        Ink()
        tab.Changed()
    end
    -- Enter or Escape in a field.
    local function Leave(self)
        if card and Typed() < 100 then
            if card.maxPriceOn then
                ns.Wants.SetPrice(card, false)
                Tick(false)
                tab.Changed()
            end
            Paint()
        end
        self:ClearFocus()
    end
    local function Mark(self)
        self:HighlightText()
    end
    for _, box in ipairs({ gold, silver }) do
        box:SetScript("OnTextChanged", Changed)
        box:SetScript("OnEditFocusGained", Mark)
        box:SetScript("OnEnterPressed", Leave)
        box:SetScript("OnEscapePressed", Leave)
    end
    gold:SetScript("OnTabPressed", function() silver:SetFocus() end)
    silver:SetScript("OnTabPressed", function() gold:SetFocus() end)
    button.Gold, button.Silver = gold, silver

    -- The tick box, the words (which the game puts 7 after it), and the two fields, each
    -- with its coin.
    return BOX_WIDTH + 7 + words:GetStringWidth() + 6 + GOLD_WIDTH + COIN_GAP + COIN_SIZE
        + 6 + SILVER_WIDTH + COIN_GAP + COIN_SIZE, LINE_HEIGHT
end

-- The game calls this each time the menu opens.
local function Menu(_, root)
    local gear = tab.View() == "gear"
    -- What the best set for a budget holds is not for the price filters or for "Top N" to
    -- say: while the list shows that set, their lines are grey.
    local free = not (gear and tab.Planned())
    AddCheck(root, L.AFFORD, IsSet, Flip, "affordableOnly", nil, free)
    if not gear then
        AddCheck(root, L.SUP_BEST, IsSet, Flip, "bestOnly", L.SUP_BEST_TIP)
        return
    end
    AddCheck(root, L.PRICE_MAX, PriceOn, FlipPrice, nil, L.PRICE_MAX_TIP, free):AddInitializer(AddSum)
    local top = ns.Results.TOP_COUNT
    AddCheck(root, L.TOP:format(top), IsSet, Flip, "topOnly", L.TOP_TIP:format(top), free)
    -- "Best armor type for the class" keeps the heaviest armor the character wears, and its
    -- tooltip names it. One that wears cloth alone has nothing to leave out, and no line.
    local owner = Owner()
    local armor = ns.Wants.Armor(owner)
    if armor then
        AddCheck(root, L.ARMOR_BEST, ArmorOnly, FlipArmor, nil, L.ARMOR_BEST_TIP, nil, ArmorNote(owner, armor))
    end
    AddCheck(root, L.GAIN_MIN, GainOn, FlipGain, nil, L.GAIN_MIN_TIP):AddInitializer(AddNumber)
    root:CreateDivider():AddInitializer(Widgets.SkinMenuDivider)
    AddCheck(root, L.NET_VALUE, IsSet, Flip, "net", L.NET_TIP)
end

---------------------------------------------------------------------------
-- The field
---------------------------------------------------------------------------
-- Makes the field on a tab's frame. Returns it, and the text that stands beside it.
--   hooks   what the tab tells the field, and hears from it:
--             View()       "gear" or "supplies": the view the frame shows
--             Planned()    the list of gear shows the best set for a budget
--             Changed(sameOffers)   a box was ticked or a number typed. `sameOffers`: what
--                          changed is how the offers are judged (Value by net cost), not
--                          which of them the filters let through
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
