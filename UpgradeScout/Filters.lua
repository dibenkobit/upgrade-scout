local _, ns = ...
local L = ns.L

-- The Filters field of the addon's two tabs: one of the game's dropdowns, like the profile
-- field, whose menu has a tick box for every filter of the list in view. (The tick boxes once
-- stood in a row above the list, and three of them filled it.)
--   Upgrades      Only what I can afford, Buyout up to (a sum), Top N per slot, Hide worse
--                 deals, Best armor type for the class, Upgrade at least N %, Gear at most
--                 N levels below,
--                 Weapons (a line that opens a menu of its own: how the hands are filled,
--                 and the kinds of weapon); and under a rule Value by net cost, which is no
--                 filter: it says which of a row's two prices the best value is judged by
--   Consumables   Only what I can afford, Best for me, Everything I can use. The last one
--                 lets more in where the others leave out: unticked, the list is of what
--                 has a score (see Supplies.lua)
-- The menu stays open while its boxes are ticked, as the game's own menu of auction filters
-- does. Beside the field stand the names of the filters that are on, so that it is plain
-- without a click why the list is what it is; where they do not fit, how many are on.
--
-- Most of the filters of gear are kept with the character the list is for: every character
-- has its own, whichever character of the account shops for it (see Wants.lua). They are
-- about that character, its armor, the least gain, the levels below its own and its weapons;
-- and one is the most to pay for one item for it. The others are the player's (ns.db), the
-- number of "Top N per slot" with them.
local Filters = {}
ns.Filters = Filters

local Widgets = ns.Widgets
local NewSlices, NewText = Widgets.NewSlices, Widgets.NewText
local CREAM, SOFT, MUTED = Widgets.CREAM, Widgets.SOFT, Widgets.MUTED

local FIELD_HEIGHT, FIELD_MIN = 24, 86
local NUMBER_WIDTH, NUMBER_HEIGHT = 46, 18      -- the field for a percent: four digits and air
local LEVELS_WIDTH = 30                         -- the field for two digits: a number of levels, or of rows
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
    -- With the best set for a budget shown, the list is that set: the two price filters,
    -- "Top N" and "Hide worse deals" have no say.
    local planned = gear and tab.Planned()
    if ns.db.affordableOnly and not planned then Add(L.AFFORD_SHORT, L.AFFORD) end
    if not gear then
        if ns.db.bestOnly then Add(L.SUP_BEST) end
        if ns.db.allUsable then Add(L.SUP_ALL_SHORT, L.SUP_ALL) end
        return out
    end
    local cap = not planned and ns.Wants.Price(Owner())
    if cap then Add(L.PRICE_MAX_SHORT:format(ns.Money(cap)), L.PRICE_MAX_FULL:format(ns.Money(cap))) end
    if ns.db.topOnly and not planned then
        local top = ns.Results.TopCount()
        Add(L.TOP_SHORT:format(top), L.TOP_FULL:format(top))
    end
    if ns.db.hideWorse and not planned then Add(L.DEALS_SHORT, L.DEALS) end
    local owner = Owner()
    local wants = ns.Wants.Of(owner)
    if wants and wants.armor then Add(L.ARMOR_BEST_SHORT, L.ARMOR_BEST) end
    if wants and wants.gain then Add(L.GAIN_MIN_SHORT:format(wants.gain), L.GAIN_MIN_FULL:format(wants.gain)) end
    -- Beside the field stands the level the number comes to for this character, which is
    -- what the list goes by; the field's tooltip has the line as the menu has it. A number
    -- that reaches down to the first level leaves nothing out (it is none of the wants),
    -- and the box is named all the same while it is ticked: "From level 1".
    if owner and owner.maxBelowOn == true then
        Add(L.LEVEL_MIN_SHORT:format(ns.Wants.LevelTyped(owner) or 1), L.LEVEL_MIN_FULL:format(ns.Wants.Below(owner)))
    end
    -- How the hands are filled is named where it leaves something out, whether the player
    -- chose it or the profile did: either way it is why the list is what it is.
    if wants and wants.hands == "TWO" then Add(L.HANDS_TWO) end
    if wants and wants.hands == "ONE" then Add(L.HANDS_ONE_SHORT, L.HANDS_ONE) end
    if wants and wants.kinds then
        -- How many kinds of weapon are still offered, of those the class has.
        local _, gone = ns.Wants.KindsOut(owner)
        local all = #ns.Roster.WeaponKinds(owner.class)
        Add(L.KINDS_SHORT:format(all - gone, all), L.KINDS_FULL:format(all - gone, all))
    end
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

-- The three that are the character's.
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

local function BelowOn()
    local card = Owner()
    return card ~= nil and card.maxBelowOn == true
end

local function FlipBelow()
    local card = Owner()
    if not card then return end
    -- (A card comes out of a saved file: only a true tick is one, and whatever else stands
    -- there gives way to a click.)
    ns.Wants.SetBelow(card, card.maxBelowOn ~= true)
    tab.Changed()
end

-- And the fourth that is kept with the character: the most to pay for one item.
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

-- "Gear at most N levels below" counts from the level of the character the list is for, so
-- the line's tooltip says which level the number comes to for that character, ticked or
-- not: "Diluna: From level 20". (From level 1 where it reaches that far down: everything.)
local function LevelNote(card)
    if not card then return nil end
    local word = L.LEVEL_MIN_SHORT:format(ns.Wants.LevelTyped(card) or 1)
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

-- A line with a number: after the words of its tick box, a field for the number and what
-- stands after it. "Upgrade at least [ 50 ] %" is one, "Gear at most [ 10 ] levels below"
-- another, "Top [ 5 ] per slot" the third.
--   * A number typed is asked for at once, and ticks the box.
--   * Unticked, the box leaves the number in the field, in a dimmer ink.
--   * An empty field asks for nothing. Left empty, it unticks the box and shows the last
--     number again.
--   * More typed than is taken (99 levels) is asked for as the most there is, and the field
--     shows that when it is left.
-- Ticking a line by typing must not draw the menu again, which would take the field from
-- under the keys: the tick is switched on the line itself (see Widgets.SkinMenuCheck).
-- `kind` is the number of the line:
--   width, letters   how wide its field is, and how many digits it takes
--   after            what stands after the field: a sign, or the words the line goes on with
--   IsOn(card)       is it asked for of the character, Typed(card) the number typed for it,
--   Set(card, on, number)   and what sets both (Wants.lua)
--   Holder()         whose the number is, where it is not the character's: what it returns
--                    stands for the card in the three above (the buyer's settings, ns.db)
--   Open()           is the line to be typed into: not while it is grey, when its field is
--                    only read, as the fields of the sum are. Always, where there is none.
-- Returns what the game calls when it draws the line, which returns the size of the line:
-- the game would otherwise have to measure it.
local function NumberLine(kind)
    return function(button)
        local card
        if kind.Holder then card = kind.Holder() else card = Owner() end
        local open = not kind.Open or kind.Open()
        local words = button.fontString
        local box = NewField(button, kind.width, kind.letters, open)
        box:SetPoint("LEFT", words, "RIGHT", 6, -1)

        local function Ink()
            local ink = open and card and kind.IsOn(card) and CREAM or MUTED
            box:SetTextColor(ink[1], ink[2], ink[3])
        end
        local function Tick(shown)
            if button.Tick then button.Tick:SetShown(shown) end
        end
        box:SetText(tostring(kind.Typed(card)))
        Ink()

        box:SetScript("OnTextChanged", function(self, userInput)
            if not userInput or not card then return end
            local number = self:GetNumber()
            if number < 1 then return end
            kind.Set(card, true, number)
            Tick(true)
            Ink()
            tab.Changed()
        end)
        -- The field is left: by Enter or Escape, by a click elsewhere.
        local function Settle(self)
            if not card then return end
            local number = self:GetNumber()
            if number < 1 then
                if kind.IsOn(card) then
                    kind.Set(card, false)
                    Tick(false)
                    tab.Changed()
                end
            elseif number == kind.Typed(card) then
                return
            end
            self:SetText(tostring(kind.Typed(card)))
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
        local ink = open and CREAM or MUTED
        sign:SetTextColor(ink[1], ink[2], ink[3])
        sign:SetTextToFit(kind.after)
        -- The tick box, the words (which the game puts 7 after it), the field and what
        -- stands after it.
        return BOX_WIDTH + 7 + words:GetStringWidth() + 6 + kind.width + 4 + sign:GetStringWidth(), LINE_HEIGHT
    end
end

-- "Upgrade at least [ 50 ] %": the least an upgrade has to add, in percent.
local AddGain = NumberLine({
    width = NUMBER_WIDTH, letters = 4, after = "%",
    IsOn = function(card) return card.minGainOn end,
    Typed = function(card) return ns.Wants.Gain(card) end,
    Set = function(card, on, number) ns.Wants.SetGain(card, on, number) end,
})

-- "Gear at most [ 10 ] levels below": how far below the character's level gear may be made
-- for. Its words go on after the field, in the languages that put them there.
local AddLevels = NumberLine({
    width = LEVELS_WIDTH, letters = 2, after = L.LEVEL_MIN_AFTER,
    IsOn = function(card) return card.maxBelowOn == true end,
    Typed = function(card) return ns.Wants.Below(card) end,
    Set = function(card, on, number) ns.Wants.SetBelow(card, on, number) end,
})

-- "Top [ 5 ] per slot": how many of its biggest upgrades a slot shows, from 1 to 99. The
-- number is the buyer's, as its tick box is (ns.db), and stays when the box is unticked.
-- While the list shows the best set for a budget the line is grey and its field only read.
local AddTop = NumberLine({
    width = LEVELS_WIDTH, letters = 2, after = L.TOP_AFTER,
    Holder = function() return ns.db end,
    Open = function() return not tab.Planned() end,
    IsOn = function(db) return db.topOnly end,
    Typed = function() return ns.Results.TopCount() end,
    Set = function(db, on, number)
        if number then db.topCount = math.min(math.floor(number), ns.Results.TOP_MAX) end
        db.topOnly = on and true or false
    end,
})

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

-- The line "Weapons". It opens a menu of its own beside it, with what the character the list
-- is for is to be offered for its hands (Wants.lua):
--   * how it fills them, one of three: any way; with a two-hander; with a weapon for one
--     hand and a shield, a held item or a second weapon beside it. Until the player chooses,
--     the profile does (Wants.Hands), and the line it chose is the one marked: its tooltip
--     says who chose.
--   * under a rule, a tick box for every kind of weapon the character's class can ever
--     wield, by the game's own names, those for one hand, for both and for the ranged slot
--     each under a rule of their own. All are ticked until one is unticked: that kind is
--     then left out of the list.
-- A click on any of them leaves both menus open, as a tick box of the menu itself does. A
-- line that is one choice of several closes its menu unless it says otherwise: these say so.
local function HandsAre(hands)
    local card = Owner()
    return card ~= nil and ns.Wants.Hands(card) == hands
end

local function SetHands(hands)
    local card = Owner()
    if not card then return end
    ns.Wants.SetHands(card, hands)
    tab.Changed()
end

local function KindOn(kind)
    local card = Owner()
    return card ~= nil and not ns.Wants.KindOut(card, kind)
end

local function FlipKind(kind)
    local card = Owner()
    if not card then return end
    ns.Wants.SetKind(card, kind, ns.Wants.KindOut(card, kind))
    tab.Changed()
end

-- The line itself has no tick box: its word stands where the words of the lines above it
-- do, after the room of a box, and not under their boxes.
local function Indent(button)
    local words = button.fontString
    if not words then return end
    words:ClearAllPoints()
    words:SetPoint("LEFT", button, "LEFT", BOX_WIDTH + 7, 0)
end

local function AddWeapons(root, owner)
    local menu = root:CreateButton(L.WEAPONS)
    menu:AddInitializer(Widgets.SkinMenuLine)
    menu:AddInitializer(Indent)
    for _, hands in ipairs(ns.Wants.HANDS) do
        local text = L["HANDS_" .. hands]
        local line = menu:CreateRadio(text, HandsAre, SetHands, hands)
        line:SetResponse(MenuResponse.Refresh)
        line:AddInitializer(Widgets.SkinMenuLine)
        line:SetTooltip(function(tooltip)
            GameTooltip_SetTitle(tooltip, text)
            GameTooltip_AddNormalLine(tooltip, L["HANDS_" .. hands .. "_TIP"])
            -- The line the profile chose, while the player has not: on which profile.
            local card = Owner()
            local now, own = ns.Wants.Hands(card)
            local profile = card and not own and now == hands and hands ~= "ANY" and ns.Score.Current(card)
            if profile then GameTooltip_AddHighlightLine(tooltip, L.HANDS_BY_PROFILE:format(profile.title)) end
        end)
    end
    local held
    for _, weapon in ipairs(ns.Roster.WeaponKinds(owner.class)) do
        local name = C_Item.GetItemSubClassInfo(Enum.ItemClass.Weapon, weapon.kind)
        -- (A kind the game has no name for has no line: there is nothing to call it by.)
        if type(name) == "string" and name ~= "" then
            if weapon.held ~= held then
                held = weapon.held
                menu:CreateDivider():AddInitializer(Widgets.SkinMenuDivider)
            end
            AddCheck(menu, name, KindOn, FlipKind, weapon.kind, L.KINDS_TIP)
        end
    end
end

-- The game calls this each time the menu opens.
local function Menu(_, root)
    local gear = tab.View() == "gear"
    -- What the best set for a budget holds is not for the price filters, for "Top N" or for
    -- "Hide worse deals" to say: while the list shows that set, their lines are grey.
    local free = not (gear and tab.Planned())
    AddCheck(root, L.AFFORD, IsSet, Flip, "affordableOnly", nil, free)
    if not gear then
        AddCheck(root, L.SUP_BEST, IsSet, Flip, "bestOnly", L.SUP_BEST_TIP)
        AddCheck(root, L.SUP_ALL, IsSet, Flip, "allUsable", L.SUP_ALL_TIP)
        return
    end
    AddCheck(root, L.PRICE_MAX, PriceOn, FlipPrice, nil, L.PRICE_MAX_TIP, free):AddInitializer(AddSum)
    -- "Top [ 5 ] per slot". The words of its tick box alone are no name for it: its tooltip
    -- is titled with the line in full, with the number as it stands at that moment.
    local top = AddCheck(root, L.TOP, IsSet, Flip, "topOnly", nil, free)
    top:AddInitializer(AddTop)
    top:SetTooltip(function(tooltip)
        GameTooltip_SetTitle(tooltip, L.TOP_FULL:format(ns.Results.TopCount()))
        GameTooltip_AddNormalLine(tooltip, L.TOP_TIP)
    end)
    -- "Hide worse deals", which goes with "Top N" or without it (Results.Build).
    AddCheck(root, L.DEALS, IsSet, Flip, "hideWorse", L.DEALS_TIP, free)
    -- "Best armor type for the class" keeps the heaviest armor the character wears, and its
    -- tooltip names it. One that wears cloth alone has nothing to leave out, and no line.
    local owner = Owner()
    local armor = ns.Wants.Armor(owner)
    if armor then
        AddCheck(root, L.ARMOR_BEST, ArmorOnly, FlipArmor, nil, L.ARMOR_BEST_TIP, nil, ArmorNote(owner, armor))
    end
    AddCheck(root, L.GAIN_MIN, GainOn, FlipGain, nil, L.GAIN_MIN_TIP):AddInitializer(AddGain)
    -- "Gear at most N levels below" reads the same for every character, so the line's
    -- tooltip names the level it comes to for the one the list is for.
    AddCheck(root, L.LEVEL_MIN, BelowOn, FlipBelow, nil, L.LEVEL_MIN_TIP, nil, LevelNote(owner)):AddInitializer(AddLevels)
    if owner then AddWeapons(root, owner) end
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
