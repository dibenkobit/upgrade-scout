local ADDON, ns = ...
local L = ns.L

-- Gear bought for another character of the account, on its way to that character.
-- What is bought at the auction house comes to the mailbox of the character that paid. When
-- the lists were for another character (Roster.Target), that purchase is written down as a
-- parcel, for the whole account. At a mailbox a button for each such character then puts the
-- parcels the player has in the bags into a letter to it: the Send Mail page is opened, the
-- name and a subject are filled in, the items are attached. Sending is left to the player,
-- who sees the letter first and presses the game's own Send.
--
-- Nothing here goes through the cursor or calls the game's send: the items are attached the
-- way a right-click attaches them while the Send Mail page is open (the same way the one
-- addon made for this client, Mastercraft, does it).
--
-- A parcel is struck off when its item leaves in a letter, whoever put it in: the button or
-- the player by hand (see "Letters going out"). One that went some other way (sold, put on,
-- sent before the addon could see it) is struck off at a mailbox, once the game has listed the
-- mail and the item is nowhere to be sent from (see Settle).
--
-- Only gear is followed. Consumables stack with what the player already has, and a stack
-- cannot be told apart into "bought for the other one" and "mine".
local M = {}
ns.Mail = M

local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12
local MAX_RECEIVE = ATTACHMENTS_MAX_RECEIVE or 16
local KEEP_DAYS = 30            -- a parcel nobody sent is forgotten after this long
local SETTLE = 600              -- seconds before a parcel missing from the mail is taken as gone
local MAX_BUTTONS = 6           -- characters with parcels the mailbox lists at once
local STEP = 0.1                -- seconds between two attachments
local WATCH = 0.2               -- seconds between two looks at the game's mail window

-- The strip under the mail window: its width, its margin, how far down its buttons begin, and
-- the height of a button and the room between two.
local WIDTH, EDGE, TOP = 320, 10, 36
local BUTTON_HEIGHT, BUTTON_GAP = 22, 4

-- The game writes a full name with this between the name and the surname.
local SEPARATOR = Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR

local panel
local sending           -- the letter that went out and has not been answered yet (see SendMail below)
local inboxRead         -- the game has listed the mail since the mailbox was opened

-- A parcel and the item in the bags are the same thing when the player would say so.
local ItemKey = ns.ItemKey

local function Parcels()
    local account = ns.account
    if type(account.parcels) ~= "table" then account.parcels = {} end
    return account.parcels
end

-- The name a letter to the character is addressed to.
function M.Address(card)
    if type(card.last) == "string" and card.last ~= "" then return card.name .. SEPARATOR .. card.last end
    return card.name
end

-- Writes a purchase down as a parcel for `who` (a card from Roster), held by the character
-- being played.
function M.Bought(offer, who)
    local me = ns.Roster.Me()
    if not who or not me or who == me then return end
    local parcels = Parcels()
    parcels[#parcels + 1] = {
        to = who.key, from = me.key, link = offer.link, itemID = offer.itemID, name = offer.name, at = time(),
    }
end

-- The unbound items in the bags, by item key: { { bag, slot, locked }, ... } for each. A
-- locked item is one the player put into the letter being written: it stays in its place in
-- the bags until the letter goes.
local function Bags()
    local out = {}
    local container = C_Container
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, container.GetContainerNumSlots(bag) or 0 do
            local info = container.GetContainerItemInfo(bag, slot)
            local key = info and not info.isBound and ItemKey(info.hyperlink) or nil
            if key then
                local list = out[key]
                if not list then
                    list = {}
                    out[key] = list
                end
                list[#list + 1] = { bag = bag, slot = slot, locked = info.isLocked and true or false }
            end
        end
    end
    return out
end

-- Takes a place of the item out of `places`: one that is not locked, or (locked = true) one
-- that is. nil when there is none.
local function TakePlace(places, locked)
    for i = #(places or {}), 1, -1 do
        if places[i].locked == locked then return table.remove(places, i) end
    end
end

-- The items in the mail the game has listed, by item key: how many of each. nil while the
-- game has not listed it, or lists only a part of it (a mailbox holds more letters than the
-- game shows at once).
local function Inbox()
    if not inboxRead or not (GetInboxNumItems and GetInboxItemLink) then return nil end
    local shown, total = GetInboxNumItems()
    if not shown or (total or shown) > shown then return nil end
    local out = {}
    for i = 1, shown do
        for j = 1, MAX_RECEIVE do
            local key = ItemKey(GetInboxItemLink(i, j))
            if key then out[key] = (out[key] or 0) + 1 end
        end
    end
    return out
end

-- The parcels the character being played holds, by the character they are for:
--   { { card = the one they are for, parcels = {...}, count = n,
--       ready = { [parcel] = { bag, slot } }, letter = { [parcel] = true } }, ... }
-- `ready` has the parcels that are in the bags, each with a place of its own; `letter` those
-- already in the letter being written. `count` is the two together. Parcels that are too old,
-- or for a character that is no longer remembered, are dropped on the way.
function M.Pending()
    local me = ns.Roster.Me()
    local out, byKey = {}, {}
    if not me then return out end
    local parcels = Parcels()
    local bags = Bags()
    local oldest = time() - KEEP_DAYS * 86400
    for i = #parcels, 1, -1 do
        local parcel = parcels[i]
        local card = type(parcel) == "table" and ns.Roster.Get(parcel.to) or nil
        if not card or (parcel.at or 0) < oldest then
            table.remove(parcels, i)
        elseif parcel.from == me.key and card.realm == me.realm then
            -- (A letter does not go to another realm; such a parcel waits for nothing here.)
            local group = byKey[card.key]
            if not group then
                group = { card = card, parcels = {}, ready = {}, letter = {}, count = 0 }
                byKey[card.key] = group
                out[#out + 1] = group
            end
            table.insert(group.parcels, 1, parcel)
        end
    end
    -- First the copies that can still be put into a letter, then those already in it.
    for _, locked in ipairs({ false, true }) do
        for g = 1, #out do
            local group = out[g]
            for i = 1, #group.parcels do
                local parcel = group.parcels[i]
                if not group.ready[parcel] and not group.letter[parcel] then
                    local place = TakePlace(bags[ItemKey(parcel.link) or ""], locked)
                    if place then
                        if locked then group.letter[parcel] = true else group.ready[parcel] = place end
                        group.count = group.count + 1
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.card.key < b.card.key end)
    return out
end

local function MailOpen()
    return MailFrame ~= nil and MailFrame:IsShown()
end

-- What the letter being written holds: its first empty place for an item, and whether it
-- has any item at all.
local function Letter(used)
    local free, any = nil, false
    for i = 1, MAX_ATTACH do
        local name, itemID = GetSendMailItem(i)
        if name or itemID then
            any = true
        elseif not free and not (used and used[i]) then
            free = i
        end
    end
    return free, any
end

-- Puts the group's parcels that are in the bags into a letter to its character.
local function Attach(group)
    local card = group.card
    local to = M.Address(card)
    local name = ns.Roster.Colored(card, card.name)
    -- The Send Mail page takes a right-clicked item as an attachment only while it is up.
    if MailFrameTab2 and MailFrameTab2.Click then MailFrameTab2:Click() end
    C_Timer.After(0.2, function()
        if not MailOpen() then return end
        local _, any = Letter()
        local written = SendMailNameEditBox and SendMailNameEditBox:GetText() or ""
        -- Never into a letter that is going to someone else.
        if any and written ~= "" and written:lower() ~= to:lower() then
            ns.Print(L.MAIL_BUSY:format(written))
            return
        end
        -- The bags as they are now: a letter sent or the bags sorted since the mailbox was
        -- opened must not put the wrong thing in.
        local fresh
        for _, now in ipairs(M.Pending()) do
            if now.card == card then fresh = now end
        end
        local queue = {}
        for i = 1, fresh and #fresh.parcels or 0 do
            local parcel = fresh.parcels[i]
            if fresh.ready[parcel] then queue[#queue + 1] = { parcel = parcel, place = fresh.ready[parcel] } end
        end
        if #queue == 0 then
            -- (Everything at hand may be in the letter already: then there is nothing to say.)
            if not (fresh and next(fresh.letter)) then ns.Print(L.MAIL_NONE:format(name)) end
            return
        end
        if SendMailNameEditBox then SendMailNameEditBox:SetText(to) end
        if SendMailSubjectEditBox and (SendMailSubjectEditBox:GetText() or "") == "" then
            SendMailSubjectEditBox:SetText("Upgrade Scout")
        end

        local done, waits, used = 0, 0, {}
        local function Next()
            if not MailOpen() then return end
            local item = queue[1]
            local free = Letter(used)
            if not item or not free then
                ns.Print((item and L.MAIL_FULL or L.MAIL_DONE):format(done, name))
                return
            end
            -- Something is still on the cursor (the player's own doing): a moment later.
            if CursorHasItem() then
                waits = waits + 1
                if waits <= 10 then
                    C_Timer.After(STEP, Next)
                else
                    ns.Print(L.MAIL_DONE:format(done, name))
                end
                return
            end
            table.remove(queue, 1)
            local info = C_Container.GetContainerItemInfo(item.place.bag, item.place.slot)
            if info and not info.isLocked and ItemKey(info.hyperlink) == ItemKey(item.parcel.link) then
                C_Container.UseContainerItem(item.place.bag, item.place.slot)
                used[free] = true
                done = done + 1
            end
            C_Timer.After(STEP, Next)
        end
        Next()
    end)
end

-- Takes the group's parcels out of the record: the player has seen to them otherwise.
local function Forget(group)
    local parcels = Parcels()
    for i = #parcels, 1, -1 do
        for j = 1, #group.parcels do
            if parcels[i] == group.parcels[j] then
                table.remove(parcels, i)
                break
            end
        end
    end
    ns.Print(L.MAIL_FORGOT:format(ns.Roster.Colored(group.card, group.card.name)))
end

---------------------------------------------------------------------------
-- The buttons under the mailbox
---------------------------------------------------------------------------
local function ButtonOnEnter(button)
    local group = button.group
    if not group then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, L.MAIL_TITLE)
    for i = 1, #group.parcels do
        local parcel = group.parcels[i]
        if group.ready[parcel] then
            GameTooltip_AddHighlightLine(GameTooltip, parcel.link)
        elseif group.letter[parcel] then
            GameTooltip_AddHighlightLine(GameTooltip, parcel.link .. " " .. L.MAIL_IN_LETTER)
        else
            GameTooltip_AddDisabledLine(GameTooltip, parcel.link .. " " .. L.MAIL_NOT_IN_BAGS)
        end
    end
    GameTooltip_AddBlankLineToTooltip(GameTooltip)
    GameTooltip_AddNormalLine(GameTooltip, L.MAIL_TIP:format(ns.Roster.Colored(group.card, group.card.name)))
    GameTooltip:Show()
end

local function ButtonOnClick(button, mouse)
    local group = button.group
    if not group then return end
    if mouse == "RightButton" then
        Forget(group)
        M.Refresh()
    elseif group.count > 0 then
        Attach(group)
    else
        ns.Print(L.MAIL_NONE:format(ns.Roster.Colored(group.card, group.card.name)))
    end
end

local function Build()
    -- A frame of its own beside the game's mail window, not a part of it: nothing of the
    -- addon's then runs inside the game's own mail code. It has the look of the addon's tabs
    -- (Widgets.lua): a dark plate in a gold edge, the addon's emblem and a gold title, a
    -- button in a gold rim for each character.
    local W = ns.Widgets
    panel = CreateFrame("Frame", "UpgradeScoutMailFrame", UIParent)
    panel:SetSize(WIDTH, TOP)
    -- Above what other addons keep at that spot of the screen (a guide, the bags), and on it.
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:Hide()
    W.NewSlices(panel, "Panel", 0.375, 12, "BACKGROUND", 0, 1.5)
    local emblem = panel:CreateTexture(nil, "ARTWORK")
    emblem:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\icon")
    emblem:SetSize(16, 16)
    emblem:SetPoint("LEFT", panel, "TOPLEFT", EDGE, -EDGE - 8)
    panel.Title = W.NewText(panel, 11, W.GOLD)
    panel.Title:SetPoint("LEFT", emblem, "RIGHT", 6, 0)
    panel.Title:SetPoint("RIGHT", panel, "TOPRIGHT", -EDGE, -EDGE - 8)
    panel.Title:SetText(L.MAIL_TITLE)
    local rule = W.NewRule(panel)
    rule:SetPoint("TOPLEFT", panel, "TOPLEFT", EDGE - 4, -(TOP - 6))
    rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(EDGE - 4), -(TOP - 6))
    panel.Buttons = {}
    for i = 1, MAX_BUTTONS do
        local button = W.NewButton(panel, WIDTH - 2 * EDGE, BUTTON_HEIGHT, "ButtonDark", 11)
        button.Label:SetWidth(WIDTH - 2 * EDGE - 16)
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", EDGE, -(TOP + (i - 1) * (BUTTON_HEIGHT + BUTTON_GAP)))
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", ButtonOnClick)
        button:SetScript("OnEnter", ButtonOnEnter)
        button:SetScript("OnLeave", GameTooltip_Hide)
        panel.Buttons[i] = button
    end
end

-- Shows a button for every character that has parcels here, while a mailbox is open.
function M.Refresh()
    if not MailOpen() then
        if panel then panel:Hide() end
        return
    end
    local groups = M.Pending()
    if #groups == 0 then
        if panel then panel:Hide() end
        return
    end
    if not panel then Build() end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", MailFrame, "BOTTOMLEFT", 4, -6)
    for i = 1, MAX_BUTTONS do
        local button, group = panel.Buttons[i], groups[i]
        button.group = group
        button:SetShown(group ~= nil)
        if group then
            button.Label:SetText(L.MAIL_TO:format(ns.Roster.Colored(group.card, group.card.name), group.count, #group.parcels))
        end
    end
    -- The plate is as tall as the buttons it holds.
    local shown = math.min(#groups, MAX_BUTTONS)
    panel:SetHeight(TOP + shown * (BUTTON_HEIGHT + BUTTON_GAP) - BUTTON_GAP + EDGE)
    panel:Show()
end

local RefreshSoon = ns.Soon(0.3, function() M.Refresh() end)

---------------------------------------------------------------------------
-- Letters going out
---------------------------------------------------------------------------
-- Whatever sends a letter calls the game's SendMail, the game's own Send button as well. What
-- the letter holds is read right then, while its items are still in it; the game says a
-- moment later whether it went (MAIL_SEND_SUCCESS). Each item that went strikes off a parcel
-- of the same item, the one for the character the letter went to if there is one. A parcel
-- is struck off only where more parcels of the item are left than copies at hand: an item the
-- player had twice and sent the other copy of (their own, say) leaves its parcel standing.
local function Squash(text)
    return (tostring(text or ""):gsub("%s+", ""):lower())
end

-- Whether a letter to `recipient` (as the player wrote it: with or without the surname, with
-- a realm after a "-" or without) is a letter to the character the parcel is for.
local function IsFor(parcel, recipient)
    local card = ns.Roster.Get(parcel.to)
    if not card then return false end
    local to = Squash(recipient):gsub("%-.*$", "")
    return to == Squash(card.name) or to == Squash(M.Address(card))
end

local function ReadLetter(recipient)
    sending = nil
    if issecretvalue and issecretvalue(recipient) then return end
    local bags = Bags()
    local items = {}
    for i = 1, GetSendMailItemLink and MAX_ATTACH or 0 do
        local key = ItemKey(GetSendMailItemLink(i))
        if key then items[#items + 1] = key end
    end
    -- (Should the game have emptied the letter before this runs, its items are still the
    -- locked ones in the bags.)
    if #items == 0 then
        for key, places in pairs(bags) do
            for _, place in ipairs(places) do
                if place.locked then items[#items + 1] = key end
            end
        end
    end
    if #items == 0 then return end
    -- What is left at hand of each once the letter has gone: the copies in the bags that are
    -- not in it, and those in the mail.
    local inbox = Inbox() or {}
    local left = {}
    for _, key in ipairs(items) do
        local free = 0
        for _, place in ipairs(bags[key] or {}) do
            if not place.locked then free = free + 1 end
        end
        left[key] = free + (inbox[key] or 0)
    end
    sending = { to = recipient, items = items, left = left }
end
if SendMail then hooksecurefunc("SendMail", ReadLetter) end

local function LetterSent()
    local letter = sending
    sending = nil
    local me = ns.Roster.Me()
    if not letter or not me then return end
    local parcels = Parcels()
    for _, key in ipairs(letter.items) do
        local mine = {}
        for i = 1, #parcels do
            local parcel = parcels[i]
            if type(parcel) == "table" and parcel.from == me.key and ItemKey(parcel.link) == key then
                mine[#mine + 1] = i
            end
        end
        if #mine > letter.left[key] then
            local index = mine[1]           -- the oldest, unless one is for the addressee
            for _, i in ipairs(mine) do
                if IsFor(parcels[i], letter.to) then
                    index = i
                    break
                end
            end
            table.remove(parcels, index)
        end
    end
    -- (The bags tell of the letter a moment later.)
    RefreshSoon()
end

-- A parcel whose item is nowhere this character could send it from went some other way:
-- sold, put on, given away, or sent before the addon could see the letter. Once the game has
-- listed all the mail after the mailbox was opened, such parcels are struck off: where more
-- parcels of an item are left than copies in the bags (in the letter being written too), the
-- mail and the bank, the oldest go. Only once a visit, before the player has taken anything
-- out (an item on its way from the mail to the bags is in neither for a moment), and never a
-- parcel bought within the last minutes, whose letter may still be on its way.
local function Banked(itemID)
    if not (itemID and C_Item.GetItemCount) then return 0 end
    return math.max(0, C_Item.GetItemCount(itemID, true) - C_Item.GetItemCount(itemID))
end

local function Settle()
    local inbox, me = Inbox(), ns.Roster.Me()
    if not inbox or not me then return end
    local bags = Bags()
    local byKey = {}
    local parcels = Parcels()
    for i = 1, #parcels do
        local parcel = parcels[i]
        local key = type(parcel) == "table" and parcel.from == me.key and ItemKey(parcel.link) or nil
        if key then
            byKey[key] = byKey[key] or {}
            table.insert(byKey[key], parcel)
        end
    end
    local oldest = time() - SETTLE
    local gone = {}
    for key, list in pairs(byKey) do
        -- The newest are taken to be the copies at hand; the oldest are the ones missing.
        table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
        local have = #(bags[key] or {}) + (inbox[key] or 0) + Banked(list[1].itemID)
        for i = have + 1, #list do
            if (list[i].at or 0) < oldest then gone[list[i]] = true end
        end
    end
    for i = #parcels, 1, -1 do
        if gone[parcels[i]] then table.remove(parcels, i) end
    end
end

---------------------------------------------------------------------------
-- The strip and the mail window
---------------------------------------------------------------------------
-- The strip follows the game's mail window while a mailbox is open. The window may come up a
-- moment after the game says a mailbox is open, or later still, and the game hides it while
-- another window takes its place. A frame of the addon's own looks at it a few times a
-- second: nothing of the addon's runs inside the game's mail code.
local watcher = CreateFrame("Frame")
watcher:Hide()
local seen, since = false, 0
watcher:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < WATCH then return end
    since = 0
    local open = MailOpen()
    if open ~= seen then
        seen = open
        M.Refresh()
    end
end)

local settled               -- Settle has had its turn on this visit
local SettleSoon = ns.Soon(0.5, function()
    if settled or not watcher:IsShown() then return end
    settled = true
    Settle()
    M.Refresh()
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.Listen("GEAR_BOUGHT", M.Bought)

ns.On("MAIL_SHOW", function()
    inboxRead, settled = false, false
    seen, since = MailOpen(), 0
    watcher:Show()
    M.Refresh()
end)

-- The game has listed the mail (on opening, and whenever something is taken out of it).
ns.On("MAIL_INBOX_UPDATE", function()
    if not watcher:IsShown() then return end
    inboxRead = true
    SettleSoon()
    RefreshSoon()
end)

-- The bags change all day long; the strip follows them at a mailbox.
ns.On("BAG_UPDATE", function()
    if MailOpen() then RefreshSoon() end
end)

ns.On("MAIL_CLOSED", function()
    watcher:Hide()
    inboxRead = false
    if panel then panel:Hide() end
end)

ns.On("MAIL_SEND_SUCCESS", LetterSent)
-- (MAIL_FAILED is not listened for: it is said of any mail matter that goes wrong, not only
-- of a letter. A letter that did not go leaves its items in the bags, and the next letter
-- sent is read anew.)
