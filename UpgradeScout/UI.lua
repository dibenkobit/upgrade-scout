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
--   the filters     the same, with tick boxes in its menu (Filters.lua)
-- A purchase is asked about in a box of ours (see BuildBuyBox), for gear as for consumables.
--
-- The "Consumables" tab is the same frame in another view (`view`): the same list with rows
-- of another kind, other filters, a status line of its own, and a box that asks how many
-- pieces to buy. What differs between the views is gathered in ApplyView.
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
--   gear           item, pick, gain, buyout, net cost
--   a consumable   item, effect, score, price of a piece, pieces for sale
-- `name` is the room for the item's name, `second` where the pick or the effect begins,
-- `upgrade` and `price` where the gain (or the score) and the price end, `last` where the
-- last column does, right before the Buy button: the net cost of gear, the pieces of a
-- consumable.
-- A price has PRICE_ROOM to stand in, and never takes more (see SetMoney): with the coins
-- as close as they stand, that is 999 gold to the copper in the game's own font. The two
-- prices of gear are each that wide, and a step (PRICE_STEP) apart.
local PAD = 8                               -- between neighbours
local ICON_LEFT, ICON_SIZE = 6, 22
local NAME_LEFT, NAME_MIN_WIDTH = 36, 110
local PICK_WIDTH, METER_WIDTH = 140, 72
local PRICE_ROOM, PRICE_STEP = 94, 106
local LAST_RIGHT = 684                      -- where the last column ends
local COLUMNS = {
    gear = { name = 204, second = 252, upgrade = LAST_RIGHT - 2 * PRICE_STEP, price = LAST_RIGHT - PRICE_STEP, last = LAST_RIGHT },
    supplies = { name = 228, second = 276, upgrade = 492, price = 596, last = LAST_RIGHT },
}
local TITLE_LEFT, TITLE_TOP = 10, 16        -- the first title, and how far down the titles are
local SCAN_WIDTH, STATUS_BAR_WIDTH = 118, 140
local DROPDOWN_MIN, DROPDOWN_MAX = 110, 200
local FILTERS_ROOM = 270                    -- kept for the names of the filters that are on: three of them
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
local scanButton, profileDropdown
local view = "gear"         -- what the frame shows: "gear" (Upgrades) or "supplies" (Consumables)
local holder                -- the frame the Consumables tab is made with (see Build)
local buyBox                -- the box that asks before a purchase
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

-- What that character wants of its gear: the filters of the list that are the character's
-- own (see Wants.lua). nil when it leaves nothing out.
local function Wanted()
    return ns.Wants.Of(ns.Roster.Target() or ns.Roster.Me())
end

-- The game puts the tooltip of the worn item beside an item's by itself, but it knows only
-- what the character being played wears. For another character the item its card remembers
-- in the slot is put there, in the game's own second tooltip. Pawn, Forever Companion and
-- Forever Leveling BiS, where the player has them, are kept from writing there what the item
-- would be to the character being played (Score.Hushed).
-- The game may have put its own comparison up by then, as the item's tooltip was filled
-- in: it does with Shift held, and always for a player who has set it so. That is what the
-- character being played wears, in that second tooltip, and at times in a third beside it
-- (with a two-hander worn and an item for one hand looked at, the game adds what could go
-- into the other hand). Both are taken down first: they are about the wrong character, and
-- the third would lie under the item put up here.
local wornShown = false

local function HideWorn()
    if wornShown then ShoppingTooltip1:Hide() end
    wornShown = false
end

local function ShowWorn(links)
    local tip = ShoppingTooltip1
    tip:Hide()
    if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
    wornShown = false
    if not links or not links[1] then return end
    tip:SetOwner(GameTooltip, "ANCHOR_NONE")
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", 0, -10)
    ns.Score.Hushed(tip.SetHyperlink, tip, links[1])
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
local AddHeader, AddGain, AddOwn = ns.Tooltip.AddHeader, ns.Tooltip.AddGain, ns.Tooltip.AddOwn

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
                    offValue = ns.Score.OffValue(scored, profile.name, ctx.level),
                }
                gain = ns.Compare.Gain(item, ns.Score.Rescore(ctx, profile.name), entry.group)
            end
            if gain then gains[#gains + 1] = { title = profile.title, gain = gain } end
        end
    end
    gainsOf = { entry = entry, gains = gains }
    return gains
end

-- A consumable's own tooltip, and under it what the row is there for: its score, and how
-- much of it is for sale. These are notes on a row, as the ones under gear (AddNotes), and
-- go by the same box of the welcome window (ns.Shows "rowNotes"): with it unticked the
-- tooltip is the item's own and no more; what the lines say is in the row's columns.
local function ShowSupplyTooltip(row)
    local entry = row.entry
    local supply = entry.supply
    local who = ns.Roster.Target()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local hideVendorPrice = true
    GameTooltip:SetHyperlink(supply.link, nil, nil, hideVendorPrice)
    if ns.Shows("rowNotes") then
        -- On the right, whose profile the score is on.
        AddHeader(GameTooltip, who and L.ST_WHO:format(WhoName(who), ProfileTitle()) or ProfileTitle(), true)
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
    end
    GameTooltip:Show()
end

-- What a row's tooltip says about buying the item, after how much better it is: how it
-- would be worn, what the score leaves out, what the player is short of. Nothing of the
-- prices: the row has both, the buyout and the net cost.
local function AddNotes(tooltip, entry, who)
    local offer = entry.offer
    if entry.note == "OFFHAND_EMPTY" then
        GameTooltip_AddNormalLine(tooltip, who and L.TT_OFFHAND_EMPTY_WHO or L.TT_OFFHAND_EMPTY)
    elseif entry.note == "BOTH_HANDS" then
        GameTooltip_AddNormalLine(tooltip, L.TT_BOTH_HANDS)
    end
    if offer.effects then
        GameTooltip_AddNormalLine(tooltip, L.TT_EFFECTS)
    end
    -- A price that came with the item out of the auction list, and has not been looked up
    -- yet (see ListCandidates in Scanner.lua). The row writes it like any other price: a
    -- dimmer ink made the row look like one that cannot be bought, and most such prices
    -- are right. This line says so, and the status line while the prices are looked up.
    if offer.unsure then
        GameTooltip_AddNormalLine(tooltip, L.TT_UNSURE)
    end
    if not entry.affordable then
        GameTooltip_AddErrorLine(tooltip, L.TT_CANT_AFFORD:format(ns.Money(offer.buyout - GetMoney())))
    end
end

-- Has AddNotes anything to say of this row?
local function HasNotes(entry)
    local note = entry.note
    return note == "OFFHAND_EMPTY" or note == "BOTH_HANDS" or entry.offer.effects or entry.offer.unsure or not entry.affordable
end

-- Our lines under the tooltip of a row of gear. They are of two kinds, and each has a box
-- of its own in the welcome window:
--   the score (ns.Shows "rowTooltip"): how much better the item is, as an item's tooltip
--     says it anywhere in the game (Tooltip.lua);
--   the notes (ns.Shows "rowNotes"): what the row cannot say for want of room (the hands,
--     the effects) and what is missing to pay.
-- With Pawn scoring (Score.Engine) the score in a tooltip is not the box's to switch.
-- Under a row of the player's own list stand Pawn's lines: how much of an upgrade the item
-- is on each of the player's scales. Ours would say it twice and are left out. Under a row
-- of a list for another character ours always stand, on that character's Pawn scales: Pawn
-- can tell an upgrade only for the character being played (PawnIsItemAnUpgrade goes by
-- that one's scales, class, level and what it wears, and its lines are kept out of such a
-- row: ShowItemTooltip), so ours are all there is to say it, and a player who has Pawn
-- score counts on finding the score there.
-- The same with Forever Companion or Forever Leveling BiS scoring, while it writes its own
-- lines into tooltips (Score.Writes): they are about the character being played. With them
-- switched off in its options the score is ours to write again, by the box, on its scales.
-- Notes without the score stand under the addon's name. With nothing to note, nothing is
-- written at all.
local function AddOfferLines(entry, who)
    local score = ns.Shows("rowTooltip")
    if ns.Score.Writes() then score = who ~= nil end
    local notes = ns.Shows("rowNotes") and HasNotes(entry)
    if score and ns.OwnTree() and S.ctx then
        -- The tree in use alone: one line, for the profile the list is made on, which reads
        -- as the row does. Whose list it is stands before the profile, as in the field.
        local title = ns.Score.Title(S.ctx.profile)
        AddOwn(GameTooltip, who and L.ST_WHO:format(WhoName(who), title) or title, entry, S.ctx.class)
    elseif score or notes then
        -- On the right, whose list it is when it is not the character's own.
        AddHeader(GameTooltip, who and WhoName(who) or nil, score)
        if score then
            -- How much better the item is on each profile of the class, in the class's colour.
            for _, line in ipairs(ProfileGains(entry)) do
                AddGain(GameTooltip, line.title, line.gain, S.ctx.class)
            end
        end
    end
    if notes then AddNotes(GameTooltip, entry, who) end
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
    if who then
        -- A list for another character. Pawn, Forever Companion or Forever Leveling BiS,
        -- where the player has one, would write here how much of an upgrade the item is for
        -- the character being played, which is no part of a tooltip about someone else: they
        -- are kept from it (Score.Hushed). What the item is to that character is in our
        -- lines below.
        ns.Score.Hushed(GameTooltip.SetHyperlink, GameTooltip, offer.link, nil, nil, hideVendorPrice)
    else
        GameTooltip:SetHyperlink(offer.link, nil, nil, hideVendorPrice)
    end
    -- Our lines, as far as they are switched on for the rows of the tabs (the welcome
    -- window). With none of them the tooltip is the item's own, with the worn item beside it
    -- as ever.
    AddOfferLines(entry, who)
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

-- Puts the coins of a coin display close together, as they stand in the game's bags, and
-- returns how wide the amount then is.
-- The game lays a price out for a table: silver and copper each get a slot wide enough for two
-- digits, so that the coins of all rows stand in columns. A price with one digit of silver or
-- copper then has a hole in it ("2g 90s    0c") that money has nowhere else in the game. So
-- after the game has set the amount, each of its three parts is drawn in on itself, its
-- number right before its coin, and the parts are put side by side from the right, a small
-- step apart. (A part is the game's: `Text` its number, `Icon` its coin, which is not there
-- for a player who has the letters g, s and c instead.)
local COIN_GAP = 4          -- from a coin to the next number
local COIN_AIR = 1          -- from a number to its coin; the game leaves 2
local COINS = { "CopperDisplay", "SilverDisplay", "GoldDisplay" }
local function LayCoins(money)
    local after         -- the nearest part to the right that is shown
    local width = 0
    for i = 1, #COINS do
        local coin = money[COINS[i]]
        if coin then
            coin:ClearAllPoints()
            if after then
                coin:SetPoint("RIGHT", after, "LEFT", -COIN_GAP, 0)
            else
                coin:SetPoint("RIGHT", money, "RIGHT", 0, 0)
            end
            if coin:IsShown() then
                local icon = coin.Icon:IsShown() and coin.Icon:GetWidth() + COIN_AIR or 0
                coin.Text:SetPoint("RIGHT", coin, "RIGHT", -icon, 0)
                coin:SetWidth(coin.Text:GetStringWidth() + icon)
                width = width + coin:GetWidth() + (after and COIN_GAP or 0)
                after = coin
            end
        end
    end
    return width
end

-- Shows an amount in a coin display of ours. `room` is how wide it may be: an amount that
-- would take more gives up its copper, and if that is not enough its silver. Thousands of
-- gold are not a matter of copper, and the box that asks before a purchase has the price
-- in full. So a price never reaches into the column beside it, whatever the sum, the
-- language or the font. (How wide a number is, the game says: nothing is guessed.)
-- A display marked `noCopper` never has copper: the prices of an auction house that deals
-- in whole silver.
local function SetMoney(money, copper, room)
    local small, middle = money.CopperDisplay, money.SilverDisplay
    small:SetForcedHidden(money.noCopper == true)
    middle:SetForcedHidden(false)
    money:SetAmount(copper)
    local width = LayCoins(money)
    if room and width > room and small:IsShown() then
        small:SetForcedHidden(true)
        width = LayCoins(money)
    end
    if room and width > room and money.GoldDisplay:IsShown() then
        middle:SetForcedHidden(true)
        width = LayCoins(money)
    end
    return width
end

-- What is paid, in a row: a buyout, or the price of a consumable's piece. An auction house
-- that deals in whole silver has no copper in its prices.
local function SetPrice(money, copper, room)
    money.noCopper = not C_AuctionHouse.SupportsCopperValues()
    return SetMoney(money, copper, room)
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
    -- The last column: the net cost of gear, or the pieces of a consumable.
    row.Net:SetShown(kind == "gear")
    row.Stock:SetShown(kind ~= "gear")
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

    -- "One-Hand", "Two-Hand"...: on weapon rows only, in a column of its own that ends where
    -- the name's room does, a step before the place of the pick. A row with a pick and a row
    -- without one have it there alike, so the labels of a slot stand one under another.
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

    -- What is paid: the buyout of gear, the price of a consumable's piece (SetPrice).
    row.Price = CreateFrame("Frame", nil, row, "MoneyDisplayFrameTemplate")
    -- After it, what gear costs in the end: to the copper wherever the auction house is,
    -- for a vendor pays to the copper.
    row.Net = CreateFrame("Frame", nil, row, "MoneyDisplayFrameTemplate")
    row.Net:SetPoint("RIGHT", row, "LEFT", LAST_RIGHT, 0)

    -- A consumable's row says what the item does where a gear row has its pick, and after
    -- the price how many pieces are for sale, where a gear row has its net cost. Its score
    -- stands where a gear row has its gain, over the same meter; a row without a score gives
    -- that room to the words. The list hands a frame from one view to the other, so every
    -- row has both sets of parts and shows the one its entry calls for (see InitItemRow).
    row.Effect = NewText(row, 11.5, SOFT, "LEFT", true)
    row.Effect:SetPoint("LEFT", row, "LEFT", COLUMNS.supplies.second, 0)
    row.Stock = NewText(row, 12, SOFT, "RIGHT", true)
    row.Stock:SetPoint("RIGHT", row, "LEFT", LAST_RIGHT, 0)

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

-- (Also while a scan looks up its prices: the list is there to buy from by then.)
local function CanBuy()
    return S.CanBuy()
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
    SetPrice(row.Price, supply.price, at.price - at.upgrade - PAD)

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

    SetPick(row.Pick, entry.pick)

    -- The name has the room up to the pick. "Main Hand" lists one-hand and two-hand weapons
    -- together, so each row says which it is, at the end of that room (see BuildItemRow): the
    -- name gives up what the label takes, down to the least a name is given, and a label that
    -- would take more is cut short itself. A row with neither a pick nor a label has nothing
    -- after its name, which may run on to where the gain begins. A weapon's does not, pick or
    -- no pick: its label would move with it, and the labels of a slot would stand apart.
    local at = COLUMNS.gear
    local nameWidth = at.name
    local hand = ns.Compare.HandLabel(offer.invType)
    row.Hand:SetShown(hand ~= nil)
    if hand then
        row.Hand:SetText(hand)
        local handWidth = math.min(row.Hand:GetUnboundedStringWidth(), nameWidth - NAME_MIN_WIDTH - PAD)
        row.Hand:SetWidth(handWidth)
        nameWidth = nameWidth - handWidth - PAD
    elseif not entry.pick then
        nameWidth = at.upgrade - METER_WIDTH - PAD - NAME_LEFT
    end
    row.Name:SetWidth(nameWidth)

    row.Upgrade:SetText(GainText(entry))
    row.Meter:SetWidth(math.max((METER_WIDTH - 1) * data.share, 2))
    row.Meter:SetTexCoord(0, math.max(data.share, 0.03), 0, 1)

    -- Two prices, always: the buyout, which is what is paid, and what is left of it once a
    -- vendor has the item (Results.Net). The one the best value is judged by stands in
    -- white and the other in grey: the buyout, unless "Value by net cost" is ticked. A
    -- buyout the player cannot pay is red whichever it is.
    local byNet = ns.db.net and true or false
    row.Price:SetFontObject(not entry.affordable and PriceFontRed or byNet and PriceFontGray or PriceFontWhite)
    SetPrice(row.Price, offer.buyout, PRICE_ROOM)
    row.Net:SetFontObject(byNet and PriceFontWhite or PriceFontGray)
    SetMoney(row.Net, ns.Results.Net(offer.buyout, offer.sell), PRICE_ROOM)

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
        if summary.items == 0 and summary.hidden > 0 then
            parts[#parts + 1] = L.ST_SUP_NONE_AFFORD:format(summary.hidden)
        elseif summary.items == 0 then
            -- Nothing with a score, and things without one that the list leaves out: the
            -- line says which box of the Filters menu lists them.
            parts[#parts + 1] = summary.scoreless > 0 and L.ST_SUP_NONE_SCORED or L.ST_SUP_NONE
        elseif summary.hidden > 0 then
            parts[#parts + 1] = L.ST_SUP_DONE_HIDDEN:format(summary.items, summary.groups, summary.hidden)
        else
            parts[#parts + 1] = L.ST_SUP_DONE:format(summary.items, summary.groups)
        end
        if S.suppliesPartial and not S.suppliesNote then parts[#parts + 1] = L.ST_PARTIAL end
    end
    return ForWho(table.concat(parts, " "))
end

-- Why the list of gear may be short of something, for the end of its status line; nil when
-- it is not, or when a note of the scanner's already says what happened.
local function Shortfall()
    if S.message then return nil end
    if S.partial or S.halted then return L.ST_PARTIAL end
    -- The scan ran to its end, and the auction house left some item searches unanswered.
    if S.unanswered > 0 then return L.ST_UNANSWERED:format(S.unanswered) end
    return nil
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
        parts[#parts + 1] = Shortfall()
    elseif S.finishedAt then
        if summary.upgrades == 0 and (summary.unwanted or 0) > 0 then
            -- There are upgrades, and the character's own filters leave every one out.
            parts[#parts + 1] = L.ST_NONE_WANTED:format(summary.unwanted)
        elseif summary.hidden > 0 then
            -- Upgrades are left out for their price: by the sum typed ("Buyout up to"), which
            -- the line then names, or by the purse.
            local ceiling, typed = S.Ceiling()
            if typed and summary.upgrades == 0 then
                parts[#parts + 1] = L.ST_NONE_OVER:format(summary.hidden, ns.Money(ceiling))
            elseif typed then
                parts[#parts + 1] = L.ST_DONE_OVER:format(summary.upgrades, summary.slots, summary.hidden, ns.Money(ceiling))
            elseif summary.upgrades == 0 then
                parts[#parts + 1] = L.ST_NONE_AFFORD:format(summary.hidden)
            else
                parts[#parts + 1] = L.ST_DONE_HIDDEN:format(summary.upgrades, summary.slots, summary.hidden)
            end
        elseif summary.upgrades == 0 then
            parts[#parts + 1] = L.ST_NONE
        else
            parts[#parts + 1] = L.ST_DONE:format(summary.upgrades, summary.slots)
        end
        parts[#parts + 1] = Shortfall()
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
    -- (And who scores: with another addon the profiles are its scales.)
    return (ns.Score.Engine() or "") .. "\n" .. (who and who.key or "") .. "\n" .. #ns.Roster.List() .. "\n"
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
-- the list shows that set and nothing else (see Plan.lua). The two price filters ("Only what
-- I can afford", "Buyout up to") and "Top N per slot" then have no say, and their lines of
-- the Filters menu are grey (Filters.lua); what the character wants of its gear (Wants.lua)
-- holds for a set as it does for the list.
local PLAN_HEIGHT = 30
local planCache = {}

local function Planned()
    return view == "gear" and ns.db.plan and S.ctx ~= nil
end

-- The set for the budget, as rows for the list.
local function PlanRows()
    local money = GetMoney()
    local wants = Wanted()
    -- The ladder of sets is made for all the gold there is, and made again only when what it
    -- is made of has changed; a budget picks a rung of it.
    if planCache.changes ~= S.changes or planCache.ctx ~= S.ctx or planCache.money ~= money
        or planCache.bought ~= #S.acquired or planCache.wants ~= wants then
        planCache = {
            changes = S.changes, ctx = S.ctx, money = money, bought = #S.acquired, wants = wants,
            ladder = ns.Plan.Ladder(S.offers, ns.Plan.Wearing(S.ctx, S.acquired), money, wants),
        }
    end
    return ns.Plan.Rows(ns.Plan.Choose(planCache.ladder, S.PlanCap()), ns.db.net)
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
    if not shown then return end

    local planned = Planned()
    SetCheck(planBar.Check, ns.db.plan)
    PaintBudget()
    local text = ""
    if planned and summary.upgrades > 0 then
        -- What is paid for the set now, and what it costs in the end: as its rows have both.
        text = L.PLAN_SUM:format(summary.upgrades, ns.Num(summary.gain), ns.Money(summary.cost), ns.Money(summary.net))
    elseif planned and not S.IsScan() then
        -- Said of a set that is made, and not while a scan is still finding what there is
        -- or looking up its prices: an empty set means nothing then, and the status line
        -- says what the scan is at.
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
            all = ns.db.allUsable,
            value = SupplyValue(who),
            mana = mana,
        })
    elseif Planned() then
        all, summary = PlanRows()
    else
        all, summary = ns.Results.Build(S.offers, S.ctx, {
            money = GetMoney(),
            affordableOnly = ns.db.affordableOnly,
            cap = ns.Wants.Price(ns.Roster.Target() or ns.Roster.Me()),
            net = ns.db.net,
            wants = Wanted(),
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
    -- Beside the Filters field: which of the filters are on.
    ns.Filters.Paint()

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
    ns.Score.Choose(owner, choice.profile)
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

-- The same choice made away from the tab, in the welcome window (Welcome.lua): `id` is a
-- profile of the character being played. While the lists are for that character, it is as if
-- its line of the menu were clicked. While they are for another one they stay as they are:
-- the choice is written on the character's card, the bags and the tooltips go by it, and the
-- menu shows it the next time it opens.
function UI.ChooseProfile(id)
    local me = ns.Roster.Me()
    if not me then return end
    if frame and not ns.Roster.Target() then
        Choose({ who = false, profile = id })
        -- The field shows a choice made in its own menu by itself; this one it has to read.
        profileDropdown:GenerateMenu()
        return
    end
    local current = ns.Score.Current()
    if current and current.name == id then return end
    ns.Score.Choose(me, id)
    ns.Fire("PROFILE_CHANGED", me)
end

-- Another one scores (the addon, Pawn, Forever Companion or Forever Leveling BiS: the
-- choice in the welcome window), or the scales of the one that does changed. As when
-- another profile is chosen:
-- what a scan for gear
-- found means nothing now, and a view that had a list of gear, or was making one, gets it
-- made again. Consumables are scored as their list is drawn.
ns.Listen("SCORING_CHANGED", function()
    local listed = frame ~= nil and frame:IsShown() and view == "gear" and (S.finishedAt ~= nil or S.state ~= "idle")
    -- A purchase of gear that was being asked about is about a list that is gone.
    if buyBox and buyBox:IsShown() and buyBox.offer then buyBox:Hide() end
    S.Reset()
    if listed and S.IsOpen() then S.Start() end
    toTop = true
    ns.Fire("OFFERS_CHANGED")
    UI.Refresh()
end)

-- Does the menu have lines for other characters (see ProfileMenu)? The field then has to
-- show a name with a profile.
local function OthersListed()
    local me = ns.Roster.Me()
    for _, card in ipairs(ns.Roster.List()) do
        local _, theirs = ns.Score.Current(card)
        if card ~= me and #theirs > 0 then return true end
    end
    return false
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

-- A tick box for a setting of the list (ns.db): a recess, a gold tick, the label beside it.
-- A click on the label ticks the box, as everywhere in the game. The best set for a budget
-- has one; the list's filters have theirs in the menu of the Filters field (Filters.lua).
local function NewFilterCheck(text, setting, tip, parent)
    local check = CreateFrame("CheckButton", nil, parent)
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
-- Gear (`offer`): the gain the list shows for the item, its buyout, and under them what the
-- item costs in the end (its net cost), whether the list is priced by "Net cost" or not. When
-- the price has moved since the scan (`was`), the price the list had stands over the one it
-- has now.
--   confirm  the item was looked up again and is still there
--   wait     "Buy" was pressed: the bid is out, and the box stays until the auction house
--            answers, as the game's own question before a buyout does
--   check    the auction house turned the bid down (someone else was faster): the item is
--            being looked up once more, and the box goes back to `confirm` with the price it
--            has now under the one the player agreed to
--   gone     that lookup found none left: the box says so in place of its lines, and stays
--            until the player closes it. A box that went away by itself would look like a
--            purchase.
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
local BOX_LINE = 32         -- from one line of the box to the next
local BOX_FIRST = -70       -- its first line, from the top of the box

local function PlaceBoxLine(label, value, y)
    label:SetPoint("LEFT", buyBox, "TOPLEFT", BOX_EDGE, y)
    value:SetPoint("RIGHT", buyBox, "TOPRIGHT", -BOX_EDGE, y)
end

-- The lines under the first. What is paid is always there. Only gear has the other two: the
-- old price over it when the price has moved, and the net cost under it. The box is taller by
-- each; the buttons hang from its bottom edge.
local function ShowBoxLines(was, net)
    local y = BOX_FIRST - BOX_LINE
    buyBox.WasLabel:SetShown(was)
    buyBox.Was:SetShown(was)
    if was then y = y - BOX_LINE end
    PlaceBoxLine(buyBox.TotalLabel, buyBox.Total, y)
    buyBox.NetLabel:SetShown(net)
    buyBox.Net:SetShown(net)
    if net then PlaceBoxLine(buyBox.NetLabel, buyBox.Net, y - BOX_LINE) end
    buyBox:SetHeight(BOX_HEIGHT + ((was and 1 or 0) + (net and 1 or 0)) * BOX_LINE)
end

local function PaintGearBox()
    local offer, step, was = buyBox.offer, buyBox.step, buyBox.was
    buyBox.Buy.Label:SetText(ns.Upper(L.BUY))
    -- Nothing left to price or to buy: the box holds its note (see BUY_GONE).
    if step == "gone" then
        buyBox.Buy:SetEnabled(false)
        return
    end
    local affordable = offer.buyout <= GetMoney()
    ShowBoxLines(was ~= nil, true)
    if was then SetMoney(buyBox.Was, was) end
    -- What is paid is the buyout, whatever the list prices the item at.
    buyBox.TotalLabel:SetText(Caption(was and L.BOX_NOW or L.COL_PRICE))
    buyBox.Total:Show()
    buyBox.Total:SetFontObject(affordable and PriceFontWhite or PriceFontRed)
    SetMoney(buyBox.Total, offer.buyout)
    -- And what it costs in the end, with the "Net cost" filter on or off: it is what the
    -- player is about to spend for good.
    SetMoney(buyBox.Net, ns.Results.Net(offer.buyout, offer.sell))
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

-- The row of the list an offer is on, for the gain the box repeats. (An offer is not listed
-- when it was bought from somewhere else than its row.)
local function ListedEntry(offer)
    for i = 1, #rows do
        local entry = rows[i].entry
        if entry and entry.offer and entry.offer.id == offer.id then return entry end
    end
end

-- What the list has of the thing the box asks about, as its row's tooltip wants it; nil when
-- the list has no row for it (an item that is gone). Gear is told as the box has it: the
-- price may have moved since the row was drawn.
local function BoxEntry()
    local offer = buyBox.offer
    if not offer then
        for i = 1, #rows do
            local entry = rows[i].entry
            if entry and entry.supply and entry.supply == buyBox.supply then return entry end
        end
        return nil
    end
    -- (An item that has just gone may still be on the list for a moment: the list is redrawn
    -- a beat after the scanner speaks.)
    local listed = buyBox.step ~= "gone" and ListedEntry(offer)
    if not listed then return nil end
    local entry = {}
    for key, value in pairs(listed) do entry[key] = value end
    entry.offer, entry.affordable = offer, offer.buyout <= GetMoney()
    return entry
end

-- The item at the top of the box has the tooltip its row in the list has, with our lines
-- under it (ShowItemTooltip): the box stands over the list, and what the player was reading
-- there is still to be read. An item the list has no row for has the tooltip it has
-- anywhere in the game. A modified click links the item or tries it on, as on a row.
local function BoxItemOnEnter(item)
    local entry = BoxEntry()
    -- (Tooltip.lua leaves alone a tooltip that writes its lines itself.)
    item.entry, item.upgradeScoutRow = entry, entry ~= nil
    if entry then
        ShowItemTooltip(item)
        return
    end
    GameTooltip:SetOwner(item, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(buyBox.link, nil, nil, true)
    GameTooltip:Show()
end

local function BoxItemOnLeave()
    HideWorn()
    GameTooltip_Hide()
end

-- The box goes without the mouse leaving the item: bought, or closed with Escape.
local function BoxItemOnHide(item)
    if GameTooltip:IsOwned(item) then BoxItemOnLeave() end
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
    item:SetScript("OnLeave", BoxItemOnLeave)
    item:SetScript("OnHide", BoxItemOnHide)
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

    -- The lines under the first stand where ShowBoxLines puts them.
    -- The price the list had for gear, in grey: it is no longer the price.
    buyBox.WasLabel = NewText(buyBox, 9.5, GOLD_DIM)
    buyBox.WasLabel:SetText(Caption(L.BOX_WAS))
    buyBox.Was = CreateFrame("Frame", nil, buyBox, "MoneyDisplayFrameTemplate")
    buyBox.Was:SetFontObject(PriceFontGray)
    PlaceBoxLine(buyBox.WasLabel, buyBox.Was, BOX_FIRST - BOX_LINE)

    buyBox.TotalLabel = NewText(buyBox, 9.5, GOLD_DIM)
    buyBox.Total = CreateFrame("Frame", nil, buyBox, "MoneyDisplayFrameTemplate")
    -- An auction house that deals in whole silver has no copper in its prices (see SetMoney).
    local noCopper = not C_AuctionHouse.SupportsCopperValues()
    buyBox.Was.noCopper, buyBox.Total.noCopper = noCopper, noCopper

    -- The net cost of gear. To the copper wherever the auction house is: a vendor pays to
    -- the copper.
    buyBox.NetLabel = NewText(buyBox, 9.5, GOLD_DIM)
    buyBox.NetLabel:SetText(Caption(L.NET))
    buyBox.Net = CreateFrame("Frame", nil, buyBox, "MoneyDisplayFrameTemplate")
    buyBox.Net:SetFontObject(PriceFontWhite)
    ShowBoxLines(false, false)

    -- What the box says in place of its lines when the item is gone, in the middle of the
    -- room the first two have.
    buyBox.Note = NewText(buyBox, 12, CREAM, "CENTER")
    PlaceBoxLine(buyBox.Note, buyBox.Note, BOX_FIRST - BOX_LINE / 2)
    buyBox.Note:SetText(L.BOX_GONE)
    buyBox.Note:Hide()

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
    -- A new question: whatever the last one ended with, its lines are back.
    buyBox.Note:Hide()
    buyBox.TotalLabel:Show()
    buyBox.Gain:SetShown(gear)
    buyBox.Count:SetShown(not gear)
    buyBox.Stock:SetShown(not gear)
    -- A consumable is used up, and its price is asked for on the spot: it has neither a net
    -- cost nor an old price. (For gear, PaintGearBox says.)
    if not gear then ShowBoxLines(false, false) end
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
-- Makes the frame's controls and titles those of `view`. The list itself follows at the
-- next refresh.
local function ApplyView()
    local gear = view == "gear"
    local list = frame.List

    -- Item, pick, gain, buyout, net cost; or item, effect, score, price of a piece, pieces
    -- for sale. Each title over its column, where this view has it (see COLUMNS). A title
    -- has `room`: a long word in some language is cut short before it reaches the title
    -- beside it.
    local at, titles = COLUMNS[view], list.Titles
    local function Title(title, text, point, x, room)
        title:SetText(ns.Upper(text))
        title:SetWidth(title:GetUnboundedStringWidth() > room and room or 0)
        title:ClearAllPoints()
        title:SetPoint(point, list, "TOPLEFT", LIST_LEFT + x, -TITLE_TOP)
    end
    local third = 100           -- for the title of the gain, which is wider than its meter in some languages
    Title(titles[2], gear and L.COL_PICK or L.COL_EFFECT, "LEFT", at.second, at.upgrade - third - PAD - at.second)
    Title(titles[3], gear and L.COL_UPGRADE or L.COL_SCORE, "RIGHT", at.upgrade, third)
    Title(titles[4], gear and L.COL_PRICE or L.COL_UNIT, "RIGHT", at.price, at.price - at.upgrade - PAD)
    Title(titles[5], gear and L.NET or L.COL_STOCK, "RIGHT", at.last, at.last - at.price - PAD)
    intro.Heading:SetText(ns.Upper(gear and L.TITLE or L.TITLE_SUP))

    -- The Filters field stands against the right edge in both views; its menu is the view's
    -- own, made each time it opens (Filters.lua). Left of it are the names of the filters
    -- that are on, which are kept some room (FILTERS_ROOM), and the profile field takes what
    -- that leaves, within reason. Where a language leaves too little, the profile field
    -- stands without its own label; its tooltip says what it is. Too little is less than the
    -- field has a use for: with other characters in its menu it shows a name and a profile
    -- ("Diluna: Beast Mastery"), which takes all the width it can have.
    local label = frame.ProfileLabel
    local labelWidth = label:GetStringWidth() + PAD
    local room = AuctionHouseFrame:GetWidth() - (BAR_LEFT + SCAN_WIDTH + 2 * PAD
        + 2 * PAD + FILTERS_ROOM + PAD + frame.FilterField:GetWidth() + BAR_RIGHT)
    local labelled = room - labelWidth >= (OthersListed() and DROPDOWN_MAX or DROPDOWN_MIN)
    label:SetShown(labelled)
    if not labelled then labelWidth = 0 end
    local width = Clamp(room - labelWidth, DROPDOWN_MIN, DROPDOWN_MAX)
    profileDropdown:SetWidth(width)
    profileDropdown:ClearAllPoints()
    profileDropdown:SetPoint("LEFT", scanButton, "RIGHT", 2 * PAD + labelWidth, 0)
    -- The names have all there is between the two fields.
    ns.Filters.SetRoom(FILTERS_ROOM + room - labelWidth - width)

    buyBox:Hide()
    toTop = true
end

-- What the Consumables view adds to the frame Build has made, and what makes the frame serve
-- two tabs. (A part of Build in its own right, also because one Lua function can refer to
-- only so many of a file's local names.)
local function BuildViews(auction)
    BuildBuyBox()
    BuildPlan()
    frame.BuyBox = buyBox

    -- The filters of the list in view, in the menu of a field at the right end of the strip
    -- above it (Filters.lua). One line of that menu is no filter: "Value by net cost". A row
    -- of gear has both its prices, the buyout and what it costs in the end (the buyout less
    -- what a vendor pays for it afterwards); the line says which of them the best value and
    -- "Top N per slot" go by (Results.Cost). What the player can pay for, and the best set
    -- for a budget, stay a matter of the buyout.
    -- Ticking it sends for no prices: a scan looks up what the list needs either way (see
    -- SkipReason in Scanner.lua), and price checks that were stopped stay stopped. Nor does
    -- it send the list back to its top, as a filter does: a row or two may come or go, and
    -- the player is looking at the ones in view.
    local field, names = ns.Filters.Build(frame, {
        View = function() return view end,
        Planned = Planned,
        Changed = function(sameOffers)
            if sameOffers then
                keepPlace = true
            else
                toTop = true
                -- The player changed what the list shows: price checks that were stopped may go on.
                S.Resume()
            end
            UI.Refresh()
        end,
    })
    field:SetPoint("RIGHT", frame, "TOPRIGHT", -BAR_RIGHT, -BAR_MIDDLE)
    frame.FilterField, frame.FilterNames = field, names

    -- The library that makes the tabs shows and hides the frame a tab was made with. So the
    -- Consumables tab is made with an empty frame of its own, and the real one comes and goes
    -- with it. Which of the two tabs brought the frame up says which view it is to show.
    holder = CreateFrame("Frame", nil, auction)
    holder:Hide()
    holder:SetScript("OnShow", function() frame:Show() end)
    holder:SetScript("OnHide", function() frame:Hide() end)

    -- The gold display at the foot of the window is the game's own, the same on every tab.
    -- While one of our tabs is up its coins stand as close as those of our prices do
    -- (LayCoins); on the game's tabs it is as the game lays it out. The game writes the
    -- amount into it again whenever the gold changes, which undoes the closing up: hence
    -- the hook, and hence writing the amount again is how it is given back.
    local purse = auction.MoneyFrameBorder and auction.MoneyFrameBorder.MoneyFrame
    if purse and purse.SetAmount and purse.CopperDisplay and purse.CopperDisplay.Text then
        hooksecurefunc(purse, "SetAmount", function(self)
            if frame:IsShown() then LayCoins(self) end
        end)
    else
        purse = nil
    end

    frame:SetScript("OnShow", function()
        local shown = holder:IsShown() and "supplies" or "gear"
        if shown ~= view then
            view = shown
            ApplyView()
        end
        if purse then LayCoins(purse) end
        UI.Refresh()
    end)
    -- Another tab, or the window closed: a question about buying must not stay up.
    frame:SetScript("OnHide", function()
        buyBox:Hide()
        if purse then purse:SetAmount(GetMoney()) end
    end)
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

    -- After it the profile field, and against the right edge the Filters field (BuildViews).
    -- How wide the profile field is, and whether it has its label, is for ApplyView to say.
    local profileLabel = NewText(frame, 9.5, GOLD_DIM)
    frame.ProfileLabel = profileLabel
    profileLabel:SetPoint("LEFT", scanButton, "RIGHT", 2 * PAD, 0)
    profileLabel:SetText(Caption(L.PROFILE))

    profileDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    profileDropdown:SetHeight(24)
    Widgets.SkinDropdown(profileDropdown)
    profileDropdown:SetDefaultText(NONE)
    profileDropdown:SetupMenu(ProfileMenu)
    profileDropdown:SetTooltip(function(tooltip)
        local who = ns.Roster.Target()
        GameTooltip_SetTitle(tooltip, who and L.ST_WHO:format(WhoName(who), ProfileTitle()) or ProfileTitle())
        -- Only what helps to choose. Where the weights come from is in the README.
        GameTooltip_AddNormalLine(tooltip, ns.Score.Text("TIP") or L.PROFILE_TIP)
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

    -- The titles of the columns, five in either view. The list has one order, best upgrade
    -- first in every slot: a title is not a button. The first is "Item" in both views. What
    -- the four after it say, and where they stand, is the view's (see ApplyView).
    list.Titles = {}
    for i = 1, 5 do
        list.Titles[i] = NewText(list, 9.5, GOLD_DIM, i > 2 and "RIGHT" or "LEFT")
    end
    list.Titles[1]:SetPoint("LEFT", list, "TOPLEFT", LIST_LEFT + TITLE_LEFT, -TITLE_TOP)
    list.Titles[1]:SetText(ns.Upper(L.COL_ITEM))
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
-- `was` is the price the list had, when the item is no longer at it.
ns.Listen("CONFIRM_BUY", function(offer, was)
    -- The lookup before the question takes a moment; the player may have left the view since.
    -- Nothing is asked then; a price that has moved is told in the chat.
    if not frame:IsVisible() or view ~= "gear" then
        S.CancelPurchase()
        if was then ns.Print(L.MSG_PRICE:format(offer.link, ns.Money(offer.buyout), ns.Money(was))) end
        return
    end
    buyBox.offer, buyBox.supply, buyBox.tiers, buyBox.auction = offer, nil, nil, nil
    buyBox.was = was
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

-- The auction house's answer to the bid. Bought: the box has done its work, and the scanner
-- tells the purchase in the chat. (Whatever step the box is in: an error from elsewhere may
-- have sent it to look the item up while the bid was still on its way.)
ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
    if buyBox and buyBox:IsShown() and buyBox.offer and buyBox.offer.auctionID == auctionID then
        buyBox:Hide()
    end
end)

-- Turned down: someone else was faster, most likely; the game shows what went wrong. The
-- player is not sent back to the list to press "Buy" again: the box stays, the item is
-- looked up once more, and the box shows what came of it. That is the price it has now
-- (CONFIRM_BUY), or that there is none left (BUY_GONE).
ns.On("AUCTION_HOUSE_SHOW_ERROR", function()
    if not (buyBox and buyBox:IsShown() and buyBox.offer and buyBox.step == "wait") then return end
    if S.BuyAgain(buyBox.offer) then
        buyBox.step = "check"
        PaintBox()
    else
        buyBox:Hide()
    end
end)

ns.Listen("BUY_GONE", function(offer)
    if not (buyBox:IsShown() and buyBox.offer == offer) then return end
    buyBox.step = "gone"
    buyBox.FirstLabel:Hide()
    buyBox.Gain:Hide()
    ShowBoxLines(false, false)
    buyBox.TotalLabel:Hide()
    buyBox.Total:Hide()
    buyBox.Note:Show()
    PaintBox()
end)

-- The auction house did not answer the lookup: the scanner says so in the chat.
ns.Listen("BUY_FAILED", function(offer)
    if buyBox:IsShown() and buyBox.offer == offer then buyBox:Hide() end
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
-- /upscout opens the tab when the auction house is open, and the welcome window otherwise;
-- /upscout stats tells how the last scan went; /upscout forget Name takes a character that is
-- gone (deleted, renamed) out of the profile field's menu
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
    -- At the auction house, with another tab in view: to ours. Anywhere else, and on our own
    -- tab: the window that says what the addon does and has its settings (Welcome.lua).
    if frame and S.IsOpen() and not frame:IsVisible() then
        LibStub("LibAHTab-1-0"):SetSelected(TAB_ID)
        return
    end
    ns.Welcome.Show()
end
