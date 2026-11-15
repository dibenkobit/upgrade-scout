local ADDON, ns = ...

-- The look of the addon's tabs, and the parts they are put together from.
--
-- The look is the addon's own: a dark plate in a fine gold edge, headings in gold capitals,
-- buttons in gold rims. Its art is the textures in Media, drawn by scripts/make-textures.py at
-- two texture pixels per window unit; frames and buttons are cut in nine, so one small picture
-- serves any size (see NewSlices).
-- Nothing in this file knows what a tab is for: UI.lua makes the tabs out of these parts, and
-- Mail.lua its strip at the mailbox.
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

-- The alphabets the game has fonts for, as its font families name them, and the one of the
-- client's own language where that is not the Latin one.
local ALPHABETS = { "roman", "korean", "simplifiedchinese", "traditionalchinese", "russian" }
local OWN_ALPHABET = { koKR = "korean", zhCN = "simplifiedchinese", zhTW = "traditionalchinese", ruRU = "russian" }

-- A font of the tabs': the file `file` at `size`, and for the alphabets that file is not for,
-- the files the game's own font `like` writes them with. A text set to one font file shows
-- squares for the letters the file lacks: the name of a Russian character on an English
-- client. A font family, which is what the game's own fonts are, takes the file that suits
-- what is written. Made once for a file and a size.
local families, familyCount = {}, 0
local function Family(file, size, like)
    local key = file .. "@" .. size
    local family = families[key]
    if not family then
        local own = OWN_ALPHABET[GetLocale()]
        local members = {}
        for i = 1, #ALPHABETS do
            local alphabet = ALPHABETS[i]
            local written = file
            -- The client's font has the letters of its own language and the Latin ones.
            if alphabet ~= "roman" and alphabet ~= own then
                local object = like:GetFontObjectForAlphabet(alphabet)
                written = object and object:GetFont() or file
            end
            members[i] = { alphabet = alphabet, file = written, height = size, flags = "" }
        end
        familyCount = familyCount + 1
        family = CreateFontFamily(ADDON .. "Font" .. familyCount, members)
        families[key] = family
    end
    return family
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function File(name)
    return MEDIA .. name
end

-- The game moves textures onto whole screen pixels. Pieces of one picture must meet edge to
-- edge at any interface scale instead.
local function Unsnap(texture)
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
    return texture
end

local function NewTexture(parent, name, layer, sublevel)
    local texture = Unsnap(parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0))
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
--   attach   where the pieces come from when the frame may not make textures of its own (a
--            menu of the game's: see MenuStyle); by default the frame makes them
-- Pieces are numbered row by row: 1 2 3, 4 5 6, 7 8 9.
local Slices = {}
Slices.__index = Slices

local function NewSlices(parent, name, corner, edge, layer, sublevel, outset, attach)
    local stops = { 0, corner, 1 - corner, 1 }
    local parts = {}
    for i = 1, 9 do
        local across, down = (i - 1) % 3 + 1, math.floor((i - 1) / 3) + 1
        local part
        if attach then
            part = Unsnap(attach())
            part:SetDrawLayer(layer or "ARTWORK", sublevel or 0)
        else
            part = NewTexture(parent, nil, layer, sublevel)
        end
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

-- A picture cut in three from top to bottom, for something narrow that is tall (the knob of a
-- scroll bar): the ends keep their height, the middle stretches. The picture is as wide as the
-- frame less `inset` on each side.
--   cap    the height of an end in the picture, as a share of the picture's height
--   edge   the height of an end on screen
local function NewColumn(parent, name, cap, edge, layer, sublevel, inset)
    inset = inset or 0
    local top = NewTexture(parent, nil, layer, sublevel)
    top.coords = { 0, 1, 0, cap }
    top:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, 0)
    top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -inset, 0)
    top:SetHeight(edge)
    local bottom = NewTexture(parent, nil, layer, sublevel)
    bottom.coords = { 0, 1, 1 - cap, 1 }
    bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", inset, 0)
    bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, 0)
    bottom:SetHeight(edge)
    local middle = NewTexture(parent, nil, layer, sublevel)
    middle.coords = { 0, 1, cap, 1 - cap }
    middle:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
    middle:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")

    local column = setmetatable({ parts = { top, middle, bottom } }, Slices)
    column:SetFile(name)
    return column
end

function Slices:SetFile(name)
    if self.file == name then return end
    self.file = name
    for _, part in ipairs(self.parts) do
        part:SetTexture(File(name))
        part:SetTexCoord(part.coords[1], part.coords[2], part.coords[3], part.coords[4])
    end
end

function Slices:SetVertexColor(r, g, b, a)
    for _, part in ipairs(self.parts) do part:SetVertexColor(r, g, b, a or 1) end
end

function Slices:SetDesaturated(desaturated)
    for _, part in ipairs(self.parts) do part:SetDesaturated(desaturated) end
end

function Slices:SetBlendMode(mode)
    for _, part in ipairs(self.parts) do part:SetBlendMode(mode) end
end

function Slices:SetShown(shown)
    for _, part in ipairs(self.parts) do part:SetShown(shown) end
end

-- Text in the game's own fonts, so that it reads right in every language and follows a font
-- the player has put in their place: the standard one for words, the narrow one the game
-- writes numbers and auction lists in for the rows. A name in another writing than the
-- client's (a character of the account, in the status line) is written with the game's font
-- for that writing: see Family. `color` is one of the tables above.
local function NewText(parent, size, color, justify, narrow)
    local text = parent:CreateFontString(nil, "ARTWORK")
    if narrow then
        text:SetFontObject(Family(NumberFont(), size, Number13FontWhite))
    else
        text:SetFontObject(Family(TextFont(), size, GameFontNormal))
    end
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

---------------------------------------------------------------------------
-- The game's own parts, in our colours
---------------------------------------------------------------------------
-- Where the game's part does work that is best left to it (scrolling, a menu), it stays, and
-- only its look is ours. Its own pictures are made see-through, not removed: the game goes on
-- setting them as the mouse comes and goes.

-- An arrow of a scroll bar: a gold chevron, grey while there is nothing more that way (the
-- game greys the whole button then, and ours is dimmed as well).
local function PaintStepper(button)
    button.Chevron:SetAlpha(button:IsEnabled() and 1 or 0.35)
end

local function SkinStepper(button, up)
    button.Texture:SetAlpha(0)
    local chevron = NewTexture(button, "Chevron", "ARTWORK")
    chevron:SetSize(14, 14)
    chevron:SetPoint("CENTER", button, "CENTER", 0, 0)
    chevron:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    local glow = NewTexture(button, "Chevron", "HIGHLIGHT")
    glow:SetSize(14, 14)
    glow:SetPoint("CENTER", button, "CENTER", 0, 0)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.85, 0.50, 0.6)
    if up then
        chevron:SetTexCoord(0, 1, 1, 0)
        glow:SetTexCoord(0, 1, 1, 0)
    end
    button.Chevron = chevron
    button:HookScript("OnEnable", PaintStepper)
    button:HookScript("OnDisable", PaintStepper)
    PaintStepper(button)
end

-- The game's MinimalScrollBar as a gold knob on a dark rail, with gold arrows.
local function SkinScrollBar(bar)
    local track = bar.Track
    local thumb = track.Thumb
    for _, region in ipairs({ track.Begin, track.Middle, track.End, thumb.Begin, thumb.Middle, thumb.End }) do
        region:SetAlpha(0)
    end
    -- The rail is narrower than the knob, which stands out on both sides of it.
    NewColumn(track, "ScrollTrack", 0.0625, 2, "BACKGROUND", 0, 2)
    NewColumn(thumb, "ScrollThumb", 0.125, 4, "ARTWORK")
    local glow = NewColumn(thumb, "ScrollThumb", 0.125, 4, "HIGHLIGHT")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 1, 1, 0.4)
    SkinStepper(bar.Back, true)
    SkinStepper(bar.Forward, false)
end

-- A menu the game opens for a dropdown of ours, on our plate. The game makes a menu out of a
-- "style": a table it copies onto the menu's frame, whose Generate draws the background and
-- whose two other functions say how far the lines keep from the edges. A dropdown takes its
-- style from its `menuMixin` field. On a menu's frame textures are not made but attached
-- (AttachTexture), so that the game can take them back when the menu closes.
-- The plate is drawn on a frame of its own inside the menu: an addon that restyles every menu
-- of the game repaints the menu's own textures, and leaves those of a frame inside it alone.
local MENU_INSET = { left = 11, top = 11, right = 11, bottom = 11 }
local MENU_PADDING = { width = 20, height = 0 }
local MenuStyle = {}

function MenuStyle:Generate()
    local plate = self:AttachFrame("Frame")
    plate:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    plate:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
    -- Under the lines of the menu, which are frames of their own as well.
    plate:SetFrameLevel(self:GetFrameLevel())
    NewSlices(plate, "Panel", 0.375, 12, "BACKGROUND", -8, 1.5, function() return plate:AttachTexture() end)
end

-- (Called on the menu's frame, which they have no need of.)
function MenuStyle.GetInset()
    return MENU_INSET
end

function MenuStyle.GetChildExtentPadding()
    return MENU_PADDING
end

-- A line of such a menu that can be chosen (root:CreateRadio), as the game has just drawn it:
-- a diamond where the game has its round mark, gold when the line is the one chosen and grey
-- when it is not, the light of our rows under the mouse, the words in our colours. Given to
-- the line with AddInitializer, so it runs after the game's own drawing every time the line
-- is shown. The game makes the second mark only for the line that is chosen.
local function SkinMenuLine(button)
    local mark, chosen = button.leftTexture1, button.leftTexture2
    if mark then
        mark:SetTexture(File("Diamond"))
        mark:SetTexCoord(0, 1, 0, 1)
        mark:SetSize(14, 14)
        mark:SetDesaturated(true)
        mark:SetAlpha(0.45)
    end
    if chosen then
        chosen:SetTexture(File("Diamond"))
        chosen:SetTexCoord(0, 1, 0, 1)
        chosen:SetSize(14, 14)
    end
    local glow = button.highlight
    if glow then
        glow:SetTexture(File("RowGlow"))
        glow:SetTexCoord(0, 1, 0, 1)
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(1, 0.72, 0.30, 0.22)
    end
    local text = button.fontString
    if text then
        local color = chosen and GOLD or CREAM
        text:SetTextColor(color[1], color[2], color[3])
    end
end

-- A line across such a menu (root:CreateDivider): our gold rule.
local function SkinMenuDivider(frame)
    local line = frame.divider
    if not line then return end
    line:SetTexture(File("Line"))
    line:SetTexCoord(0, 1, 0, 1)
    line:SetHeight(1)
    line:SetVertexColor(0.80, 0.60, 0.26, 0.55)
end

Widgets.GOLD, Widgets.GOLD_DIM, Widgets.CREAM, Widgets.SOFT, Widgets.MUTED, Widgets.GREEN = GOLD, GOLD_DIM, CREAM, SOFT, MUTED, GREEN
Widgets.NumberFont = NumberFont
Widgets.File, Widgets.NewTexture, Widgets.NewLine, Widgets.NewRule = File, NewTexture, NewLine, NewRule
Widgets.NewSlices, Widgets.NewColumn, Widgets.NewText = NewSlices, NewColumn, NewText
Widgets.NewButton, Widgets.NewBar, Widgets.SetBar = NewButton, NewBar, SetBar
Widgets.SkinScrollBar, Widgets.MenuStyle = SkinScrollBar, MenuStyle
Widgets.SkinMenuLine, Widgets.SkinMenuDivider = SkinMenuLine, SkinMenuDivider
