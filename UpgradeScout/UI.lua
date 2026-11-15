local ADDON, ns = ...
local L = ns.L
local S = ns.Scanner

-- The "Upgrades" tab of the auction house window.
--
-- The tab has a look of its own, made of the parts in Widgets.lua: a dark plate in a fine gold
-- edge, headings in gold capitals, buttons in gold rims.
-- Some parts that do the work are still the game's own, in our colours:
--   the list        WowScrollBoxList, and MinimalScrollBar as a gold knob on a dark rail
--   prices          MoneyDisplayFrameTemplate
--   the profile     WowStyle1DropdownTemplate: its text, and its menu on our plate
-- A purchase is asked about in a box of ours (see BuildBuyBox), for gear as for consumables.
--
-- The "Consumables" tab is the same frame in another view (`view`): the same list with rows
-- of another kind, another second filter, a status line of its own, and a box that asks how
-- many pieces to buy. What differs between the views is gathered in ApplyView.
local UI = {}
ns.UI = UI

local TAB_ID = "UpgradeScout"
local TAB_SUPPLIES = "UpgradeScoutSupplies"

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
-- so do the titles above them. Each view has columns of its own:
--   gear           item, pick, gain, buyout
--   a consumable   item, effect, score, price of a piece, pieces for sale
-- `name` is the room for the item's name, `second` where the pick or the effect begins,
-- `upgrade` and `price` where the gain (or the score) and the price end. The price of gear
-- ends right before the Buy button; that of a consumable leaves room for the pieces.
local PAD = 8                               -- between neighbours
local ICON_LEFT, ICON_SIZE = 6, 22
local NAME_LEFT, NAME_MIN_WIDTH = 36, 110
local PICK_WIDTH, METER_WIDTH = 140, 72
local STOCK_RIGHT = 684                     -- where the count of a consumable's pieces ends
local COLUMNS = {
    gear = { name = 276, second = 324, upgrade = 564, price = 684 },
    supplies = { name = 228, second = 276, upgrade = 492, price = 596 },
}
local TITLE_LEFT, TITLE_TOP = 10, 16        -- the first title, and how far down the titles are
local SCAN_WIDTH, STATUS_BAR_WIDTH = 118, 140
local DROPDOWN_MIN, DROPDOWN_MAX = 110, 200
local CHECK_SIZE, CHECK_GAP = 16, 6         -- a tick box and the room before its label

-- What the tab is drawn with (see Widgets.lua): pictures, text, buttons, bars, and the
-- colours of the text.
local Widgets = ns.Widgets
local File, NewTexture, NewLine, NewRule = Widgets.File, Widgets.NewTexture, Widgets.NewLine, Widgets.NewRule
local NewSlices, NewText = Widgets.NewSlices, Widgets.NewText
local NewButton, NewBar, SetBar = Widgets.NewButton, Widgets.NewBar, Widgets.SetBar
local GOLD, GOLD_DIM, CREAM, SOFT, MUTED, GREEN =
    Widgets.GOLD, Widgets.GOLD_DIM, Widgets.CREAM, Widgets.SOFT, Widgets.MUTED, Widgets.GREEN

-- The plates the two picks are named on.
local PICKS = {
    UPGRADE = { text = L.PICK_UPGRADE, fill = { 1.00, 0.78, 0.26, 0.16 }, edge = { 1.00, 0.78, 0.26, 0.80 }, ink = { 1.00, 0.86, 0.42 } },
    VALUE = { text = L.PICK_VALUE, fill = { 0.42, 0.86, 0.36, 0.15 }, edge = { 0.42, 0.86, 0.36, 0.75 }, ink = { 0.56, 0.94, 0.48 } },
    -- Both at once: solid gold, dark letters.
    BOTH = { text = L.PICK_BOTH, fill = { 1.00, 0.80, 0.30, 1 }, edge = { 1.00, 0.92, 0.62, 1 }, ink = { 0.17, 0.10, 0.02 }, solid = true },
}

local frame, scrollBox, provider, hint, intro, status, statusBar, listBar, age
local scanButton, profileDropdown, affordCheck, topCheck
local view = "gear"         -- what the frame shows: "gear" (Upgrades) or "supplies" (Consumables)
local holder                -- the frame the Consumables tab is made with (see Build)
local bestCheck, buyBox     -- the Consumables view's own filter, and its box for buying
local planBar               -- the strip under the list for the best set for a budget (see BuildPlan)
local rows = {}
local summary               -- what the last refresh counted, for the status line
local elements = {}       -- row key -> the table the scroll box knows the row by (see SyncList)
local syncCount = 0
local toTop = false         -- scroll back to the top at the next refresh
local keepPlace = false     -- the next refresh must not move the list (see SyncList)
local profileShown            -- what the profile dropdown was last built from (see ProfileKey)

-- How far the scanner is with what it is doing, 0 to 1; nil when it cannot tell.
local function Progress()
    local info = S.info
    if S.state == "score" and info.toScore > 0 then
        return info.scored / info.toScore
    elseif S.state == "verify" and S.IsScan() and info.toVerify > 0 then
        return info.verified / info.toVerify
    end
    return nil
end

---------------------------------------------------------------------------
-- Whom the lists are for
---------------------------------------------------------------------------
-- The lists are for the character being played unless another one of the account is chosen
-- in the profile field (see "Controls"). That one's card (see Roster.lua) is `who` throughout
-- this file; nil is the character being played.
local function WhoName(who)
    return ns.Roster.Colored(who, who.name)
end

local function ProfileTitle()
    local profile = ns.Score.Current(ns.Roster.Target())
    return profile and profile.title or NONE
end

-- The game puts the tooltip of the worn item beside an item's by itself, but it knows only
-- what the character being played wears. For another character the item its card remembers
-- in the slot is put there, in the game's own second tooltip.
local wornShown = false

local function HideWorn()
    if wornShown then ShoppingTooltip1:Hide() end
    wornShown = false
end

local function ShowWorn(links)
    local tip = ShoppingTooltip1
    if not links or not links[1] then return end
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
-- Our lines under a row's tooltip (see Tooltip.lua for how they look).
local AddHeader, AddGain = ns.Tooltip.AddHeader, ns.Tooltip.AddGain

-- What the offer of a row gains on every profile of the class, as Pawn shows its scales:
-- { { title, gain }, ... } in the order of the profile menu. The profile the
-- list is made on reads as the row does. Each of the others weighs the item and the gear the
-- same way on its own weights, and measures it against what it would take off: the weaker
-- of two rings on that profile, say. The game redraws a tooltip that is up several times a
-- second; the answer is kept while the row is the same.
local gainsOf = {}

local function ProfileGains(entry)
    if gainsOf.entry == entry then return gainsOf.gains end
    local gains = {}
    local ctx = S.ctx
    if ctx then
        -- The gear the list measured against: with the best set for a budget, the items
        -- bought for it count as worn (see Plan.Wearing).
        if view == "gear" and ns.db.plan then ctx = ns.Plan.Wearing(ctx, S.acquired) end
        local offer = entry.offer
        local scored = ns.Score.Item(offer.link)
        for _, profile in ipairs(ns.Score.Profiles(ctx.who)) do
            local gain
            if profile.name == ctx.profile then
                gain = entry
            elseif scored then
                local item = {
                    link = offer.link, itemID = offer.itemID, invType = offer.invType, unique = offer.unique,
                    value = ns.Score.Value(scored, profile.name, ctx.level),
                }
                gain = ns.Compare.Gain(item, ns.Score.Rescore(ctx, profile.name), entry.group)
            end
            if gain then gains[#gains + 1] = { title = profile.title, gain = gain } end
        end
    end
    gainsOf = { entry = entry, gains = gains }
    return gains
end

-- A consumable's own tooltip, and under it how much of it is for sale.
local function ShowSupplyTooltip(row)
    local entry = row.entry
    local supply = entry.supply
    local who = ns.Roster.Target()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local hideVendorPrice = true
    GameTooltip:SetHyperlink(supply.link, nil, nil, hideVendorPrice)
    -- On the right, whose profile the score is on.
    AddHeader(GameTooltip, who and L.ST_WHO:format(WhoName(who), ProfileTitle()) or ProfileTitle())
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

    -- On the right, whose list it is when it is not the character's own.
    AddHeader(GameTooltip, who and WhoName(who) or nil)
    -- How much better the item is on each profile of the class, in the class's colour.
    for _, line in ipairs(ProfileGains(entry)) do
        AddGain(GameTooltip, line.title, line.gain, S.ctx.class)
    end
    if entry.note == "OFFHAND_EMPTY" then
        GameTooltip_AddNormalLine(GameTooltip, who and L.TT_OFFHAND_EMPTY_WHO or L.TT_OFFHAND_EMPTY)
    elseif entry.note == "BOTH_HANDS" then
        GameTooltip_AddNormalLine(GameTooltip, L.TT_BOTH_HANDS)
    end
    if offer.effects then
        GameTooltip_AddNormalLine(GameTooltip, L.TT_EFFECTS)
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
    pick:SetPoint("LEFT", row, "LEFT", COLUMNS.gear.second, 0)
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
    local width = math.min(text:GetUnboundedStringWidth(), PICK_WIDTH - 14)
    text:SetWidth(width)
    pick:SetWidth(width + 14)
    pick.Fill:SetVertexColor(look.fill[1], look.fill[2], look.fill[3], look.fill[4])
    pick.Edge:SetVertexColor(look.edge[1], look.edge[2], look.edge[3], look.edge[4])
end

-- Puts the parts that both kinds of row have (the gain or the score with its meter, and the
-- price) over the columns of one kind, "gear" or "supplies". The list hands a frame from one
-- view to the other, so a row may have to move them.
local function Arrange(row, kind)
    if row.columns == kind then return end
    row.columns = kind
    local at = COLUMNS[kind]
    row.Upgrade:ClearAllPoints()
    row.Upgrade:SetPoint("RIGHT", row, "LEFT", at.upgrade, 3)
    row.Trough:ClearAllPoints()
    row.Trough:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", at.upgrade, 5)
    row.Price:ClearAllPoints()
    row.Price:SetPoint("RIGHT", row, "LEFT", at.price, 0)
end

-- The scroll box hands out bare frames; each gets its parts here the first time it is used.
local function BuildItemRow(row)
    row.built = true
    -- Its tooltip has our lines from ShowItemTooltip, not from Tooltip.lua.
    row.upgradeScoutRow = true

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
    row.Hand:SetPoint("RIGHT", row, "LEFT", NAME_LEFT + COLUMNS.gear.name, 0)

    row.Pick = NewPick(row)

    -- "+80%" over a meter: how much better the item is than what it takes the place of, and
    -- how its gain compares with the best one in the slot. Where these and the price stand
    -- is for Arrange to say.
    row.Upgrade = NewText(row, 14, GREEN, "RIGHT", true)
    row.Trough = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.Trough:SetColorTexture(0, 0, 0, 0.6)
    row.Trough:SetSize(METER_WIDTH, 4)
    row.Meter = NewTexture(row, "Bar", "ARTWORK")
    row.Meter:SetHeight(3)
    row.Meter:SetPoint("LEFT", row.Trough, "LEFT", 0.5, 0)

    row.Price = CreateFrame("Frame", nil, row, "MoneyDisplayFrameTemplate")
    -- An auction house that deals in whole silver shows no copper in its prices.
    if not C_AuctionHouse.SupportsCopperValues() then
        row.Price.CopperDisplay:SetForcedHidden(true)
    end

    -- A consumable's row says what the item does where a gear row has its pick, and after
    -- the price how many pieces are for sale. Its score stands where a gear row has its
    -- gain, over the same meter; a row without a score gives that room to the words. The
    -- list hands a frame from one view to the other, so every row has both sets of parts and
    -- shows the one its entry calls for (see InitItemRow).
    row.Effect = NewText(row, 11.5, SOFT, "LEFT", true)
    row.Effect:SetPoint("LEFT", row, "LEFT", COLUMNS.supplies.second, 0)
    row.Stock = NewText(row, 12, SOFT, "RIGHT", true)
    row.Stock:SetPoint("RIGHT", row, "LEFT", STOCK_RIGHT, 0)

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

-- The gain in percent of what is worn. There is no percent of nothing: an empty slot says
-- "New", and a slot whose item scores nothing on the profile (white armor with no stat but
-- its armor, say) gets the gain in points. The rows of one slot all replace the same thing,
-- so they all read the same way and can be told apart by their numbers.
local function GainText(entry)
    if entry.percent then return "+" .. FormatPercentage(entry.percent, true) end
    if entry.replaced then return L.GAIN_POINTS:format(ns.Num(entry.delta)) end
    return L.NEW
end

-- A consumable: its name, what it does, what that is worth on the profile (when the game's
-- tables say), the price of one piece and how many are for sale.
local function InitSupplyRow(row, entry, share)
    local supply = entry.supply
    local at = COLUMNS.supplies
    row.Icon:SetTexture(supply.icon)
    -- What is of no use to the character is listed in grey (and only when everything is).
    row.Icon:SetDesaturated(entry.useless)
    row.Rim:SetVertexColor(ns.QualityColor(supply.quality))
    row.Name:SetText(ns.QualityText(supply.name, supply.quality))
    row.Name:SetWidth(at.name)
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
    -- The words end before the meter of the score, or where the score would.
    row.Effect:SetWidth(at.upgrade - at.second - (scored and METER_WIDTH + PAD or 0))
    if scored then
        -- Its score in points, where a gear row has its gain in percent: a consumable takes
        -- the place of nothing.
        row.Upgrade:SetText("+" .. ns.Num(entry.value))
        row.Meter:SetWidth(math.max((METER_WIDTH - 1) * share, 2))
        row.Meter:SetTexCoord(0, math.max(share, 0.03), 0, 1)
    end

    row.Price:SetFontObject(entry.affordable and PriceFontWhite or PriceFontRed)
    SetMoney(row.Price, supply.price)

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
    Arrange(row, gear and "gear" or "supplies")
    row.Effect:SetShown(not gear)
    row.Stock:SetShown(not gear)
    if not gear then
        InitSupplyRow(row, entry, data.share or 1)
        return
    end
    row.Upgrade:Show()
    row.Trough:Show()
    row.Meter:Show()

    row.Icon:SetTexture(offer.icon)
    row.Icon:SetDesaturated(false)
    row.Rim:SetVertexColor(ns.QualityColor(offer.quality))

    local name = ns.QualityText(offer.name, offer.quality)
    if offer.effects then name = name .. " " .. NORMAL_FONT_COLOR:WrapTextInColorCode("*") end
    row.Name:SetText(name)

    -- "Main Hand" lists one-hand and two-hand weapons together, so each row says which it is.
    -- The name gives up the room the label takes.
    local hand = ns.Compare.HandLabel(offer.invType)
    local nameWidth = COLUMNS.gear.name
    row.Hand:SetShown(hand ~= nil)
    if hand then
        row.Hand:SetText(hand)
        row.Name:SetWidth(math.max(nameWidth - row.Hand:GetStringWidth() - PAD, NAME_MIN_WIDTH))
    else
        row.Name:SetWidth(nameWidth)
    end

    SetPick(row.Pick, entry.pick)

    row.Upgrade:SetText(GainText(entry))
    row.Meter:SetWidth(math.max((METER_WIDTH - 1) * data.share, 2))
    row.Meter:SetTexCoord(0, math.max(data.share, 0.03), 0, 1)

    row.Price:SetFontObject(entry.affordable and PriceFontWhite or PriceFontRed)
    SetMoney(row.Price, offer.buyout)

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
    -- A heading of the best set for a budget has nothing to fold away.
    row.Arrow:SetShown(not data.plain)
    row.Toggle:SetShown(not data.plain)
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
        if S.IsScan() then
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
    if S.finishedAt and summary.cost then
        -- The best set for a budget: what it comes to stands in the strip under the list.
        if summary.upgrades == 0 then parts[#parts + 1] = L.PLAN_NONE end
        if (S.partial or S.halted) and not S.message then parts[#parts + 1] = L.ST_PARTIAL end
    elseif S.finishedAt then
        if summary.upgrades == 0 then
            parts[#parts + 1] = summary.hidden > 0 and L.ST_NONE_AFFORD:format(summary.hidden) or L.ST_NONE
        elseif summary.hidden > 0 then
            parts[#parts + 1] = L.ST_DONE_HIDDEN:format(summary.upgrades, summary.slots, summary.hidden)
        else
            parts[#parts + 1] = L.ST_DONE:format(summary.upgrades, summary.slots)
        end
        if (S.partial or S.halted) and not S.message then parts[#parts + 1] = L.ST_PARTIAL end
    end
    return ForWho(table.concat(parts, " "))
end

-- How long ago this view's last scan was, for the right end of the strip; "" while the scanner
-- works (its bar stands there then) and before the first scan.
local function AgeText()
    local at = FinishedAt()
    if S.state ~= "idle" or not at then return "" end
    return L.ST_AGE:format(ns.Ago(time() - at))
end

-- Whom the lists are for, the profiles to choose from and the one in use, as one string: the
-- dropdown is rebuilt when this changes (another character chosen, a character forgotten).
local function ProfileKey()
    local who = ns.Roster.Target()
    local current, profiles = ns.Score.Current(who)
    local names = {}
    for i = 1, #profiles do names[i] = profiles[i].name end
    return (who and who.key or "") .. "\n" .. #ns.Roster.List() .. "\n"
        .. (current and current.name or "") .. "=" .. table.concat(names, "\n")
end

-- What an empty list says before its first scan: what the scan will find, and for whom.
local function IntroText()
    local who = ns.Roster.Target()
    if view == "supplies" then
        return who and L.SUP_HINT_WHO:format(WhoName(who)) or L.SUP_HINT
    end
    if who then return L.HINT_WHO:format(WhoName(who), ProfileTitle()) end
    return L.HINT:format(ProfileTitle())
end

-- The status line, with a bar at its right end while the scanner works and the age of the last
-- scan there when it does not. An empty list has the middle of the plate to say more:
--   before the first scan   the addon's emblem and what to do
--   during a scan           the same words as the status line, over a wider bar
--   after one               why the list is empty
local function ShowStatus()
    local text = StatusText()
    local idle = S.state == "idle"
    local progress = not idle and Progress() or nil

    status:SetText(text)
    local ageText = AgeText()
    age:SetText(ageText)
    age:SetShown(ageText ~= "")
    -- The line gives way to what stands at its right end: the bar, or the age.
    local right = PAD
    if not idle then
        right = BAR_RIGHT + STATUS_BAR_WIDTH + PAD
    elseif ageText ~= "" then
        right = BAR_RIGHT + age:GetStringWidth() + PAD
    end
    status:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -right, PANEL_BOTTOM - 1)
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

-- The age of the scan grows with the clock, and no event comes when a second passes. This
-- runs on a frame inside the tab, so only while the tab is in view.
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

-- How the list of consumables is to score what one of them adds: on the profile in use, for
-- the character's level. Nothing for a character without a profile; the list then has no
-- scores and leaves nothing out.
local MANA = Enum.PowerType.Mana
local function SupplyValue(who)
    local profile = ns.Score.Current(who)
    if not profile then return nil end
    local name = profile.name
    local level = who and who.level or UnitLevel("player")
    return function(stats) return ns.Score.StatsValue(stats, name, level) end
end

---------------------------------------------------------------------------
-- The best set for a budget
---------------------------------------------------------------------------
-- A strip along the bottom of the list's plate, in the Upgrades view once there is a scan: a
-- tick box, the budget in gold and silver, and what the set comes to. With the box ticked
-- the list shows that set and nothing else (see Plan.lua), and the two filters above the
-- list have no say.
local PLAN_HEIGHT = 30
local planCache = {}

local function Planned()
    return view == "gear" and ns.db.plan and S.ctx ~= nil
end

-- The set for the budget, as rows for the list.
local function PlanRows()
    local money = GetMoney()
    -- The ladder of sets is made for all the gold there is, and made again only when what it
    -- is made of has changed; a budget picks a rung of it.
    if planCache.changes ~= S.changes or planCache.ctx ~= S.ctx or planCache.money ~= money
        or planCache.bought ~= #S.acquired then
        planCache = {
            changes = S.changes, ctx = S.ctx, money = money, bought = #S.acquired,
            ladder = ns.Plan.Ladder(S.offers, ns.Plan.Wearing(S.ctx, S.acquired), money),
        }
    end
    return ns.Plan.Rows(ns.Plan.Choose(planCache.ladder, S.PlanCap()))
end

-- The budget in its two fields: the sum that was typed, or, in a dimmer ink, all the gold
-- there is. A field that is being typed in is left alone.
local function PaintBudget()
    local gold, silver = planBar.Gold, planBar.Silver
    if gold:HasFocus() or silver:HasFocus() then return end
    local copper = S.budget or GetMoney()
    local ink = S.budget and CREAM or MUTED
    gold:SetText(tostring(math.floor(copper / 10000)))
    silver:SetText(("%02d"):format(math.floor(copper / 100) % 100))
    gold:SetTextColor(ink[1], ink[2], ink[3])
    silver:SetTextColor(ink[1], ink[2], ink[3])
end

local function PaintPlan()
    local shown = view == "gear" and S.ctx ~= nil
    if shown ~= planBar:IsShown() then
        planBar:SetShown(shown)
        -- The list gives up the height of the strip.
        scrollBox:SetPoint("BOTTOMRIGHT", frame.List, "BOTTOMRIGHT", -LIST_RIGHT, LIST_BOTTOM + (shown and PLAN_HEIGHT or 0))
    end
    local planned = Planned()
    -- What the set holds is not for the two filters to say.
    affordCheck:SetEnabled(not planned)
    affordCheck:SetAlpha(planned and 0.4 or 1)
    topCheck:SetEnabled(not planned)
    topCheck:SetAlpha(planned and 0.4 or 1)
    if not shown then return end

    SetCheck(planBar.Check, ns.db.plan)
    PaintBudget()
    local text = ""
    if planned and summary.upgrades > 0 then
        text = L.PLAN_SUM:format(summary.upgrades, ns.Num(summary.gain), ns.Money(summary.cost))
    elseif planned then
        text = L.PLAN_NONE
    end
    planBar.Summary:SetText(text)
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
    elseif Planned() then
        all, summary = PlanRows()
    else
        all, summary = ns.Results.Build(S.offers, S.ctx, {
            money = GetMoney(),
            affordableOnly = ns.db.affordableOnly,
            limit = ns.db.topOnly and ns.Results.TOP_COUNT or nil,
            unchecked = S.Unchecked(),
        })
    end
    -- Nothing of a set is folded away: it is all meant to be bought.
    rows = summary.cost and all or Fold(all)
    SyncList()
    PaintPlan()

    local idle = S.state == "idle"
    ShowStatus()
    -- Red while it starts a scan, dark while it stops one.
    scanButton.Label:SetText(ns.Upper(idle and L.SCAN or L.STOP))
    scanButton.Face:SetFile(idle and "ButtonRed" or "ButtonDark")
    -- (A lookup around a purchase is over in a moment, and is not for the button to stop.)
    scanButton:SetEnabled(idle or S.IsScan() or S.mode == "supplies")
    SetCheck(affordCheck, ns.db.affordableOnly)
    SetCheck(topCheck, ns.db.topOnly)
    SetCheck(bestCheck, ns.db.bestOnly)

    local profileKey = ProfileKey()
    if profileKey ~= profileShown then
        profileShown = profileKey
        profileDropdown:GenerateMenu()
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
-- The profile field answers two questions at once: whom the lists are for, and on which of
-- that character's profiles. Its menu has the profiles of the character being played, and
-- under them those of every other character of the account the addon has seen (Roster.List),
-- each line beginning with the character's name. A line of the menu is a "choice":
--   { who = the character's key, false for the one being played; profile = the profile's name }
local function IsChoice(choice)
    local who = ns.Roster.Target()
    if (who and who.key or false) ~= choice.who then return false end
    local profile = ns.Score.Current(who)
    return profile ~= nil and profile.name == choice.profile
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
    -- A character's profile is remembered with the character, whoever chose it.
    owner.profile = choice.profile
    ns.Fire("PROFILE_CHANGED", owner)

    if sameWho then
        -- Scores of gear from another profile mean nothing now, and the Upgrades view scans
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
        buyBox:Hide()
        ns.Roster.SetTarget(card)
        S.Retarget()
        if rescan and S.IsOpen() then
            if view == "supplies" then S.StartSupplies() else S.Start() end
        elseif card then
            -- Nothing to scan yet: the character's gear is asked of the server now, so that
            -- it is at hand when the scan comes (see Score.Context).
            ns.Score.Context(choice.profile, card)
        end
    end
    -- The dropdown shows the choice by itself; it must not be rebuilt while its menu is open.
    profileShown = ProfileKey()
    toTop = true
    UI.Refresh()
end

local MENU_ROWS = 20        -- a menu with more lines than this scrolls

-- The lines and the rules of the menu in our colours (see Widgets.SkinMenuLine).
local function AddLine(root, text, choice)
    root:CreateRadio(text, IsChoice, Choose, choice):AddInitializer(Widgets.SkinMenuLine)
end

local function ProfileMenu(_, root)
    local lines = 0
    local _, profiles = ns.Score.Current()
    for i = 1, #profiles do
        AddLine(root, profiles[i].title, { who = false, profile = profiles[i].name })
        lines = lines + 1
    end

    local me = ns.Roster.Me()
    local cards = ns.Roster.List()
    for c = 1, #cards do
        local card = cards[c]
        local _, theirs = ns.Score.Current(card)
        if card ~= me and #theirs > 0 then
            if lines > 0 then root:CreateDivider():AddInitializer(Widgets.SkinMenuDivider) end
            -- The name in the colour of the class, then the profile: "Diluna: Balance".
            -- The field shows the line that is chosen, so
            -- it says whose list this is as long as it is not one's own.
            local name = WhoName(card)
            -- What is bought here cannot be sent to another realm: a character of one is
            -- listed with its realm, so that it is not chosen by mistake.
            if me and card.realm and me.realm and card.realm ~= me.realm then
                name = name .. " (" .. card.realm .. ")"
            end
            for i = 1, #theirs do
                AddLine(root, name .. ": " .. theirs[i].title, { who = card.key, profile = theirs[i].name })
                lines = lines + 1
            end
        end
    end
    if lines > MENU_ROWS then root:SetScrollMode(MENU_ROWS * 20) end
end

-- The game's dropdown under a face of ours: a recess with a gold arrow. Its own plate and
-- arrow are made see-through, not removed, because the dropdown goes on setting them as its
-- state changes; its text is left as it is. Its menu opens on our plate (Widgets.MenuStyle).
local function SkinDropdown(dropdown)
    dropdown.menuMixin = Widgets.MenuStyle
    dropdown.Background:SetAlpha(0)
    dropdown.Arrow:SetAlpha(0)
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
local function NewFilterCheck(text, setting, tip, parent)
    local check = CreateFrame("CheckButton", nil, parent or frame)
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

-- A caption beside a field: the words of a label in capitals, without the colon they end in
-- (the plain one, or the wide one of Chinese).
local function Caption(text)
    return ns.Upper((text:gsub("%s*:%s*$", ""):gsub("：$", "")))
end

---------------------------------------------------------------------------
-- The box that asks before a purchase
---------------------------------------------------------------------------
-- One box for both views: the item at its top, two lines about the purchase, "Buy" and
-- "Cancel". It follows the purchase in `step`.
-- Gear (`offer`): the gain the list shows for the item, and its buyout.
--   confirm  the item was looked up again and is still there at its price
--   wait     "Buy" was pressed: the bid is out, and the box stays until the auction house
--            answers, as the game's own question before a buyout does
-- A consumable (`supply`, `tiers`) is bought by the piece, in steps (see "Consumables: the scan
-- and the purchase" in Scanner.lua): how many, and what that many cost.
--   choose   the player types how many; the box shows what that many cost by the price list
--   quote    "Buy" was pressed: the server is being asked what exactly they cost
--   confirm  the server's price is shown and the button reads "Confirm"
--   wait     pressed again: the purchase is on its way
-- A consumable sold as separate auctions is bought a piece at a time, each with a press of its
-- own: the box offers one piece from the cheapest auction (`auction`), and there is nothing to
-- choose.
local BOX_WIDTH, BOX_HEIGHT, BOX_EDGE = 330, 162, 18

local function PaintGearBox()
    local offer, step = buyBox.offer, buyBox.step
    local affordable = offer.buyout <= GetMoney()
    buyBox.TotalLabel:SetText(Caption(L.COL_PRICE))
    buyBox.Total:Show()
    buyBox.Total:SetFontObject(affordable and PriceFontWhite or PriceFontRed)
    SetMoney(buyBox.Total, offer.buyout)
    buyBox.Buy.Label:SetText(ns.Upper(L.BUY))
    buyBox.Buy:SetEnabled(step == "confirm" and affordable)
end

local function PaintBox()
    if buyBox.offer then
        PaintGearBox()
        return
    end
    if not buyBox.tiers then return end
    local step = buyBox.step
    local settled = step == "confirm" or step == "wait"
    local cost
    if settled then
        cost = buyBox.quoted
    elseif buyBox.auction then
        cost = buyBox.auction.price
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
        SetMoney(buyBox.Total, cost)
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
    if buyBox.offer then
        if step ~= "confirm" then return end
        buyBox.step = "wait"
        S.ConfirmPurchase(buyBox.offer)
    elseif step == "confirm" then
        buyBox.step = "wait"
        S.ConfirmSupply()
    elseif step ~= "choose" then
        return
    elseif buyBox.auction then
        buyBox.step, buyBox.quoted = "wait", buyBox.auction.price
        S.BuySupplyAuction(buyBox.supply, buyBox.tiers)
    else
        buyBox.step = "quote"
        S.QuoteSupply(buyBox.supply, buyBox.tiers, buyBox.Count:GetNumber())
    end
    PaintBox()
end

-- The item at the top of the box has its tooltip, and a modified click links it or tries it
-- on, as on a row.
local function BoxItemOnEnter(item)
    GameTooltip:SetOwner(item, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(buyBox.link, nil, nil, true)
    GameTooltip:Show()
end

local function BoxItemOnClick()
    HandleModifiedItemClick(buyBox.link)
end

local function BuildBuyBox()
    -- By name: Escape closes it, as it does the game's own windows (UISpecialFrames).
    buyBox = CreateFrame("Frame", "UpgradeScoutBuyBox", frame)
    table.insert(UISpecialFrames, buyBox:GetName())
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
    local item = CreateFrame("Button", nil, buyBox)
    item:SetPoint("TOPLEFT", buyBox.Rim, "TOPLEFT", 0, 0)
    item:SetPoint("BOTTOMRIGHT", buyBox.Name, "BOTTOMRIGHT", 0, 0)
    item:SetScript("OnEnter", BoxItemOnEnter)
    item:SetScript("OnLeave", GameTooltip_Hide)
    item:SetScript("OnClick", BoxItemOnClick)
    buyBox.Item = item

    local rule = NewRule(buyBox)
    rule:SetPoint("TOPLEFT", buyBox, "TOPLEFT", BOX_EDGE - 4, -48)
    rule:SetPoint("TOPRIGHT", buyBox, "TOPRIGHT", -(BOX_EDGE - 4), -48)

    -- The first line: how many pieces of a consumable, or what the gear gains.
    buyBox.FirstLabel = NewText(buyBox, 9.5, GOLD_DIM)
    buyBox.FirstLabel:SetPoint("LEFT", buyBox, "TOPLEFT", BOX_EDGE, -70)
    buyBox.Gain = NewText(buyBox, 14, GREEN, "RIGHT", true)
    buyBox.Gain:SetPoint("RIGHT", buyBox, "TOPRIGHT", -BOX_EDGE, -70)

    -- The field for the number: an edit box of the game's in a recess of ours.
    local count = CreateFrame("EditBox", nil, buyBox)
    count:SetSize(56, 22)
    count:SetPoint("LEFT", buyBox.FirstLabel, "RIGHT", PAD, 0)
    NewSlices(count, "Inset", 0.25, 6, "BACKGROUND")
    count:SetFont(Widgets.NumberFont(), 13, "")
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
    buyBox:SetScript("OnHide", function()
        if buyBox.offer then S.CancelPurchase() else S.CancelSupply() end
    end)
end

-- What the box shows at its top, and which of its parts the kind of purchase has.
local function SetBoxItem(icon, quality, name, link)
    buyBox.Icon:SetTexture(icon)
    buyBox.Rim:SetVertexColor(ns.QualityColor(quality))
    buyBox.Name:SetText(ns.QualityText(name, quality))
    buyBox.link = link
end

local function SetBoxKind(gear)
    buyBox.Gain:SetShown(gear)
    buyBox.Count:SetShown(not gear)
    buyBox.Stock:SetShown(not gear)
end

-- The row of the list an offer is on, for the gain the box repeats. (An offer is not listed
-- when it was bought from somewhere else than its row.)
local function ListedEntry(offer)
    for i = 1, #rows do
        local entry = rows[i].entry
        if entry and entry.offer and entry.offer.id == offer.id then return entry end
    end
end

---------------------------------------------------------------------------
-- The strip for the best set for a budget
---------------------------------------------------------------------------
-- What is typed into a field of the budget. Both fields empty is no budget of one's own: all
-- the gold there is.
local function BudgetTyped(box, userInput)
    if not userInput then return end
    local gold, silver = planBar.Gold, planBar.Silver
    -- The first thing typed into the gold field of a budget that was not one's own starts a
    -- sum in whole gold: the silver the purse happens to hold is not meant.
    if not S.budget and box == gold then silver:SetText("00") end
    if gold:GetText() == "" and silver:GetText() == "" then
        S.budget = nil
    else
        S.budget = gold:GetNumber() * 10000 + silver:GetNumber() * 100
    end
    toTop = true
    -- The player changed what the list shows: price checks that were stopped may go on.
    S.Resume()
    QueueRefresh()
end

local function BudgetDone(box)
    box:ClearFocus()
end

-- A field for a number: an edit box of the game's in a recess of ours, a coin after it.
local function NewCoinField(width, letters, coin, tip)
    local field = CreateFrame("EditBox", nil, planBar)
    field:SetSize(width, 20)
    NewSlices(field, "Inset", 0.25, 6, "BACKGROUND")
    field:SetFont(Widgets.NumberFont(), 12, "")
    field:SetJustifyH("CENTER")
    field:SetAutoFocus(false)
    field:SetNumeric(true)
    field:SetMaxLetters(letters)
    field:SetScript("OnTextChanged", BudgetTyped)
    field:SetScript("OnEnterPressed", BudgetDone)
    field:SetScript("OnEscapePressed", BudgetDone)
    field:SetScript("OnEditFocusLost", PaintBudget)
    field:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, L.PLAN)
        GameTooltip_AddNormalLine(GameTooltip, tip)
        GameTooltip:Show()
    end)
    field:SetScript("OnLeave", GameTooltip_Hide)
    field.Coin = field:CreateTexture(nil, "ARTWORK")
    field.Coin:SetTexture("Interface\\MoneyFrame\\UI-" .. coin .. "Icon")
    field.Coin:SetSize(13, 13)
    field.Coin:SetPoint("LEFT", field, "RIGHT", 3, 0)
    return field
end

local function BuildPlan()
    local list = frame.List
    planBar = CreateFrame("Frame", nil, list)
    planBar:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", LIST_LEFT, LIST_BOTTOM)
    planBar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -LIST_LEFT, LIST_BOTTOM)
    planBar:SetHeight(PLAN_HEIGHT)
    planBar:Hide()
    local rule = NewRule(planBar)
    rule:SetPoint("TOPLEFT", planBar, "TOPLEFT", 0, 0)
    rule:SetPoint("TOPRIGHT", planBar, "TOPRIGHT", 0, 0)

    local check = NewFilterCheck(L.PLAN, "plan", L.PLAN_TIP, planBar)
    check:SetPoint("LEFT", planBar, "LEFT", 6, -1)
    planBar.Check = check

    planBar.Gold = NewCoinField(54, 6, "Gold", L.PLAN_TIP)
    planBar.Gold:SetPoint("LEFT", check, "RIGHT", CHECK_GAP + check.Text:GetStringWidth() + PAD, 0)
    planBar.Silver = NewCoinField(30, 2, "Silver", L.PLAN_TIP)
    planBar.Silver:SetPoint("LEFT", planBar.Gold.Coin, "RIGHT", 6, 0)
    planBar.Gold:SetScript("OnTabPressed", function() planBar.Silver:SetFocus() end)
    planBar.Silver:SetScript("OnTabPressed", function() planBar.Gold:SetFocus() end)

    -- What the set comes to: how many items, how many points, for how much.
    planBar.Summary = NewText(planBar, 11, CREAM, "RIGHT")
    planBar.Summary:SetPoint("RIGHT", planBar, "RIGHT", -8, -1)
    frame.PlanBar = planBar
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

    -- Item, pick, gain, buyout; or item, effect, score, price of a piece, pieces for sale.
    -- Each title over its column, where this view has it (see COLUMNS).
    local at, titles = COLUMNS[view], list.Titles
    local function Title(title, text, point, x)
        title:SetText(ns.Upper(text))
        title:ClearAllPoints()
        title:SetPoint(point, list, "TOPLEFT", LIST_LEFT + x, -TITLE_TOP)
    end
    Title(titles[2], gear and L.COL_PICK or L.COL_EFFECT, "LEFT", at.second)
    Title(titles[3], gear and L.COL_UPGRADE or L.COL_SCORE, "RIGHT", at.upgrade)
    Title(titles[4], gear and L.COL_PRICE or L.COL_UNIT, "RIGHT", at.price)
    titles[5]:SetShown(not gear)
    intro.Heading:SetText(ns.Upper(gear and L.TITLE or L.TITLE_SUP))

    -- Both views score on the profile; their second filter is another one.
    local second = gear and topCheck or bestCheck
    topCheck:SetShown(gear)
    bestCheck:SetShown(not gear)
    affordCheck:ClearAllPoints()
    affordCheck:SetPoint("LEFT", second, "LEFT", -(2 * PAD + CheckWidth(affordCheck)), 0)

    -- The profile field takes the room this view's labels leave, within reason. Where a
    -- language's labels leave too little, the field stands without its own label; its tooltip
    -- says what it is.
    local label = frame.ProfileLabel
    local labelWidth = label:GetStringWidth() + PAD
    local room = AuctionHouseFrame:GetWidth() - (BAR_LEFT + SCAN_WIDTH + 2 * PAD
        + 2 * PAD + CheckWidth(affordCheck) + 2 * PAD + CheckWidth(second) + BAR_RIGHT)
    local labelled = room - labelWidth >= DROPDOWN_MIN
    label:SetShown(labelled)
    if not labelled then labelWidth = 0 end
    profileDropdown:SetWidth(Clamp(room - labelWidth, DROPDOWN_MIN, DROPDOWN_MAX))
    profileDropdown:ClearAllPoints()
    profileDropdown:SetPoint("LEFT", scanButton, "RIGHT", 2 * PAD + labelWidth, 0)

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
    BuildPlan()
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
    frame:SetScript("OnHide", function() buyBox:Hide() end)
    ApplyView()
end

local function Build()
    local auction = AuctionHouseFrame

    frame = CreateFrame("Frame", "UpgradeScoutFrame", auction)
    frame:SetAllPoints()
    frame:Hide()

    -- The strip above the list, where the Buy tab has its search box.
    scanButton = NewButton(frame, SCAN_WIDTH, 26, "ButtonRed", 12)
    scanButton:SetPoint("LEFT", frame, "TOPLEFT", BAR_LEFT, -BAR_MIDDLE)
    scanButton.Label:SetText(ns.Upper(L.SCAN))
    scanButton:SetScript("OnClick", ScanOnClick)

    -- The filters stand against the right edge. (Where the price filter and the profile field
    -- go, and how wide the field is, depends on the view: see ApplyView.)
    topCheck = NewFilterCheck(L.TOP:format(ns.Results.TOP_COUNT), "topOnly", L.TOP_TIP:format(ns.Results.TOP_COUNT))
    topCheck:SetPoint("LEFT", frame, "TOPRIGHT", -(BAR_RIGHT + CheckWidth(topCheck)), -BAR_MIDDLE)
    affordCheck = NewFilterCheck(L.AFFORD, "affordableOnly")

    local profileLabel = NewText(frame, 9.5, GOLD_DIM)
    frame.ProfileLabel = profileLabel
    profileLabel:SetPoint("LEFT", scanButton, "RIGHT", 2 * PAD, 0)
    profileLabel:SetText(Caption(L.PROFILE))

    profileDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    profileDropdown:SetHeight(24)
    SkinDropdown(profileDropdown)
    profileDropdown:SetDefaultText(NONE)
    profileDropdown:SetupMenu(ProfileMenu)
    profileDropdown:SetTooltip(function(tooltip)
        local who = ns.Roster.Target()
        GameTooltip_SetTitle(tooltip, who and L.ST_WHO:format(WhoName(who), ProfileTitle()) or ProfileTitle())
        -- Only what helps to choose. Where the weights come from is in the README.
        GameTooltip_AddNormalLine(tooltip, L.PROFILE_TIP)
        local _, profiles = ns.Score.Current(who)
        for i = 1, #profiles do
            if ns.Score.IsApprox(profiles[i].name) then
                GameTooltip_AddNormalLine(tooltip, L.PROFILE_APPROX:format(ns.Weights.APPROX_MARK))
                break
            end
        end
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

    -- The titles of the columns. The list has one order, best upgrade first in every slot: a
    -- title is not a button. The first is "Item" in both views, and the fifth, how many pieces
    -- are for sale, is there for consumables only. What the three between them say, and
    -- where they stand, is the view's (see ApplyView).
    list.Titles = {}
    for i = 1, 5 do
        list.Titles[i] = NewText(list, 9.5, GOLD_DIM, i > 2 and "RIGHT" or "LEFT")
    end
    list.Titles[1]:SetPoint("LEFT", list, "TOPLEFT", LIST_LEFT + TITLE_LEFT, -TITLE_TOP)
    list.Titles[1]:SetText(ns.Upper(L.COL_ITEM))
    list.Titles[5]:SetPoint("RIGHT", list, "TOPLEFT", LIST_LEFT + STOCK_RIGHT, -TITLE_TOP)
    list.Titles[5]:SetText(ns.Upper(L.COL_STOCK))
    local rule = NewRule(list)
    rule:SetPoint("TOPLEFT", list, "TOPLEFT", LIST_LEFT, -(LIST_TOP - 3))
    rule:SetPoint("TOPRIGHT", list, "TOPRIGHT", -LIST_LEFT, -(LIST_TOP - 3))

    -- The game's scroll box and scroll bar, set up the way Blizzard_AuctionHouseItemList sets
    -- up the Buy tab's list. Scrolling, the mouse wheel and the bar are all the scroll box's own;
    -- the bar only looks ours.
    scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", list, "TOPLEFT", LIST_LEFT, -LIST_TOP)
    scrollBox:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -LIST_RIGHT, LIST_BOTTOM)
    local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 8, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 8, 2)
    Widgets.SkinScrollBar(scrollBar)

    local listView = CreateScrollBoxListLinearView()
    listView:SetElementFactory(RowFactory)
    -- Frames made from a frame type, not a template, have no height of their own.
    listView:SetElementExtent(ROW_HEIGHT)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, listView)

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
    -- How long ago the last scan was, against the right end of the strip, where the bar is
    -- while a scan runs.
    age = NewText(frame, 11, SOFT, "RIGHT")
    age:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -BAR_RIGHT, GOLD_BOTTOM + 12)
    age:Hide()

    -- The parts by name, as the game's own windows have theirs.
    frame.ScanButton, frame.ProfileDropdown = scanButton, profileDropdown
    frame.AffordCheck, frame.TopCheck = affordCheck, topCheck
    frame.List, frame.Progress, frame.Status, frame.Age = list, statusBar, status, age
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
-- Buying gear (the box is built in BuildBuyBox)
---------------------------------------------------------------------------
ns.Listen("CONFIRM_BUY", function(offer)
    -- The lookup before the question takes a moment; the player may have left the view since.
    if not frame:IsVisible() or view ~= "gear" then
        S.CancelPurchase()
        return
    end
    buyBox.offer, buyBox.supply, buyBox.tiers, buyBox.auction = offer, nil, nil, nil
    buyBox.step = "confirm"
    SetBoxItem(offer.icon, offer.quality, offer.name, offer.link)
    SetBoxKind(true)
    local entry = ListedEntry(offer)
    buyBox.FirstLabel:SetText(Caption(L.COL_UPGRADE))
    buyBox.FirstLabel:SetShown(entry ~= nil)
    buyBox.Gain:SetText(entry and GainText(entry) or "")
    buyBox:Show()
    PaintBox()
end)

-- The auction house's answer to the bid: bought, or turned down (someone else was faster).
-- Either way the box has done its work. A purchase is told in the chat by the scanner; what
-- went wrong, the game shows itself.
ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
    if buyBox and buyBox:IsShown() and buyBox.offer and buyBox.step == "wait"
        and buyBox.offer.auctionID == auctionID then
        buyBox:Hide()
    end
end)

ns.On("AUCTION_HOUSE_SHOW_ERROR", function()
    if buyBox and buyBox:IsShown() and buyBox.offer and buyBox.step == "wait" then buyBox:Hide() end
end)

---------------------------------------------------------------------------
-- Buying a consumable
---------------------------------------------------------------------------
ns.Listen("CONFIRM_SUPPLY", function(supply, tiers)
    -- The lookup before the question takes a moment; the player may have left the view since.
    if not frame:IsVisible() or view ~= "supplies" then
        S.CancelSupply()
        return
    end
    buyBox.offer, buyBox.supply, buyBox.tiers = nil, supply, tiers
    buyBox.auction = tiers[1].auctionID and tiers[1] or nil
    buyBox.step, buyBox.quoted = "choose", nil
    SetBoxItem(supply.icon, supply.quality, supply.name, supply.link)
    SetBoxKind(false)
    buyBox.FirstLabel:SetText(Caption(L.QTY))
    buyBox.FirstLabel:Show()
    buyBox.Stock:SetText(L.QTY_OF:format(supply.quantity))
    buyBox:Show()

    -- To begin with: one stack, or as much of one as there is for sale and money for. Of what
    -- is sold as separate auctions, the one piece a press buys.
    local count = 1
    if not buyBox.auction then
        local money = GetMoney()
        count = math.min(supply.stack, supply.quantity)
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
-- the profile field's menu
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
        -- With an item after it, what the game counts for the item; alone, the last scan.
        local item = message:match("^%s*%a+%s+(.-)%s*$")
        if item and item ~= "" then ns.Stats.Report(item) else ns.Print(S.StatsText()) end
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
