local ADDON, ns = ...

-- The look of the addon's tabs, and the parts they are put together from.
--
-- The look is the addon's own: a dark plate in a fine gold edge, headings in gold capitals,
-- buttons in gold rims. Its art is the textures in Media, drawn by scripts/make-textures.py at
-- two texture pixels per window unit; frames and buttons are cut in nine, so one small picture
-- serves any size (see NewSlices).
-- Nothing in this file knows what a tab is for: UI.lua makes the tabs out of these parts.
local Widgets = {}
ns.Widgets = Widgets

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- Colours of the text.
local GOLD, GOLD_DIM = { 1.00, 0.83, 0.32 }, { 0.76, 0.61, 0.32 }
local CREAM, SOFT, MUTED = { 0.95, 0.91, 0.83 }, { 0.74, 0.70, 0.63 }, { 0.54, 0.50, 0.45 }
local GREEN = { 0.45, 0.92, 0.38 }

-- The font files the tabs write with: the game's standard one for words, and the narrow one it
-- writes numbers and auction lists in. They are asked for when a text is made, not when this
-- file loads: by then the game has settled on its fonts for the player's language, and so has
-- any addon that replaces them.
local function TextFont()
    return STANDARD_TEXT_FONT
end

local function NumberFont()
    return (Number13FontWhite:GetFont())
end

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
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
    if name then texture:SetTexture(File(name)) end
    return texture
end

-- A fine line that fades out at both ends, one screen pixel thick at any interface scale.
local function NewLine(parent, layer)
    local line = parent:CreateTexture(nil, layer or "ARTWORK")
    line:SetTexture(File("Line"))
    PixelUtil.SetHeight(line, 1, 1)
    return line
end

-- The gold rule that sets a part of a plate off from the rest.
local function NewRule(parent)
    local rule = NewLine(parent)
    rule:SetVertexColor(0.80, 0.60, 0.26, 0.55)
    return rule
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
    text:SetFont(narrow and NumberFont() or TextFont(), size, "")
    text:SetTextColor(color[1], color[2], color[3])
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    return text
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

Widgets.GOLD, Widgets.GOLD_DIM, Widgets.CREAM, Widgets.SOFT, Widgets.MUTED, Widgets.GREEN = GOLD, GOLD_DIM, CREAM, SOFT, MUTED, GREEN
Widgets.NumberFont = NumberFont
Widgets.File, Widgets.NewTexture, Widgets.NewLine, Widgets.NewRule = File, NewTexture, NewLine, NewRule
Widgets.NewSlices, Widgets.NewText = NewSlices, NewText
Widgets.NewButton, Widgets.NewBar, Widgets.SetBar = NewButton, NewBar, SetBar
