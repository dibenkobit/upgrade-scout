local _, ns = ...

-- An arrow on the icon of an item in the bags or the bank that is an upgrade for the character
-- being played: on the profile in use its line in the item's tooltip is green
-- (Tooltip.Upgrade). The arrow is green when nothing in the item's tooltip is red, so the
-- character can put it on now, and grey when the one red line is the level it asks for: an
-- upgrade to keep for later. Anything else in red (a class, a skill, a reputation, armor not
-- learned) and there is no arrow.
-- With Pawn scoring (Score.Engine) the arrows stay, and go by the Pawn scale in use: Pawn's
-- own arrow does not reach the bags of this game.
-- With Forever Companion scoring they give way to its own: it draws an arrow on an upgrade
-- in the bags and the bank itself, by the same scale, and two on one icon would say one
-- thing twice. Where its arrows are switched off in its options, ours are drawn, by its
-- scale in use (Score.DrawsArrows). The same with Forever Leveling BiS scoring, in the bags:
-- it draws none in the bank, and there ours stay.
-- The arrow is the game's own, the one its bag slots have a place for and Forever leaves
-- unused. It is drawn on a texture of our own in that place: another addon that shows or
-- hides the game's does not take ours with it.
-- Where another addon shows the bags and the bank in windows of its own, the slots of those
-- get the same arrow by the same rule, once a file that knows the addon says what they show
-- (B.Other; for EllesmereUI that is Ellesmere.lua).
local B = {}
ns.Bags = B

local ATLAS = "bags-greenarrow"
local RETRIES = 10              -- times the items not yet judged are looked at again
local RETRY_DELAY = 1           -- seconds between those times

local REQUIREMENT = Enum.TooltipDataLineType.UsageRequirement
local LEVEL = Enum.TooltipDataUsageRequirementType.Level

-- When the character can put an item on, by link: "now", "later" (when it has the level the
-- item asks for) or false; kept until the level, the gear, the spells or the skills change.
local wearable = {}

local function Wearable(link)
    local known = wearable[link]
    if known ~= nil then return known end
    local data = C_TooltipInfo.GetHyperlink(link)
    local lines = data and data.lines
    local name = lines and lines[1] and lines[1].leftText
    if not name or name == "" or name == RETRIEVING_ITEM_INFO then return nil end
    known = "now"
    for i = 2, #lines do
        local line = lines[i]
        if ns.IsRedLine(line) then
            if line.type == REQUIREMENT and line.requirementType == LEVEL then
                known = "later"
            else
                known = false
                break
            end
        end
    end
    wearable[link] = known
    return known
end

-- Is the item one the character has asked not to be offered, in the Filters menu of the
-- Upgrades tab (see Wants.lua)? Armor of a lighter kind than "Best armor type for the class"
-- keeps, a kind of weapon it left out, a two-hander for one that fills its hands with a
-- weapon for one hand and a shield, or the other way about. What the list at the auction
-- house leaves out for that gets no arrow either.
local function Unwanted(link)
    return not ns.Wants.FitsLink(ns.Wants.Of(ns.Roster.Me()), link)
end

-- "now" when the item gets the green arrow, "later" when it gets the grey one, false when it
-- gets none, nil while that cannot be told yet.
-- where: "bank" for an item in the bank; nil for one in the bags.
-- addon: whose windows the item is in, where they are not the game's own ("ellesmere").
function B.Arrow(link, where, addon)
    -- Switched off in the welcome window: no item gets one.
    if not ns.Shows("arrows") then return false end
    -- The addon that scores draws its own there: none of ours beside them.
    if ns.Score.DrawsArrows(where, addon) then return false end
    local upgrade = ns.Tooltip.Upgrade(link)
    if not upgrade then return upgrade end
    if Unwanted(link) then return false end
    return Wearable(link)
end

---------------------------------------------------------------------------
-- The arrows
---------------------------------------------------------------------------
local pending = false           -- an item on view could not be judged yet
local retries, retryQueued = 0, false
local MarkAll

-- What B.Arrow says of the item a slot holds (link nil: none, and no arrow), with a note of
-- an item that could not be judged yet.
local function Kind(link, where, addon)
    if not link then return false end
    local kind = B.Arrow(link, where, addon)
    if kind == nil then pending = true end
    return kind
end

-- An arrow as that says: green, grey, or out of sight.
local function Paint(arrow, kind)
    arrow:SetShown(kind and true or false)
    arrow:SetDesaturated(kind == "later")
end

-- Shows or hides the arrow on an item button of the game's for the item it holds (link nil:
-- none).
-- where: "bank" for a slot of the bank.
local function Mark(button, link, where)
    local kind = Kind(link, where)
    local arrow = button.UpgradeScoutArrow
    if kind and not arrow then
        arrow = button:CreateTexture(nil, "OVERLAY", nil, 1)
        arrow:SetAtlas(ATLAS, true)
        arrow:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        button.UpgradeScoutArrow = arrow
    end
    if arrow then Paint(arrow, kind) end
end

-- An item not judged yet (the game still loads it, or what is worn): a look again in a moment.
local function AfterMarking()
    if not pending or retryQueued or retries >= RETRIES then return end
    retryQueued = true
    retries = retries + 1
    C_Timer.After(RETRY_DELAY, function()
        retryQueued = false
        MarkAll()
    end)
end

---------------------------------------------------------------------------
-- The windows of another addon
---------------------------------------------------------------------------
-- An addon that shows the bags and the bank in windows of its own has slots of its own,
-- which the hooks further down never hear of. The file that knows such an addon is told by
-- it when a slot has been drawn, and says so here (B.Other). What each slot shows is kept
-- from then on, and its arrow once it has needed one: by the slot's button and not on it.
-- The button is one of the game's secure ones and the other addon's to write on, not ours;
-- the table does not keep a button that is no more.
-- With that kept, the arrows of such a window are put right here whenever the answers
-- change (MarkAll), as the game's are. The other addon is never asked to draw its window
-- again for it: that would have it sort and lay out every slot anew, for a change that is
-- nothing to it, and as often as an item is looked at again while the game loads it.
local theirs = setmetatable({}, { __mode = "k" })       -- [button] = { addon, place, host, link, where, arrow }

-- Shows or hides the arrow of such a slot for the item it shows. The arrow is a texture on
-- a frame of the other addon's that lies over the item's icon (slot.host): made when the
-- slot first needs one, and the same one for whatever the slot shows later.
local function MarkTheirs(slot)
    local kind = Kind(slot.link, slot.where, slot.addon)
    local arrow = slot.arrow
    if kind and not arrow then
        arrow = slot.host:CreateTexture(nil, "OVERLAY", nil, 1)
        arrow:SetAtlas(ATLAS)
        slot.place(arrow, slot.host)
        slot.arrow = arrow
    end
    if arrow then Paint(arrow, kind) end
end

-- The windows of another addon, for the file that knows it. Gives the function to call
-- whenever a slot of theirs has been drawn: Drawn(button, host, link, where).
--   addon    whose windows they are, as B.Arrow is asked: "ellesmere"
--   place    function(arrow, host): puts a slot's new arrow where it goes in such a window,
--            which need not be where the game's own slots have it
--   button   the slot's button
--   host     the frame of theirs over the item's icon, for the arrow to be drawn on: the
--            same one for a button every time
--   link     the item the slot shows now; nil for none
--   where    "bank" for a slot of the bank
function B.Other(addon, place)
    return function(button, host, link, where)
        local slot = theirs[button]
        if not slot then
            slot = { addon = addon, place = place }
            theirs[button] = slot
        end
        slot.host, slot.link, slot.where = host, link, where
        MarkTheirs(slot)
        AfterMarking()
    end
end

local function MarkBag(frame)
    for _, button in frame:EnumerateValidItems() do
        local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
        Mark(button, info and info.hyperlink)
    end
end

-- A slot of the bank holds what it read last (BankPanelItemButtonMixin:RefreshItemInfo).
local function MarkBankButton(button)
    local info = button.itemInfo
    Mark(button, info and info.hyperlink, "bank")
end

-- The game's bag windows: one for all the bags, or one for each.
local function BagFrames()
    local frames = {}
    if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
    local container = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
    for _, frame in ipairs(container or {}) do frames[#frames + 1] = frame end
    return frames
end

MarkAll = function()
    pending = false
    for _, frame in ipairs(BagFrames()) do
        if frame:IsShown() then MarkBag(frame) end
    end
    if BankPanel and BankPanel:IsShown() and BankPanel.EnumerateValidItems then
        for button in BankPanel:EnumerateValidItems() do MarkBankButton(button) end
    end
    -- The slots of another addon's windows, those in sight. One out of sight is left as it
    -- is, as a closed window of the game's is: nothing is judged for it, and its addon
    -- draws it, and says so, when its window opens. While the whole screen is hidden (by
    -- the player, or for a cinematic) nothing is in sight, open or not, and nothing opens
    -- when the screen comes back: then no slot is passed over.
    local hidden = not UIParent:IsShown()
    for _, slot in pairs(theirs) do
        if slot.link and (hidden or slot.host:IsVisible()) then MarkTheirs(slot) end
    end
    AfterMarking()
end

---------------------------------------------------------------------------
-- When
---------------------------------------------------------------------------
-- After the game has drawn the items of a bag window or of a slot of the bank. Its bag windows
-- are made before any addon is loaded, each with its own copy of the function that draws the
-- items: that copy is the one hooked. The bank makes its slots when it is first opened, and
-- every slot calls the function of BankPanelItemButtonMixin.
local hooked = {}

local function Hook()
    for _, frame in ipairs(BagFrames()) do
        if not hooked[frame] and frame.UpdateItems then
            hooked[frame] = true
            hooksecurefunc(frame, "UpdateItems", function(self)
                MarkBag(self)
                AfterMarking()
            end)
        end
    end
    if not hooked.bank and BankPanelItemButtonMixin and BankPanelItemButtonMixin.Refresh then
        hooked.bank = true
        hooksecurefunc(BankPanelItemButtonMixin, "Refresh", function(self)
            MarkBankButton(self)
            AfterMarking()
        end)
    end
end
Hook()
ns.On("PLAYER_LOGIN", Hook)

-- The gear, the level, the spells or the skills changed: every item is judged again. (The
-- answers of Tooltip.lua are forgotten on the same events, and its handlers run first.)
local MarkAllSoon = ns.Soon(0.2, function() MarkAll() end)

local function Changed()
    wearable = {}
    retries = 0
    MarkAllSoon()
end
ns.On("PLAYER_EQUIPMENT_CHANGED", Changed)
ns.On("SPELLS_CHANGED", Changed)
ns.On("SKILL_LINES_CHANGED", Changed)
ns.On("PLAYER_LEVEL_UP", function()
    Changed()
    -- The game may tell the new level a moment after the event (see Tooltip.lua).
    C_Timer.After(1.2, Changed)
end)

-- Another profile chosen for the character being played.
ns.Listen("PROFILE_CHANGED", function(card)
    if card ~= ns.Roster.Me() then return end
    retries = 0
    MarkAllSoon()
end)

-- Another one scores (the addon or Pawn), or Pawn's scales changed: an upgrade to the one
-- may be none to the other.
ns.Listen("SCORING_CHANGED", function()
    retries = 0
    MarkAllSoon()
end)

-- The character being played asks for another kind of armor or of weapon, or for any again
-- (Wants.lua).
ns.Listen("WANTS_CHANGED", function(card)
    if card ~= ns.Roster.Me() then return end
    retries = 0
    MarkAllSoon()
end)

-- The arrows switched on or off in the welcome window: they come or go at once. So they do
-- when Forever Companion's own are switched in its options, while it scores ("companion"),
-- or those of Forever Leveling BiS in its settings ("leveling").
ns.Listen("SETTING_CHANGED", function(part)
    if part ~= "arrows" and part ~= "companion" and part ~= "leveling" then return end
    retries = 0
    MarkAll()
end)
