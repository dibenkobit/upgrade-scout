local _, ns = ...

-- An arrow on the icon of an item in the bags or the bank that is an upgrade for the character
-- being played: on the profile in use its line in the item's tooltip is green
-- (Tooltip.Upgrade). The arrow is green when nothing in the item's tooltip is red, so the
-- character can put it on now, and grey when the one red line is the level it asks for: an
-- upgrade to keep for later. Anything else in red (a class, a skill, a reputation, armor not
-- learned) and there is no arrow.
-- With Pawn scoring (Score.Engine) the arrows stay, and go by the Pawn scale in use: Pawn's
-- own arrow does not reach the bags of this game.
-- The arrow is the game's own, the one its bag slots have a place for and Forever leaves
-- unused. It is drawn on a texture of our own in that place: another addon that shows or
-- hides the game's does not take ours with it.
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

-- "now" when the item gets the green arrow, "later" when it gets the grey one, false when it
-- gets none, nil while that cannot be told yet.
function B.Arrow(link)
    -- Switched off in the welcome window: no item gets one.
    if not ns.Shows("arrows") then return false end
    local upgrade = ns.Tooltip.Upgrade(link)
    if not upgrade then return upgrade end
    return Wearable(link)
end

---------------------------------------------------------------------------
-- The arrows
---------------------------------------------------------------------------
local pending = false           -- an item on view could not be judged yet
local retries, retryQueued = 0, false
local MarkAll

-- Shows or hides the arrow on an item button for the item it holds (link nil: none).
local function Mark(button, link)
    local kind = false
    if link then
        kind = B.Arrow(link)
        if kind == nil then pending = true end
    end
    local arrow = button.UpgradeScoutArrow
    if kind and not arrow then
        arrow = button:CreateTexture(nil, "OVERLAY", nil, 1)
        arrow:SetAtlas(ATLAS, true)
        arrow:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        button.UpgradeScoutArrow = arrow
    end
    if arrow then
        arrow:SetShown(kind and true or false)
        arrow:SetDesaturated(kind == "later")
    end
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

local function MarkBag(frame)
    for _, button in frame:EnumerateValidItems() do
        local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
        Mark(button, info and info.hyperlink)
    end
end

-- A slot of the bank holds what it read last (BankPanelItemButtonMixin:RefreshItemInfo).
local function MarkBankButton(button)
    local info = button.itemInfo
    Mark(button, info and info.hyperlink)
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

-- The arrows switched on or off in the welcome window: they come or go at once.
ns.Listen("SETTING_CHANGED", function(part)
    if part ~= "arrows" then return end
    retries = 0
    MarkAll()
end)
