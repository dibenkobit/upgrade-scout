local ADDON, ns = ...
local L = ns.L

-- The welcome window: what the addon does and its few settings, in one look.
--
-- It comes up by itself once, a few seconds after the game is first entered with the addon (or
-- with the version that brought the window), and after that when it is asked for: the button
-- at the minimap (Minimap.lua), /upscout away from the auction house or on the addon's own
-- tab there, the addon's page in the game's own list of addons. However it is closed, it has
-- been seen.
--
-- It comes up by itself once more for a player who has Pawn, the first time since Pawn could
-- be chosen in it (see Due).
--
-- Top to bottom:
--   what the addon is, in a sentence
--   who scores gear: the addon by its own weights, or Pawn by the player's Pawn scales
--     (Score.Engine). Two buttons side by side; Pawn's is grey while Pawn is not there, and
--     says why in a tooltip of its own
--   the talent tree the character is played with, a button for each profile of its class
--     (the one in use is lit: see Score.Current). With Pawn scoring, its Pawn scales
--   what the addon puts into the game. Two cards side by side: the tabs at the auction house
--     and the arrows in the bags, each with a picture of the thing as it looks in the game,
--     its name and a sentence. The arrows can be switched off, by the tick box before the
--     name (ns.Shows).
--   under them, as wide as both, the block of the lines in an item's tooltip, which has more
--     to ask. On its left the picture of a tooltip; on its right the name, a sentence and
--     what is asked.
--     Of the score, how much better an item is, two questions. How: every talent tree or the
--     one in use, a button for each (ns.OwnTree). Where: on the addon's tabs at the auction
--     house, elsewhere in the game, a tick box for each (ns.Shows "rowTooltip" and
--     "tooltip"), so both, either or neither.
--     Of the notes in the tooltip of a row of the addon's tabs (what the player is short of,
--     what a net cost is made of, both hands: AddNotes in UI.lua), under a fine line, whether
--     they show: a tick box (ns.Shows "rowNotes").
--     The picture shows what the answers come to, and fades when nothing shows.
--     With Pawn scoring, the score in a tooltip is Pawn's to write: the block says so in
--     place of its sentence, and what is asked of the score is out of use. The notes are
--     ours whoever scores, and their box stays.
--   how to get the window back, and the button that closes it
-- Everything is laid out from the height its texts turn out to have (see Layout): a language
-- with longer words gets a taller window, not a cut sentence.
local Welcome = {}
ns.Welcome = Welcome

local Widgets = ns.Widgets
local NewTexture, NewRule, NewSlices, NewText, NewButton =
    Widgets.NewTexture, Widgets.NewRule, Widgets.NewSlices, Widgets.NewText, Widgets.NewButton
local GOLD, GOLD_DIM, CREAM, SOFT, GREEN = Widgets.GOLD, Widgets.GOLD_DIM, Widgets.CREAM, Widgets.SOFT, Widgets.GREEN

local WIDTH, EDGE = 660, 20
local GAP = 11                  -- between two cards, and between two buttons of the trees
local CARD_WIDTH = (WIDTH - 2 * EDGE - GAP) / 2
local PICTURE = 112             -- the height of a card's picture
local TREE_HEIGHT = 28
local TREES_IN_ROW = 4          -- more buttons than this (Pawn scales can be many) go in rows
local TREE_ROW_GAP = 7          -- between two such rows
-- The tooltip's block: its width; the width of the tooltip in its picture and of the room that
-- picture has on the left; where its words begin and how much room they have; the height of
-- the two buttons, their least width, and the room between two things in a row.
local BLOCK_WIDTH = WIDTH - 2 * EDGE
local TIP_WIDTH, TIP_ROOM = 167, 199
local BLOCK_TEXT = TIP_ROOM + 6
local BLOCK_ROOM = BLOCK_WIDTH - BLOCK_TEXT - 16
local HOW_HEIGHT, HOW_WIDTH, HOW_GAP = 24, 138, 7
local GREET_AFTER = 4           -- seconds in the world before the window comes up by itself
local GREET_RETRY = 5           -- and between two looks at whether the character is out of a fight

local ICON = "Interface\\AddOns\\" .. ADDON .. "\\icon"

-- The items the pictures are drawn with: two rings, which every class wears, both in the
-- game's item table (ItemSparse, build 1.60.1.70938). The game gives their names, in the
-- player's language, and their icons. The numbers are made up: what such a ring could gain on
-- the first, second, third and fourth profile of a class, what it could cost, and for the
-- first how much of that a player could be short of (`short`).
local SAMPLES = {
    { item = 16999, quality = 3, pick = "UPGRADE", gains = { 0.31, 0.36, 0.28, 0.33 }, price = 16900, short = 1200 },
    { item = 5000, quality = 2, pick = "VALUE", gains = { 0.19, 0.21, 0.17, 0.20 }, price = 2600 },
}

-- The two picks as the list names them (see PICKS in UI.lua).
local PICKS = {
    UPGRADE = { text = L.PICK_UPGRADE, fill = { 1.00, 0.78, 0.26, 0.16 }, edge = { 1.00, 0.78, 0.26, 0.80 }, ink = { 1.00, 0.86, 0.42 } },
    VALUE = { text = L.PICK_VALUE, fill = { 0.42, 0.86, 0.36, 0.15 }, edge = { 0.42, 0.86, 0.36, 0.75 }, ink = { 0.56, 0.94, 0.48 } },
}

local frame                     -- the window, made when it is first shown
local greeting = false          -- it is up for the first time: its first words are a welcome
local offering = false          -- it is up for the first time since Pawn could be chosen in it,
                                -- for a player who has Pawn: its first words say so

-- A part of a line in the softer colour: what is said in passing after what is asked.
local SOFT_CODE = string.format("|cff%02x%02x%02x", SOFT[1] * 255, SOFT[2] * 255, SOFT[3] * 255)
local function Aside(text)
    return "  " .. SOFT_CODE .. text .. "|r"
end

---------------------------------------------------------------------------
-- The sample items
---------------------------------------------------------------------------
-- What the game knows of a sample's item: its name, nil until the client has loaded it
-- (asking once makes it load, and the window is drawn again when it has: see the end of this
-- file); its quality; its icon, which takes no loading.
local asked = {}
local function Facts(sample)
    local name, _, quality = C_Item.GetItemInfo(sample.item)
    if not name and not asked[sample.item] then
        asked[sample.item] = true
        C_Item.RequestLoadItemDataByID(sample.item)
    end
    local _, _, _, _, icon = C_Item.GetItemInfoInstant(sample.item)
    return name, quality or sample.quality, icon
end

-- What a sample gains on the profile that is the `place`-th of its class.
local function Gain(sample, place)
    local share = sample.gains[(place - 1) % #sample.gains + 1]
    return "+" .. FormatPercentage(share, true)
end

---------------------------------------------------------------------------
-- The pictures
---------------------------------------------------------------------------
-- Each is made on the frame a card keeps for its picture, and has a Paint of its own that
-- takes what the window is about: { profiles = the profiles of the class, place = which of
-- them is in use, class }.

-- The auction house: a slot's heading and two rows of the list, the best upgrade and the best
-- value, each with its gain on the profile in use and its price.
local function PaintList(picture, about)
    for i = 1, #SAMPLES do
        local sample, row = SAMPLES[i], picture.Rows[i]
        local name, quality, icon = Facts(sample)
        row.Icon:SetTexture(icon)
        row.Name:SetText(name or "")
        row.Name:SetTextColor(ns.QualityColor(quality))
        row.Gain:SetText(Gain(sample, about.place))
        row.Price:SetText(ns.Money(sample.price))
    end
end

local function NewPick(row, kind)
    local look = PICKS[kind]
    local pick = CreateFrame("Frame", nil, row)
    pick:SetHeight(14)
    NewSlices(pick, "Chip", 0.3125, 5, "BACKGROUND"):SetVertexColor(look.fill[1], look.fill[2], look.fill[3], look.fill[4])
    NewSlices(pick, "ChipEdge", 0.3125, 5, "BORDER"):SetVertexColor(look.edge[1], look.edge[2], look.edge[3], look.edge[4])
    local text = NewText(pick, 9, look.ink)
    text:SetPoint("LEFT", pick, "LEFT", 6, 0)
    text:SetText(look.text)
    -- A long translation is cut short before it reaches the price.
    local width = math.min(text:GetUnboundedStringWidth(), CARD_WIDTH - 100)
    text:SetWidth(width)
    pick:SetWidth(width + 12)
    return pick
end

local function NewListPicture(picture)
    local band = NewTexture(picture, "HeaderBand", "BACKGROUND")
    band:SetPoint("TOPLEFT", picture, "TOPLEFT", 8, -11)
    band:SetPoint("TOPRIGHT", picture, "TOPRIGHT", -8, -11)
    band:SetHeight(17)
    local diamond = NewTexture(picture, "Diamond", "ARTWORK")
    diamond:SetSize(12, 12)
    diamond:SetPoint("LEFT", band, "LEFT", 4, 0)
    local slot = NewText(picture, 9.5, GOLD)
    slot:SetPoint("LEFT", band, "LEFT", 20, 0)
    slot:SetText(ns.Upper(ns.Compare.GroupLabel("FINGER")))

    picture.Rows = {}
    for i = 1, #SAMPLES do
        local row = CreateFrame("Frame", nil, picture)
        local top = 34 + (i - 1) * 38
        row:SetPoint("TOPLEFT", picture, "TOPLEFT", 9, -top)
        row:SetPoint("TOPRIGHT", picture, "TOPRIGHT", -10, -top)
        row:SetHeight(36)
        row.Icon = row:CreateTexture(nil, "ARTWORK")
        row.Icon:SetSize(17, 17)
        row.Icon:SetPoint("TOPLEFT", row, "TOPLEFT", 2.5, -2.5)
        row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local rim = NewTexture(row, "IconRim", "ARTWORK", 1)
        rim:SetSize(20, 20)
        rim:SetPoint("CENTER", row.Icon, "CENTER", 0, 0)
        row.Gain = NewText(row, 12, GREEN, "RIGHT", true)
        row.Gain:SetPoint("RIGHT", row, "TOPRIGHT", 0, -9)
        -- The name takes the room the gain leaves, and is cut short where it has too little.
        row.Name = NewText(row, 11, CREAM, "LEFT", true)
        row.Name:SetPoint("LEFT", row, "TOPLEFT", 27, -9)
        row.Name:SetPoint("RIGHT", row.Gain, "LEFT", -6, 0)
        NewPick(row, SAMPLES[i].pick):SetPoint("LEFT", row, "TOPLEFT", 27, -26)
        row.Price = NewText(row, 10, CREAM, "RIGHT", true)
        row.Price:SetPoint("RIGHT", row, "TOPRIGHT", 0, -26)
        picture.Rows[i] = row
    end
    picture.Paint = PaintList
end

-- An item's tooltip: its name, and under the addon's own heading a line for every profile of
-- the class with the gain on it, as Tooltip.lua writes them. With the tree in use alone
-- chosen (about.own) it has the one line of that profile, where the heading was, the addon's
-- icon before the profile's name (Tooltip.AddOwn).
-- Under those, a note as a row of the addon's tabs has it: what the player is short of
-- (AddNotes in UI.lua). `about.score` and `about.notes` say which of the two are in use, and
-- the picture has those: the note alone stands under the heading. With neither in use it
-- has the score's lines, for the window to fade (see Paint): what would come back.
-- How far down the heading is, the first line under it, and each line under the one before.
local TIP_HEAD, TIP_TOP, TIP_STEP = 28, 41, 12.5
local TIP_ICON = "|T" .. ICON .. ".tga:0|t "

local function PaintTip(picture, about)
    local tip = picture.Tip
    local sample = SAMPLES[1]
    local name, quality = Facts(sample)
    tip.Name:SetText(name or "")
    tip.Name:SetTextColor(ns.QualityColor(quality))

    local r, g, b = (RAID_CLASS_COLORS[about.class or ""] or HIGHLIGHT_FONT_COLOR):GetRGB()
    local score = about.score or not about.notes
    local count = #about.profiles
    local own = score and about.own and about.profiles[about.place] ~= nil
    tip.Brand:SetShown(not own)
    for i = 1, math.max(count, #tip.Lines) do
        local line = tip.Lines[i]
        if not line then
            line = { Title = NewText(tip, 9.5, CREAM), Gain = NewText(tip, 9.5, GREEN, "RIGHT") }
            line.Gain:SetTextColor(GREEN_FONT_COLOR:GetRGB())
            tip.Lines[i] = line
        end
        local profile = about.profiles[i]
        local shown = score and profile ~= nil and (not own or i == about.place)
        line.Title:SetShown(shown)
        line.Gain:SetShown(shown)
        if shown then
            local down = own and TIP_HEAD or TIP_TOP + (i - 1) * TIP_STEP
            line.Title:ClearAllPoints()
            line.Gain:ClearAllPoints()
            line.Title:SetPoint("LEFT", tip, "TOPLEFT", 8, -down)
            line.Gain:SetPoint("RIGHT", tip, "TOPRIGHT", -8, -down)
            line.Title:SetPoint("RIGHT", line.Gain, "LEFT", -6, 0)
            line.Title:SetText(own and TIP_ICON .. profile.title or profile.title)
            line.Title:SetTextColor(r, g, b)
            line.Gain:SetText(Gain(sample, i))
        end
    end
    -- How far down the last line is: of the score, or the heading where it has none.
    local last = TIP_HEAD
    if score and not own then last = TIP_TOP + math.max(count - 1, 0) * TIP_STEP end
    tip.Note:SetShown(about.notes == true)
    if about.notes then
        last = last == TIP_HEAD and TIP_TOP or last + TIP_STEP
        tip.Note:ClearAllPoints()
        tip.Note:SetPoint("LEFT", tip, "TOPLEFT", 8, -last)
        tip.Note:SetText(L.TT_CANT_AFFORD:format(ns.Money(sample.short)))
    end
    tip:SetHeight(last + 12)
end

local function NewTipPicture(picture)
    local tip = CreateFrame("Frame", nil, picture)
    tip:SetWidth(TIP_WIDTH)
    tip:SetPoint("CENTER", picture, "CENTER", 0, 0)
    local ground = tip:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints()
    ground:SetColorTexture(0.04, 0.04, 0.07, 0.94)
    -- A fine pale edge, as the game's own tooltips have: a line from corner to corner on
    -- each side, the first two lying and the last two upright.
    local sides = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }
    for i = 1, #sides do
        local edge = tip:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(0.62, 0.58, 0.50, 0.85)
        edge:SetPoint(sides[i][1], tip, sides[i][1], 0, 0)
        edge:SetPoint(sides[i][2], tip, sides[i][2], 0, 0)
        if i > 2 then edge:SetWidth(1) else edge:SetHeight(1) end
    end
    tip.Name = NewText(tip, 11, CREAM)
    tip.Name:SetPoint("LEFT", tip, "TOPLEFT", 8, -13)
    tip.Name:SetPoint("RIGHT", tip, "TOPRIGHT", -8, -13)
    -- The addon's heading in a tooltip (see T.AddHeader in Tooltip.lua).
    tip.Brand = NewText(tip, 9.5, CREAM)
    tip.Brand:SetPoint("LEFT", tip, "TOPLEFT", 8, -TIP_HEAD)
    tip.Brand:SetText(TIP_ICON .. "Upgrade Scout")
    tip.Brand:SetTextColor(0.53, 0.78, 0.96)
    tip.Lines = {}
    -- The note, in the red the game writes what the player falls short of.
    tip.Note = NewText(tip, 9.5, CREAM)
    tip.Note:SetTextColor(RED_FONT_COLOR:GetRGB())
    picture.Tip = tip
    picture.Paint = PaintTip
end

-- The bags: two slots, an arrow on each, the green one and the grey one (see Bags.lua).
local function PaintBag(picture)
    for i = 1, #SAMPLES do
        local _, _, icon = Facts(SAMPLES[i])
        picture.Slots[i].Icon:SetTexture(icon)
    end
end

local function NewBagPicture(picture)
    picture.Slots = {}
    for i = 1, #SAMPLES do
        local slot = CreateFrame("Frame", nil, picture)
        slot:SetSize(50, 50)
        slot:SetPoint("CENTER", picture, "CENTER", (i == 1 and -1 or 1) * 38, 0)
        slot.Icon = slot:CreateTexture(nil, "ARTWORK")
        slot.Icon:SetAllPoints()
        slot.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local rim = NewTexture(slot, "IconRim", "ARTWORK", 1)
        rim:SetPoint("TOPLEFT", slot, "TOPLEFT", -2, 2)
        rim:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 2, -2)
        -- The game's own arrow, a little bigger than a bag has it, for a picture.
        local arrow = slot:CreateTexture(nil, "OVERLAY", nil, 1)
        arrow:SetAtlas("bags-greenarrow")
        arrow:SetSize(26, 29)
        arrow:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
        arrow:SetDesaturated(i == 2)
        slot.Arrow = arrow
        picture.Slots[i] = slot
    end
    picture.Paint = PaintBag
end

---------------------------------------------------------------------------
-- The cards
---------------------------------------------------------------------------
local Paint

-- A tick box. `part` is what it switches: "arrows", "tooltip", "rowTooltip" or "rowNotes"
-- (ns.Shows), all on until unticked. What the box says is done at once, and written down
-- only when it is "off".
local function NewSwitch(parent, part)
    local check = CreateFrame("CheckButton", nil, parent)
    check.part = part
    check:SetSize(15, 15)
    NewSlices(check, "Inset", 0.25, 6, "BACKGROUND")
    local glow = NewTexture(check, "Glow", "HIGHLIGHT")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.74, 0.32, 0.55)
    glow:SetPoint("TOPLEFT", check, "TOPLEFT", -7, 7)
    glow:SetPoint("BOTTOMRIGHT", check, "BOTTOMRIGHT", 7, -7)
    check.Tick = NewTexture(check, "Check", "OVERLAY")
    check.Tick:SetSize(17, 17)
    check.Tick:SetPoint("CENTER", check, "CENTER", 1, 1)
    check:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if on then ns.account[part] = nil else ns.account[part] = false end
        ns.Fire("SETTING_CHANGED", part)
    end)
    return check
end

-- Shows a tick box as its part is: ticked or not.
local function PaintSwitch(switch)
    local on = ns.Shows(switch.part)
    switch:SetChecked(on)
    switch.Tick:SetShown(on)
    return on
end

-- part: what the card's tick box switches, nil for a card that has none (the auction house:
-- its tabs are in nobody's way).
local function NewCard(part, title, body, NewPicture)
    local card = CreateFrame("Frame", nil, frame)
    card:SetWidth(CARD_WIDTH)
    NewSlices(card, "Inset", 0.25, 8, "BACKGROUND")
    card.part = part

    card.Picture = CreateFrame("Frame", nil, card)
    card.Picture:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    card.Picture:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    card.Picture:SetHeight(PICTURE)
    NewPicture(card.Picture)
    local rule = NewRule(card)
    rule:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -PICTURE)
    rule:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -PICTURE)

    -- The name, after its tick box or, where there is none, a diamond in its place.
    if part then
        card.Switch = NewSwitch(card, part)
        card.Switch:SetPoint("TOPLEFT", card, "TOPLEFT", 11, -(PICTURE + 11))
    else
        local diamond = NewTexture(card, "Diamond", "ARTWORK")
        diamond:SetSize(15, 15)
        diamond:SetPoint("TOPLEFT", card, "TOPLEFT", 11, -(PICTURE + 11))
    end
    card.Title = NewText(card, 10.5, GOLD)
    card.Title:SetWordWrap(true)
    card.Title:SetWidth(CARD_WIDTH - 32 - 10)
    card.Title:SetPoint("TOPLEFT", card, "TOPLEFT", 32, -(PICTURE + 13))
    card.Title:SetText(ns.Upper(title))
    -- A click on the name ticks the box, as everywhere in the game.
    if part then card.Switch:SetHitRectInsets(0, -(6 + card.Title:GetStringWidth()), -4, -4) end

    card.Body = NewText(card, 10.5, CREAM)
    card.Body:SetWordWrap(true)
    card.Body:SetSpacing(3)
    card.Body:SetWidth(CARD_WIDTH - 24)
    card.Body:SetText(body)
    return card
end

---------------------------------------------------------------------------
-- One of several
---------------------------------------------------------------------------
-- A button for one answer of several: a profile of the class, or how a tooltip's lines are
-- written. The answer in force is lit, with a gold diamond before its name; the others are
-- dark.
local function PaintTree(button, chosen)
    button.Lit:SetShown(chosen)
    button.Mark:SetShown(chosen)
    local color = chosen and GOLD or SOFT
    button.Label:SetTextColor(color[1], color[2], color[3])
    -- The name stands in the middle: by itself, or with the diamond before it.
    button.Label:ClearAllPoints()
    button.Label:SetPoint("CENTER", button, "CENTER", chosen and 8 or 0, 0)
end

local function TreeOnClick(self)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    -- As if the profile's line were clicked in the field on the tab (the window is drawn
    -- again when the profile has changed: see PROFILE_CHANGED below).
    ns.UI.ChooseProfile(self.profile)
end

-- height: of the button; size: of its words; OnClick: what choosing it does.
local function NewChoice(parent, height, size, OnClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(height)
    NewSlices(button, "ButtonDark", 0.25, 8, "BACKGROUND", 0, 1)
    button.Lit = NewSlices(button, "ButtonGlow", 0.25, 8, "BORDER", 0, 1)
    button.Lit:SetBlendMode("ADD")
    button.Lit:SetVertexColor(1, 0.70, 0.28, 0.9)
    button.Glow = NewSlices(button, "ButtonGlow", 0.25, 8, "HIGHLIGHT", 0, 1)
    button.Glow:SetBlendMode("ADD")
    button.Label = NewText(button, size, SOFT, "CENTER")
    button.Mark = NewTexture(button, "Diamond", "ARTWORK")
    button.Mark:SetSize(14, 14)
    button.Mark:SetPoint("RIGHT", button.Label, "LEFT", -3, 0)
    button:SetScript("OnClick", OnClick)
    return button
end

local function NewTree()
    return NewChoice(frame, TREE_HEIGHT, 12, TreeOnClick)
end

---------------------------------------------------------------------------
-- The tooltip's block
---------------------------------------------------------------------------
-- How the lines are written: for every profile of the class (self.own false), or one line for
-- the profile in use (true). Written down only when it is not the usual, every profile.
local function HowOnClick(self)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if ns.OwnTree() == self.own then return end
    ns.account.ownTree = self.own or nil
    ns.Fire("SETTING_CHANGED", "ownTree")
end

local function NewHow(block, own, text)
    local button = NewChoice(block, HOW_HEIGHT, 10.5, HowOnClick)
    button.own = own
    button.Label:SetText(text)
    return button
end

-- A tick box with its words after it, which a click ticks as well: one of the places the
-- score can show in, or the notes. `wide` is how wide its words are on one line.
local function NewWhere(block, part, text)
    local switch = NewSwitch(block, part)
    switch.Label = NewText(block, 10.5, CREAM)
    switch.Label:SetSpacing(3)
    switch.Label:SetPoint("TOPLEFT", switch, "TOPLEFT", 21, -2)
    switch.Label:SetText(text)
    switch.wide = switch.Label:GetStringWidth()
    switch:SetHitRectInsets(0, -(6 + switch.wide), -4, -4)
    return switch
end

-- How tall such a tick box is where it has a line of the block to itself. Words too long for
-- the line go on to a second one.
local function WhereHeight(switch)
    local room = BLOCK_ROOM - 21
    if switch.wide <= room then return 15 end
    switch.Label:SetWordWrap(true)
    switch.Label:SetWidth(room)
    local tall = math.max(15, 2 + switch.Label:GetStringHeight())
    switch:SetHitRectInsets(0, -(6 + room), -4, -(4 + tall - 15))
    return tall
end

-- As wide as the two cards. What a card has under one another the block has side by side:
-- the picture on the left, the name and the sentence on the right, and under the sentence
-- the two questions (see Layout for where each part goes).
local function NewBlock()
    local block = CreateFrame("Frame", nil, frame)
    block:SetWidth(BLOCK_WIDTH)
    NewSlices(block, "Inset", 0.25, 8, "BACKGROUND")

    block.Picture = CreateFrame("Frame", nil, block)
    block.Picture:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
    block.Picture:SetPoint("BOTTOMLEFT", block, "BOTTOMLEFT", 0, 0)
    block.Picture:SetWidth(TIP_ROOM)
    NewTipPicture(block.Picture)

    local diamond = NewTexture(block, "Diamond", "ARTWORK")
    diamond:SetSize(15, 15)
    diamond:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_TEXT, -15)
    block.Title = NewText(block, 10.5, GOLD)
    block.Title:SetWordWrap(true)
    block.Title:SetWidth(BLOCK_ROOM - 21)
    block.Title:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_TEXT + 21, -17)
    block.Title:SetText(ns.Upper(L.WELCOME_TOOLTIP))
    block.Body = NewText(block, 10.5, CREAM)
    block.Body:SetWordWrap(true)
    block.Body:SetSpacing(3)
    block.Body:SetWidth(BLOCK_ROOM)
    block.Body:SetText(L.WELCOME_TOOLTIP_TEXT)

    block.All, block.Own = NewHow(block, false, L.WELCOME_HOW_ALL), NewHow(block, true, L.WELCOME_HOW_OWN)
    block.Tabs = NewWhere(block, "rowTooltip", L.WELCOME_WHERE_TABS)
    block.Elsewhere = NewWhere(block, "tooltip", L.WELCOME_WHERE_ELSE)
    -- The notes are another matter than the score: a fine line stands between.
    block.Rule = NewRule(block)
    block.Notes = NewWhere(block, "rowNotes", L.WELCOME_NOTES)
    return block
end

---------------------------------------------------------------------------
-- Who scores
---------------------------------------------------------------------------
-- The two answers are buttons of the same make as the trees', side by side: the addon
-- itself, and Pawn. `engine` is what a click on one makes of Score.Engine: nil or "pawn".
-- Pawn's cannot be chosen while Pawn is not there (`off`, see Paint): it is grey, a click
-- does nothing, and with the mouse on it a tooltip says why. (The button is not switched off
-- the game's way: one that is hears nothing of the mouse.)
local function EngineOnClick(self)
    if self.off then return end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    -- The window is drawn again when the choice is made (SETTING_CHANGED below), and what
    -- keeps scores makes them again (SCORING_CHANGED).
    ns.Score.SetEngine(self.engine)
end

local function EngineOnEnter(self)
    if not self.off then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip_AddNormalLine(GameTooltip, L.WELCOME_NO_PAWN)
    GameTooltip:Show()
end

local function NewEngine(name, engine)
    local button = NewTree()
    button.engine = engine
    button.Label:SetText(name)
    button:SetScript("OnClick", EngineOnClick)
    button:SetScript("OnEnter", EngineOnEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
-- Puts everything where the heights of the texts say. Top to bottom, `down` is how far from
-- the top of the window the next part begins.
local function Layout()
    local down = math.max(41 + frame.About:GetStringHeight() + 12, 70)
    frame.TopRule:ClearAllPoints()
    frame.TopRule:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE - 4, -down)
    frame.TopRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(EDGE - 4), -down)
    down = down + 13

    -- Who scores: the question, and its two answers side by side.
    frame.Who:ClearAllPoints()
    frame.Who:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE + 2, -down)
    down = down + frame.Who:GetStringHeight() + 9
    local half = (WIDTH - 2 * EDGE - GAP) / 2
    for i = 1, #frame.Engines do
        local button = frame.Engines[i]
        button:SetWidth(half)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE + (i - 1) * (half + GAP), -down)
    end
    down = down + TREE_HEIGHT + 15

    -- The trees: the question, and the buttons in a row as wide as the three cards. More of
    -- them than a row holds (a player may have many Pawn scales) stand in rows of equal
    -- number, a last row of fewer filling the width as well. With nothing to choose from
    -- the question's place has a sentence that says why (see Paint), and no buttons.
    local count = frame.treeCount
    frame.Ask:SetShown(frame.asks)
    if frame.asks then
        frame.Ask:ClearAllPoints()
        frame.Ask:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE + 2, -down)
        down = down + frame.Ask:GetStringHeight() + (count > 0 and 9 or 15)
    end
    if count > 0 then
        local rows = math.ceil(count / TREES_IN_ROW)
        local inRow = math.ceil(count / rows)
        for i = 1, count do
            local row, place = math.floor((i - 1) / inRow), (i - 1) % inRow
            local here = math.min(inRow, count - row * inRow)
            local width = (WIDTH - 2 * EDGE - (here - 1) * GAP) / here
            local button = frame.Trees[i]
            button:SetWidth(width)
            -- A name too long for its button is cut short, not written over the next one.
            button.Label:SetWidth(math.min(button.Label:GetUnboundedStringWidth() + 2, width - 40))
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE + place * (width + GAP),
                -(down + row * (TREE_HEIGHT + TREE_ROW_GAP)))
        end
        down = down + rows * TREE_HEIGHT + (rows - 1) * TREE_ROW_GAP + 15
    end

    frame.Shows:ClearAllPoints()
    frame.Shows:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE + 2, -down)
    down = down + frame.Shows:GetStringHeight() + 9

    -- The two cards are as tall as the one with the more to say.
    local words = 0
    for i = 1, #frame.Pair do
        local card = frame.Pair[i]
        local title = math.max(card.Title:GetStringHeight(), 15)
        card.Body:ClearAllPoints()
        card.Body:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -(PICTURE + 11 + title + 8))
        words = math.max(words, 11 + title + 8 + card.Body:GetStringHeight() + 12)
    end
    for i = 1, #frame.Pair do
        local card = frame.Pair[i]
        card:SetHeight(PICTURE + words)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE + (i - 1) * (CARD_WIDTH + GAP), -down)
    end
    down = down + PICTURE + words + GAP

    -- The tooltip's block. `under` is how far under its top the next part of its words
    -- begins: the name, the sentence, the two buttons, the two tick boxes of the score, and
    -- under a fine line the tick box of the notes.
    local block = frame.Tips
    local under = 15 + math.max(block.Title:GetStringHeight(), 15) + 7
    block.Body:ClearAllPoints()
    block.Body:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_TEXT, -under)
    under = under + block.Body:GetStringHeight() + 10
    -- The buttons are as wide as the longer of their names asks for, and no wider than half
    -- of the room.
    local wide = math.max(block.All.Label:GetStringWidth(), block.Own.Label:GetStringWidth()) + 46
    wide = math.min(math.max(wide, HOW_WIDTH), (BLOCK_ROOM - HOW_GAP) / 2)
    block.All:SetWidth(wide)
    block.Own:SetWidth(wide)
    block.All:ClearAllPoints()
    block.All:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_TEXT, -under)
    block.Own:ClearAllPoints()
    block.Own:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_TEXT + wide + HOW_GAP, -under)
    under = under + HOW_HEIGHT + 11
    -- The tick boxes stand side by side where their words leave room for that, and one under
    -- the other where they do not.
    local first = 21 + block.Tabs.wide
    block.Tabs:ClearAllPoints()
    block.Tabs:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_TEXT, -under)
    block.Elsewhere:ClearAllPoints()
    if first + 24 + 21 + block.Elsewhere.wide <= BLOCK_ROOM then
        block.Elsewhere:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_TEXT + first + 24, -under)
        under = under + 15
    else
        under = under + WhereHeight(block.Tabs) + 7
        block.Elsewhere:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_TEXT, -under)
        under = under + WhereHeight(block.Elsewhere)
    end
    under = under + 10
    block.Rule:ClearAllPoints()
    block.Rule:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_TEXT, -under)
    block.Rule:SetPoint("TOPRIGHT", block, "TOPRIGHT", -16, -under)
    under = under + 10
    block.Notes:ClearAllPoints()
    block.Notes:SetPoint("TOPLEFT", block, "TOPLEFT", BLOCK_TEXT, -under)
    under = under + WhereHeight(block.Notes)
    under = under + 16
    -- As tall as its words, or as its picture where a class has many trees.
    block:SetHeight(math.max(under, block.Picture.Tip:GetHeight() + 32))
    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE, -down)
    down = down + block:GetHeight() + 12

    frame.BottomRule:ClearAllPoints()
    frame.BottomRule:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE - 4, -down)
    frame.BottomRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(EDGE - 4), -down)
    down = down + 11
    frame.Done:ClearAllPoints()
    frame.Done:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(EDGE + 2), -down)
    frame.Again:ClearAllPoints()
    frame.Again:SetPoint("LEFT", frame, "TOPLEFT", EDGE + 2, -(down + 14))
    frame:SetHeight(down + 28 + 13)
end

-- Fills the window in for the character being played, as things stand now.
Paint = function()
    local me = ns.Roster.Me()
    local current, profiles = ns.Score.Current()
    local about = { profiles = profiles, place = 1, class = me and me.class, own = ns.OwnTree() }

    frame.About:SetText(greeting and L.WELCOME_FIRST or L.WELCOME_ABOUT)
    frame.Shows:SetText(L.WELCOME_SHOWS .. Aside(L.WELCOME_OFF))
    -- Up to say that Pawn can be chosen now: that comes first.
    if offering then frame.About:SetText(L.WELCOME_PAWN_NEW) end

    -- Who scores: the one that does is lit. The question stands alone: the two names on the
    -- buttons are the answer. Pawn cannot be chosen while it is not there: its button is
    -- grey then and does not light up under the mouse, a click on it does nothing, and its
    -- tooltip says why (EngineOnEnter).
    local pawn = ns.Score.Engine() == "pawn"
    local usable = ns.Pawn.Usable()
    frame.Who:SetText(L.WELCOME_ENGINE)
    for i = 1, #frame.Engines do
        local button = frame.Engines[i]
        local there = button.engine == nil or usable
        PaintTree(button, (button.engine == "pawn") == pawn)
        button.off = not there
        button.Glow:SetShown(there)
        button:SetAlpha(there and 1 or 0.45)
    end
    -- The pictures show the addon's own lines, whoever scores: its profiles, not Pawn's scales.
    if pawn then about.profiles = ns.Score.Trees() end

    -- A button for each profile of the class, the one in use lit. With Pawn scoring they are
    -- the character's Pawn scales; a character that has none switched on is told so.
    frame.treeCount = #profiles
    frame.asks = me ~= nil and (pawn or #profiles > 0)
    if frame.asks then
        local name = ns.Roster.Colored(me, me.name or "")
        if not pawn then
            frame.Ask:SetText(L.WELCOME_TREE:format(name) .. Aside(L.WELCOME_TREE_WHY))
        elseif #profiles > 0 then
            frame.Ask:SetText(L.WELCOME_SCALE:format(name) .. Aside(L.WELCOME_SCALE_WHY))
        else
            frame.Ask:SetText(L.WELCOME_NO_SCALE:format(name))
        end
    end
    for i = 1, math.max(#profiles, #frame.Trees) do
        local button = frame.Trees[i]
        if not button then
            button = NewTree()
            frame.Trees[i] = button
        end
        local profile = profiles[i]
        button:SetShown(profile ~= nil)
        if profile then
            local chosen = current ~= nil and profile.name == current.name
            if chosen then about.place = i end
            button.profile = profile.name
            button.Label:SetText(profile.title)
            PaintTree(button, chosen)
        end
    end
    -- (The pictures then count places among the addon's own profiles: the first.)
    if pawn then about.place = 1 end

    for i = 1, #frame.Pair do
        local card = frame.Pair[i]
        local on = not card.Switch or PaintSwitch(card.Switch)
        -- What is switched off is still shown, faded: it is what would come back.
        card.Picture:SetAlpha(on and 1 or 0.3)
        card.Picture:Paint(about)
    end

    -- The tooltip's block. Of the score it asks how its lines are written, and where they
    -- show. Shown nowhere, there is nothing to choose between: the two buttons keep what
    -- they say and go dim until one of the boxes is ticked again.
    -- With Pawn scoring the score in a tooltip is Pawn's to write (Tooltip.lua, AddOfferLines
    -- in UI.lua): the block says so in place of its sentence, and what it asks of the score
    -- is out of use until the addon scores again, the buttons dim, the two boxes empty and
    -- dim. (Out of the mouse's reach as well: what is switched off would still light up
    -- under it.) What the boxes were left at is kept, and a list for another character,
    -- whose score Pawn does not write, still goes by it.
    -- The notes under a row of our tabs are ours whoever scores: their box is always in use.
    -- So are the arrows in the bags, on their card.
    local block = frame.Tips
    local tabs, elsewhere, notes = PaintSwitch(block.Tabs), PaintSwitch(block.Elsewhere), PaintSwitch(block.Notes)
    block.Body:SetText(pawn and L.WELCOME_TOOLTIP_PAWN or L.WELCOME_TOOLTIP_TEXT)
    for _, switch in ipairs({ block.Tabs, block.Elsewhere }) do
        if pawn then
            switch:SetChecked(false)
            switch.Tick:SetShown(false)
        end
        switch:SetEnabled(not pawn)
        switch:EnableMouse(not pawn)
        switch:SetAlpha(pawn and 0.4 or 1)
        switch.Label:SetAlpha(pawn and 0.5 or 1)
    end
    local score = (tabs or elsewhere) and not pawn
    PaintTree(block.All, not about.own)
    PaintTree(block.Own, about.own)
    for _, button in ipairs({ block.All, block.Own }) do
        button:SetEnabled(score)
        button:EnableMouse(score)
        button:SetAlpha(score and 1 or 0.35)
    end
    -- The picture has what is in use: the score's lines, the note, or both. With neither it
    -- fades: it then has the score's lines, which would come back.
    about.score, about.notes = score, notes
    block.Picture:SetAlpha((score or notes) and 1 or 0.3)
    block.Picture:Paint(about)
    Layout()
end

local function Build()
    -- By name: Escape closes it, as it does the game's own windows (UISpecialFrames).
    frame = CreateFrame("Frame", "UpgradeScoutWelcome", UIParent)
    table.insert(UISpecialFrames, frame:GetName())
    frame:SetWidth(WIDTH)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    -- It can be dragged out of the way of what is behind it.
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    NewSlices(frame, "Panel", 0.375, 12, "BACKGROUND", 0, 1.5)
    -- Closed in any way, it has been seen, and does not come up by itself again.
    frame:SetScript("OnHide", function()
        ns.account.welcomed = true
        greeting = false
        -- And, with Pawn there, the choice of who scores has been seen with it.
        if ns.Pawn.Usable() then ns.account.pawnOffered = true end
        offering = false
    end)

    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ICON)
    logo:SetSize(44, 44)
    logo:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE, -15)
    local name = NewText(frame, 19, GOLD)
    name:SetPoint("LEFT", frame, "TOPLEFT", 72, -27)
    name:SetText("Upgrade Scout")
    frame.About = NewText(frame, 11.5, CREAM)
    frame.About:SetWordWrap(true)
    frame.About:SetSpacing(3)
    frame.About:SetWidth(WIDTH - 72 - 44)
    frame.About:SetPoint("TOPLEFT", frame, "TOPLEFT", 72, -41)

    -- The cross in the corner.
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -8)
    close.Label = NewText(close, 18, GOLD_DIM, "CENTER", true)
    close.Label:SetPoint("CENTER", close, "CENTER", 0, 0)
    close.Label:SetText("×")
    close:SetScript("OnEnter", function(self) self.Label:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end)
    close:SetScript("OnLeave", function(self) self.Label:SetTextColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3]) end)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.Close = close

    frame.TopRule, frame.BottomRule = NewRule(frame), NewRule(frame)

    -- Who scores: the question and its two answers, each by its own name.
    frame.Who = NewText(frame, 12, CREAM)
    frame.Who:SetWordWrap(true)
    frame.Who:SetSpacing(3)
    frame.Who:SetWidth(WIDTH - 2 * EDGE - 4)
    frame.Engines = { NewEngine("Upgrade Scout", nil), NewEngine("Pawn", "pawn") }

    frame.Ask = NewText(frame, 12, CREAM)
    frame.Ask:SetWordWrap(true)
    frame.Ask:SetSpacing(3)
    frame.Ask:SetWidth(WIDTH - 2 * EDGE - 4)
    frame.Trees, frame.treeCount = {}, 0

    frame.Shows = NewText(frame, 12, CREAM)
    frame.Shows:SetWordWrap(true)
    frame.Shows:SetSpacing(3)
    frame.Shows:SetWidth(WIDTH - 2 * EDGE - 4)

    -- The two cards, and under them the tooltip's block.
    frame.Pair = {
        NewCard(nil, L.WELCOME_AUCTION, L.WELCOME_AUCTION_TEXT:format(L.SCAN, L.TAB, L.TAB_SUP), NewListPicture),
        NewCard("arrows", L.WELCOME_ARROWS, L.WELCOME_ARROWS_TEXT, NewBagPicture),
    }
    frame.Tips = NewBlock()

    frame.Done = NewButton(frame, 118, 28, "ButtonRed", 13)
    frame.Done.Label:SetText(L.WELCOME_DONE)
    frame.Done:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        frame:Hide()
    end)
    frame.Again = NewText(frame, 10.5, SOFT)
    frame.Again:SetWordWrap(true)
    frame.Again:SetWidth(WIDTH - 2 * EDGE - 4 - 118 - 12)
    frame.Again:SetText(L.WELCOME_AGAIN)
end

function Welcome.Show()
    if not frame then Build() end
    -- The first words are a welcome until the window has been seen once.
    greeting = not ns.account.welcomed
    -- Seen before, but not since Pawn could be chosen in it, by a player who has Pawn: the
    -- first words are about that.
    offering = not greeting and not ns.account.pawnOffered and ns.Pawn.Usable()
    Paint()
    frame:Show()
end

function Welcome.Hide()
    if frame then frame:Hide() end
end

function Welcome.IsShown()
    return frame ~= nil and frame:IsShown()
end

-- What the window shows has changed while it is up: another profile, a tick box, an item of
-- the pictures that the game has loaded since.
local function Repaint()
    if Welcome.IsShown() then Paint() end
end
ns.Listen("PROFILE_CHANGED", Repaint)
ns.Listen("SETTING_CHANGED", Repaint)
-- Pawn's scales changed, in Pawn's own window, while Pawn scores.
ns.Listen("SCORING_CHANGED", Repaint)

local function OnItemLoaded(itemID)
    for i = 1, #SAMPLES do
        if SAMPLES[i].item == itemID then return Repaint() end
    end
end
ns.On("ITEM_DATA_LOAD_RESULT", OnItemLoaded)
ns.On("GET_ITEM_INFO_RECEIVED", OnItemLoaded)

---------------------------------------------------------------------------
-- The first time
---------------------------------------------------------------------------
-- A few seconds after the character is in the world: by then the game knows who it is and
-- what it wears, and the card is written (Roster.Update), its talent tree with it. Not in the
-- middle of a fight: the window waits for the end of it.
-- The same once more for a player who has Pawn and saw the window before Pawn could be
-- chosen in it (2.6.0): nothing else would tell them of the choice.
local waiting = false

-- Has the window a reason to come up by itself?
local function Due()
    if not ns.account.welcomed then return true end
    return not ns.account.pawnOffered and ns.Pawn.Usable()
end

local function Greet()
    waiting = false
    if not Due() or Welcome.IsShown() then return end
    if InCombatLockdown() or not ns.Roster.Me() then
        waiting = true
        C_Timer.After(GREET_RETRY, Greet)
        return
    end
    Welcome.Show()
end

ns.On("PLAYER_ENTERING_WORLD", function()
    -- (Whether Pawn is there is asked when the wait is over: it reads its scales as the
    -- character logs in.)
    if waiting or (ns.account.welcomed and ns.account.pawnOffered) then return end
    waiting = true
    C_Timer.After(GREET_AFTER, Greet)
end)

---------------------------------------------------------------------------
-- In the game's own list of addons
---------------------------------------------------------------------------
-- Options > AddOns has a page for the addon, as players expect of one: its name, what it does
-- and a button that opens this window. The page is made once and has no scripts of its own:
-- none of our code runs as the game's window comes and goes. (Mastercraft does it this way and
-- says why: addon code on the way out of that window gets the game's Log Out and Exit blocked.)
ns.On("PLAYER_LOGIN", function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local page = CreateFrame("Frame")
    page:Hide()
    local logo = page:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ICON)
    logo:SetSize(64, 64)
    logo:SetPoint("TOP", page, "TOP", 0, -48)
    local name = NewText(page, 24, GOLD, "CENTER")
    name:SetPoint("TOP", logo, "BOTTOM", 0, -10)
    name:SetText("Upgrade Scout")
    local about = NewText(page, 13, CREAM, "CENTER")
    about:SetWordWrap(true)
    about:SetWidth(480)
    about:SetPoint("TOP", name, "BOTTOM", 0, -14)
    about:SetText(L.WELCOME_ABOUT)
    local open = NewButton(page, 200, 30, "ButtonRed", 13)
    open:SetPoint("TOP", about, "BOTTOM", 0, -22)
    open.Label:SetText(L.WELCOME_OPEN)
    open:SetScript("OnClick", Welcome.Show)
    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(page, "Upgrade Scout"))
end)
