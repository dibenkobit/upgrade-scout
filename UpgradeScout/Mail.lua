local _, ns = ...
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
-- Only gear is followed. Consumables stack with what the player already has, and a stack
-- cannot be told apart into "bought for the other one" and "mine".
local M = {}
ns.Mail = M

local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12
local KEEP_DAYS = 30            -- a parcel nobody sent is forgotten after this long
local MAX_BUTTONS = 6           -- characters with parcels the mailbox lists at once
local STEP = 0.1                -- seconds between two attachments

-- The game writes a full name with this between the name and the surname.
local SEPARATOR = Constants and Constants.CharacterNameSeparatorConsts
    and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "

local panel
local attached          -- the parcels put into the letter that is being written: { to = key, parcels = {...} }
local refreshing = false

-- An item by what the player sees of it: its number and its name, suffix and all. The other
-- fields of a link (the level of the one looking, for one) change without the item changing.
local function ItemKey(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("item:(%d+)")
    if not id then return nil end
    return id .. ":" .. (link:match("%[(.-)%]") or "")
end

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

-- The unbound items in the bags, by item key: { { bag, slot }, ... } for each.
local function Bags()
    local out = {}
    local container = C_Container
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, container.GetContainerNumSlots(bag) or 0 do
            local info = container.GetContainerItemInfo(bag, slot)
            local key = info and not info.isBound and not info.isLocked and ItemKey(info.hyperlink) or nil
            if key then
                local list = out[key]
                if not list then
                    list = {}
                    out[key] = list
                end
                list[#list + 1] = { bag = bag, slot = slot }
            end
        end
    end
    return out
end

-- The parcels the character being played holds, by the character they are for:
--   { { card = the one they are for, parcels = {...}, ready = { [parcel] = { bag, slot } } }, ... }
-- `ready` has the parcels that are in the bags, each with a place of its own. Parcels that
-- are too old, or for a character that is no longer remembered, are dropped on the way.
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
                group = { card = card, parcels = {}, ready = {}, count = 0 }
                byKey[card.key] = group
                out[#out + 1] = group
            end
            table.insert(group.parcels, 1, parcel)
        end
    end
    for g = 1, #out do
        local group = out[g]
        for i = 1, #group.parcels do
            local parcel = group.parcels[i]
            local places = bags[ItemKey(parcel.link) or ""]
            if places and #places > 0 then
                group.ready[parcel] = table.remove(places)
                group.count = group.count + 1
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
        if not fresh or fresh.count == 0 then
            ns.Print(L.MAIL_NONE:format(name))
            return
        end
        local queue = {}
        for i = 1, #fresh.parcels do
            local parcel = fresh.parcels[i]
            if fresh.ready[parcel] then queue[#queue + 1] = { parcel = parcel, place = fresh.ready[parcel] } end
        end
        if SendMailNameEditBox then SendMailNameEditBox:SetText(to) end
        if SendMailSubjectEditBox and (SendMailSubjectEditBox:GetText() or "") == "" then
            SendMailSubjectEditBox:SetText("Upgrade Scout")
        end

        attached = { to = card.key, parcels = {} }
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
            if CursorHasItem and CursorHasItem() then
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
                attached.parcels[#attached.parcels + 1] = item.parcel
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
    -- addon's then runs inside the game's own mail code.
    panel = CreateFrame("Frame", "UpgradeScoutMailFrame", UIParent)
    panel:SetSize(320, 24)
    panel:Hide()
    panel.Title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.Title:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, 0)
    panel.Title:SetText(L.MAIL_TITLE)
    panel.Buttons = {}
    for i = 1, MAX_BUTTONS do
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(320, 22)
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(16 + (i - 1) * 24))
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", ButtonOnClick)
        button:SetScript("OnEnter", ButtonOnEnter)
        button:SetScript("OnLeave", GameTooltip_Hide)
        panel.Buttons[i] = button
    end
end

-- Shows a button for every character that has parcels here, while a mailbox is open.
function M.Refresh()
    refreshing = false
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
            button:SetText(L.MAIL_TO:format(ns.Roster.Colored(group.card, group.card.name), group.count, #group.parcels))
        end
    end
    panel:Show()
end

local function RefreshSoon()
    if refreshing or not MailOpen() then return end
    refreshing = true
    C_Timer.After(0.3, M.Refresh)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.Listen("GEAR_BOUGHT", M.Bought)

ns.On("MAIL_SHOW", M.Refresh)
ns.On("BAG_UPDATE", RefreshSoon)

ns.On("MAIL_CLOSED", function()
    attached = nil
    if panel then panel:Hide() end
end)

-- A letter went out. The parcels that were put into it and are in the bags no more have gone
-- with it; one the player took out again is still a parcel.
ns.On("MAIL_SEND_SUCCESS", function()
    local sent = attached
    attached = nil
    if not sent then return end
    C_Timer.After(0.5, function()
        local bags = Bags()
        local parcels = Parcels()
        for i = #parcels, 1, -1 do
            for j = 1, #sent.parcels do
                if parcels[i] == sent.parcels[j] then
                    local places = bags[ItemKey(parcels[i].link) or ""]
                    if places and #places > 0 then
                        table.remove(places)        -- still here: it was taken out of the letter
                    else
                        table.remove(parcels, i)
                    end
                    break
                end
            end
        end
        M.Refresh()
    end)
end)

ns.On("MAIL_FAILED", function()
    attached = nil
end)
