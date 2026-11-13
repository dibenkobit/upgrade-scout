local _, ns = ...
local L = ns.L
local S = ns.Scanner

-- The "Upgrades" tab of the auction house window.
--
-- It is put together from the parts the game builds its own auction tabs from, sized and
-- placed as the Buy tab has them, so that it looks and works like one of those tabs:
--   the list        WowScrollBoxList and MinimalScrollBar; rows with the height, stripes,
--                   highlight, fonts and icon frame of AuctionHouseItemListLineTemplate
--   column titles   ColumnDisplayButtonShortTemplate
--   prices          MoneyDisplayFrameTemplate
--   the Pawn scale  WowStyle1DropdownTemplate
--   buying          a StaticPopup shaped like the game's own BUYOUT_AUCTION
-- Blizzard_AuctionHouseUI is the reference for every number and name below.
local UI = {}
ns.UI = UI

local TAB_ID = "UpgradeScout"
local POPUP = "UPGRADESCOUT_BUY"

-- Layout, in the coordinates of the auction window (800 by 538). The Buy tab keeps a bar 40
-- high for its search controls, 29 below the top; its lists start under that bar, 4 in from
-- the left, leave 27 on the right for the scroll bar and end 2 above the gold display.
local BAR_MIDDLE = 49
local BAR_LEFT, BAR_RIGHT = 72, 12          -- left: clear of the portrait in the corner
local LIST_LEFT, LIST_RIGHT, LIST_TOP, LIST_BOTTOM = 4, 27, 74, 27
local GOLD_RIGHT, GOLD_BOTTOM = 167, 3      -- the frame around the gold display (MoneyFrameInset)
local TITLES_HEIGHT = 19
local ROW_HEIGHT = 20
local REFRESH_INTERVAL = 0.1                -- seconds between redraws while a scan reports progress

-- Columns, in the coordinates of a row: left edge and width. Numbers sit against the right
-- edge of their column, and so do the titles above them.
local COLUMNS = {
    { key = "item", title = L.COL_ITEM, left = 0, width = 262 },
    { key = "pick", title = L.COL_PICK, left = 262, width = 126 },
    { key = "upgrade", title = L.COL_UPGRADE, left = 388, width = 88, numeric = true },
    { key = "price", title = L.COL_PRICE, left = 476, width = 122, numeric = true },
    { key = "per", title = L.COL_PER, left = 598, width = 104, numeric = true },
    { key = "buy", title = "", left = 702 },            -- to the right edge
}
local COLUMN = {}
for i = 1, #COLUMNS do COLUMN[COLUMNS[i].key] = COLUMNS[i] end
local PAD = 8                               -- between the edge of a column and what is in it
local NAME_LEFT, NAME_MIN_WIDTH = 24, 110   -- a name starts after the icon; the least it keeps
local NAME_WIDTH = COLUMN.item.width - NAME_LEFT - PAD

local frame, scrollBox, provider, hint, spinner, status, scanButton, scaleDropdown, affordCheck, topCheck
local rows = {}
local elements = {}         -- row key -> the table the scroll box knows the row by (see SyncList)
local syncCount = 0
local toTop = false         -- scroll back to the top at the next refresh
local scaleShown            -- what the scale dropdown was last built from (see ScaleKey)

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function ShowItemTooltip(row)
    local entry = row.entry
    local offer = entry.offer
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    -- No vendor price, as on the Buy tab: this is something to buy, not to sell.
    local hideVendorPrice = true
    GameTooltip:SetHyperlink(offer.link, nil, nil, hideVendorPrice)

    GameTooltip_AddBlankLineToTooltip(GameTooltip)
    if entry.base > 0 then
        -- All three to the precision of the difference, so that they add up: 1.548, 1.5, +0.048.
        local digits = ns.Decimals(entry.delta)
        GameTooltip_AddColoredLine(GameTooltip, L.TT_SCORE:format(ns.Num(offer.value, digits),
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
        GameTooltip_AddNormalLine(GameTooltip, L.TT_OFFHAND_EMPTY)
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
    GameTooltip_ShowCompareItem(GameTooltip)
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
    GameTooltip_Hide()
end

-- A row that scrolls out of view, or whose offer goes, is hidden without the mouse leaving it.
local function ItemRowOnHide(row)
    row:SetScript("OnUpdate", nil)
    if GameTooltip:IsOwned(row) then
        ResetCursor()
        GameTooltip_Hide()
    end
end

-- Shift-click links the item in chat, Ctrl-click tries it on: the game decides which.
local function ItemRowOnClick(row)
    HandleModifiedItemClick(row.entry.offer.link)
end

local function BuyOnClick(button)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    S.Buy(button:GetParent().entry.offer)
end

local function NewText(parent, font, justify)
    local text = parent:CreateFontString(nil, "ARTWORK", font)
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    return text
end

-- A coin display against the right edge of a column.
local function NewMoney(row, column)
    local money = CreateFrame("Frame", nil, row, "MoneyDisplayFrameTemplate")
    money:SetPoint("RIGHT", row, "LEFT", column.left + column.width - PAD, 0)
    return money
end

-- The scroll box hands out bare frames; each gets its parts here the first time it is used.
local function BuildItemRow(row)
    row.built = true

    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas("auctionhouse-ui-row-highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints()

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(14, 14)
    row.Icon:SetPoint("LEFT", 4, 0)
    local border = row:CreateTexture(nil, "ARTWORK", nil, 1)
    border:SetAtlas("auctionhouse-itemicon-small-border")
    border:SetSize(16, 16)
    border:SetPoint("CENTER", row.Icon)

    row.Name = NewText(row, "Number14FontWhite")
    row.Name:SetPoint("LEFT", row, "LEFT", NAME_LEFT, 0)

    -- "One-Hand", "Two-Hand"...: at the right end of the name column, on weapon rows only.
    row.Hand = NewText(row, "Number13FontGray", "RIGHT")
    row.Hand:SetPoint("RIGHT", row, "LEFT", NAME_LEFT + NAME_WIDTH, 0)

    row.Pick = NewText(row, "Number13FontWhite")
    row.Pick:SetPoint("LEFT", row, "LEFT", COLUMN.pick.left + PAD, 0)
    row.Pick:SetWidth(COLUMN.pick.width - PAD)

    row.Upgrade = NewText(row, "Number14FontWhite", "RIGHT")
    row.Upgrade:SetPoint("RIGHT", row, "LEFT", COLUMN.upgrade.left + COLUMN.upgrade.width - PAD, 0)
    row.Upgrade:SetWidth(COLUMN.upgrade.width - PAD)

    row.Price = NewMoney(row, COLUMN.price)
    -- An auction house that deals in whole silver shows no copper in its prices.
    if not C_AuctionHouse.SupportsCopperValues() then
        row.Price.CopperDisplay:SetForcedHidden(true)
    end
    row.PerPoint = NewMoney(row, COLUMN.per)
    row.PerPoint:SetFontObject(PriceFontWhite)

    row.Buy = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.Buy:SetSize(56, 18)
    row.Buy:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.Buy:SetNormalFontObject("GameFontNormalSmall")
    row.Buy:SetHighlightFontObject("GameFontHighlightSmall")
    row.Buy:SetDisabledFontObject("GameFontDisableSmall")
    row.Buy:SetText(L.BUY)
    row.Buy:SetScript("OnClick", BuyOnClick)

    row:SetScript("OnEnter", ItemRowOnEnter)
    row:SetScript("OnLeave", ItemRowOnLeave)
    row:SetScript("OnHide", ItemRowOnHide)
    row:SetScript("OnClick", ItemRowOnClick)
    -- The game redraws a tooltip through this while it is up: the price the player is short
    -- by changes with their money, and the item data may still be arriving.
    row.UpdateTooltip = ShowItemTooltip
end

local function BuildHeaderRow(row)
    row.built = true

    local band = row:CreateTexture(nil, "BACKGROUND")
    band:SetAllPoints()
    band:SetColorTexture(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 0.10)

    row.Title = NewText(row, "GameFontNormal")
    row.Title:SetPoint("LEFT", row, "LEFT", PAD, 0)
end

local PICK_TEXT = {
    BOTH = GREEN_FONT_COLOR:WrapTextInColorCode(L.PICK_BOTH),
    UPGRADE = NORMAL_FONT_COLOR:WrapTextInColorCode(L.PICK_UPGRADE),
    VALUE = GREEN_FONT_COLOR:WrapTextInColorCode(L.PICK_VALUE),
}

local function CanBuy()
    return S.state == "idle" and S.IsOpen()
end

local function InitItemRow(row, element)
    if not row.built then BuildItemRow(row) end
    local entry = element.data.entry
    local offer = entry.offer
    row.entry = entry

    row.Stripe:SetAtlas(element.odd and "auctionhouse-rowstripe-1" or "auctionhouse-rowstripe-2")
    row.Icon:SetTexture(offer.icon)

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

    row.Pick:SetText(entry.pick and PICK_TEXT[entry.pick] or "")

    local gain = GREEN_FONT_COLOR:WrapTextInColorCode("+" .. ns.Num(entry.delta))
    local share = entry.percent and ("+" .. FormatPercentage(entry.percent, true)) or L.NEW
    row.Upgrade:SetText(gain .. " " .. GRAY_FONT_COLOR:WrapTextInColorCode("(" .. share .. ")"))

    row.Price:SetFontObject(entry.affordable and PriceFontWhite or PriceFontRed)
    row.Price:SetAmount(offer.buyout)
    row.PerPoint:SetAmount(ns.Copper(entry.costPer))

    row.Buy:SetEnabled(CanBuy() and entry.affordable)
end

local function InitHeaderRow(row, element)
    if not row.built then BuildHeaderRow(row) end
    local data = element.data
    local title = ns.Compare.GroupLabel(data.group)
    if data.shown < data.total then
        -- "3 of about 19": some of the 19 have not had their price looked up. The word is
        -- spelled out because the game's font draws "~" raised, like an accent.
        local count = (data.approx and L.TOP_OF_ABOUT or L.TOP_OF):format(data.shown, data.total)
        title = title .. " " .. GRAY_FONT_COLOR:WrapTextInColorCode("(" .. count .. ")")
    end
    row.Title:SetText(title)
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

-- More rows than this coming or going at once (a filter switched, a new scan) are not worth
-- patching in: the collection is emptied and filled again.
local PATCH_LIMIT = 40

-- Makes the scroll box show `rows`.
local function SyncList()
    syncCount = syncCount + 1
    local fresh = {}
    local odd = true
    for i = 1, #rows do
        local row = rows[i]
        local key = RowKey(row)
        local element = elements[key]
        if not element then
            element = { key = key }
            elements[key] = element
            fresh[#fresh + 1] = element
        end
        -- The stripes alternate from the top of each slot.
        odd = row.kind == "header" or not odd
        element.data, element.order, element.odd, element.seen = row, i, odd, syncCount
    end
    local stale = {}
    for key, element in pairs(elements) do
        if element.seen ~= syncCount then
            stale[#stale + 1] = element
            elements[key] = nil
        end
    end

    if #stale + #fresh > PATCH_LIMIT then
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
local function StatusText(summary)
    if S.state == "browse" then
        return L.ST_BROWSE:format(S.info.rows)
    elseif S.state == "score" then
        return L.ST_SCORE:format(S.info.scored, S.info.toScore)
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
    return table.concat(parts, " ")
end

-- The scales Pawn shows and the one in use, as one string: the dropdown is rebuilt when this
-- changes (a scale enabled or hidden in Pawn while the auction house is open).
local function ScaleKey()
    if ns.Pawn.Problem() then return "" end
    local current, scales = ns.Pawn.CurrentScale()
    local names = {}
    for i = 1, #scales do names[i] = scales[i].name end
    return (current and current.name or "") .. "=" .. table.concat(names, "\n")
end

local function ScaleTitle()
    if ns.Pawn.Problem() then return NONE end
    local scale = ns.Pawn.CurrentScale()
    return scale and scale.title or NONE
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end

    local summary
    rows, summary = ns.Results.Build(S.offers, S.ctx, {
        money = GetMoney(),
        affordableOnly = ns.db.affordableOnly,
        limit = ns.db.topOnly and ns.Results.TOP_COUNT or nil,
        unchecked = S.Unchecked(),
    })
    SyncList()

    local idle = S.state == "idle"
    status:SetText(StatusText(summary))
    scanButton:SetText(idle and L.SCAN or L.STOP)
    scanButton:SetEnabled(idle or S.mode == "scan" or S.mode == "more")
    affordCheck:SetChecked(ns.db.affordableOnly and true or false)
    topCheck:SetChecked(ns.db.topOnly and true or false)

    local scaleKey = ScaleKey()
    if scaleKey ~= scaleShown then
        scaleShown = scaleKey
        scaleDropdown:GenerateMenu()
    end

    -- An empty list says what to do or why it is empty; while a scan fills it, the game's
    -- spinner turns in its place.
    spinner:SetShown(#rows == 0 and not idle)
    if #rows > 0 or not idle then
        hint:SetText("")
    elseif S.finishedAt or S.message then
        hint:SetText(StatusText(summary))
    else
        hint:SetText(ns.Pawn.Problem() or L.HINT:format(ScaleTitle()))
    end

    -- The scan looks up only the prices the list can show. If the list now needs more of them
    -- (a filter was switched off, an offer was bought), this is where it asks.
    S.Demand()
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
local function IsScale(name)
    local scale = ns.Pawn.CurrentScale()
    return scale ~= nil and scale.name == name
end

local function ChooseScale(name)
    if ns.db.scale == name then return end
    ns.db.scale = name
    -- The dropdown shows the choice by itself; it must not be rebuilt while its menu is open.
    scaleShown = ScaleKey()
    -- Scores from another scale mean nothing now.
    local rescan = S.finishedAt ~= nil or S.state ~= "idle"
    S.Reset()
    if rescan and S.IsOpen() then S.Start() end
    UI.Refresh()
end

local function ScaleMenu(_, root)
    if ns.Pawn.Problem() then return end
    local _, scales = ns.Pawn.CurrentScale()
    for i = 1, #scales do
        root:CreateRadio(scales[i].title, IsScale, ChooseScale, scales[i].name)
    end
end

local function ScanOnClick()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if S.state == "idle" then
        S.Start()
    else
        S.Stop(L.ST_STOPPED)
    end
    UI.Refresh()
end

-- A checkbox for one of the list's two filters. Its label is the template's own, and a click
-- on the label ticks the box, as everywhere in the game.
local function NewFilterCheck(text, setting, tip)
    local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check.Text:SetFontObject(GameFontHighlightSmall)
    check.Text:SetText(text)
    check:SetHitRectInsets(0, -check.Text:GetStringWidth(), 0, 0)
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

local function Build()
    local auction = AuctionHouseFrame
    frame = CreateFrame("Frame", "UpgradeScoutFrame", auction)
    frame:SetAllPoints()
    frame:Hide()

    -- The bar above the list, where the Buy tab has its search box.
    scanButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    scanButton:SetSize(110, 22)
    scanButton:SetPoint("LEFT", frame, "TOPLEFT", BAR_LEFT, -BAR_MIDDLE)
    scanButton:SetText(L.SCAN)
    scanButton:SetScript("OnClick", ScanOnClick)

    topCheck = NewFilterCheck(L.TOP:format(ns.Results.TOP_COUNT), "topOnly", L.TOP_TIP:format(ns.Results.TOP_COUNT))
    topCheck:SetPoint("RIGHT", frame, "TOPRIGHT", -(BAR_RIGHT + topCheck.Text:GetStringWidth()), -BAR_MIDDLE)
    affordCheck = NewFilterCheck(L.AFFORD, "affordableOnly")
    affordCheck:SetPoint("RIGHT", topCheck, "LEFT", -(PAD + affordCheck.Text:GetStringWidth()), 0)

    local scaleLabel = NewText(frame, "GameFontNormalSmall")
    scaleLabel:SetPoint("LEFT", scanButton, "RIGHT", 2 * PAD, 0)
    scaleLabel:SetText(L.SCALE)

    -- The dropdown takes the room the labels leave, within reason.
    local taken = BAR_LEFT + scanButton:GetWidth() + 2 * PAD + scaleLabel:GetStringWidth() + PAD
        + 2 * PAD + affordCheck:GetWidth() + affordCheck.Text:GetStringWidth()
        + PAD + topCheck:GetWidth() + topCheck.Text:GetStringWidth() + BAR_RIGHT
    scaleDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    scaleDropdown:SetWidth(Clamp(auction:GetWidth() - taken, 110, 200))
    scaleDropdown:SetPoint("LEFT", scaleLabel, "RIGHT", PAD, 0)
    scaleDropdown:SetDefaultText(NONE)
    scaleDropdown:SetupMenu(ScaleMenu)
    scaleDropdown:SetTooltip(function(tooltip)
        GameTooltip_SetTitle(tooltip, ScaleTitle())
        GameTooltip_AddNormalLine(tooltip, L.SCALE_TIP)
    end)

    -- Column titles stand on the top edge of the list's frame, as on the Buy tab.
    local titles = CreateFrame("Frame", nil, frame)
    titles:SetHeight(TITLES_HEIGHT)
    titles:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_LEFT + 4, -(LIST_TOP + 1))
    titles:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(LIST_RIGHT + 4), -(LIST_TOP + 1))
    for i = 1, #COLUMNS do
        local column = COLUMNS[i]
        local title = CreateFrame("Button", nil, titles, "ColumnDisplayButtonShortTemplate")
        title:SetPoint("LEFT", titles, "LEFT", column.left, 0)
        if column.width then
            title:SetWidth(column.width)
        else
            title:SetPoint("RIGHT", titles, "RIGHT", 0, 0)
        end
        title:SetText(column.title)
        if column.numeric then
            title.Text:ClearAllPoints()
            title.Text:SetPoint("RIGHT", title, "RIGHT", -PAD, 0)
        end
        -- The list has one order, best upgrade first in every slot: nothing to click.
        title:SetEnabled(false)
    end

    local list = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_LEFT, -(LIST_TOP + TITLES_HEIGHT))
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -LIST_RIGHT, LIST_BOTTOM)
    local background = list:CreateTexture(nil, "BACKGROUND")
    background:SetAtlas("auctionhouse-background-index")
    background:SetPoint("TOPLEFT", list, "TOPLEFT", 3, -3)
    background:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -3, 3)

    -- The game's scroll box and scroll bar, set up the way Blizzard_AuctionHouseItemList sets
    -- up the Buy tab's list. Scrolling, the mouse wheel and the bar are all the scroll box's own.
    scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", titles, "BOTTOMLEFT", 0, -6)
    scrollBox:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -4, 3)
    local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 9, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 9, 4)

    local view = CreateScrollBoxListLinearView()
    view:SetElementFactory(RowFactory)
    -- Frames made from a frame type, not a template, have no height of their own.
    view:SetElementExtent(ROW_HEIGHT)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    provider = CreateDataProvider()
    provider:SetSortComparator(ByOrder, true)       -- true: nothing to sort yet
    scrollBox:SetDataProvider(provider)

    spinner = CreateFrame("Frame", nil, frame, "SpinnerTemplate")
    spinner:SetSize(90, 90)
    spinner:SetPoint("CENTER", scrollBox, "CENTER", 0, 0)
    spinner:Hide()

    hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint:SetPoint("TOP", scrollBox, "TOP", 0, -45)
    hint:SetPoint("LEFT", list, "LEFT", 45, 0)
    hint:SetPoint("RIGHT", list, "RIGHT", -45, 0)

    -- The strip at the bottom, to the right of the gold display.
    status = NewText(frame, "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", GOLD_RIGHT + PAD, GOLD_BOTTOM)
    status:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -PAD, LIST_BOTTOM)

    frame:SetScript("OnShow", UI.Refresh)
    -- Another tab, or the window closed: a question about buying must not stay up.
    frame:SetScript("OnHide", function() StaticPopup_Hide(POPUP) end)
end

---------------------------------------------------------------------------
-- The tab itself
---------------------------------------------------------------------------
-- The game loads its auction window the first time an auction house is opened; the tab is
-- added to it right then.
EventUtil.ContinueOnAddOnLoaded("Blizzard_AuctionHouseUI", function()
    Build()
    LibStub("LibAHTab-1-0"):CreateTab(TAB_ID, frame, L.TAB, L.TITLE)
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
-- /upscout opens the tab when the auction house is open; /upscout stats tells how the last
-- scan went
---------------------------------------------------------------------------
SLASH_UPGRADESCOUT1 = "/upscout"
SLASH_UPGRADESCOUT2 = "/upgradescout"
SlashCmdList["UPGRADESCOUT"] = function(message)
    if message:lower():match("^%s*stats") then
        ns.Print(S.StatsText())
        return
    end
    if not (frame and S.IsOpen()) then
        ns.Print(L.ERR_AH_CLOSED)
        return
    end
    LibStub("LibAHTab-1-0"):SetSelected(TAB_ID)
end
