local ADDON, ns = ...
local L = ns.L
local S = ns.Scanner

-- The "Upgrades" tab of the auction house window.
--
-- The tab has a look of its own: a dark plate in a fine gold edge, headings in gold capitals,
-- buttons in gold rims. Its art is the textures in Media, drawn by scripts/make-textures.py at
-- two texture pixels per window unit; frames and buttons are cut in nine, so one small picture
-- serves any size (see NewSlices).
-- The parts that do the work are still the game's own:
--   the list        WowScrollBoxList and MinimalScrollBar
--   prices          MoneyDisplayFrameTemplate
--   the Pawn scale  WowStyle1DropdownTemplate: its menu and its text, under a face of ours
--   buying          a StaticPopup shaped like the game's own BUYOUT_AUCTION
--
-- The "Consumables" tab is the same frame in another view (`view`): the same list with rows
-- of another kind, another second filter, a status line of its own, and a box that asks how
-- many pieces to buy. What differs between the views is gathered in ApplyView.
local UI = {}
ns.UI = UI

local TAB_ID = "UpgradeScout"
local TAB_SUPPLIES = "UpgradeScoutSupplies"
local POPUP = "UPGRADESCOUT_BUY"
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- Layout, in the coordinates of the auction window (800 by 538). The game keeps the strip
-- under the title for a tab's controls and the strip at the bottom for the gold display; the
-- plate with the list takes what is between them.
local BAR_MIDDLE = 49                       -- the controls above the list are centred on this line
local BAR_LEFT, BAR_RIGHT = 72, 14          -- left: clear of the portrait in the corner
local PANEL_LEFT, PANEL_RIGHT, PANEL_TOP, PANEL_BOTTOM = 6, 6, 72, 28
local LIST_LEFT, LIST_RIGHT, LIST_TOP, LIST_BOTTOM = 8, 24, 30, 7   -- the rows, inside the plate
local GOLD_RIGHT, GOLD_BOTTOM = 167, 3      -- the frame around the gold display (MoneyFrameInset)
local ROW_HEIGHT = 30
local REFRESH_INTERVAL = 0.1                -- seconds between redraws while a scan reports progress

-- Across a row, from its left edge. Numbers sit against the right edge of their column, and
-- so do the titles above them.
local PAD = 8                               -- between neighbours
local ICON_LEFT, ICON_SIZE = 6, 22
local NAME_LEFT, NAME_WIDTH, NAME_MIN_WIDTH = 36, 228, 110
local PICK_LEFT, PICK_WIDTH = 276, 140
local UPGRADE_RIGHT, METER_WIDTH = 492, 72
local SCORE_LEFT = UPGRADE_RIGHT - METER_WIDTH  -- where a consumable's score begins: its meter's left end
local PRICE_RIGHT, PER_RIGHT = 596, 684
local TITLES = {
    { text = L.COL_ITEM, at = 10 },
    { text = L.COL_PICK, at = PICK_LEFT },
    { text = L.COL_UPGRADE, at = UPGRADE_RIGHT, numeric = true },
    { text = L.COL_PRICE, at = PRICE_RIGHT, numeric = true },
    { text = L.COL_PER, at = PER_RIGHT, numeric = true },
}
local SCAN_WIDTH, STATUS_BAR_WIDTH = 118, 140
local DROPDOWN_MIN, DROPDOWN_MAX = 110, 200
local CHECK_SIZE, CHECK_GAP = 16, 6         -- a tick box and the room before its label

-- Colours of the text.
local GOLD, GOLD_DIM = { 1.00, 0.83, 0.32 }, { 0.76, 0.61, 0.32 }
local CREAM, SOFT, MUTED = { 0.95, 0.91, 0.83 }, { 0.74, 0.70, 0.63 }, { 0.54, 0.50, 0.45 }
local GREEN = { 0.45, 0.92, 0.38 }

-- The plates the two picks are named on.
local PICKS = {
    UPGRADE = { text = L.PICK_UPGRADE, fill = { 1.00, 0.78, 0.26, 0.16 }, edge = { 1.00, 0.78, 0.26, 0.80 }, ink = { 1.00, 0.86, 0.42 } },
    VALUE = { text = L.PICK_VALUE, fill = { 0.42, 0.86, 0.36, 0.15 }, edge = { 0.42, 0.86, 0.36, 0.75 }, ink = { 0.56, 0.94, 0.48 } },
    -- Both at once: solid gold, dark letters.
    BOTH = { text = L.PICK_BOTH, fill = { 1.00, 0.80, 0.30, 1 }, edge = { 1.00, 0.92, 0.62, 1 }, ink = { 0.17, 0.10, 0.02 }, solid = true },
}

local frame, scrollBox, provider, hint, intro, status, statusBar, listBar
local scanButton, scaleDropdown, affordCheck, topCheck
local view = "gear"         -- what the frame shows: "gear" (Upgrades) or "supplies" (Consumables)
local holder                -- the frame the Consumables tab is made with (see Build)
local bestCheck, buyBox     -- the Consumables view's own filter, and its box for buying
local rows = {}
local summary               -- what the last refresh counted, for the status line
local elements = {}       -- row key -> the table the scroll box knows the row by (see SyncList)
local syncCount = 0
local toTop = false         -- scroll back to the top at the next refresh
local keepPlace = false     -- the next refresh must not move the list (see SyncList)
local scaleShown            -- what the scale dropdown was last built from (see ScaleKey)
local textFont, numberFont  -- font files, settled when the tab is built (see Build)

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function File(name)
    return MEDIA .. name
end

local function NewTexture(parent, name, layer, sublevel)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
    -- The game moves textures onto whole screen pixels. Pieces of one picture must meet edge
    -- to edge at any interface scale instead.
    if texture.SetSnapToPixelGrid then
        texture:SetSnapToPixelGrid(false)
        texture:SetTexelSnappingBias(0)
    end
    if name then texture:SetTexture(File(name)) end
    return texture
end

-- A fine line that fades out at both ends, one screen pixel thick where the game can say how
-- much that is.
local function NewLine(parent, layer)
    local line = parent:CreateTexture(nil, layer or "ARTWORK")
    line:SetTexture(File("Line"))
    if PixelUtil and PixelUtil.SetHeight then
        PixelUtil.SetHeight(line, 1, 1)
    else
        line:SetHeight(1)
    end
    return line
end

-- A picture cut in nine: the corners keep their size, the edges and the middle stretch.
--   corner   the side of a corner in the picture, as a share of the picture's side
--   edge     the side of a corner on screen
--   outset   how far the picture reaches beyond the frame (the soft shadow around a button)
-- Pieces are numbered row by row: 1 2 3, 4 5 6, 7 8 9.
local Slices = {}
Slices.__index = Slices

local function NewSlices(parent, name, corner, edge, layer, sublevel, outset)
    local stops = { 0, corner, 1 - corner, 1 }
    local parts = {}
    for i = 1, 9 do
        local across, down = (i - 1) % 3 + 1, math.floor((i - 1) / 3) + 1
        local part = NewTexture(parent, nil, layer, sublevel)
        part.coords = { stops[across], stops[across + 1], stops[down], stops[down + 1] }
        parts[i] = part
    end
    outset = outset or 0
    parts[1]:SetSize(edge, edge)
    parts[1]:SetPoint("TOPLEFT", parent, "TOPLEFT", -outset, outset)
    parts[3]:SetSize(edge, edge)
    parts[3]:SetPoint("TOPRIGHT", parent, "TOPRIGHT", outset, outset)
    parts[7]:SetSize(edge, edge)
    parts[7]:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -outset, -outset)
    parts[9]:SetSize(edge, edge)
    parts[9]:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", outset, -outset)
    parts[2]:SetPoint("TOPLEFT", parts[1], "TOPRIGHT")
    parts[2]:SetPoint("BOTTOMRIGHT", parts[3], "BOTTOMLEFT")
    parts[8]:SetPoint("TOPLEFT", parts[7], "TOPRIGHT")
    parts[8]:SetPoint("BOTTOMRIGHT", parts[9], "BOTTOMLEFT")
    parts[4]:SetPoint("TOPLEFT", parts[1], "BOTTOMLEFT")
    parts[4]:SetPoint("BOTTOMRIGHT", parts[7], "TOPRIGHT")
    parts[6]:SetPoint("TOPLEFT", parts[3], "BOTTOMLEFT")
    parts[6]:SetPoint("BOTTOMRIGHT", parts[9], "TOPRIGHT")
    parts[5]:SetPoint("TOPLEFT", parts[1], "BOTTOMRIGHT")
    parts[5]:SetPoint("BOTTOMRIGHT", parts[9], "TOPLEFT")

    local slices = setmetatable({ parts = parts }, Slices)
    slices:SetFile(name)
    return slices
end

function Slices:SetFile(name)
    if self.file == name then return end
    self.file = name
    for i = 1, 9 do
        local part = self.parts[i]
        part:SetTexture(File(name))
        part:SetTexCoord(part.coords[1], part.coords[2], part.coords[3], part.coords[4])
    end
end

function Slices:SetVertexColor(r, g, b, a)
    for i = 1, 9 do self.parts[i]:SetVertexColor(r, g, b, a or 1) end
end

function Slices:SetDesaturated(desaturated)
    for i = 1, 9 do self.parts[i]:SetDesaturated(desaturated) end
end

function Slices:SetBlendMode(mode)
    for i = 1, 9 do self.parts[i]:SetBlendMode(mode) end
end

function Slices:SetShown(shown)
    for i = 1, 9 do self.parts[i]:SetShown(shown) end
end

-- Text in the game's own fonts, so that it reads right in every language and follows a font
-- the player has put in their place: the standard one for words, the narrow one the game
-- writes numbers and auction lists in for the rows. `color` is one of the tables above.
local function NewText(parent, size, color, justify, narrow)
    local text = parent:CreateFontString(nil, "ARTWORK")
    text:SetFont(narrow and numberFont or textFont, size, "")
    text:SetTextColor(color[1], color[2], color[3])
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    return text
end

-- How wide a text is when nothing cuts it short.
local function TextWidth(text)
    if text.GetUnboundedStringWidth then return text:GetUnboundedStringWidth() end
    return text:GetStringWidth()
end

---------------------------------------------------------------------------
-- Buttons, tick boxes, bars
---------------------------------------------------------------------------
-- A button looks the part it is in: pressed is darker with the label a step down, switched
-- off is grey. Under the mouse it lights up by itself (the HIGHLIGHT layer).
local function PaintButton(button)
    local enabled = button:IsEnabled()
    local down = enabled and button.down
    local shade = (not enabled and 0.55) or (down and 0.80) or 1
    button.Face:SetDesaturated(not enabled)
    button.Face:SetVertexColor(shade, shade, shade)
    button.Glow:SetShown(enabled)
    local color = enabled and GOLD or MUTED
    button.Label:SetTextColor(color[1], color[2], color[3])
    button.Label:SetPoint("CENTER", button, "CENTER", down and 1 or 0, down and -1 or 0)
end

local function ButtonDown(button)
    button.down = true
    PaintButton(button)
end

local function ButtonUp(button)
    button.down = false
    PaintButton(button)
end

-- face: "ButtonRed" for the one button that matters, "ButtonDark" for the rest.
local function NewButton(parent, width, height, face, fontSize)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    local edge = math.min(8, (height + 2) / 3)
    button.Face = NewSlices(button, face, 0.25, edge, "BACKGROUND", 0, 1)
    button.Glow = NewSlices(button, "ButtonGlow", 0.25, edge, "HIGHLIGHT", 0, 1)
    button.Glow:SetBlendMode("ADD")
    button.Label = NewText(button, fontSize, GOLD, "CENTER")
    button:SetScript("OnMouseDown", ButtonDown)
    button:SetScript("OnMouseUp", ButtonUp)
    -- Hidden while held down, a button never hears that the mouse let go.
    button:SetScript("OnHide", ButtonUp)
    button:SetScript("OnEnable", PaintButton)
    button:SetScript("OnDisable", PaintButton)
    PaintButton(button)
    return button
end

-- A bar that fills with gold: SetBar(bar, 0..1). Work whose end is not known, SetBar(bar, nil),
-- shows as a piece of gold going to and fro.
local function BarOnUpdate(bar)
    local piece = bar.room * 0.3
    local at = (bar.room - piece) * (0.5 - 0.5 * math.cos(GetTime() * 2.4))
    bar.Fill:SetWidth(piece)
    bar.Fill:SetPoint("LEFT", bar, "LEFT", 1.5 + at, 0)
end

local function SetBar(bar, value)
    bar.value = value
    if not value then
        bar.Fill:Show()
        bar.Fill:SetTexCoord(0, 0.3, 0, 1)
        if not bar:GetScript("OnUpdate") then
            bar:SetScript("OnUpdate", BarOnUpdate)
            BarOnUpdate(bar)
        end
        return
    end
    bar:SetScript("OnUpdate", nil)
    value = Clamp(value, 0, 1)
    bar.Fill:SetShown(value > 0)
    bar.Fill:SetWidth(math.max(bar.room * value, 1))
    -- As much of the picture as the bar is full, so that the gold keeps its grain.
    bar.Fill:SetTexCoord(0, math.max(value, 0.02), 0, 1)
    bar.Fill:SetPoint("LEFT", bar, "LEFT", 1.5, 0)
end

local function NewBar(parent, width, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, height)
    NewSlices(bar, "Inset", 0.25, height / 2, "BACKGROUND")
    bar.room = width - 3
    bar.Fill = NewTexture(bar, "Bar", "ARTWORK")
    bar.Fill:SetHeight(height - 3)
    SetBar(bar, 0)
    return bar
end

-- How far the scanner is with what it is doing, 0 to 1; nil when it cannot tell.
local function Progress()
    local info = S.info
    if S.state == "score" and info.toScore > 0 then
        return info.scored / info.toScore
    elseif S.state == "verify" and (S.mode == "scan" or S.mode == "more") and info.toVerify > 0 then
        return info.verified / info.toVerify
    end
    return nil
end

---------------------------------------------------------------------------
-- Whom the lists are for
---------------------------------------------------------------------------
-- The lists are for the character being played unless another one of the account is chosen
-- in the scale field (see "Controls"). That one's card (see Roster.lua) is `who` throughout
-- this file; nil is the character being played.
local function WhoName(who)
    return ns.Roster.Colored(who, who.name)
end

-- The game puts the tooltip of the worn item beside an item's by itself, but it knows only
-- what the character being played wears. For another character the item its card remembers
-- in the slot is put there, in the game's own second tooltip.
local wornShown = false

local function HideWorn()
    if wornShown and ShoppingTooltip1 then ShoppingTooltip1:Hide() end
    wornShown = false
end

local function ShowWorn(links)
    local tip = ShoppingTooltip1
    if not tip or not links or not links[1] then return end
    tip:SetOwner(GameTooltip, "ANCHOR_NONE")
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", 0, -10)
    tip:SetHyperlink(links[1])
    tip:Show()
    -- To the right of the item's tooltip where the screen has room, otherwise to its left.
    local right, edge, width = GameTooltip:GetRight(), UIParent:GetRight(), tip:GetWidth()
    if right and edge and width and right + width > edge then
        tip:ClearAllPoints()
        tip:SetPoint("TOPRIGHT", GameTooltip, "TOPLEFT", 0, -10)
    end
    wornShown = true
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
-- A consumable's own tooltip, and under it how much of it is for sale.
local function ShowSupplyTooltip(row)
    local entry = row.entry
    local supply = entry.supply
    local who = ns.Roster.Target()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local hideVendorPrice = true
    GameTooltip:SetHyperlink(supply.link, nil, nil, hideVendorPrice)
    GameTooltip_AddBlankLineToTooltip(GameTooltip)
    if who then GameTooltip_AddHighlightLine(GameTooltip, L.TT_WHO:format(WhoName(who))) end
    if entry.value then
        GameTooltip_AddNormalLine(GameTooltip, L.TT_SUP_SCORE:format("+" .. ns.Num(entry.value)))
    elseif entry.why == "MANA" then
        GameTooltip_AddNormalLine(GameTooltip, who and L.TT_SUP_NO_MANA_WHO or L.TT_SUP_NO_MANA)
    elseif entry.why then
        GameTooltip_AddNormalLine(GameTooltip, who and L.TT_SUP_NO_WEIGHT_WHO or L.TT_SUP_NO_WEIGHT)
    end
    GameTooltip_AddHighlightLine(GameTooltip, L.TT_STOCK:format(supply.quantity, ns.Money(supply.price)))
    if not entry.affordable then
        GameTooltip_AddErrorLine(GameTooltip, L.TT_CANT_AFFORD:format(ns.Money(supply.price - GetMoney())))
    end
    GameTooltip:Show()
end

local function ShowItemTooltip(row)
    local entry = row.entry
    if entry.supply then
        ShowSupplyTooltip(row)
        return
    end
    local offer = entry.offer
    local who = ns.Roster.Target()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    -- No vendor price, as on the Buy tab: this is something to buy, not to sell.
    local hideVendorPrice = true
    GameTooltip:SetHyperlink(offer.link, nil, nil, hideVendorPrice)

    GameTooltip_AddBlankLineToTooltip(GameTooltip)
    if who then GameTooltip_AddHighlightLine(GameTooltip, L.TT_WHO:format(WhoName(who))) end
    if entry.base > 0 then
        -- All three to the precision of the difference, so that they add up: 1.548, 1.5, +0.048.
        local digits = ns.Decimals(entry.delta)
        GameTooltip_AddColoredLine(GameTooltip, (who and L.TT_SCORE_WHO or L.TT_SCORE):format(ns.Num(offer.value, digits),
            ns.Num(entry.base, digits), ns.Num(entry.delta, digits)), GREEN_FONT_COLOR)
    else
        GameTooltip_AddColoredLine(GameTooltip, L.TT_SCORE_EMPTY:format(ns.Num(offer.value)), GREEN_FONT_COLOR)
    end
    if entry.replaced then
        for i = 1, #entry.replaced do
            GameTooltip_AddHighlightLine(GameTooltip, L.TT_REPLACES:format(entry.replaced[i]))
        end
    end
    GameTooltip_AddHighlightLine(GameTooltip, L.TT_COST:format(ns.Money(entry.costPer)))
    if entry.note == "OFFHAND_EMPTY" then
        GameTooltip_AddNormalLine(GameTooltip, who and L.TT_OFFHAND_EMPTY_WHO or L.TT_OFFHAND_EMPTY)
    elseif entry.note == "BOTH_HANDS" then
        GameTooltip_AddNormalLine(GameTooltip, L.TT_BOTH_HANDS)
    end
    if offer.effects then
        GameTooltip_AddNormalLine(GameTooltip, L.TT_EFFECTS)
    end
    if offer.more then
        GameTooltip_AddDisabledLine(GameTooltip, L.TT_MORE_SOME)
    elseif offer.count > 1 then
        GameTooltip_AddDisabledLine(GameTooltip, L.TT_MORE:format(offer.count - 1))
    end
    if not entry.affordable then
        GameTooltip_AddErrorLine(GameTooltip, L.TT_CANT_AFFORD:format(ns.Money(offer.buyout - GetMoney())))
    end
    GameTooltip:Show()

    -- What the item would replace is the point of this list, so the worn item's tooltip is
    -- always put next to it; elsewhere in the game that takes holding Shift.
    if who then
        ShowWorn(entry.replaced)
    else
        GameTooltip_ShowCompareItem(GameTooltip)
    end
end

-- While the mouse is on a row: the magnifying glass when a click would try the item on.
local function ItemRowOnUpdate()
    if IsModifiedClick("DRESSUP") then
        ShowInspectCursor()
    else
        ResetCursor()
    end
end

local function ItemRowOnEnter(row)
    row:SetScript("OnUpdate", ItemRowOnUpdate)
    ShowItemTooltip(row)
end

local function ItemRowOnLeave(row)
    row:SetScript("OnUpdate", nil)
    ResetCursor()
    HideWorn()
    GameTooltip_Hide()
end

-- A row that scrolls out of view, or whose offer goes, is hidden without the mouse leaving it.
local function ItemRowOnHide(row)
    row:SetScript("OnUpdate", nil)
    if GameTooltip:IsOwned(row) then
        ResetCursor()
        HideWorn()
        GameTooltip_Hide()
    end
end

-- Shift-click links the item in chat, Ctrl-click tries it on: the game decides which.
local function ItemRowOnClick(row)
    HandleModifiedItemClick((row.entry.supply or row.entry.offer).link)
end

local function BuyOnClick(button)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    local entry = button:GetParent().entry
    if entry.supply then
        S.BuySupply(entry.supply)
    else
        S.Buy(entry.offer)
    end
end

-- A click on a slot's heading folds the slot away, or brings it back.
local function HeaderOnClick(toggle)
    local group = toggle:GetParent().group
    local collapsed = not ns.db.collapsed[group]
    PlaySound(collapsed and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    ns.db.collapsed[group] = collapsed or nil
    -- The heading under the mouse stays where it is, however many rows come or go below it.
    keepPlace = true
    UI.Refresh()
end

-- A coin display against a line `right` from the row's left edge.
local function NewMoney(row, right)
    local money = CreateFrame("Frame", nil, row, "MoneyDisplayFrameTemplate")
    money:SetPoint("RIGHT", row, "LEFT", right, 0)
    return money
end

-- Shows an amount in a coin display, the coins standing close together.
-- The game lays a price out for a table: silver and copper each get a slot wide enough for two
-- digits, so that the coins of all rows stand in columns. A price with one digit of silver or
-- copper then has a hole in it ("2g 90s    0c") that money has nowhere else in the game. So
-- after the game has set the amount, its three parts (each as wide as its number and its
-- coin) are put side by side from the right, every number the same step after the coin
-- before it: the step a two-digit number has in the game's own layout.
local COIN_GAP = 9
local COINS = { "CopperDisplay", "SilverDisplay", "GoldDisplay" }
local function SetMoney(money, copper)
    money:SetAmount(copper)
    local after         -- the nearest part to the right that is shown
    for i = 1, #COINS do
        local coin = money[COINS[i]]
        if coin then
            coin:ClearAllPoints()
            if after then
                coin:SetPoint("RIGHT", after, "LEFT", -COIN_GAP, 0)
            else
                coin:SetPoint("RIGHT", money, "RIGHT", 0, 0)
            end
            if coin:IsShown() then after = coin end
        end
    end
end

-- The plate a pick is named on.
local function NewPick(row)
    local pick = CreateFrame("Frame", nil, row)
    pick:SetHeight(17)
    pick:SetPoint("LEFT", row, "LEFT", PICK_LEFT, 0)
    pick.Fill = NewSlices(pick, "Chip", 0.3125, 5, "BACKGROUND")
    pick.Edge = NewSlices(pick, "ChipEdge", 0.3125, 5, "BORDER")
    pick.Text = NewText(pick, 10.5, CREAM)
    pick.Text:SetPoint("LEFT", pick, "LEFT", 7, 0)
    return pick
end

local function SetPick(pick, kind)
    local look = PICKS[kind]
    pick:SetShown(look ~= nil)
    if not look then
        pick.Text:SetText("")
        return
    end
    local text = pick.Text
    text:SetText(look.text)
    text:SetTextColor(look.ink[1], look.ink[2], look.ink[3])
    text:SetShadowColor(0, 0, 0, look.solid and 0 or 0.9)
    -- A long translation is cut short before it reaches the next column.
    local width = math.min(TextWidth(text), PICK_WIDTH - 14)
    text:SetWidth(width)
    pick:SetWidth(width + 14)
    pick.Fill:SetVertexColor(look.fill[1], look.fill[2], look.fill[3], look.fill[4])
    pick.Edge:SetVertexColor(look.edge[1], look.edge[2], look.edge[3], look.edge[4])
end

-- The scroll box hands out bare frames; each gets its parts here the first time it is used.
local function BuildItemRow(row)
    row.built = true

    local glow = NewTexture(row, "RowGlow", "HIGHLIGHT")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.72, 0.30, 0.16)
    glow:SetAllPoints()

    local line = NewLine(row, "BACKGROUND")
    line:SetVertexColor(0.70, 0.52, 0.24, 0.22)
    line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 0)
    line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 0)

    -- The icon without the edge the game draws into it, in a rim of the item's quality colour.
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(ICON_SIZE - 3, ICON_SIZE - 3)
    row.Icon:SetPoint("CENTER", row, "LEFT", ICON_LEFT + ICON_SIZE / 2, 0)
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.Rim = NewTexture(row, "IconRim", "ARTWORK", 1)
    row.Rim:SetSize(ICON_SIZE, ICON_SIZE)
    row.Rim:SetPoint("CENTER", row.Icon, "CENTER", 0, 0)

    row.Name = NewText(row, 13, CREAM, "LEFT", true)
    row.Name:SetPoint("LEFT", row, "LEFT", NAME_LEFT, 0)

    -- "One-Hand", "Two-Hand"...: at the right end of the name column, on weapon rows only.
    row.Hand = NewText(row, 11, MUTED, "RIGHT", true)
    row.Hand:SetPoint("RIGHT", row, "LEFT", NAME_LEFT + NAME_WIDTH, 0)

    row.Pick = NewPick(row)

    -- "+4.7 +80%" over a meter: how the gain compares with the best one in the slot.
    row.Share = NewText(row, 11, MUTED, "RIGHT", true)
    row.Share:SetPoint("RIGHT", row, "LEFT", UPGRADE_RIGHT, 3)
    row.Upgrade = NewText(row, 14, GREEN, "RIGHT", true)
    row.Upgrade:SetPoint("RIGHT", row.Share, "LEFT", -5, 0)
    row.Trough = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.Trough:SetColorTexture(0, 0, 0, 0.6)
    row.Trough:SetSize(METER_WIDTH, 4)
    row.Trough:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", UPGRADE_RIGHT, 5)
    row.Meter = NewTexture(row, "Bar", "ARTWORK")
    row.Meter:SetHeight(3)
    row.Meter:SetPoint("LEFT", row.Trough, "LEFT", 0.5, 0)

    row.Price = NewMoney(row, PRICE_RIGHT)
    -- An auction house that deals in whole silver shows no copper in its prices.
    if not C_AuctionHouse.SupportsCopperValues() then
        row.Price.CopperDisplay:SetForcedHidden(true)
    end
    row.PerPoint = NewMoney(row, PER_RIGHT)
    row.PerPoint:SetFontObject(PriceFontWhite)
    row.PerPoint:SetAlpha(0.8)

    -- A consumable's row says what the item does where a gear row has its pick, and how many
    -- pieces are for sale where a gear row has its price per point. Its score stands where a
    -- gear row has its gain, over the same meter; a row without a score gives that room to
    -- the words. The list hands a frame from one view to the other, so every row has both
    -- sets of parts and shows the one its entry calls for (see InitItemRow).
    row.Effect = NewText(row, 11.5, SOFT, "LEFT", true)
    row.Effect:SetPoint("LEFT", row, "LEFT", PICK_LEFT, 0)
    row.Stock = NewText(row, 12, SOFT, "RIGHT", true)
    row.Stock:SetPoint("RIGHT", row, "LEFT", PER_RIGHT, 0)

    row.Buy = NewButton(row, 58, 20, "ButtonDark", 9.5)
    row.Buy:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.Buy.Label:SetText(ns.Upper(L.BUY))
    row.Buy:SetScript("OnClick", BuyOnClick)

    row:SetScript("OnEnter", ItemRowOnEnter)
    row:SetScript("OnLeave", ItemRowOnLeave)
    row:SetScript("OnHide", ItemRowOnHide)
    row:SetScript("OnClick", ItemRowOnClick)
    -- The game redraws a tooltip through this while it is up: the price the player is short
    -- by changes with their money, and the item data may still be arriving.
    row.UpdateTooltip = ShowItemTooltip
end

-- A slot's heading: an amber band with the slot's name on it. The whole band is the switch
-- that folds the slot away; the arrow at its end shows which way it is.
local function BuildHeaderRow(row)
    row.built = true

    local band = NewTexture(row, "HeaderBand", "BACKGROUND")
    band:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
    band:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 3)

    local diamond = NewTexture(row, "Diamond", "ARTWORK")
    diamond:SetSize(12, 12)
    diamond:SetPoint("LEFT", row, "LEFT", 6, 0)

    row.Title = NewText(row, 11.5, GOLD)
    row.Title:SetPoint("LEFT", row, "LEFT", 24, 0)

    row.Arrow = NewTexture(row, "Chevron", "ARTWORK")
    row.Arrow:SetSize(12, 12)
    row.Arrow:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.Arrow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])

    -- "5 of 17": how many of the slot's upgrades are listed.
    row.Count = NewText(row, 10.5, SOFT, "RIGHT")
    row.Count:SetPoint("RIGHT", row.Arrow, "LEFT", -6, 0)

    row.Toggle = CreateFrame("Button", nil, row)
    row.Toggle:SetAllPoints()
    local glow = NewTexture(row.Toggle, "RowGlow", "HIGHLIGHT")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.72, 0.30, 0.20)
    glow:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
    glow:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 3)
    row.Toggle:SetScript("OnClick", HeaderOnClick)
end

local function CanBuy()
    return S.state == "idle" and S.IsOpen()
end

-- A consumable: its name, what it does, what that is worth on the Pawn scale (when Pawn can
-- say), the price of one piece and how many are for sale.
local function InitSupplyRow(row, entry, share)
    local supply = entry.supply
    row.Icon:SetTexture(supply.icon)
    -- What is of no use to the character is listed in grey (and only when everything is).
    row.Icon:SetDesaturated(entry.useless)
    row.Rim:SetVertexColor(ns.QualityColor(supply.quality))
    row.Name:SetText(ns.QualityText(supply.name, supply.quality))
    row.Name:SetWidth(NAME_WIDTH)
    row.Hand:Hide()
    SetPick(row.Pick, nil)

    -- The best of its kind reads brighter than the others listed under it.
    local color = entry.best and not entry.useless and CREAM or MUTED
    row.Effect:SetTextColor(color[1], color[2], color[3])
    row.Effect:SetText(supply.effect or "")
    row.Stock:SetText(tostring(supply.quantity))

    local scored = entry.value ~= nil
    row.Upgrade:SetShown(scored)
    row.Trough:SetShown(scored)
    row.Meter:SetShown(scored)
    row.Effect:SetWidth(scored and SCORE_LEFT - PAD - PICK_LEFT or UPGRADE_RIGHT - PICK_LEFT)
    if scored then
        -- The number alone, where a gear row has "+4.7 +80%".
        row.Upgrade:ClearAllPoints()
        row.Upgrade:SetPoint("RIGHT", row, "LEFT", UPGRADE_RIGHT, 3)
        row.Upgrade:SetText("+" .. ns.Num(entry.value))
        row.Meter:SetWidth(math.max((METER_WIDTH - 1) * share, 2))
        row.Meter:SetTexCoord(0, math.max(share, 0.03), 0, 1)
    end

    row.Price:SetFontObject(entry.affordable and PriceFontWhite or PriceFontRed)
    SetMoney(row.Price, ns.Copper(supply.price))

    row.Buy:SetEnabled(CanBuy() and entry.affordable)
end

local function InitItemRow(row, element)
    if not row.built then BuildItemRow(row) end
    local data = element.data
    local entry = data.entry
    local offer = entry.offer
    row.entry = entry

    -- The frame may have been a row of the other view a moment ago.
    local gear = entry.supply == nil
    row.Share:SetShown(gear)
    row.PerPoint:SetShown(gear)
    row.Effect:SetShown(not gear)
    row.Stock:SetShown(not gear)
    if not gear then
        InitSupplyRow(row, entry, data.share or 1)
        return
    end
    row.Upgrade:Show()
    row.Trough:Show()
    row.Meter:Show()
    row.Upgrade:ClearAllPoints()
    row.Upgrade:SetPoint("RIGHT", row.Share, "LEFT", -5, 0)

    row.Icon:SetTexture(offer.icon)
    row.Icon:SetDesaturated(false)
    row.Rim:SetVertexColor(ns.QualityColor(offer.quality))

    local name = ns.QualityText(offer.name, offer.quality)
    if offer.effects then name = name .. " " .. NORMAL_FONT_COLOR:WrapTextInColorCode("*") end
    row.Name:SetText(name)

    -- "Main Hand" lists one-hand and two-hand weapons together, so each row says which it is.
    -- The name gives up the room the label takes.
    local hand = ns.Compare.HandLabel(offer.invType)
    row.Hand:SetShown(hand ~= nil)
    if hand then
        row.Hand:SetText(hand)
        row.Name:SetWidth(math.max(NAME_WIDTH - row.Hand:GetStringWidth() - PAD, NAME_MIN_WIDTH))
    else
        row.Name:SetWidth(NAME_WIDTH)
    end

    SetPick(row.Pick, entry.pick)

    row.Upgrade:SetText("+" .. ns.Num(entry.delta))
    row.Share:SetText(entry.percent and ("+" .. FormatPercentage(entry.percent, true)) or L.NEW)
    row.Meter:SetWidth(math.max((METER_WIDTH - 1) * data.share, 2))
    row.Meter:SetTexCoord(0, math.max(data.share, 0.03), 0, 1)

    row.Price:SetFontObject(entry.affordable and PriceFontWhite or PriceFontRed)
    SetMoney(row.Price, offer.buyout)
    SetMoney(row.PerPoint, ns.Copper(entry.costPer))

    row.Buy:SetEnabled(CanBuy() and entry.affordable)
end

local function InitHeaderRow(row, element)
    if not row.built then BuildHeaderRow(row) end
    local data = element.data
    row.group = data.group
    -- A slot's name, or the title a heading of consumables comes with.
    row.Title:SetText(ns.Upper(data.title or ns.Compare.GroupLabel(data.group)))

    local count = ""
    if data.shown < data.total then
        -- "3 of about 19": some of the 19 have not had their price looked up. The word is
        -- spelled out because the game's font draws "~" raised, like an accent.
        count = (data.approx and L.TOP_OF_ABOUT or L.TOP_OF):format(data.shown, data.total)
    elseif data.collapsed then
        -- A folded slot still says how much there is in it.
        count = tostring(data.total)
    end
    row.Count:SetText(count)
    row.Arrow:SetTexture(File(data.collapsed and "ChevronRight" or "Chevron"))
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
-- The scroll box shows a "data provider": an ordered collection of tables, one per row. It
-- makes frames only for the rows in view and asks an initializer to fill each one in. It tells
-- rows apart by their table: a row that keeps its table keeps its frame. So every row has one
-- table for as long as it is listed (`elements`, by key), and a refresh changes what is in
-- that table instead of replacing it. A list that refreshes after every price check of a
-- scan would otherwise rebuild the row under the mouse each time, and its tooltip with it.

local function RowKey(row)
    if row.kind == "header" then return "H:" .. row.group end
    if row.kind == "supply" then return "U:" .. row.entry.supply.id end
    return "I:" .. row.entry.group .. ":" .. tostring(row.entry.offer.id)
end

-- Slot headings are plain frames, offers are buttons: two kinds of row, each with its own
-- frames. A row never changes its kind, the kind being part of its key.
local function RowFactory(factory, element)
    if element.data.kind == "header" then
        factory("Frame", InitHeaderRow)
    else
        factory("Button", InitItemRow)
    end
end

local function ByOrder(a, b)
    return a.order < b.order
end

-- What the list shows of the rows Results.Build made: a folded slot keeps its heading and
-- nothing else. Every offer also learns how its gain compares with the best one in its slot,
-- for its meter; a slot lists its biggest gain first.
local function Fold(all)
    local collapsed = ns.db.collapsed
    local out, hidden, best = {}, false, nil
    for i = 1, #all do
        local row = all[i]
        if row.kind == "header" then
            hidden = collapsed[row.group] == true
            row.collapsed = hidden
            best = nil
            out[#out + 1] = row
        else
            -- A consumable's meter measures its score against the best one under the heading.
            -- (One without a score has no meter.)
            local delta = row.entry.delta or row.entry.value
            if delta then
                best = best or delta
                row.share = best > 0 and math.min(delta / best, 1) or 1
            end
            if not hidden then out[#out + 1] = row end
        end
    end
    return out
end

-- More rows than this coming or going at once (a filter switched, a new scan) are not worth
-- patching in: the collection is emptied and filled again. That starts the list from its
-- top, so a slot folded or unfolded is patched in whatever its size (keepPlace).
local PATCH_LIMIT = 40

-- Makes the scroll box show `rows`.
local function SyncList()
    syncCount = syncCount + 1
    local fresh = {}
    for i = 1, #rows do
        local row = rows[i]
        local key = RowKey(row)
        local element = elements[key]
        if not element then
            element = { key = key }
            elements[key] = element
            fresh[#fresh + 1] = element
        end
        element.data, element.order, element.seen = row, i, syncCount
    end
    local stale = {}
    for key, element in pairs(elements) do
        if element.seen ~= syncCount then
            stale[#stale + 1] = element
            elements[key] = nil
        end
    end

    local patch = keepPlace or #stale + #fresh <= PATCH_LIMIT
    keepPlace = false
    if not patch then
        local all = {}
        for i = 1, #rows do all[i] = elements[RowKey(rows[i])] end
        provider:Flush()
        provider:InsertTable(all)
    else
        if #stale > 0 then provider:Remove(unpack(stale)) end
        if #fresh > 0 then
            provider:InsertTable(fresh)         -- sorts itself into place (ByOrder)
        else
            -- Nothing new, but the rows that stay may have changed places.
            local last, sorted = 0, true
            for _, element in provider:Enumerate() do
                if element.order < last then sorted = false break end
                last = element.order
            end
            if not sorted then provider:Sort() end
        end
    end

    -- The rows in view kept their frames; show what their tables hold now.
    scrollBox:ReinitializeFrames()

    if toTop then
        toTop = false
        scrollBox:ScrollToBegin(ScrollBoxConstants.NoScrollInterpolation)
    end
end

---------------------------------------------------------------------------
-- Status line and refresh
---------------------------------------------------------------------------
-- Each view has a scan of its own: when the last one ended, and the note it left.
local function FinishedAt()
    if view == "supplies" then return S.suppliesAt end
    return S.finishedAt
end

local function Note()
    if view == "supplies" then return S.suppliesNote end
    return S.message
end

-- What a scan found reads with the character's name in front when the list is not for the
-- one being played: whose list this is must not be a guess.
local function ForWho(text)
    local who = ns.Roster.Target()
    if not who or text == "" then return text end
    return L.ST_WHO:format(WhoName(who), text)
end

-- What the last scan for consumables found, for the status line.
local function SuppliesText()
    local parts = {}
    if S.suppliesNote then parts[#parts + 1] = S.suppliesNote end
    if S.suppliesAt then
        if summary.items == 0 then
            parts[#parts + 1] = summary.hidden > 0 and L.ST_SUP_NONE_AFFORD:format(summary.hidden) or L.ST_SUP_NONE
        elseif summary.hidden > 0 then
            parts[#parts + 1] = L.ST_SUP_DONE_HIDDEN:format(summary.items, summary.groups, summary.hidden)
        else
            parts[#parts + 1] = L.ST_SUP_DONE:format(summary.items, summary.groups)
        end
        if S.suppliesPartial and not S.suppliesNote then parts[#parts + 1] = L.ST_PARTIAL end
        parts[#parts + 1] = L.ST_AGE:format(ns.Ago(time() - S.suppliesAt))
    end
    return ForWho(table.concat(parts, " "))
end

local function StatusText()
    -- What the scanner is doing is said in both views, whichever of them it is working for.
    if S.state == "browse" then
        return L.ST_BROWSE:format(S.info.rows)
    elseif S.state == "score" then
        return (S.mode == "supplies" and L.ST_SUP_SCORE or L.ST_SCORE):format(S.info.scored, S.info.toScore)
    elseif S.state == "verify" then
        if S.mode == "scan" or S.mode == "more" then
            local text = L.ST_VERIFY:format(S.info.verified, S.info.toVerify)
            -- Known only when every remaining price will be looked up (see Scanner.TimeLeft).
            local left = S.TimeLeft()
            if left then text = text .. L.ST_LEFT:format(ns.Duration(left)) end
            return text
        end
        return L.ST_BUYCHECK
    end
    if view == "supplies" then return SuppliesText() end

    local parts = {}
    if S.message then parts[#parts + 1] = S.message end
    if S.finishedAt then
        if summary.upgrades == 0 then
            parts[#parts + 1] = summary.hidden > 0 and L.ST_NONE_AFFORD:format(summary.hidden) or L.ST_NONE
        elseif summary.hidden > 0 then
            parts[#parts + 1] = L.ST_DONE_HIDDEN:format(summary.upgrades, summary.slots, summary.hidden)
        else
            parts[#parts + 1] = L.ST_DONE:format(summary.upgrades, summary.slots)
        end
        if (S.partial or S.halted) and not S.message then parts[#parts + 1] = L.ST_PARTIAL end
        parts[#parts + 1] = L.ST_AGE:format(ns.Ago(time() - S.finishedAt))
    end
    return ForWho(table.concat(parts, " "))
end

-- Whom the lists are for, the scales to choose from and the one in use, as one string: the
-- dropdown is rebuilt when this changes (a scale enabled or hidden in Pawn while the auction
-- house is open, a character forgotten).
local function ScaleKey()
    if ns.Pawn.Problem() then return "" end
    local who = ns.Roster.Target()
    local current, scales = ns.Pawn.CurrentScale(who)
    local names = {}
    for i = 1, #scales do names[i] = scales[i].name end
    return (who and who.key or "") .. "\n" .. #ns.Roster.List() .. "\n"
        .. (current and current.name or "") .. "=" .. table.concat(names, "\n")
end

local function ScaleTitle()
    if ns.Pawn.Problem() then return NONE end
    local scale = ns.Pawn.CurrentScale(ns.Roster.Target())
    return scale and scale.title or NONE
end

-- What an empty list says before its first scan: what the scan will find, and for whom.
local function IntroText()
    local who = ns.Roster.Target()
    if view == "supplies" then
        -- Consumables can be listed without Pawn, only without scores: what is wrong with
        -- Pawn is said in the Upgrades view, which cannot do without it.
        return who and L.SUP_HINT_WHO:format(WhoName(who)) or L.SUP_HINT
    end
    local problem = ns.Pawn.Problem()
    if problem then return problem end
    if who then return L.HINT_WHO:format(WhoName(who), ScaleTitle()) end
    return L.HINT:format(ScaleTitle())
end

-- The status line, with a bar beside it while the scanner works. An empty list has the
-- middle of the plate to say more:
--   before the first scan   the addon's emblem and what to do (or what is wrong with Pawn)
--   during a scan           the same words as the status line, over a wider bar
--   after one               why the list is empty
local function ShowStatus()
    local text = StatusText()
    local idle = S.state == "idle"
    local progress = not idle and Progress() or nil

    status:SetText(text)
    -- The line gives way to the bar only while there is one.
    status:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT",
        idle and -PAD or -(BAR_RIGHT + STATUS_BAR_WIDTH + PAD), PANEL_BOTTOM - 1)
    statusBar:SetShown(not idle)
    if not idle then SetBar(statusBar, progress) end

    local empty = #rows == 0
    local first = empty and idle and not (FinishedAt() or Note())
    intro:SetShown(first)
    listBar:SetShown(empty and not idle)
    hint:ClearAllPoints()
    if not empty then
        hint:SetText("")
    elseif not idle then
        SetBar(listBar, progress)
        hint:SetPoint("BOTTOM", listBar, "TOP", 0, 10)
        hint:SetText(text)
    elseif first then
        hint:SetPoint("TOP", intro, "BOTTOM", 0, -12)
        hint:SetText(IntroText())
    else
        hint:SetPoint("CENTER", scrollBox, "CENTER", 0, 10)
        hint:SetText(text)
    end
end

-- The age of the scan in the status line grows with the clock, and no event comes when a
-- second passes. This runs on a frame inside the tab, so only while the tab is in view.
local clockAt
local function ClockOnUpdate()
    local now = time()
    if now == clockAt then return end
    clockAt = now
    if S.state == "idle" and FinishedAt() then ShowStatus() end
end

local function SetCheck(check, checked)
    checked = checked and true or false
    check:SetChecked(checked)
    check.Tick:SetShown(checked)
end

-- How the list of consumables is to score what one of them adds: with Pawn, on the scale in
-- use. Nothing when Pawn cannot be asked; the list then has no scores and leaves nothing out.
local MANA = Enum.PowerType and Enum.PowerType.Mana or 0
local function SupplyValue(who)
    if ns.Pawn.Problem() then return nil end
    local scale = ns.Pawn.CurrentScale(who)
    if not scale then return nil end
    local name = scale.name
    return function(stats) return ns.Pawn.StatsValue(stats, name) end
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end

    local all
    if view == "supplies" then
        -- What is paid with is always the gold of the character being played; what a
        -- consumable is worth, and whether mana is of any use, is the question of the
        -- character the list is for.
        local who = ns.Roster.Target()
        local mana
        if who then mana = who.mana and true or false else mana = (UnitPowerMax("player", MANA) or 0) > 0 end
        all, summary = ns.Supplies.Build(S.supplies, {
            money = GetMoney(),
            affordableOnly = ns.db.affordableOnly,
            bestOnly = ns.db.bestOnly,
            value = SupplyValue(who),
            mana = mana,
        })
    else
        all, summary = ns.Results.Build(S.offers, S.ctx, {
            money = GetMoney(),
            affordableOnly = ns.db.affordableOnly,
            limit = ns.db.topOnly and ns.Results.TOP_COUNT or nil,
            unchecked = S.Unchecked(),
        })
    end
    rows = Fold(all)
    SyncList()

    local idle = S.state == "idle"
    ShowStatus()
    -- Red while it starts a scan, dark while it stops one.
    scanButton.Label:SetText(ns.Upper(idle and L.SCAN or L.STOP))
    scanButton.Face:SetFile(idle and "ButtonRed" or "ButtonDark")
    scanButton:SetEnabled(idle or S.mode == "scan" or S.mode == "more" or S.mode == "supplies")
    SetCheck(affordCheck, ns.db.affordableOnly)
    SetCheck(topCheck, ns.db.topOnly)
    SetCheck(bestCheck, ns.db.bestOnly)

    local scaleKey = ScaleKey()
    if scaleKey ~= scaleShown then
        scaleShown = scaleKey
        scaleDropdown:GenerateMenu()
    end

    -- The scan looks up only the prices the list can show. If the list now needs more of them
    -- (a filter was switched off, an offer was bought), this is where it asks. Only the gear
    -- list asks: a lookup started behind the Consumables view would keep its Buy buttons grey.
    if view == "gear" then S.Demand() end
end

-- Redraws soon, and once however many times it is asked: a scan reports progress many times
-- a second. The wait runs on the tab's own OnUpdate, so nothing is drawn while it is hidden.
local wait = 0
local function RefreshOnUpdate(self, elapsed)
    wait = wait - elapsed
    if wait <= 0 then
        self:SetScript("OnUpdate", nil)
        UI.Refresh()
    end
end

local function QueueRefresh()
    if not frame or not frame:IsShown() or frame:GetScript("OnUpdate") then return end
    wait = REFRESH_INTERVAL
    frame:SetScript("OnUpdate", RefreshOnUpdate)
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------
-- The scale field answers two questions at once: whom the lists are for, and on which of
-- that character's Pawn scales. Its menu has the scales of the character being played, and
-- under them those of every other character of the account the addon has seen (Roster.List),
-- each line beginning with the character's name. A line of the menu is a "choice":
--   { who = the character's key, false for the one being played; scale = the scale's name }
local function IsChoice(choice)
    local who = ns.Roster.Target()
    if (who and who.key or false) ~= choice.who then return false end
    local scale = ns.Pawn.CurrentScale(who)
    return scale ~= nil and scale.name == choice.scale
end

local function Choose(choice)
    if IsChoice(choice) then return end
    local card = nil
    if choice.who then
        card = ns.Roster.Get(choice.who)
        if not card then return end
    end
    local owner = card or ns.Roster.Me()
    if not owner then return end
    local sameWho = card == ns.Roster.Target()
    -- A character's scale is remembered with the character, whoever chose it.
    owner.scale = choice.scale

    if sameWho then
        -- Scores of gear from another scale mean nothing now, and the Upgrades view scans
        -- again. Consumables are scored as their list is drawn, so theirs follow with the
        -- refresh; a scan for gear is not started from their view, where it would grey out
        -- the Buy buttons.
        local rescan = view == "gear" and (S.finishedAt ~= nil or S.state ~= "idle")
        S.Reset()
        if rescan and S.IsOpen() then S.Start() end
    else
        -- Another character: neither list is about it. The view that had a list, or was
        -- making one, gets it made again; the other waits for its Scan button.
        local rescan = S.state ~= "idle"
        if view == "gear" then rescan = rescan or S.finishedAt ~= nil else rescan = rescan or S.suppliesAt ~= nil end
        StaticPopup_Hide(POPUP)
        buyBox:Hide()
        ns.Roster.SetTarget(card)
        S.Retarget()
        if rescan and S.IsOpen() then
            if view == "supplies" then S.StartSupplies() else S.Start() end
        elseif card and not ns.Pawn.Problem() then
            -- Nothing to scan yet: the character's gear is asked of the server now, so that
            -- it is at hand when the scan comes (see PawnBridge.Context).
            ns.Pawn.Context(choice.scale, card)
        end
    end
    -- The dropdown shows the choice by itself; it must not be rebuilt while its menu is open.
    scaleShown = ScaleKey()
    toTop = true
    UI.Refresh()
end

local MENU_ROWS = 20        -- a menu with more lines than this scrolls

local function ScaleMenu(_, root)
    if ns.Pawn.Problem() then return end
    local lines = 0
    local _, scales = ns.Pawn.CurrentScale()
    for i = 1, #scales do
        root:CreateRadio(scales[i].title, IsChoice, Choose, { who = false, scale = scales[i].name })
        lines = lines + 1
    end

    local me = ns.Roster.Me()
    local cards = ns.Roster.List()
    for c = 1, #cards do
        local card = cards[c]
        local _, theirs = ns.Pawn.CurrentScale(card)
        if card ~= me and #theirs > 0 then
            if lines > 0 and root.CreateDivider then root:CreateDivider() end
            -- The name in the colour of the class, then the scale without the class it is
            -- named after: "Diluna: Balance". The field shows the line that is chosen, so
            -- it says whose list this is as long as it is not one's own.
            local name = WhoName(card)
            -- What is bought here cannot be sent to another realm: a character of one is
            -- listed with its realm, so that it is not chosen by mistake.
            if me and card.realm and me.realm and card.realm ~= me.realm then
                name = name .. " (" .. card.realm .. ")"
            end
            for i = 1, #theirs do
                root:CreateRadio(name .. ": " .. ns.Roster.Short(card, theirs[i].title), IsChoice, Choose,
                    { who = card.key, scale = theirs[i].name })
                lines = lines + 1
            end
        end
    end
    if lines > MENU_ROWS and root.SetScrollMode then root:SetScrollMode(MENU_ROWS * 20) end
end

-- The game's dropdown under a face of ours: a recess with a gold arrow. Its own plate and
-- arrow are made see-through, not removed, because the dropdown goes on setting them as its
-- state changes; its text and its menu are left as they are.
local function SkinDropdown(dropdown)
    for _, key in ipairs({ "Background", "Arrow" }) do
        local art = dropdown[key]
        if type(art) == "table" and art.SetAlpha then art:SetAlpha(0) end
    end
    NewSlices(dropdown, "Inset", 0.25, 8, "BACKGROUND", -1)
    NewSlices(dropdown, "ButtonGlow", 0.25, 8, "HIGHLIGHT"):SetBlendMode("ADD")
    local arrow = NewTexture(dropdown, "Chevron", "OVERLAY")
    arrow:SetSize(14, 14)
    arrow:SetPoint("RIGHT", dropdown, "RIGHT", -7, 0)
    arrow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
end

local function ScanOnClick()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if S.state ~= "idle" then
        S.Stop(L.ST_STOPPED)
    elseif view == "supplies" then
        S.StartSupplies()
    else
        S.Start()
    end
    UI.Refresh()
end

-- A tick box for one of the list's two filters: a recess, a gold tick, the label beside it.
-- A click on the label ticks the box, as everywhere in the game.
local function NewFilterCheck(text, setting, tip)
    local check = CreateFrame("CheckButton", nil, frame)
    check:SetSize(CHECK_SIZE, CHECK_SIZE)
    NewSlices(check, "Inset", 0.25, 6, "BACKGROUND")
    local glow = NewTexture(check, "Glow", "HIGHLIGHT")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.74, 0.32, 0.55)
    glow:SetPoint("TOPLEFT", check, "TOPLEFT", -7, 7)
    glow:SetPoint("BOTTOMRIGHT", check, "BOTTOMRIGHT", 7, -7)
    check.Tick = NewTexture(check, "Check", "OVERLAY")
    check.Tick:SetSize(18, 18)
    check.Tick:SetPoint("CENTER", check, "CENTER", 1, 1)
    check.Text = NewText(check, 11, CREAM)
    check.Text:SetPoint("LEFT", check, "RIGHT", CHECK_GAP, 0)
    check.Text:SetText(text)
    check:SetHitRectInsets(0, -(CHECK_GAP + check.Text:GetStringWidth()), -4, -4)
    check:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        ns.db[setting] = checked
        toTop = true
        -- The player changed what the list shows: price checks that were stopped may go on.
        S.Resume()
        UI.Refresh()
    end)
    if tip then
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip_SetTitle(GameTooltip, text)
            GameTooltip_AddNormalLine(GameTooltip, tip)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", GameTooltip_Hide)
    end
    return check
end

-- The label of the scale field: the words of L.SCALE without the colon they end in.
local function ScaleLabel()
    return ns.Upper((L.SCALE:gsub("%s*:%s*$", ""):gsub("：$", "")))
end

---------------------------------------------------------------------------
-- The box that asks how many of a consumable to buy
---------------------------------------------------------------------------
-- A purchase of a consumable goes in steps (see "Consumables: the scan and the purchase" in
-- Scanner.lua), and the box follows them in `step`:
--   choose   the player types how many; the box shows what that many cost by the price list
--   quote    "Buy" was pressed: the server is being asked what exactly they cost
--   confirm  the server's price is shown and the button reads "Confirm"
--   wait     pressed again: the purchase is on its way
-- A consumable sold as separate auctions has nothing to choose: the box offers its cheapest
-- auction (`auction`) as it is, and one press buys it.
local BOX_WIDTH, BOX_HEIGHT, BOX_EDGE = 330, 162, 18

-- A caption beside a field: the words of a label without the colon they end in.
local function Caption(text)
    return ns.Upper((text:gsub("%s*:%s*$", ""):gsub("：$", "")))
end

local function PaintBox()
    if not buyBox.tiers then return end
    local step = buyBox.step
    local settled = step == "confirm" or step == "wait"
    local cost
    if settled then
        cost = buyBox.quoted
    elseif buyBox.auction then
        cost = buyBox.auction.cost
    else
        local count = buyBox.Count:GetNumber()
        cost = count > 0 and S.SupplyCost(buyBox.tiers, count) or nil
    end
    local affordable = cost ~= nil and cost <= GetMoney()

    buyBox.TotalLabel:SetText(Caption(settled and L.QTY_FINAL or L.QTY_TOTAL))
    -- No price for nothing, or for more pieces than there are.
    buyBox.Total:SetShown(cost ~= nil)
    if cost then
        buyBox.Total:SetFontObject(affordable and PriceFontWhite or PriceFontRed)
        SetMoney(buyBox.Total, ns.Copper(cost))
    end
    buyBox.Buy.Label:SetText(ns.Upper(step == "confirm" and L.QTY_CONFIRM or L.BUY))
    buyBox.Buy:SetEnabled((step == "choose" or step == "confirm") and affordable and S.Ready())
    buyBox.Count:SetEnabled(step == "choose" and buyBox.auction == nil)
end

local function CloseBox()
    buyBox:Hide()
end

local function BoxBuyOnClick()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    local step = buyBox.step
    if step == "confirm" then
        buyBox.step = "wait"
        S.ConfirmSupply()
    elseif step ~= "choose" then
        return
    elseif buyBox.auction then
        buyBox.step, buyBox.quoted = "wait", buyBox.auction.cost
        S.BuySupplyAuction(buyBox.supply, buyBox.tiers)
    else
        buyBox.step = "quote"
        S.QuoteSupply(buyBox.supply, buyBox.tiers, buyBox.Count:GetNumber())
    end
    PaintBox()
end

local function BuildBuyBox()
    buyBox = CreateFrame("Frame", nil, frame)
    buyBox:SetSize(BOX_WIDTH, BOX_HEIGHT)
    buyBox:SetPoint("CENTER", scrollBox, "CENTER", 0, 0)
    -- Above the rows, and in the way of clicks meant for the rows under it.
    buyBox:SetFrameStrata("DIALOG")
    buyBox:EnableMouse(true)
    buyBox:Hide()
    NewSlices(buyBox, "Panel", 0.375, 12, "BACKGROUND", 0, 1.5)

    buyBox.Icon = buyBox:CreateTexture(nil, "ARTWORK")
    buyBox.Icon:SetSize(ICON_SIZE - 3, ICON_SIZE - 3)
    buyBox.Icon:SetPoint("CENTER", buyBox, "TOPLEFT", BOX_EDGE + ICON_SIZE / 2, -28)
    buyBox.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    buyBox.Rim = NewTexture(buyBox, "IconRim", "ARTWORK", 1)
    buyBox.Rim:SetSize(ICON_SIZE, ICON_SIZE)
    buyBox.Rim:SetPoint("CENTER", buyBox.Icon, "CENTER", 0, 0)
    buyBox.Name = NewText(buyBox, 13, CREAM, "LEFT", true)
    buyBox.Name:SetPoint("LEFT", buyBox.Rim, "RIGHT", PAD, 0)
    buyBox.Name:SetWidth(BOX_WIDTH - 2 * BOX_EDGE - ICON_SIZE - PAD)

    local rule = NewLine(buyBox)
    rule:SetVertexColor(0.80, 0.60, 0.26, 0.55)
    rule:SetPoint("TOPLEFT", buyBox, "TOPLEFT", BOX_EDGE - 4, -48)
    rule:SetPoint("TOPRIGHT", buyBox, "TOPRIGHT", -(BOX_EDGE - 4), -48)

    local countLabel = NewText(buyBox, 9.5, GOLD_DIM)
    countLabel:SetPoint("LEFT", buyBox, "TOPLEFT", BOX_EDGE, -70)
    countLabel:SetText(Caption(L.QTY))

    -- The field for the number: an edit box of the game's in a recess of ours.
    local count = CreateFrame("EditBox", nil, buyBox)
    count:SetSize(56, 22)
    count:SetPoint("LEFT", countLabel, "RIGHT", PAD, 0)
    NewSlices(count, "Inset", 0.25, 6, "BACKGROUND")
    count:SetFont(numberFont, 13, "")
    count:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    count:SetJustifyH("CENTER")
    count:SetAutoFocus(false)
    count:SetNumeric(true)
    count:SetMaxLetters(4)
    count:SetScript("OnTextChanged", PaintBox)
    count:SetScript("OnEnterPressed", function() buyBox.Buy:Click() end)
    count:SetScript("OnEscapePressed", CloseBox)
    buyBox.Count = count

    -- "of 152 for sale"
    buyBox.Stock = NewText(buyBox, 11, MUTED, "LEFT", true)
    buyBox.Stock:SetPoint("LEFT", count, "RIGHT", PAD, 0)

    buyBox.TotalLabel = NewText(buyBox, 9.5, GOLD_DIM)
    buyBox.TotalLabel:SetPoint("LEFT", buyBox, "TOPLEFT", BOX_EDGE, -102)
    buyBox.Total = CreateFrame("Frame", nil, buyBox, "MoneyDisplayFrameTemplate")
    buyBox.Total:SetPoint("RIGHT", buyBox, "TOPRIGHT", -BOX_EDGE, -102)
    if not C_AuctionHouse.SupportsCopperValues() then
        buyBox.Total.CopperDisplay:SetForcedHidden(true)
    end

    buyBox.Buy = NewButton(buyBox, 138, 24, "ButtonRed", 11)
    buyBox.Buy:SetPoint("BOTTOMLEFT", buyBox, "BOTTOMLEFT", BOX_EDGE, 16)
    buyBox.Buy:SetScript("OnClick", BoxBuyOnClick)
    buyBox.Cancel = NewButton(buyBox, 138, 24, "ButtonDark", 11)
    buyBox.Cancel:SetPoint("BOTTOMRIGHT", buyBox, "BOTTOMRIGHT", -BOX_EDGE, 16)
    buyBox.Cancel.Label:SetText(ns.Upper(CANCEL))
    buyBox.Cancel:SetScript("OnClick", CloseBox)

    -- However the box goes away, a purchase that was not confirmed is off.
    buyBox:SetScript("OnHide", function() S.CancelSupply() end)
end

---------------------------------------------------------------------------
-- The two views
---------------------------------------------------------------------------
local function CheckWidth(check)
    return CHECK_SIZE + CHECK_GAP + check.Text:GetStringWidth()
end

-- Makes the frame's controls and titles those of `view`. The list itself follows at the
-- next refresh.
local function ApplyView()
    local gear = view == "gear"
    local list = frame.List

    -- Item, pick, gain, buyout, price per point; or item, effect, score, price of a piece, pieces.
    list.Titles[2]:SetText(ns.Upper(gear and L.COL_PICK or L.COL_EFFECT))
    list.Titles[3]:SetText(ns.Upper(gear and L.COL_UPGRADE or L.COL_SCORE))
    list.Titles[4]:SetText(ns.Upper(gear and L.COL_PRICE or L.COL_UNIT))
    list.Titles[5]:SetText(ns.Upper(gear and L.COL_PER or L.COL_STOCK))
    intro.Heading:SetText(ns.Upper(gear and L.TITLE or L.TITLE_SUP))

    -- Both views score with the Pawn scale; their second filter is another one.
    local second = gear and topCheck or bestCheck
    topCheck:SetShown(gear)
    bestCheck:SetShown(not gear)
    affordCheck:ClearAllPoints()
    affordCheck:SetPoint("LEFT", second, "LEFT", -(2 * PAD + CheckWidth(affordCheck)), 0)

    -- The scale field takes the room this view's labels leave, as in Build; where they leave
    -- too little, it stands without its own label.
    local label = frame.ScaleLabel
    local labelWidth = label and label:GetStringWidth() + PAD or 0
    local room = AuctionHouseFrame:GetWidth() - (BAR_LEFT + SCAN_WIDTH + 2 * PAD
        + 2 * PAD + CheckWidth(affordCheck) + 2 * PAD + CheckWidth(second) + BAR_RIGHT)
    local labelled = label ~= nil and room - labelWidth >= DROPDOWN_MIN
    if label then label:SetShown(labelled) end
    if not labelled then labelWidth = 0 end
    scaleDropdown:SetWidth(Clamp(room - labelWidth, DROPDOWN_MIN, DROPDOWN_MAX))
    scaleDropdown:ClearAllPoints()
    scaleDropdown:SetPoint("LEFT", scanButton, "RIGHT", 2 * PAD + labelWidth, 0)

    buyBox:Hide()
    toTop = true
end

-- What the Consumables view adds to the frame Build has made, and what makes the frame serve
-- two tabs. (A part of Build in its own right, also because one Lua function can refer to
-- only so many of a file's local names.)
local function BuildViews(auction)
    -- Where the Upgrades view has "Top N per slot".
    bestCheck = NewFilterCheck(L.SUP_BEST, "bestOnly", L.SUP_BEST_TIP)
    bestCheck:SetPoint("LEFT", frame, "TOPRIGHT", -(BAR_RIGHT + CheckWidth(bestCheck)), -BAR_MIDDLE)
    BuildBuyBox()
    frame.BestCheck, frame.BuyBox = bestCheck, buyBox

    -- The library that makes the tabs shows and hides the frame a tab was made with. So the
    -- Consumables tab is made with an empty frame of its own, and the real one comes and goes
    -- with it. Which of the two tabs brought the frame up says which view it is to show.
    holder = CreateFrame("Frame", nil, auction)
    holder:Hide()
    holder:SetScript("OnShow", function() frame:Show() end)
    holder:SetScript("OnHide", function() frame:Hide() end)

    frame:SetScript("OnShow", function()
        local shown = holder:IsShown() and "supplies" or "gear"
        if shown ~= view then
            view = shown
            ApplyView()
        end
        UI.Refresh()
    end)
    -- Another tab, or the window closed: a question about buying must not stay up.
    frame:SetScript("OnHide", function()
        StaticPopup_Hide(POPUP)
        buyBox:Hide()
    end)
    ApplyView()
end

local function Build()
    local auction = AuctionHouseFrame
    -- By now the game has settled on its fonts for the player's language, and so has any
    -- addon that replaces them.
    textFont = STANDARD_TEXT_FONT
    numberFont = Number13FontWhite and Number13FontWhite:GetFont() or textFont

    frame = CreateFrame("Frame", "UpgradeScoutFrame", auction)
    frame:SetAllPoints()
    frame:Hide()

    -- The strip above the list, where the Buy tab has its search box.
    scanButton = NewButton(frame, SCAN_WIDTH, 26, "ButtonRed", 12)
    scanButton:SetPoint("LEFT", frame, "TOPLEFT", BAR_LEFT, -BAR_MIDDLE)
    scanButton.Label:SetText(ns.Upper(L.SCAN))
    scanButton:SetScript("OnClick", ScanOnClick)

    topCheck = NewFilterCheck(L.TOP:format(ns.Results.TOP_COUNT), "topOnly", L.TOP_TIP:format(ns.Results.TOP_COUNT))
    local topWidth = CHECK_SIZE + CHECK_GAP + topCheck.Text:GetStringWidth()
    topCheck:SetPoint("LEFT", frame, "TOPRIGHT", -(BAR_RIGHT + topWidth), -BAR_MIDDLE)
    affordCheck = NewFilterCheck(L.AFFORD, "affordableOnly")
    local affordWidth = CHECK_SIZE + CHECK_GAP + affordCheck.Text:GetStringWidth()
    affordCheck:SetPoint("LEFT", topCheck, "LEFT", -(2 * PAD + affordWidth), 0)

    local scaleLabel = NewText(frame, 9.5, GOLD_DIM)
    frame.ScaleLabel = scaleLabel
    scaleLabel:SetPoint("LEFT", scanButton, "RIGHT", 2 * PAD, 0)
    scaleLabel:SetText(ScaleLabel())

    -- The dropdown takes the room the labels leave, within reason. Where a language's labels
    -- leave too little, the field stands without its label; its tooltip says what it is.
    local labelWidth = scaleLabel:GetStringWidth() + PAD
    local room = auction:GetWidth() - (BAR_LEFT + SCAN_WIDTH + 2 * PAD + labelWidth
        + 2 * PAD + affordWidth + 2 * PAD + topWidth + BAR_RIGHT)
    if room < DROPDOWN_MIN then
        scaleLabel:Hide()
        frame.ScaleLabel = nil
        room = room + labelWidth
        labelWidth = 0
    end
    scaleDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    scaleDropdown:SetSize(Clamp(room, DROPDOWN_MIN, DROPDOWN_MAX), 24)
    scaleDropdown:SetPoint("LEFT", scanButton, "RIGHT", 2 * PAD + labelWidth, 0)
    SkinDropdown(scaleDropdown)
    scaleDropdown:SetDefaultText(NONE)
    scaleDropdown:SetupMenu(ScaleMenu)
    scaleDropdown:SetTooltip(function(tooltip)
        local who = ns.Roster.Target()
        GameTooltip_SetTitle(tooltip, who and L.ST_WHO:format(WhoName(who), ScaleTitle()) or ScaleTitle())
        GameTooltip_AddNormalLine(tooltip, L.SCALE_TIP)
        GameTooltip_AddBlankLineToTooltip(tooltip)
        if who then
            -- How old what is known of the character is: the list is only as good as that.
            GameTooltip_AddHighlightLine(tooltip, L.WHO_SEEN:format(WhoName(who), who.level,
                ns.Ago(math.max(0, time() - (who.seen or time())))))
        end
        GameTooltip_AddNormalLine(tooltip, L.WHO_TIP)
    end)

    -- The plate the list lies on, with the column titles along its top.
    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", PANEL_LEFT, -PANEL_TOP)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PANEL_RIGHT, PANEL_BOTTOM)
    NewSlices(list, "Panel", 0.375, 12, "BACKGROUND", 0, 1.5)

    list.Titles = {}
    for i = 1, #TITLES do
        local column = TITLES[i]
        local point = column.numeric and "RIGHT" or "LEFT"
        local title = NewText(list, 9.5, GOLD_DIM, point)
        title:SetPoint(point, list, "TOPLEFT", LIST_LEFT + column.at, -16)
        -- The list has one order, best upgrade first in every slot: a title is not a button.
        title:SetText(ns.Upper(column.text))
        list.Titles[i] = title
    end
    local rule = NewLine(list)
    rule:SetVertexColor(0.80, 0.60, 0.26, 0.55)
    rule:SetPoint("TOPLEFT", list, "TOPLEFT", LIST_LEFT, -(LIST_TOP - 3))
    rule:SetPoint("TOPRIGHT", list, "TOPRIGHT", -LIST_LEFT, -(LIST_TOP - 3))

    -- The game's scroll box and scroll bar, set up the way Blizzard_AuctionHouseItemList sets
    -- up the Buy tab's list. Scrolling, the mouse wheel and the bar are all the scroll box's own.
    scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", list, "TOPLEFT", LIST_LEFT, -LIST_TOP)
    scrollBox:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -LIST_RIGHT, LIST_BOTTOM)
    local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 8, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 8, 2)

    local view = CreateScrollBoxListLinearView()
    view:SetElementFactory(RowFactory)
    -- Frames made from a frame type, not a template, have no height of their own.
    view:SetElementExtent(ROW_HEIGHT)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    provider = CreateDataProvider()
    provider:SetSortComparator(ByOrder, true)       -- true: nothing to sort yet
    scrollBox:SetDataProvider(provider)

    -- The middle of an empty list (see ShowStatus).
    intro = CreateFrame("Frame", nil, list)
    intro:SetSize(320, 86)
    intro:SetPoint("CENTER", scrollBox, "CENTER", 0, 36)
    local emblem = intro:CreateTexture(nil, "ARTWORK")
    emblem:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\icon")
    emblem:SetSize(52, 52)
    emblem:SetPoint("TOP", intro, "TOP", 0, 0)
    local heading = NewText(intro, 12.5, GOLD, "CENTER")
    heading:SetPoint("TOP", emblem, "BOTTOM", 0, -12)
    heading:SetText(ns.Upper(L.TITLE))
    intro.Heading = heading
    local underline = NewLine(intro)
    underline:SetVertexColor(0.85, 0.64, 0.28, 0.7)
    underline:SetPoint("BOTTOMLEFT", intro, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", intro, "BOTTOMRIGHT", 0, 0)

    listBar = NewBar(list, 300, 10)
    listBar:SetPoint("TOP", scrollBox, "CENTER", 0, -6)
    listBar:Hide()

    hint = NewText(list, 12, SOFT, "CENTER")
    hint:SetWordWrap(true)
    hint:SetSpacing(3)
    hint:SetWidth(460)

    -- The strip at the bottom, to the right of the gold display.
    status = NewText(frame, 11, SOFT)
    status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", GOLD_RIGHT + PAD, GOLD_BOTTOM)
    status:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -PAD, PANEL_BOTTOM - 1)
    statusBar = NewBar(frame, STATUS_BAR_WIDTH, 10)
    statusBar:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -BAR_RIGHT, GOLD_BOTTOM + 12)
    statusBar:Hide()

    -- The parts by name, as the game's own windows have theirs.
    frame.ScanButton, frame.ScaleDropdown = scanButton, scaleDropdown
    frame.AffordCheck, frame.TopCheck = affordCheck, topCheck
    frame.List, frame.Progress = list, statusBar
    list.Intro, list.Hint, list.Progress = intro, hint, listBar

    CreateFrame("Frame", nil, frame):SetScript("OnUpdate", ClockOnUpdate)

    BuildViews(auction)
end

---------------------------------------------------------------------------
-- The tab itself
---------------------------------------------------------------------------
-- The game loads its auction window the first time an auction house is opened; the tab is
-- added to it right then.
EventUtil.ContinueOnAddOnLoaded("Blizzard_AuctionHouseUI", function()
    Build()
    local tabs = LibStub("LibAHTab-1-0")
    tabs:CreateTab(TAB_ID, frame, L.TAB, L.TITLE)
    tabs:CreateTab(TAB_SUPPLIES, holder, L.TAB_SUP, L.TITLE_SUP)
end)

ns.On("PLAYER_MONEY", QueueRefresh)

ns.Listen("SCAN_STATE", QueueRefresh)
ns.Listen("SCAN_PROGRESS", QueueRefresh)
ns.Listen("OFFERS_CHANGED", QueueRefresh)

---------------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------------
-- The question before a purchase, shaped like the game's own BUYOUT_AUCTION: its words, the
-- price as coins, and after "Accept" the box stays up until the auction house has answered.
-- On top of that it shows the item itself, with its tooltip.
local function PopupOnAccept(dialog)
    S.ConfirmPurchase(dialog.data.offer)
end

-- true closes the box.
local function PopupOnEvent(dialog, event, ...)
    if event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        local auctionID = ...
        return auctionID == dialog.data.offer.auctionID
    end
    return event == "AUCTION_HOUSE_SHOW_ERROR"
end

StaticPopupDialogs[POPUP] = {
    text = BUYOUT_AUCTION_CONFIRMATION,
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = GenerateClosure(StaticPopup_OnAcceptWithSpinner, PopupOnAccept, PopupOnEvent,
        { "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR" }, 2),
    OnShow = function(dialog, data)
        MoneyFrame_Update(dialog.MoneyFrame, data.offer.buyout)
    end,
    -- However the box goes away, the scanner may go back to work.
    OnHide = function() S.CancelPurchase() end,
    hasItemFrame = 1,
    hasMoneyFrame = 1,
    timeout = 0,
    hideOnEscape = 1,
}

ns.Listen("CONFIRM_BUY", function(offer)
    -- The lookup before the question takes a moment; the player may have left the tab since.
    if not frame:IsVisible() then
        S.CancelPurchase()
        return
    end
    -- link and useLinkForItemInfo are for the popup's item frame, which fills in the rest.
    StaticPopup_Show(POPUP, nil, nil, { offer = offer, link = offer.link, useLinkForItemInfo = true })
end)

---------------------------------------------------------------------------
-- Buying a consumable (the box is built in BuildBuyBox)
---------------------------------------------------------------------------
ns.Listen("CONFIRM_SUPPLY", function(supply, tiers)
    -- The lookup before the question takes a moment; the player may have left the view since.
    if not frame:IsVisible() or view ~= "supplies" then
        S.CancelSupply()
        return
    end
    buyBox.supply, buyBox.tiers = supply, tiers
    buyBox.auction = tiers[1].auctionID and tiers[1] or nil
    buyBox.step, buyBox.quoted = "choose", nil
    buyBox.Icon:SetTexture(supply.icon)
    buyBox.Rim:SetVertexColor(ns.QualityColor(supply.quality))
    buyBox.Name:SetText(ns.QualityText(supply.name, supply.quality))
    buyBox.Stock:SetText(L.QTY_OF:format(supply.quantity))
    buyBox:Show()

    -- To begin with: one stack, or as much of one as there is for sale and money for.
    local count = buyBox.auction and buyBox.auction.quantity or math.min(supply.stack, supply.quantity)
    if not buyBox.auction then
        local money = GetMoney()
        while count > 1 and S.SupplyCost(tiers, count) > money do count = count - 1 end
    end
    buyBox.Count:SetNumber(count)
    buyBox.Count:SetFocus()
    buyBox.Count:HighlightText()
    PaintBox()
end)

ns.Listen("SUPPLY_QUOTED", function(total)
    if not buyBox:IsShown() or (buyBox.step ~= "quote" and buyBox.step ~= "confirm") then return end
    buyBox.step, buyBox.quoted = "confirm", total
    PaintBox()
end)

-- Bought, or not: either way the box has done its work.
ns.Listen("SUPPLY_DONE", function()
    if buyBox then buyBox:Hide() end
end)

-- The buttons of the box wait for the auction house to be ready for the next request.
ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
    if buyBox and buyBox:IsShown() then PaintBox() end
end)

---------------------------------------------------------------------------
-- /upscout opens the tab when the auction house is open; /upscout stats tells how the last
-- scan went; /upscout forget Name takes a character that is gone (deleted, renamed) out of
-- the scale field's menu
---------------------------------------------------------------------------
local function Forget(name)
    local was = ns.Roster.Target()
    local card = ns.Roster.Forget(name)
    if not card then
        local names = {}
        local me, cards = ns.Roster.Me(), ns.Roster.List()
        for i = 1, #cards do
            if cards[i] ~= me then names[#names + 1] = cards[i].name end
        end
        ns.Print(L.MSG_FORGET_WHO:format(#names > 0 and table.concat(names, ", ") or NONE))
        return
    end
    ns.Print(L.MSG_FORGOT:format(card.name))
    -- The lists were for that character: they go back to being for the one being played.
    if was == card then S.Retarget() end
    UI.Refresh()
end

SLASH_UPGRADESCOUT1 = "/upscout"
SLASH_UPGRADESCOUT2 = "/upgradescout"
SlashCmdList["UPGRADESCOUT"] = function(message)
    if message:lower():match("^%s*stats") then
        ns.Print(S.StatsText())
        return
    end
    if message:lower():match("^%s*forget") then
        Forget(message:match("^%s*%a+%s*(.-)%s*$"))
        return
    end
    if not (frame and S.IsOpen()) then
        ns.Print(L.ERR_AH_CLOSED)
        return
    end
    LibStub("LibAHTab-1-0"):SetSelected(TAB_ID)
end
