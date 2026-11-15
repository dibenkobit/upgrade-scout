local ADDON, ns = ...
local L = ns.L

-- The button at the minimap, as addons have one: a click opens the addon's window
-- (Welcome.lua), where its settings are. The button can be dragged around the minimap and
-- stays where it was left, for every character of the account.
--
-- It is our own, drawn the way the game draws such buttons: the ring, and the addon's icon in
-- it. The addon brings no library for it. But many players have an addon that brings
-- LibDBIcon, and with it tools that gather the buttons of the minimap and know only the ones
-- that library made (Leatrix Plus is one). Where the library is there, it makes the button
-- instead of us: the same click, the same words, the same place. The same goes for
-- LibDataBroker and the bars that show its launchers. (Mastercraft does it this way.)

local ICON = "Interface\\AddOns\\" .. ADDON .. "\\icon"
local START = 175       -- where the button is to begin with: degrees around the minimap, 0 its right side and 90 its top
local OUT = 10          -- how far past the edge of the minimap the middle of the button is
local CROP = 0.10       -- the icon without its own gold frame: the ring is the frame here
local ZOOM = 0.04       -- and a little closer still, until the button is pressed

local button            -- the button at the minimap: our own, or the one LibDBIcon made
local place             -- ns.account.minimap: { minimapPos = the angle }, by LibDBIcon's names, which keeps it for its button

local function Click()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if ns.Welcome.IsShown() then ns.Welcome.Hide() else ns.Welcome.Show() end
end

-- What the button says of itself. The first line of a tooltip is its title.
local function Tip(tooltip)
    tooltip:AddLine("Upgrade Scout", 1, 1, 1)
    tooltip:AddLine(L.MINIMAP_CLICK)
    -- Only the button at the minimap can be dragged: a launcher on a bar stays in its place.
    if button and tooltip:GetOwner() == button then tooltip:AddLine(L.MINIMAP_DRAG) end
end

---------------------------------------------------------------------------
-- Our own button
---------------------------------------------------------------------------
-- Is the corner of the minimap round, for each quarter of it: right and left of the bottom,
-- right and left of the top. An addon that reshapes the minimap says which shape it gave it
-- (GetMinimapShape, a function such addons define; LibDBIcon goes by the same names).
local ROUND = {
    ["ROUND"] = { true, true, true, true }, ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true }, ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false }, ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true }, ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true }, ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true }, ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true }, ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

-- Puts the button on the edge of the minimap, at its angle. The size and the shape of the
-- minimap are read each time: the addons that change them do it when they please.
local function Place()
    local angle = math.rad(place.minimapPos)
    local x, y, quarter = math.cos(angle), math.sin(angle), 1
    if x < 0 then quarter = quarter + 1 end
    if y > 0 then quarter = quarter + 2 end
    local shape = GetMinimapShape and GetMinimapShape()
    local w, h = Minimap:GetWidth() / 2 + OUT, Minimap:GetHeight() / 2 + OUT
    if (ROUND[shape] or ROUND.ROUND)[quarter] then
        x, y = x * w, y * h
    else
        -- A square corner: along its two sides.
        local dw, dh = math.sqrt(2 * w * w) - 10, math.sqrt(2 * h * h) - 10
        x = math.max(-w, math.min(x * dw, w))
        y = math.max(-h, math.min(y * dh, h))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While the button is dragged: it goes to where the cursor is, seen from the middle of the
-- minimap.
local function Drag()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    place.minimapPos = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
    Place()
end

-- The icon stands a little closer than it is drawn, and steps back while the button is held
-- down: what a pressed button of the minimap looks like.
local function Zoom(icon, pressed)
    local cut = pressed and CROP or CROP + ZOOM
    icon:SetTexCoord(cut, 1 - cut, cut, 1 - cut)
end

local function Build()
    -- By this name the tools that gather the minimap's buttons tell whose it is.
    button = CreateFrame("Button", "UpgradeScoutMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- The game's own pictures for a button of the minimap: a dark ground, the icon, the ring
    -- over both. (The ring's picture has its ring in the top left corner.)
    local ground = button:CreateTexture(nil, "BACKGROUND")
    ground:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    ground:SetSize(24, 24)
    ground:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetTexture(ICON)
    button.Icon:SetSize(18, 18)
    button.Icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    Zoom(button.Icon, false)
    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(50, 50)
    ring:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    button:SetScript("OnClick", Click)
    button:SetScript("OnMouseDown", function(self) Zoom(self.Icon, true) end)
    button:SetScript("OnMouseUp", function(self) Zoom(self.Icon, false) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        Tip(GameTooltip)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", Drag)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    Place()
    -- On the edge again when the minimap changes its size, and a moment after the character
    -- is in the world: some addons reshape the minimap then, without a change of size.
    Minimap:HookScript("OnSizeChanged", Place)
    ns.On("PLAYER_ENTERING_WORLD", function()
        Place()
        C_Timer.After(1, Place)
        C_Timer.After(3, Place)
    end)
end

---------------------------------------------------------------------------
-- Whose button it is
---------------------------------------------------------------------------
-- At login: the saved place is read by then, and every addon has brought its libraries.
ns.On("PLAYER_LOGIN", function()
    if type(ns.account.minimap) ~= "table" then ns.account.minimap = {} end
    place = ns.account.minimap
    if type(place.minimapPos) ~= "number" then place.minimapPos = START end

    -- A launcher on the bars that show them, where an addon has brought the library for it.
    local brokers = LibStub("LibDataBroker-1.1", true)
    local launcher = brokers and brokers:NewDataObject(ADDON, {
        type = "launcher", label = "Upgrade Scout", tocname = ADDON,
        icon = ICON, iconCoords = { CROP, 1 - CROP, CROP, 1 - CROP },
        OnClick = Click, OnTooltipShow = Tip,
    })
    -- The button by LibDBIcon, where an addon has brought that; our own where none has, or
    -- where the library would not make one.
    local icons = LibStub("LibDBIcon-1.0", true)
    if launcher and icons and pcall(icons.Register, icons, ADDON, launcher, place) then
        button = icons:GetMinimapButton(ADDON)
        return
    end
    Build()
end)
