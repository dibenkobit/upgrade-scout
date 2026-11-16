-- A small stand-in for the World of Warcraft client, enough to run Upgrade Scout outside the
-- game: frames, events, timers, an item database, an auction house server with paging and a
-- request throttle. Widget methods are a fixed list on purpose: calling a
-- method that is not on the list fails the test, which catches misspelled API calls.
local W = {}

W.now = 1000
W.frames = {}
W.texts = {}            -- every font string, so tests can read what the tab says
W.timers = {}
W.printed = {}
W.items = {}        -- "id:suffix" -> item
W.equipped = {}     -- slot -> link
-- The character being played. Beyond these a test may give it: last (a surname, as Forever
-- has them), mana, race, spells ({ [spell id] = true }: what it knows, which is how the
-- game says which weapons and armor it has learned) and professions ({ { name, rank }, ... }).
W.player = { name = "Tester", level = 10, class = "WARRIOR", money = 100000, dualWield = false }

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
-- def: { id, suffix, name, level, equipLoc, classID, subClassID, quality, value, value2,
--        red, unique, uniqueEquipped, effects, noStats, uncached,
--        sell = what a vendor pays for it, in copper: a silver unless said, 0 for an item no
--               vendor buys,
--        values = { [profile] = score } for profiles other than the two the tests began with,
--        game = { ITEM_MOD_STRENGTH_SHORT = 5, ... }: stats as the game itself counts them,
--        pawn = { Strength = 5, ... }: stats as Pawn reads them, where it is installed,
--        classes = "Druid, Shaman" (the classes it is for), races = "Orc, Troll",
--        skill = { "Engineering", 150 } (the profession it asks for), reputation = true }
function W.AddItem(def)
    def.suffix = def.suffix or 0
    def.quality = def.quality or 2
    def.classID = def.classID or 4
    def.subClassID = def.subClassID or 0
    def.level = def.level or 1
    def.cached = not def.uncached
    W.items[def.id .. ":" .. def.suffix] = def
    return def
end

-- An item link as the Forever client writes one, after a real one from the game
-- ("item:9788::::::::15:1491:::1:12727::::::"). The seventh field, where the first game had the
-- random suffix, is empty. The variant ("of the Tiger") is named by a bonus ID, the fourteenth
-- field, and that is another number than the suffix in the key of an auction row. The ninth is
-- the level of the character looking at the item: the same item has another link for another
-- character.
local BONUS_BASE = 12000
function W.Link(id, suffix)
    suffix = suffix or 0
    local item = W.items[id .. ":" .. suffix]
    local bonus = suffix ~= 0 and ("1:" .. (BONUS_BASE + suffix)) or ":"
    return "|cff1eff00|Hitem:" .. id .. "::::::::" .. W.player.level .. "::::" .. bonus .. "::::::|h[" .. item.name .. "]|h|r"
end

local function ParseItem(info)
    if type(info) == "number" then return W.items[info .. ":0"], info, 0 end
    local fields = {}
    for field in ((info:match("item:([%-%d:]+)") or "") .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
    local id = tonumber(fields[1])
    if not id then return nil end
    local suffix = fields[13] == "1" and tonumber(fields[14]) - BONUS_BASE or 0
    return W.items[id .. ":" .. suffix], id, suffix
end
W.ParseItem = ParseItem

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local M = {}
local WidgetMT = { __index = M }

local function Widget(kind, name, parent, template)
    local w = setmetatable({
        _kind = kind, _name = name, _parent = parent, _template = template,
        _shown = true, _scripts = {}, _events = {}, _enabled = true,
    }, WidgetMT)
    if name then _G[name] = w end
    if kind ~= "Texture" and kind ~= "FontString" then W.frames[#W.frames + 1] = w end
    if kind == "FontString" then W.texts[#W.texts + 1] = w end
    return w
end
W.Widget = Widget

local function noop() end
for _, name in ipairs({
    "SetAllPoints", "SetJustifyH", "SetWordWrap", "SetSpacing",
    "SetColorTexture", "SetBlendMode", "SetTexCoord", "SetVertexColor", "SetDrawLayer",
    "SetTextColor", "SetShadowColor", "SetShadowOffset",
    "SetHitRectInsets", "SetTitle", "UnregisterEvent", "RegisterForClicks", "SetHighlightTexture",
    "SetSnapToPixelGrid", "SetTexelSnappingBias", "SetClampedToScreen",
    -- a window the player can drag about
    "SetMovable", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
    -- edit boxes
    "SetAutoFocus", "SetNumeric", "SetMaxLetters", "SetFocus", "ClearFocus", "HighlightText",
}) do
    M[name] = noop
end

-- Where a part is anchored: widget._points is { { point, to, toPoint, x, y }, ... }, so that a
-- test can see what stands where. As in the game, a part has one anchor for each of its
-- points: setting a point again moves it.
function M:ClearAllPoints() self._points = {} end
function M:SetPoint(point, to, toPoint, x, y)
    assert(type(point) == "string", "the name of a point")
    -- The short forms: SetPoint("RIGHT") and SetPoint("RIGHT", x, y) are against the parent,
    -- SetPoint("RIGHT", to, x, y) against the same point of `to`.
    if to == nil or type(to) == "number" then
        to, toPoint, x, y = self._parent, point, to, toPoint
    elseif toPoint == nil or type(toPoint) == "number" then
        toPoint, x, y = point, toPoint, x
    end
    local points = self._points or {}
    self._points = points
    local at = #points + 1
    for i = 1, #points do
        if points[i].point == point then at = i end
    end
    points[at] = { point = point, to = to, toPoint = toPoint, x = x or 0, y = y or 0 }
end

-- Edit boxes. What the addon writes into one and what the player types (W.Type) both reach the
-- box's OnTextChanged, as in the game; the second argument says which of the two it was.
function M:SetNumber(number)
    assert(self._kind == "EditBox" and type(number) == "number", "a number for an edit box")
    self._text = tostring(number)
    if self._scripts.OnTextChanged then self._scripts.OnTextChanged(self, false) end
end
function M:GetNumber() return tonumber(self._text) or 0 end
-- Nobody is typing while a test runs: what W.Type writes is there at once.
function M:HasFocus() return false end
function W.Type(box, text)
    assert(box._kind == "EditBox" and box._enabled and box:IsVisible(), "an edit box that takes typing")
    box._text = text
    if box._scripts.OnTextChanged then box._scripts.OnTextChanged(box, true) end
end
-- The Enter key in an edit box.
function W.PressEnter(box)
    assert(box._kind == "EditBox" and box._enabled and box:IsVisible(), "an edit box that takes typing")
    if box._scripts.OnEnterPressed then box._scripts.OnEnterPressed(box) end
end

function M:SetTexture(file) self._texture = file end
-- How see-through a part is: the addon hides some of the game's own pictures this way.
function M:SetAlpha(alpha) self._alpha = alpha end
function M:GetAlpha() return self._alpha or 1 end
function M:SetFrameLevel(level) self._level = level end
function M:GetFrameLevel() return self._level or 1 end
-- The layer a frame is drawn in: its own where it was given one, or else its parent's. A frame
-- in a lower layer than another is drawn under it, whatever their levels.
function M:SetFrameStrata(strata)
    assert(type(strata) == "string", "the name of a layer")
    self._strata = strata
end
function M:GetFrameStrata()
    local widget = self
    while widget do
        if widget._strata then return widget._strata end
        widget = widget._parent
    end
    return "MEDIUM"
end
-- Whether the mouse reaches the frame: widget._mouse, for a frame that was told.
function M:EnableMouse(enabled) self._mouse = enabled and true or false end
function M:GetTexture() return self._texture end
function M:SetFont(file, size, flags)
    assert(type(file) == "string" and type(size) == "number" and type(flags) == "string", "a font file, a size and flags")
    self._font = file
end
-- A font object of the game's, or a family made with CreateFontFamily: widget._font is that object.
function M:SetFontObject(font)
    assert(type(font) == "table", "a font object")
    self._font = font
end

function M:SetAtlas(atlas)
    assert(type(atlas) == "string", "an atlas name")
    self._atlas = atlas
end
function M:SetSize(w, h) self._width, self._height = w, h end
function M:SetWidth(w) self._width = w end
function M:SetDesaturated(grey) self._grey = grey and true or false end
function M:GetParent() return self._parent end
-- Six pixels a character, colour codes not counted.
function M:GetStringWidth()
    local text = (self._text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return #text * 6
end
-- How wide the text would be if nothing cut it short.
M.GetUnboundedStringWidth = M.GetStringWidth
-- How tall the text stands: twelve pixels a line, and as many lines as it takes to fit the
-- width the text was given (one where it was given none). Nothing for no text.
function M:GetStringHeight()
    local width = self:GetStringWidth()
    if width == 0 then return 0 end
    local room = self._width or 0
    return 12 * (room > 0 and math.ceil(width / room) or 1)
end
function M:SetHeight(h) self._height = h end
function M:GetHeight() return self._height or 0 end
function M:GetWidth() return self._width or 0 end
function M:GetName() return self._name end
function M:IsObjectType(kind) return kind == self._kind or (kind == "Frame" and self._kind ~= "Texture" and self._kind ~= "FontString") end
function M:Show()
    local was = self._shown
    self._shown = true
    if not was and self._scripts.OnShow then self._scripts.OnShow(self) end
end
function M:Hide()
    local was = self._shown
    self._shown = false
    if self._kind == "GameTooltip" then self._owner = nil end       -- a hidden tooltip has no owner
    if was and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function M:SetShown(shown) if shown then self:Show() else self:Hide() end end
function M:IsShown() return self._shown end
-- Shown, and so is everything it sits in.
function M:IsVisible()
    local widget = self
    while widget do
        if not widget._shown then return false end
        widget = widget._parent
    end
    return true
end
function M:SetScript(name, fn) self._scripts[name] = fn end
function M:GetScript(name) return self._scripts[name] end
function M:HookScript(name, fn)
    local old = self._scripts[name]
    self._scripts[name] = function(...)
        if old then old(...) end
        fn(...)
    end
end
function M:RegisterEvent(event) self._events[event] = true end
-- A frame keeps the textures made on it, so that a test can see what it is drawn with.
function M:CreateTexture()
    local texture = Widget("Texture", nil, self)
    self._textures = self._textures or {}
    self._textures[#self._textures + 1] = texture
    return texture
end
function M:CreateFontString(name, layer, template)
    local text = Widget("FontString", nil, self)
    text._font = template       -- a font string made from a font template can be written at once
    return text
end
function M:SetText(text)
    -- The game refuses to write with no font. (The tab of the window gets its font from a template.)
    if self._kind == "FontString" then assert(self._font, "a font is set before the text") end
    self._text = text
end
function M:GetText() return self._text end
-- Writes a text and makes the font string as wide as the text is.
function M:SetTextToFit(text)
    assert(self._kind == "FontString", "a font string")
    self:SetText(text)
    self._width = self:GetStringWidth()
end
-- As in the game, a button is told when it is switched on or off, and only when that changes.
function M:SetEnabled(enabled)
    enabled = enabled and true or false
    if enabled == self._enabled then return end
    self._enabled = enabled
    local script = self._scripts[enabled and "OnEnable" or "OnDisable"]
    if script then script(self) end
end
function M:IsEnabled() return self._enabled end
function M:SetChecked(checked) self._checked = checked and true or false end
function M:GetChecked() return self._checked end
function M:Click()
    if self._enabled and self._scripts.OnClick then self._scripts.OnClick(self, "LeftButton") end
end

-- Tooltips
function M:ClearLines() self._lines = {} self._link = nil end
-- As in the game, giving a tooltip an owner empties it.
function M:SetOwner(owner) self._owner = owner self:ClearLines() end
function M:IsOwned(frame) return self._owner == frame end
function M:GetOwner() return self._owner end
function M:NumLines() return self._lines and #self._lines or 0 end
function M:AddLine(text, r, g, b)
    self._lines = self._lines or {}
    self._lines[#self._lines + 1] = { text = text, r = r, g = g, b = b }
end
-- A line with text on the left and on the right; `text` is the left one.
function M:AddDoubleLine(left, right, r, g, b, rightR, rightG, rightB)
    self._lines = self._lines or {}
    self._lines[#self._lines + 1] = { text = left, r = r, g = g, b = b,
        right = right, rightR = rightR, rightG = rightG, rightB = rightB }
end

-- Colours, as the game's ColorMixin objects.
local function Color(r, g, b)
    local color = { r = r, g = g, b = b }
    function color:GetRGB() return self.r, self.g, self.b end
    function color:WrapTextInColorCode(text)
        return string.format("|cff%02x%02x%02x", self.r * 255, self.g * 255, self.b * 255) .. text .. "|r"
    end
    return color
end
NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR = Color(1, 0.82, 0), Color(1, 1, 1)
GREEN_FONT_COLOR, RED_FONT_COLOR = Color(0.1, 1, 0.1), Color(1, 0.125, 0.125)
GRAY_FONT_COLOR, DISABLED_FONT_COLOR = Color(0.5, 0.5, 0.5), Color(0.5, 0.5, 0.5)

-- The game's texts for what an item asks of its owner, and its names for the classes.
ITEM_CLASSES_ALLOWED, ITEM_RACES_ALLOWED = "Classes: %s", "Races: %s"
ITEM_MIN_SKILL, ITEM_REQ_REPUTATION = "Requires %s (%d)", "Requires %s - %s"
LOCALIZED_CLASS_NAMES_MALE = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
LOCALIZED_CLASS_NAMES_FEMALE = LOCALIZED_CLASS_NAMES_MALE

-- How far the character being played has got in a profession; nil if it has not got it.
local function PlayerSkill(name)
    for _, profession in ipairs(W.player.professions or {}) do
        if profession[1] == name then return profession[2] end
    end
end

-- The lines every kind of item can have about what it asks of its owner; each is red when
-- the character being played falls short of it.
-- Such a line is marked as a requirement, and says of what kind it is.
local function AddRequirements(lines, item)
    local kinds = Enum.TooltipDataUsageRequirementType
    local function Line(kind, text, met)
        lines[#lines + 1] = { leftText = text, leftColor = met and HIGHLIGHT_FONT_COLOR or RED_FONT_COLOR,
            type = Enum.TooltipDataLineType.UsageRequirement, requirementType = kind }
    end
    if item.level > 1 then
        Line(kinds.Level, "Requires Level " .. item.level, item.level <= W.player.level)
    end
    if item.classes then
        Line(kinds.RaceClass, ITEM_CLASSES_ALLOWED:format(item.classes),
            item.classes:find(LOCALIZED_CLASS_NAMES_MALE[W.player.class] or "?", 1, true) ~= nil)
    end
    if item.races then
        Line(kinds.RaceClass, ITEM_RACES_ALLOWED:format(item.races), item.races:find(W.player.race or "Human", 1, true) ~= nil)
    end
    if item.skill then
        Line(kinds.Skill, ITEM_MIN_SKILL:format(item.skill[1], item.skill[2]), (PlayerSkill(item.skill[1]) or 0) >= item.skill[2])
    end
    if item.reputation then
        Line(kinds.Reputation, ITEM_REQ_REPUTATION:format("Argent Dawn", "Revered"), false)
    end
    -- rank: a rank among one's own side's fighters, in words no pattern of the addon knows.
    if item.rank then
        Line(kinds.PvPRank, "Requires " .. item.rank, false)
    end
end

-- What the game knows to say about an item, line by line: the data its tooltips are built
-- from. A requirement the player does not meet is red; the right-hand text is the armor kind.
local function TooltipLines(link)
    local item = ParseItem(link)
    if not item or not item.cached then
        return { { leftText = RETRIEVING_ITEM_INFO, leftColor = RED_FONT_COLOR } }
    end
    if item.classID == 0 then
        -- A consumable: what it asks for (red when the player falls short of it) and, in a
        -- line that starts with "Use:", what it does. useLate: that line has not arrived.
        local lines = { { leftText = item.name, leftColor = HIGHLIGHT_FONT_COLOR } }
        AddRequirements(lines, item)
        if item.red then
            lines[#lines + 1] = { leftText = "Requires First Aid (225)", leftColor = RED_FONT_COLOR }
        end
        if item.use and not item.useLate then
            lines[#lines + 1] = { leftText = ITEM_SPELL_TRIGGER_ONUSE .. " " .. item.use, leftColor = GREEN_FONT_COLOR }
        end
        return lines
    end
    local lines = {
        { leftText = item.name, leftColor = Color(0.1, 1, 0) },
        { leftText = "Binds when equipped", leftColor = HIGHLIGHT_FONT_COLOR },
    }
    -- uniqueEquipped: any number of it can be owned, one worn. The tooltip says so, and
    -- C_Item.GetItemUniquenessByID does not (which is the worse of the two things the real
    -- one may do: the game's documentation does not tell).
    if item.uniqueEquipped then
        lines[#lines + 1] = { leftText = ITEM_UNIQUE_EQUIPPABLE, leftColor = HIGHLIGHT_FONT_COLOR }
    end
    lines[#lines + 1] = { leftText = "Chest", leftColor = HIGHLIGHT_FONT_COLOR, rightText = "Mail",
        rightColor = item.red and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR }
    AddRequirements(lines, item)
    -- block: a shield's, in a line of its own written from the game's text.
    if item.block then
        lines[#lines + 1] = { leftText = SHIELD_BLOCK_TEMPLATE:format(item.block), leftColor = HIGHLIGHT_FONT_COLOR, type = 0 }
    end
    -- effects: something the item does that is not a stat. The game marks such a line: when
    -- used (effects), while worn (equipLine), on a hit (procLine).
    if item.effects then
        lines[#lines + 1] = { leftText = ITEM_SPELL_TRIGGER_ONUSE .. " Does something.", leftColor = GREEN_FONT_COLOR,
            type = Enum.TooltipDataLineType.ItemSpellTriggerOnUse }
    end
    if item.equipLine then
        lines[#lines + 1] = { leftText = "Equip: Does something else.", leftColor = GREEN_FONT_COLOR,
            type = Enum.TooltipDataLineType.ItemSpellTriggerOnEquip }
    end
    if item.procLine then
        lines[#lines + 1] = { leftText = "Chance on hit: Does something rare.", leftColor = GREEN_FONT_COLOR,
            type = Enum.TooltipDataLineType.ItemSpellTriggerOnProc }
    end
    return lines
end

C_TooltipInfo = {}
function C_TooltipInfo.GetHyperlink(link)
    W.tooltipReads = (W.tooltipReads or 0) + 1
    return { lines = TooltipLines(link) }
end

-- The game fills the tooltip with the item's lines, then calls what addons asked it to call
-- after an item (TooltipDataProcessor), then shows it.
function M:SetHyperlink(link)
    self:ClearLines()
    for _, line in ipairs(TooltipLines(link)) do
        self:AddLine(line.leftText, line.leftColor:GetRGB())
    end
    self._link = link
    for _, call in ipairs(W.tooltipPostCalls[Enum.TooltipDataType.Item] or {}) do
        call(self, { type = Enum.TooltipDataType.Item, hyperlink = link })
    end
    -- Pawn, where it is installed, has hooked the game's own tooltips: each time one is given
    -- an item its hook asks PawnUpdateTooltip, by that name, to write Pawn's lines.
    if PawnUpdateTooltip and (self == GameTooltip or self == ShoppingTooltip1 or self == ItemRefTooltip) then
        PawnUpdateTooltip(self:GetName(), "SetHyperlink", link)
    end
    self._shown = true
end

-- What addons ask the game to call once it has filled a tooltip from its data.
W.tooltipPostCalls = {}
TooltipDataProcessor = { AllTypes = "ALL" }
function TooltipDataProcessor.AddTooltipPostCall(kind, call)
    assert(kind ~= nil and type(call) == "function", "a kind of tooltip and a function")
    W.tooltipPostCalls[kind] = W.tooltipPostCalls[kind] or {}
    table.insert(W.tooltipPostCalls[kind], call)
end

-- The item a tooltip shows: its name (nil while the client has not loaded it), link and number.
TooltipUtil = {}
function TooltipUtil.GetDisplayedItem(tooltip)
    local link = tooltip._link
    if not link then return nil end
    return (C_Item.GetItemInfo(link)), link, tonumber(link:match("item:(%d+)"))
end

---------------------------------------------------------------------------
-- The game's scrolling list, as far as the addon uses it. Written after Blizzard's
-- ScrollBox.lua, ScrollBoxListView.lua, ScrollBar.lua, ScrollController.lua and
-- DataProvider.lua; what matters here:
--   * positions are fractions from 0 to 1; a step ("pan extent") is one row, the mouse wheel
--     goes two;
--   * frames exist only for the rows in view;
--   * a row is known by its element table: when the collection changes, a row whose table is
--     still in view keeps its frame and is NOT initialized again, the others are released
--     and new ones acquired and initialized; when another provider is assigned, every frame
--     is released;
--   * when rows come or go, the list stays where it was in pixels, not in fractions.
---------------------------------------------------------------------------
local function Saturate(value) return math.max(0, math.min(1, value)) end

ScrollBoxConstants = { NoScrollInterpolation = true, RetainScrollPosition = true }

local function Callbacks(object)
    object._callbacks = {}
    function object:RegisterCallback(event, fn, owner)
        self._callbacks[#self._callbacks + 1] = { event = event, fn = fn, owner = owner }
    end
    function object:_Trigger(event, ...)
        for _, callback in ipairs(self._callbacks) do
            if callback.event == event then callback.fn(callback.owner, ...) end
        end
    end
end

function CreateDataProvider(tbl)
    local provider = { collection = {} }
    Callbacks(provider)
    function provider:GetSize() return #self.collection end
    function provider:Find(index) return self.collection[index] end
    function provider:Enumerate(indexBegin, indexEnd)
        local collection = self.collection
        local index, last = (indexBegin or 1) - 1, indexEnd or #collection
        return function()
            index = index + 1
            if index <= last and collection[index] ~= nil then return index, collection[index] end
        end
    end
    function provider:SetSortComparator(comparator, skipSort)
        self.comparator = comparator
        if not skipSort then self:Sort() end
    end
    function provider:Sort()
        if self.comparator then
            table.sort(self.collection, self.comparator)
            self:_Trigger("OnSort")
        end
    end
    function provider:InsertTable(elements)
        if #elements == 0 then return end
        for i = 1, #elements do self.collection[#self.collection + 1] = elements[i] end
        -- With a comparator the size change is announced as "about to be sorted".
        self:_Trigger("OnSizeChanged", self.comparator ~= nil)
        self:Sort()
    end
    function provider:Remove(...)
        local before = #self.collection
        for n = select("#", ...), 1, -1 do
            local element = select(n, ...)
            for index = 1, #self.collection do
                if self.collection[index] == element then
                    table.remove(self.collection, index)
                    break
                end
            end
        end
        if #self.collection ~= before then self:_Trigger("OnSizeChanged", false) end
    end
    function provider:Flush()
        self.collection = {}
        self:_Trigger("OnSizeChanged", false)
    end
    if tbl then provider:InsertTable(tbl) end
    return provider
end

function CreateScrollBoxListLinearView()
    local view = {}
    function view:SetElementExtent(extent) self.extent = extent end
    -- factory(frameTypeOrTemplate, initializer) is called back for each element.
    function view:SetElementFactory(elementFactory) self.elementFactory = elementFactory end
    function view:_Ask(element)
        local frameType, initializer
        self.elementFactory(function(kind, init) frameType, initializer = kind, init end, element)
        assert(type(frameType) == "string" and type(initializer) == "function", "the factory names a frame and an initializer")
        return frameType, initializer
    end
    return view
end

local function ScrollBarModel(bar)
    bar._percentage, bar._visible, bar._pan = 0, 0, 0.1
    -- The template's parts (MinimalScrollBar.xml): a track with its three pictures, the knob
    -- on it with three of its own, and an arrow button at each end with one.
    local track = Widget("Frame", nil, bar)
    track.Begin, track.Middle, track.End = track:CreateTexture(), track:CreateTexture(), track:CreateTexture()
    local thumb = Widget("Button", nil, track)
    thumb.Begin, thumb.Middle, thumb.End = thumb:CreateTexture(), thumb:CreateTexture(), thumb:CreateTexture()
    track.Thumb = thumb
    bar.Track, bar.Back, bar.Forward = track, Widget("Button", nil, bar), Widget("Button", nil, bar)
    bar.Back.Texture, bar.Forward.Texture = bar.Back:CreateTexture(), bar.Forward:CreateTexture()
    Callbacks(bar)
    function bar:SetVisibleExtentPercentage(value) self._visible = Saturate(value) end
    function bar:GetVisibleExtentPercentage() return self._visible end
    function bar:SetPanExtentPercentage(value) self._pan = Saturate(value) end
    function bar:GetScrollPercentage() return self._percentage end
    function bar:SetScrollPercentage(value)
        self._percentage = Saturate(value)
        self:_Trigger("OnScroll", self._percentage)
    end
    -- What the player does with the mouse, for the tests.
    function bar:Drag(percentage) self:SetScrollPercentage(percentage) end
    function bar:ClickArrow(direction) self:SetScrollPercentage(self._percentage + self._pan * direction) end
end

W.listHeight = 420                              -- 14 rows of 30

local function ScrollBoxModel(box)
    box._percentage, box._frames, box._pools = 0, {}, {}
    W.scrollBoxStats = { acquired = 0, released = 0, initialized = 0 }
    local stats = W.scrollBoxStats

    local function Size(self) return self._provider and self._provider:GetSize() or 0 end
    local function Range(self)
        return math.max(0, Size(self) * self._view.extent - W.listHeight)
    end

    local function Release(self, frame)
        frame:Hide()
        frame._element, frame._index = nil, nil
        local pool = self._pools[frame._kind]
        pool[#pool + 1] = frame
        stats.released = stats.released + 1
    end

    -- Brings the frames in line with the rows in view. `reassigned`: nothing is kept.
    function box:_Update(reassigned)
        local view, size = self._view, Size(self)
        local offset = Range(self) * self._percentage
        local first, last = 1, 0
        if size > 0 then
            first = math.floor(offset / view.extent) + 1
            last = math.min(size, math.ceil((offset + W.listHeight) / view.extent))
        end

        local kept, acquired, byElement = {}, {}, {}
        if reassigned then
            for _, frame in ipairs(self._frames) do Release(self, frame) end
        else
            for _, frame in ipairs(self._frames) do byElement[frame._element] = frame end
        end
        for index = first, last do
            local element = self._provider:Find(index)
            local frame = byElement[element]
            if frame then
                byElement[element] = nil
            else
                local frameType = view:_Ask(element)
                self._pools[frameType] = self._pools[frameType] or {}
                frame = table.remove(self._pools[frameType]) or Widget(frameType, nil, self)
                frame._element = element
                frame.GetElementData = function(this) return this._element end
                frame:SetHeight(view.extent)
                frame:Show()
                acquired[#acquired + 1] = frame
                stats.acquired = stats.acquired + 1
            end
            frame._index = index
            kept[#kept + 1] = frame
        end
        for _, frame in pairs(byElement) do Release(self, frame) end
        self._frames = kept
        self._range = Range(self)
        -- Initializers run once every frame is in place.
        for _, frame in ipairs(acquired) do
            stats.initialized = stats.initialized + 1
            local _, initializer = view:_Ask(frame._element)
            initializer(frame, frame._element)
        end

        local bar = self._bar
        if bar then
            local extent = size * view.extent
            bar:SetVisibleExtentPercentage(extent > 0 and W.listHeight / extent or 0)
            bar:SetPanExtentPercentage(self._range > 0 and view.extent / self._range or 0)
            if math.abs(bar:GetScrollPercentage() - self._percentage) > 1e-9 then
                bar:SetScrollPercentage(self._percentage)
            end
        end
    end

    -- The collection changed: stay at the same pixel offset.
    local function ContentsChanged(self)
        local offset = (self._range or 0) * self._percentage
        local range = Range(self)
        self._percentage = range > 0 and Saturate(offset / range) or 0
        self:_Update(false)
    end

    function box:SetDataProvider(provider, retainScrollPosition)
        assert(self._view, "A view is required before assigning the data provider.")
        self._provider = provider
        provider:RegisterCallback("OnSizeChanged", function(owner, pendingSort)
            if owner._provider == provider and not pendingSort then ContentsChanged(owner) end
        end, self)
        provider:RegisterCallback("OnSort", function(owner)
            if owner._provider == provider then ContentsChanged(owner) end
        end, self)
        if not retainScrollPosition then self._percentage = 0 end
        self:_Update(true)
    end
    function box:ReinitializeFrames()
        for _, frame in ipairs(self._frames) do
            stats.initialized = stats.initialized + 1
            local _, initializer = self._view:_Ask(frame._element)
            initializer(frame, frame._element)
        end
    end
    function box:SetScrollPercentage(percentage)
        percentage = Saturate(percentage)
        if math.abs(percentage - self._percentage) < 1e-9 then return end
        self._percentage = percentage
        self:_Update(false)
    end
    function box:GetScrollPercentage() return self._percentage end
    function box:ScrollToBegin() self:SetScrollPercentage(0) end
    function box:GetFrames() return self._frames end
    -- The script the template gives the frame.
    function box:OnMouseWheel(value)
        local range = Range(self)
        if range <= 0 then return end
        local pan = Saturate(self._view.extent / range * 2)
        self:SetScrollPercentage(self._percentage + (value < 0 and pan or -pan))
    end
end

ScrollUtil = {}
function ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    assert(box._template == "WowScrollBoxList", "a scroll box")
    assert(bar._template == "MinimalScrollBar", "a scroll bar")
    assert(type(view.elementFactory) == "function", "an element factory")
    -- A frame type, unlike a template, has no height of its own: the game raises this error.
    assert(view.extent, "Failed to assign an explicit element extent or set an extent calculator.")
    box._view, box._bar = view, bar
    bar:RegisterCallback("OnScroll", function(owner, percentage) owner:SetScrollPercentage(percentage) end, box)
end

-- MoneyDisplayFrameTemplate: gold, silver and copper as coins. Written after Blizzard's
-- MoneyFrame.lua. Each of the three parts is as wide as its number and its coin. Setting an
-- amount shows the parts that have something to show (gold only when there is gold) and lays
-- them out the game's way: copper against the right edge, silver and gold each a fixed slot
-- (36: room for two digits) to the left of the part after it.
--   part._amount   the number it shows
--   part._points   where it is anchored: { { point, to, toPoint, x, y }, ... }
--   part._width    how wide it is: its number, the room the game leaves after it (2), its coin (12)
--   part.Text      the number: Text._points says where it ends, from the part's right edge
--   part.Icon      the coin. W.colorblind: the player has letters in place of the coins (the
--                  game's setting for the colour blind), "12g" for 12 and a gold coin.
-- A number is as wide as any text here: six pixels a character. Gold is written with its
-- thousands apart ("1,234"), as the game writes it.
local MONEY_SLOT, MONEY_COIN, MONEY_AIR = 36, 12, 2
local function MoneyDisplayModel(money)
    local function Part(key)
        local part = { _amount = 0, _points = {}, _shown = false, _width = 0 }
        function part:ClearAllPoints() self._points = {} end
        function part:SetPoint(point, to, toPoint, x, y)
            -- The short forms: SetPoint("RIGHT") and SetPoint("RIGHT", x, y).
            if to == nil or type(to) == "number" then to, toPoint, x, y = money, point, to, toPoint end
            self._points[#self._points + 1] = { point = point, to = to, toPoint = toPoint, x = x or 0, y = y or 0 }
        end
        function part:ShouldBeShown()
            return not self._forced and (self._amount > 0 or key ~= "GoldDisplay")
        end
        function part:IsShown() return self._shown end
        function part:SetForcedHidden(hidden)
            self._forced = hidden and true or false
            self._shown = self:ShouldBeShown()
            if key == "CopperDisplay" then money._copperHidden = hidden end
        end
        function part:SetWidth(width) self._width = width end
        function part:GetWidth() return self._width end
        local text = { _points = {} }
        function text:GetText()
            local written = tostring(part._amount)
            if key == "GoldDisplay" then
                written = written:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
            end
            if W.colorblind then written = written .. key:sub(1, 1):lower() end
            return written
        end
        function text:GetStringWidth() return #self:GetText() * 6 end
        function text:SetPoint(point, to, toPoint, x, y)
            if to == nil or type(to) == "number" then to, toPoint, x, y = part, point, to, toPoint end
            assert(point == "RIGHT" and to == part and toPoint == "RIGHT", "a number ends before its coin")
            self._points = { { point = point, to = to, toPoint = toPoint, x = x or 0, y = y or 0 } }
        end
        local icon = {}
        function icon:IsShown() return not W.colorblind end
        function icon:GetWidth() return MONEY_COIN end
        part.Text, part.Icon = text, icon
        -- The game's own: the number before its coin, and the part as wide as the two.
        function part:UpdateWidth()
            local coin = icon:IsShown() and MONEY_COIN or 0
            text:SetPoint("RIGHT", -(coin + MONEY_AIR), 0)
            self._width = text:GetStringWidth() + coin + MONEY_AIR
        end
        money[key] = part
        return part
    end
    local gold, silver, copper = Part("GoldDisplay"), Part("SilverDisplay"), Part("CopperDisplay")
    function money:UpdateAnchoring()
        for _, part in ipairs({ gold, silver, copper }) do part:ClearAllPoints() end
        copper:SetPoint("RIGHT")
        if copper:ShouldBeShown() then silver:SetPoint("RIGHT", -MONEY_SLOT, 0) else silver:SetPoint("RIGHT", copper, "RIGHT") end
        if silver:ShouldBeShown() then gold:SetPoint("RIGHT", silver, "RIGHT", -MONEY_SLOT, 0) else gold:SetPoint("RIGHT", silver, "RIGHT") end
    end
    function money:SetAmount(amount)
        assert(type(amount) == "number" and amount >= 0 and amount == math.floor(amount), "a whole number of copper")
        self._amount = amount
        gold._amount, silver._amount, copper._amount = math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100
        for _, part in ipairs({ gold, silver, copper }) do
            part._shown = part:ShouldBeShown()
            if part._shown then part:UpdateWidth() end
        end
        self:UpdateAnchoring()
    end
    function money:GetAmount() return self._amount end
    -- A new font is a new width for every number: the game measures the parts again.
    function money:SetFontObject(font)
        assert(font ~= nil, "a font object")
        self._font = font
        for _, part in ipairs({ gold, silver, copper }) do part:UpdateWidth() end
    end
end
W.MoneyDisplayModel = MoneyDisplayModel

-- Where a menu hangs from its dropdown (AnchorUtil.CreateAnchor).
AnchorUtil = {}
function AnchorUtil.CreateAnchor(point, relativeTo, relativePoint, x, y)
    assert(type(point) == "string" and relativeTo ~= nil and type(relativePoint) == "string", "a point, a frame and its point")
    return { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x or 0, y = y or 0 }
end

-- WowStyle1DropdownTemplate: shows the ticked line of its menu, or the default text, or the
-- text it was told to show whatever is ticked (OverrideText). The menu is described by a
-- generator function, which runs again every time the menu opens.
--   dropdown.radios   the lines of which one is chosen (root:CreateRadio), as the generator
--                     last described them
--   dropdown.checks   the lines with a tick box (root:CreateCheckbox)
--   dropdown.lines    while the menu is open (dropdown:Open), the frames the game made for
--                     the lines with a tick box, in their order: see MenuLine
local function DropdownModel(dropdown)
    dropdown.radios, dropdown.checks = {}, {}
    -- The template's own plate and arrow, and its text.
    dropdown.Background, dropdown.Arrow = dropdown:CreateTexture(), dropdown:CreateTexture()
    dropdown.Text = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local function ShowSelection(self)
        local text = self._override
        if not text then
            for _, radio in ipairs(self.radios) do
                if radio.isSelected(radio.data) then text = radio.text end
            end
        end
        self._text = text or self._default
        self.Text:SetText(self._text or "")
    end
    function dropdown:SetDefaultText(text)
        self._default = text
        ShowSelection(self)
    end
    function dropdown:OverrideText(text)
        assert(type(text) == "string", "a text")
        self._override = text
        ShowSelection(self)
    end
    function dropdown:SetTooltip(tooltipFunc) self._tooltip = tooltipFunc end
    function dropdown:SetMenuAnchor(anchor)
        assert(type(anchor) == "table" and anchor.point, "an anchor made by AnchorUtil.CreateAnchor")
        self._anchor = anchor
    end
    function dropdown:GenerateMenu()
        assert(not self._open, "the menu is not rebuilt while it is open")
        local root = { radios = {}, checks = {}, dividers = 0, rules = {} }
        -- What the game hands back for a line of the menu: it takes functions that dress the
        -- line's frame once the game has drawn it (the addon's Widgets.SkinMenuLine), a
        -- tooltip, and whether the line can be clicked.
        local function Description(entry)
            entry.initializers = {}
            function entry:AddInitializer(fn)
                assert(type(fn) == "function", "an initializer is a function")
                self.initializers[#self.initializers + 1] = fn
            end
            function entry:SetTooltip(fn)
                assert(type(fn) == "function", "a tooltip is filled in by a function")
                self.tooltip = fn
            end
            function entry:SetEnabled(enabled)
                assert(type(enabled) == "boolean", "enabled or not")
                self.enabled = enabled
            end
            return entry
        end
        function root:CreateRadio(text, isSelected, setSelected, data)
            local radio = Description({ text = text, isSelected = isSelected, setSelected = setSelected, data = data })
            self.radios[#self.radios + 1] = radio
            return radio
        end
        function root:CreateCheckbox(text, isSelected, setSelected, data)
            assert(type(text) == "string" and type(isSelected) == "function" and type(setSelected) == "function",
                "a label and two functions")
            local check = Description({ text = text, isSelected = isSelected, setSelected = setSelected, data = data })
            self.checks[#self.checks + 1] = check
            return check
        end
        -- A line across the menu; `after` says which radio each one follows, `afterCheck`
        -- which tick box.
        function root:CreateDivider()
            self.dividers = self.dividers + 1
            self.after = self.after or {}
            self.after[#self.after + 1] = #self.radios
            local rule = Description({ afterCheck = #self.checks })
            self.rules[#self.rules + 1] = rule
            return rule
        end
        function root:SetScrollMode(extent)
            assert(type(extent) == "number" and extent > 0, "a height in pixels")
            self.scroll = extent
        end
        self._generator(self, root)
        self.radios, self.checks = root.radios, root.checks
        self.dividers, self.dividersAfter, self.scroll = root.dividers, root.after or {}, root.scroll
        self.rules = root.rules
        ShowSelection(self)
    end
    function dropdown:SetupMenu(generator)
        self._generator = generator
        self:GenerateMenu()
    end
    -- What the player does: opens the menu and clicks a line.
    function dropdown:Pick(index)
        self:GenerateMenu()
        self._open = true
        local radio = self.radios[index]
        radio.setSelected(radio.data)
        self._open = false
        ShowSelection(self)
    end

    -- A frame of the game's for a line with a tick box, drawn as the game draws it
    -- (MenuVariants.CreateCheckbox): its square, its mark when the line is ticked, the light
    -- under the mouse and the words. Then the addon's own initializers dress it. What is
    -- drawn on a menu's frame is attached, not created: the game takes it back when the menu
    -- closes. An initializer may return the size of the line (line._size).
    local function Attachable(frame)
        function frame:AttachTexture() return self:CreateTexture() end
        function frame:AttachFontString() return self:CreateFontString(nil, "ARTWORK", "GameFontHighlight") end
        function frame:AttachFrame(kind)
            assert(kind == "Frame" or kind == "Button" or kind == "CheckButton" or kind == "StatusBar" or kind == "EditBox",
                "a kind of frame a menu can attach")
            -- The game resets the frame it hands over (SetToDefaults): nothing it was made
            -- with can be taken for granted. It is in a layer of its own and not the menu's,
            -- which puts it under the menu's plate, at the bottom of that layer, out of view
            -- and deaf to the mouse, until the one who attached it says otherwise. The game's
            -- own menus do (MenuTemplates.AttachBasicButton: "Machinery is broken").
            local child = Attachable(Widget(kind, nil, self))
            child._strata, child._level, child._shown, child._mouse = "MEDIUM", 0, false, false
            return child
        end
        return frame
    end
    local function MenuLine(check)
        local line = Attachable(Widget("Button"))
        line._check = check
        -- A menu is in the layer over the game's windows, its lines above its own frame.
        line._strata, line._level = "FULLSCREEN_DIALOG", 520
        line.leftTexture1, line.highlight = line:AttachTexture(), line:AttachTexture()
        line.leftTexture1:SetAtlas("common-dropdown-ticksquare")
        if check.isSelected(check.data) then
            line.leftTexture2 = line:AttachTexture()
            line.leftTexture2:SetAtlas("common-dropdown-icon-checkmark-yellow")
        end
        line.fontString = line:AttachFontString()
        line.fontString:SetTextToFit(check.text)
        for _, dress in ipairs(check.initializers) do
            local width, height = dress(line, check, dropdown)
            if width and height then line._size = { width, height } end
        end
        line:SetEnabled(check.enabled ~= false)
        return line
    end
    local function DrawLines(self)
        self.lines = {}
        for i, check in ipairs(self.checks) do self.lines[i] = MenuLine(check) end
    end
    -- The player opens the menu: the game describes it anew and draws it.
    function dropdown:Open()
        self:GenerateMenu()
        self._open = true
        DrawLines(self)
    end
    function dropdown:Close()
        assert(self._open, "an open menu")
        -- The frames of its lines go back to the game: what is in them is hidden.
        for _, line in ipairs(self.lines) do line:Hide() end
        self._open, self.lines = false, nil
    end
    -- The tick box of the open menu with this label: its place among the tick boxes.
    function dropdown:Find(text)
        assert(self._open, "an open menu")
        for i, check in ipairs(self.checks) do
            if check.text == text then return i end
        end
    end
    -- A click on a tick box of the open menu, by its label. The game plays a sound (by
    -- whether the line was ticked before the click: MenuTemplates.lua), tells the line's
    -- function, and draws the lines again without closing the menu (MenuResponse.Refresh).
    -- A line that is not enabled takes no click.
    function dropdown:Tick(text)
        local i = assert(self:Find(text), "no tick box labelled " .. tostring(text))
        local check = self.checks[i]
        if check.enabled == false then return end
        PlaySound(check.isSelected(check.data) and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        check.setSelected(check.data)
        DrawLines(self)
    end
end

local TEMPLATES = {
    MinimalScrollBar = ScrollBarModel,
    WowScrollBoxList = ScrollBoxModel,
    MoneyDisplayFrameTemplate = MoneyDisplayModel,
    WowStyle1DropdownTemplate = DropdownModel,
    AuctionHouseFrameDisplayModeTabTemplate = function() end,       -- a tab of the window (LibAHTab)
}

function CreateFrame(kind, name, parent, template)
    local widget = Widget(kind, name, parent, template)
    if template then
        assert(TEMPLATES[template], "unknown template " .. template)(widget)
    end
    return widget
end

UIParent = Widget("Frame", "UIParent")
GameTooltip = Widget("GameTooltip", "GameTooltip")
-- The tooltip the game puts beside the main one, for the item that is worn.
ShoppingTooltip1 = Widget("GameTooltip", "ShoppingTooltip1")
ShoppingTooltip1._shown = false
-- The one for an item link clicked in the chat.
ItemRefTooltip = Widget("GameTooltip", "ItemRefTooltip")
-- Where a frame's right edge is on the screen: unknown unless a test says (frame._right).
function M:GetRight() return self._right end
-- The minimap: 140 wide and high, as the game makes it. A test says where its middle is on
-- the screen and how the game scales it (frame._center = { x, y }, frame._scale), and where
-- the cursor is (W.pointer = { x, y }, in the screen's own pixels). No addon has reshaped it:
-- a test that wants one defines GetMinimapShape, as such an addon does.
Minimap = Widget("Frame", "Minimap", UIParent)
Minimap:SetSize(140, 140)
function M:GetCenter()
    if self._center then return self._center[1], self._center[2] end
end
function M:GetEffectiveScale() return self._scale or 1 end
function GetCursorPosition() return W.pointer[1], W.pointer[2] end

---------------------------------------------------------------------------
-- Clock, timers, events
---------------------------------------------------------------------------
function GetTime() return W.now end
function time() return math.floor(W.now) end
function debugprofilestop() return W.now * 1000 end

C_Timer = {}
function C_Timer.After(delay, fn)
    W.timers[#W.timers + 1] = { at = W.now + delay, fn = fn }
end

function W.Fire(event, ...)
    for i = 1, #W.frames do
        local frame = W.frames[i]
        if frame._events[event] and frame._scripts.OnEvent then
            frame._scripts.OnEvent(frame, event, ...)
        end
    end
end

-- Advances the clock by dt: due timers run, then every frame in view gets its OnUpdate.
function W.Tick(dt)
    dt = dt or 0.05
    W.now = W.now + dt
    local due = {}
    local keep = {}
    for i = 1, #W.timers do
        local t = W.timers[i]
        if t.at <= W.now then due[#due + 1] = t else keep[#keep + 1] = t end
    end
    W.timers = keep
    table.sort(due, function(a, b) return a.at < b.at end)
    for i = 1, #due do due[i].fn() end
    for i = 1, #W.frames do
        local frame = W.frames[i]
        if frame._scripts.OnUpdate and frame:IsVisible() then frame._scripts.OnUpdate(frame, dt) end
    end
end

function W.Run(seconds, step)
    local stop = W.now + seconds
    while W.now < stop do W.Tick(step or 0.05) end
end

-- Runs until fn() is true; fails if that takes longer than `limit` game seconds.
function W.RunUntil(fn, limit)
    local stop = W.now + (limit or 120)
    while not fn() do
        if W.now >= stop then error("timed out waiting", 2) end
        W.Tick(0.05)
    end
end

---------------------------------------------------------------------------
-- Globals the addon reads
---------------------------------------------------------------------------
function GetLocale() return W.locale or "enUS" end
function GetBuildInfo() return "1.60.1", "70938", "Nov 12 2026", 16001 end
-- The game's words for a few of the stats an item can have, each under the name
-- C_Item.GetItemStats lists the stat by.
ITEM_MOD_STRENGTH_SHORT, ITEM_MOD_STAMINA_SHORT, RESISTANCE0_NAME = "Strength", "Stamina", "Armor"
ITEM_MOD_CRIT_RATING_SHORT, ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Critical Strike", "Bonus Healing"
-- Lua functions the game also offers under short global names (LibStub uses them).
strmatch, strfind, strsub, format, tinsert, tremove = string.match, string.find, string.sub, string.format, table.insert, table.remove
WOW_PROJECT_MAINLINE, WOW_PROJECT_CAMELOT = 1, 99
WOW_PROJECT_ID = WOW_PROJECT_CAMELOT
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    W.printed[#W.printed + 1] = table.concat(parts, " ")
end
-- Calls a function on its own: an error in it is reported and does not stop the caller. Here
-- "reported" is kept in W.errors, and a scenario that ends with any of them has failed.
W.errors = {}
function securecallfunction(fn, ...)
    local args, count = { ... }, select("#", ...)
    local results = { xpcall(function() return fn(unpack(args, 1, count)) end, debug.traceback) }
    if not results[1] then
        W.errors[#W.errors + 1] = results[2]
        return
    end
    return unpack(results, 2, table.maxn(results))
end
function hooksecurefunc(tbl, name, hook)
    if type(tbl) == "string" then tbl, name, hook = _G, tbl, name end
    local original = tbl[name]
    tbl[name] = function(...)
        local a, b, c, d = original(...)
        hook(...)
        return a, b, c, d
    end
end
function UnitLevel() return W.player.level end
function UnitClass() return LOCALIZED_CLASS_NAMES_MALE[W.player.class] or "Class", W.player.class end
-- Forever gives a character a surname, and says it where other clients say the realm.
function UnitName() return W.player.name, W.player.last end
function UnitRace() return W.player.race or "Human", "Human" end
function UnitFactionGroup() return "Alliance", "Alliance" end
function GetRealmName() return W.realm or "Testrealm" end
-- What the character knows: weapon and armor skills are spells to the client.
C_SpellBook = {}
function C_SpellBook.IsSpellKnown(spell) return W.player.spells ~= nil and W.player.spells[spell] == true end
-- A place for each kind of profession, as Forever has them: the two main ones, first aid,
-- fishing, cooking. A test's third profession is the character's cooking.
function GetProfessions()
    local professions = W.player.professions or {}
    return professions[1] and 1 or nil, professions[2] and 2 or nil, nil, nil, professions[3] and 3 or nil
end
function GetProfessionInfo(index)
    local profession = W.player.professions[index]
    return profession[1], 134400, profession[2], 300
end
function CanDualWield() return W.player.dualWield end
function GetMoney() return W.player.money end
-- How much mana the character can hold: none unless a test gives it some (W.player.mana).
-- W.secrets: the character is in a fight, and the game keeps the number to itself. What it
-- hands out instead cannot be compared or counted with, only passed on and asked about.
local SECRET = setmetatable({}, {
    __lt = function() error("attempt to compare a secret value") end,
    __le = function() error("attempt to compare a secret value") end,
})
function issecretvalue(value) return value == SECRET end
function UnitPowerMax(_, power)
    if W.secrets then return SECRET end
    return power == 0 and (W.player.mana or 0) or 0
end
function GetInventoryItemLink(_, slot) return W.equipped[slot] end
-- W.combat: the character is in a fight.
function InCombatLockdown() return W.combat == true end
-- Talents, as Forever keeps them: a tree of "traits" whose groups are the talent trees of the
-- first game. W.player.talents lists those from the left, each { name, points = spent in it };
-- a character without the list has a game that does not say. The game hands the groups out in
-- no order of its own (here: last first), each with its place among them.
local function Talents() return W.player.talents end
C_ClassTalents = {}
function C_ClassTalents.GetActiveConfigID() return Talents() and 1 or nil end
C_Traits = {}
function C_Traits.GetConfigInfo(config)
    assert(config == 1, "the character's own set of talents")
    return { ID = config, name = "Talents", treeIDs = { 7 } }
end
function C_Traits.GetGroupDisplayInfoByTreeID(tree)
    assert(tree == 7, "the tree of the character's talents")
    local out = {}
    for place = #Talents(), 1, -1 do
        out[#out + 1] = { groupID = 100 + place, treeID = tree, orderIndex = place, displayName = Talents()[place].name }
    end
    return out
end
function C_Traits.GetGroupCurrencyInfo(config, groups)
    assert(config == 1 and type(groups) == "table", "the set of talents and the groups asked about")
    if W.talentsFail then error("the game does not answer about talents") end
    local out = {}
    for _, group in ipairs(groups) do
        local points = Talents()[group - 100].points
        out[#out + 1] = { traitNodeGroupID = group, currencyInfos = { { traitCurrencyID = 1, quantity = 0, spent = points } } }
    end
    return out
end
-- W.modified: true for "some modifier is held", or the name of one action ("DRESSUP").
function IsModifiedClick(action) return W.modified == true or (action ~= nil and W.modified == action) end
-- The game looks at the modifier keys itself and says whether it did anything.
function HandleModifiedItemClick(link)
    if not W.modified then return false end
    W.linked = link
    return true
end
function ShowInspectCursor() W.cursor = "inspect" end
function ResetCursor() W.cursor = nil end
W.sounds = {}
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
function PlaySound(kit)
    assert(kit ~= nil, "a sound kit")
    W.sounds[#W.sounds + 1] = kit
end

function GameTooltip_ShowCompareItem(tooltip) W.compared = tooltip end
function GameTooltip_Hide() GameTooltip:Hide() end
function GameTooltip_AddColoredLine(tooltip, text, color)
    local r, g, b = color:GetRGB()
    tooltip:AddLine(text, r, g, b, true)
end
function GameTooltip_SetTitle(tooltip, text)
    tooltip:ClearLines()
    GameTooltip_AddColoredLine(tooltip, text, HIGHLIGHT_FONT_COLOR)
end
function GameTooltip_AddBlankLineToTooltip(tooltip) tooltip:AddLine(" ") end
function GameTooltip_AddNormalLine(tooltip, text) GameTooltip_AddColoredLine(tooltip, text, NORMAL_FONT_COLOR) end
function GameTooltip_AddHighlightLine(tooltip, text) GameTooltip_AddColoredLine(tooltip, text, HIGHLIGHT_FONT_COLOR) end
function GameTooltip_AddDisabledLine(tooltip, text) GameTooltip_AddColoredLine(tooltip, text, DISABLED_FONT_COLOR) end
function GameTooltip_AddErrorLine(tooltip, text) GameTooltip_AddColoredLine(tooltip, text, RED_FONT_COLOR) end

RETRIEVING_ITEM_INFO = "Retrieving item information"
ITEM_SPELL_TRIGGER_ONUSE = "Use:"
SHIELD_BLOCK_TEMPLATE = "%s Block"
ITEM_UNIQUE_EQUIPPABLE = "Unique-Equipped"
CANCEL, NONE = "Cancel", "None"
SECONDS_ABBR, MINUTES_ABBR, HOURS_ABBR, DAYS_ABBR = "%d Sec", "%d Min", "%d Hr", "%d Days"
-- The colours of the classes, as the game's ColorMixin objects.
RAID_CLASS_COLORS = { WARRIOR = Color(0.78, 0.61, 0.43), DRUID = Color(1, 0.49, 0.04), MAGE = Color(0.25, 0.78, 0.92) }
PriceFontWhite, PriceFontRed, PriceFontGray = { name = "PriceFontWhite" }, { name = "PriceFontRed" }, { name = "PriceFontGray" }
-- The font files the tab writes with: the standard one, and the one behind the game's number fonts.
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
-- The game's fonts are families: a font file for each alphabet, of which a text takes the one
-- that suits what it says. W.gameFonts are those files, as the game's Fonts.xml has them, for
-- the two fonts the addon asks: the one for words and the one for numbers.
W.gameFonts = {
    words = { roman = "Fonts\\FRIZQT__.TTF", korean = "Fonts\\2002.TTF", simplifiedchinese = "Fonts\\ARKai_T.ttf",
        traditionalchinese = "Fonts\\blei00d.TTF", russian = "Fonts\\FRIZQT___CYR.TTF" },
    numbers = { roman = "Fonts\\ARIALN.TTF", korean = "Fonts\\K_Damage.TTF", simplifiedchinese = "Fonts\\ARKai_C.ttf",
        traditionalchinese = "Fonts\\bKAI00M.TTF", russian = "Fonts\\ARIALN.TTF" },
}
local function GameFont(files, size)
    return {
        GetFont = function() return files.roman, size, "" end,
        GetFontObjectForAlphabet = function(_, alphabet)
            assert(files[alphabet], "an alphabet the game has a font for")
            return { GetFont = function() return files[alphabet], size, "" end }
        end,
    }
end
GameFontNormal = GameFont(W.gameFonts.words, 12)
Number13FontWhite = GameFont(W.gameFonts.numbers, 13)
-- A family of an addon's own. W.fontFamilies keeps them by name, which the game wants unique.
W.fontFamilies = {}
function CreateFontFamily(name, members)
    assert(type(name) == "string" and not W.fontFamilies[name], "a name no other font has")
    assert(type(members) == "table" and #members > 0, "the members of the family")
    local seen = {}
    for _, member in ipairs(members) do
        assert(W.gameFonts.words[member.alphabet] and not seen[member.alphabet], "each alphabet once, by the game's name for it")
        assert(type(member.file) == "string" and type(member.height) == "number" and type(member.flags) == "string",
            "a font file, a size and flags for every member")
        seen[member.alphabet] = true
    end
    local family = { name = name, members = members }
    W.fontFamilies[name] = family
    return family
end
ITEM_QUALITY_COLORS = { [2] = { color = Color(0.118, 1, 0) }, [3] = { color = Color(0, 0.44, 0.87) } }
ColorManager = {}
function ColorManager.GetColorDataForItemQuality(quality) return ITEM_QUALITY_COLORS[quality] end

function Clamp(value, low, high) return math.max(low, math.min(high, value)) end
-- Sizes in whole screen pixels. (A test has no screen: the size is taken as it is.)
PixelUtil = {}
function PixelUtil.SetHeight(region, height) region:SetHeight(height) end
-- What the game puts between thousands in this language, and between a name and a surname.
LARGE_NUMBER_SEPERATOR = ","
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
function FormatPercentage(share, round)
    assert(round, "rounded to a whole percent")
    return string.format("%d%%", math.floor(share * 100 + 0.5))
end
function GenerateClosure(fn, ...)
    local bound = { ... }
    return function(...)
        local args = {}
        for i = 1, #bound do args[i] = bound[i] end
        for i = 1, select("#", ...) do args[#bound + i] = (select(i, ...)) end
        return fn(unpack(args, 1, #bound + select("#", ...)))
    end
end

-- Money as text: "1g 2s 3c", zero parts left out. Whole copper only, as in the game.
MoneyStringConstants = { SeparateThousands = true }
function GetMoneyString(copper)
    assert(type(copper) == "number" and copper == math.floor(copper), "a whole number of copper")
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. "c" end
    return table.concat(parts, " ")
end
function MoneyFrame_Update(moneyFrame, copper) moneyFrame._amount = copper end

-- Addons: the game calls back once an addon has loaded, at once if it already has.
W.loaded = {}
local awaitingAddOn = {}
EventUtil = {}
function EventUtil.ContinueOnAddOnLoaded(name, callback)
    if W.loaded[name] then
        callback()
    else
        awaitingAddOn[#awaitingAddOn + 1] = { name = name, callback = callback }
    end
end
function W.AddOnLoaded(name)
    W.loaded[name] = true
    for i = #awaitingAddOn, 1, -1 do
        if awaitingAddOn[i].name == name then
            table.remove(awaitingAddOn, i).callback()
        end
    end
    W.Fire("ADDON_LOADED", name)
end

-- The character logs out. The addon hears of it, and then nothing of the session is left but
-- what the game saves: the account's variables stay where they are, the character's own are
-- put away under its name.
W.charSaved = {}
function W.Logout()
    W.Fire("PLAYER_LOGOUT")
    for i = 1, #W.frames do
        W.frames[i]._scripts, W.frames[i]._events = {}, {}
    end
    W.timers = {}
    W.loaded = {}
    W.fontFamilies = {}         -- the next session makes its fonts anew
    awaitingAddOn = {}
    W.charSaved[W.player.name] = UpgradeScoutCharDB
    UpgradeScoutCharDB = nil
    AuctionHouseFrame, LibStub = nil, nil
    W.equipped = {}
    W.ResetBags()
    W.ResetPawn()
end

-- Another character of the account comes into the world: `player` as W.player, `equipped`
-- as W.equipped. The addon is loaded after this, as a new session.
function W.Login(player, equipped)
    W.player = player
    W.equipped = equipped or {}
    UpgradeScoutCharDB = W.charSaved[player.name]
end
HEADSLOT, CHESTSLOT, FINGER0SLOT, MAINHANDSLOT, SECONDARYHANDSLOT = "Head", "Chest", "Finger", "Main Hand", "Off Hand"
-- The game's text for two of the weapon kinds; the addon has its own for the rest.
INVTYPE_2HWEAPON = "Two-Hand (game)"
SlashCmdList = {}
-- The windows Escape closes, by name.
UISpecialFrames = {}

Enum = {
    ItemClass = { Consumable = 0, Weapon = 2, Armor = 4 },
    TooltipDataType = { Item = 0 },
    PowerType = { Mana = 0, Rage = 1, Energy = 3 },
    -- Tooltip lines, as the Forever client's documentation numbers them.
    TooltipDataLineType = { UsageRequirement = 43, ItemSpellTriggerOnUse = 44, ItemSpellTriggerOnEquip = 45,
        ItemSpellTriggerOnProc = 46 },
    TooltipDataUsageRequirementType = {
        RaceClass = 0, Faction = 1, Skill = 2, PvPMedal = 3, Reputation = 4, Level = 5, Guild = 6, Achievement = 7,
        PvPRank = 8, EquippedItem = 9, ShapeshiftForm = 10, ArenaRating = 11, EarnCurrency = 12, Specialization = 13,
        NotAlreadyKnown = 14, NotInArena = 15, NotInRatedBg = 16,
    },
    AuctionHouseSortOrder = { Price = 0, Name = 1, Level = 2, Bid = 3, Buyout = 4, TimeRemaining = 5 },
    AuctionHouseFilter = {
        PoorQuality = 6, CommonQuality = 7, UncommonQuality = 8, RareQuality = 9,
        EpicQuality = 10, LegendaryQuality = 11, ArtifactQuality = 12,
    },
}

---------------------------------------------------------------------------
-- C_Item
---------------------------------------------------------------------------
C_Item = {}
function C_Item.GetItemInfoInstant(info)
    local item, id = ParseItem(info)
    if not item then
        -- A suffix the database does not list still has a base item.
        item = id and W.items[id .. ":0"]
        if not item then return nil end
    end
    return id, "Type", "SubType", item.equipLoc, 134400, item.classID, item.subClassID
end
function C_Item.GetItemInfo(info)
    local item, id, suffix = ParseItem(info)
    if not item or not item.cached then return nil end
    return item.name, W.Link(id, suffix), item.quality, item.level + 5, item.level, "Type", "SubType", item.stack or 1,
        item.equipLoc, 134400, item.sell or 100, item.classID, item.subClassID
end
-- How many of an item go into one stack: nil until the client has loaded the item.
function C_Item.GetItemMaxStackSizeByID(info)
    local item = ParseItem(info)
    if not item or not item.cached then return nil end
    return item.stack or 1
end
-- The spell an item casts when it is used: consumables have one, and say what it does (`use`).
function C_Item.GetItemSpell(info)
    local item = ParseItem(info)
    if item and item.use then return "Spell of " .. item.name, 100000 + item.id end
end
-- The game's names for the subcategories of Consumables it knows.
W.subNames = { [1] = "Potions", [2] = "Elixirs", [5] = "Food & Drink", [7] = "Bandages" }
-- And for the kinds of armor.
W.armorNames = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }
function C_Item.GetItemSubClassInfo(classID, subClassID)
    if classID == 0 then return W.subNames[subClassID] end
    if classID == 4 then return W.armorNames[subClassID] end
end
function C_Item.IsItemDataCachedByID(id)
    for _, item in pairs(W.items) do
        if item.id == id and not item.cached then return false end
    end
    return true
end
function C_Item.RequestLoadItemDataByID(id)
    C_Timer.After(W.loadDelay or 0.5, function()
        if W.neverLoad and W.neverLoad[id] then return end
        for _, item in pairs(W.items) do
            if item.id == id then item.cached = true end
        end
        W.Fire("ITEM_DATA_LOAD_RESULT", id, true)
    end)
end
function C_Item.GetItemUniquenessByID(id)
    local item = W.items[id .. ":0"]
    return item and item.unique or false
end
-- The stats the game keeps for an item, under its own names for them. Nothing for an item
-- the client has not loaded.
-- A test mostly gives an item its score outright: `value` on the first of the tests'
-- profiles, `value2` on the second, `values[profile]` on any other. Each becomes a stat
-- named after its profile, which that profile weighs at 1 and the others at nothing (see
-- TestWeights in run.lua). `game` adds stats under the game's real names.
-- An enchantment adds a thousand to the first: a score that reads an enchanted link is found out.
function C_Item.GetItemStats(info)
    local item = ParseItem(info)
    if not item or not item.cached then return nil end
    local out = {}
    if item.noStats then return out end
    if item.value then out.TEST_S1 = item.value end
    if item.value2 then out.TEST_S2 = item.value2 end
    for profile, value in pairs(item.values or {}) do out["TEST_" .. profile] = value end
    for name, amount in pairs(item.game or {}) do out[name] = amount end
    if type(info) == "string" and info:match("item:%d+:%d") then out.TEST_S1 = (out.TEST_S1 or 0) + 1000 end
    return out
end

---------------------------------------------------------------------------
-- C_AuctionHouse: a server with paging and a one-request-at-a-time throttle
---------------------------------------------------------------------------
local A = {
    auctions = {},          -- { auctionID, id, suffix, buyout, own }
    pageSize = 50,
    itemPageSize = 50,      -- auctions per page of an item search
    honorLevelSort = true,
    bucketBySuffix = true,
    sampleLinks = true,
    answerBrowse = true,
    ready = true,
    calls = { browse = 0, more = 0, search = 0, itemMore = 0, bids = {}, quotes = {}, bought = {}, cancelled = 0 },
    nextID = 1,
}
W.AH = A

function W.AddAuction(id, buyout, opts)
    opts = opts or {}
    -- bid: what a bidder pays. A lot without a buyout always has one; a lot with a buyout has
    -- one only if the seller set it.
    -- quantity: how many the seller put up at this price: pieces of what is sold by the piece,
    -- auctions of one item each of everything else. The buyout is the price of one.
    local auction = { auctionID = A.nextID, id = id, suffix = opts.suffix or 0, buyout = buyout, own = opts.own,
        bid = opts.bid or (buyout == 0 and 1 or nil), quantity = opts.quantity or 1 }
    A.nextID = A.nextID + 1
    A.auctions[#A.auctions + 1] = auction
    return auction
end

local function KeyOf(auction)
    local item = W.items[auction.id .. ":" .. auction.suffix]
    return {
        itemID = auction.id,
        itemLevel = item.level + 5,
        itemSuffix = A.bucketBySuffix and auction.suffix or 0,
        battlePetSpeciesID = 0,
    }
end

local function KeyText(key) return key.itemID .. ":" .. key.itemLevel .. ":" .. key.itemSuffix end

local function Busy()
    -- Like the real server: a request sent while another is in flight is an error in the addon.
    if not A.ready then error("request sent while the auction house throttle was not ready", 3) end
    A.ready = false
    C_Timer.After(0.15, function()
        A.ready = true
        W.Fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    end)
end

local function InBucket(key)
    local out = {}
    for i = 1, #A.auctions do
        local auction = A.auctions[i]
        if KeyText(KeyOf(auction)) == KeyText(key) then out[#out + 1] = auction end
    end
    table.sort(out, function(a, b) return a.buyout < b.buyout end)
    return out
end

C_AuctionHouse = {}
function C_AuctionHouse.IsThrottledMessageSystemReady() return A.ready end

function C_AuctionHouse.SendBrowseQuery(query)
    Busy()
    A.calls.browse = A.calls.browse + 1
    A.lastQuery = query
    if not A.answerBrowse then return end

    local classes = {}
    for _, f in ipairs(query.itemClassFilters or {}) do classes[f.classID] = true end
    local rows, seen = {}, {}
    for i = 1, #A.auctions do
        local auction = A.auctions[i]
        local item = W.items[auction.id .. ":" .. auction.suffix]
        if classes[item.classID] then
            local key = KeyOf(auction)
            local text = KeyText(key)
            local row = seen[text]
            if not row then
                row = { itemKey = key, totalQuantity = 0, minPrice = math.huge, containsOwnerItem = false, _level = item.level, _order = i }
                seen[text] = row
                rows[#rows + 1] = row
            end
            row.totalQuantity = row.totalQuantity + auction.quantity
            -- By default the row shows the lowest number on any of its lots, bids included.
            -- With bidsIgnored it shows the cheapest buyout whenever there is one.
            if auction.buyout > 0 then
                row._buyout = math.min(row._buyout or math.huge, auction.buyout)
            end
            row._any = math.min(row._any or math.huge, auction.bid or math.huge, auction.buyout > 0 and auction.buyout or math.huge)
            row.minPrice = A.bidsIgnored and row._buyout or row._any
        end
    end
    local byLevel = query.sorts[1] and query.sorts[1].sortOrder == Enum.AuctionHouseSortOrder.Level and A.honorLevelSort
    table.sort(rows, function(a, b)
        if byLevel and a._level ~= b._level then return a._level < b._level end
        if not byLevel then
            -- An order that has nothing to do with level.
            local ha, hb = (a._order * 7919) % 101, (b._order * 7919) % 101
            if ha ~= hb then return ha < hb end
        end
        return a._order < b._order
    end)
    -- A server whose "lowest price" is not what the addon takes it for.
    if A.minPriceFactor then
        for i = 1, #rows do rows[i].minPrice = rows[i].minPrice * A.minPriceFactor end
    end
    A.rows = rows
    A.shown = math.min(#rows, A.pageSize)
    C_Timer.After(0.2, function() W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end)
end

function C_AuctionHouse.RequestMoreBrowseResults()
    Busy()
    A.calls.more = A.calls.more + 1
    A.shown = math.min(#A.rows, A.shown + A.pageSize)
    C_Timer.After(0.2, function() W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", {}) end)
end

function C_AuctionHouse.GetBrowseResults()
    local out = {}
    for i = 1, A.shown or 0 do out[i] = A.rows[i] end
    return out
end
function C_AuctionHouse.HasFullBrowseResults() return (A.shown or 0) >= #(A.rows or {}) end

function C_AuctionHouse.GetItemKeyRequiredLevel(key)
    local item = W.items[key.itemID .. ":" .. key.itemSuffix] or W.items[key.itemID .. ":0"]
    return item and item.level or 0
end
function C_AuctionHouse.GetItemKeySampleLink(key)
    if not A.sampleLinks then return nil end
    -- A pile of pieces has no auction of one item to give as a sample.
    if W.IsCommodity(key.itemID) then return nil end
    local bucket = InBucket(key)
    if not bucket[1] then return nil end
    return W.Link(bucket[1].id, bucket[1].suffix)
end
function C_AuctionHouse.GetItemKeyInfo() return nil end

function C_AuctionHouse.SendSearchQuery(key, sorts, separateOwnerItems, minLevel, maxLevel)
    Busy()
    A.calls.search = A.calls.search + 1
    assert(type(sorts) == "table" and separateOwnerItems == false and minLevel == 0 and maxLevel == 0, "unexpected item search arguments")
    if A.dropSearches and A.dropSearches > 0 then
        A.dropSearches = A.dropSearches - 1
        return
    end
    A.results = A.results or {}
    A.loaded = A.loaded or {}
    local list = InBucket(key)
    if W.IsCommodity(key.itemID) then
        -- Sold by the piece: the answer is a price list, under another event.
        A.pieces = A.pieces or {}
        A.pieces[key.itemID] = list
        local itemID = key.itemID
        C_Timer.After(0.2, function() W.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", itemID) end)
        return
    end
    -- The auctions are there to be read when the answer comes, not before.
    local text = KeyText(key)
    A.results[text], A.loaded[text] = nil, nil
    local copy = { itemID = key.itemID, itemLevel = key.itemLevel, itemSuffix = key.itemSuffix, battlePetSpeciesID = 0 }
    C_Timer.After(0.2, function()
        A.results[text] = list
        A.loaded[text] = math.min(#list, A.itemPageSize)
        W.Fire("ITEM_SEARCH_RESULTS_UPDATED", copy)
    end)
end

---------------------------------------------------------------------------
-- Things sold by the piece ("commodities"): everything that stacks, which is most consumables
-- and now and then a piece of gear (the game has a grey necklace that stacks to 20). All
-- sellers' pieces of an item are one pile; a purchase takes the cheapest pieces first.
---------------------------------------------------------------------------
function W.IsCommodity(itemID)
    local item = W.items[itemID .. ":0"]
    return item ~= nil and (item.stack or 1) > 1
end
function C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    return A.pieces and A.pieces[itemID] and #A.pieces[itemID] or 0
end
function C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
    local auction = A.pieces and A.pieces[itemID] and A.pieces[itemID][index]
    if not auction then return nil end
    return {
        itemID = itemID,
        quantity = auction.quantity,
        unitPrice = auction.buyout,
        auctionID = auction.auctionID,
        owners = { "Seller" },
        numOwnerItems = auction.own and auction.quantity or 0,
        containsOwnerItem = auction.own or false,
        containsAccountItem = false,
    }
end
-- The pieces for sale now that the player can buy, cheapest first.
local function Pieces(itemID)
    local out = {}
    for i = 1, #A.auctions do
        local auction = A.auctions[i]
        if auction.id == itemID and not auction.own and auction.buyout > 0 then out[#out + 1] = auction end
    end
    table.sort(out, function(a, b) return a.buyout < b.buyout end)
    return out
end
local function PiecesCost(itemID, quantity)
    local cost, left = 0, quantity
    for _, auction in ipairs(Pieces(itemID)) do
        local take = math.min(left, auction.quantity)
        cost, left = cost + take * auction.buyout, left - take
        if left == 0 then return cost end
    end
    return nil
end
-- The game takes the first of these only from a click or a key press; the tests call it as one.
function C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)
    Busy()
    assert(W.IsCommodity(itemID) and type(quantity) == "number" and quantity >= 1 and quantity == math.floor(quantity),
        "a whole number of pieces of something sold by the piece")
    A.calls.quotes[#A.calls.quotes + 1] = { itemID = itemID, quantity = quantity }
    local total = PiecesCost(itemID, quantity)
    A.purchase = total and { itemID = itemID, quantity = quantity, total = total } or nil
    C_Timer.After(0.2, function()
        if total then
            W.Fire("COMMODITY_PRICE_UPDATED", total / quantity, total)
        else
            -- Not that many for sale: there is no price to name.
            W.Fire("COMMODITY_PRICE_UNAVAILABLE")
        end
    end)
end
function C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, quantity)
    local purchase = assert(A.purchase, "a purchase was started")
    assert(purchase.itemID == itemID and purchase.quantity == quantity, "the item and quantity that were started")
    A.purchase = nil
    -- failPurchase: someone else was faster.
    local total = not A.failPurchase and PiecesCost(itemID, quantity)
    if total then
        local left = quantity
        for _, auction in ipairs(Pieces(itemID)) do
            local take = math.min(left, auction.quantity)
            auction.quantity, left = auction.quantity - take, left - take
        end
        for i = #A.auctions, 1, -1 do
            if A.auctions[i].quantity == 0 then table.remove(A.auctions, i) end
        end
        W.player.money = W.player.money - total
        A.calls.bought[#A.calls.bought + 1] = { itemID = itemID, quantity = quantity, total = total }
    end
    C_Timer.After(0.2, function()
        W.Fire(total and "COMMODITY_PURCHASE_SUCCEEDED" or "COMMODITY_PURCHASE_FAILED")
        if total then W.Fire("PLAYER_MONEY") end
    end)
end
function C_AuctionHouse.CancelCommoditiesPurchase()
    A.calls.cancelled = A.calls.cancelled + 1
    A.purchase = nil
end
function C_AuctionHouse.GetNumItemSearchResults(key)
    return A.loaded and A.loaded[KeyText(key)] or 0
end
function C_AuctionHouse.HasFullItemSearchResults(key)
    local list = A.results and A.results[KeyText(key)]
    return not list or A.loaded[KeyText(key)] >= #list
end
-- Returns true when there is nothing more to fetch, as the game does.
function C_AuctionHouse.RequestMoreItemSearchResults(key)
    if C_AuctionHouse.HasFullItemSearchResults(key) then return true end
    Busy()
    A.calls.itemMore = A.calls.itemMore + 1
    local text = KeyText(key)
    A.loaded[text] = math.min(#A.results[text], A.loaded[text] + A.itemPageSize)
    local copy = { itemID = key.itemID, itemLevel = key.itemLevel, itemSuffix = key.itemSuffix, battlePetSpeciesID = 0 }
    C_Timer.After(0.2, function() W.Fire("ITEM_SEARCH_RESULTS_ADDED", copy) end)
    return false
end
function C_AuctionHouse.GetItemSearchResultInfo(key, index)
    if index > (A.loaded[KeyText(key)] or 0) then return nil end
    local auction = A.results[KeyText(key)][index]
    if not auction then return nil end
    return {
        itemKey = key,
        itemLink = W.Link(auction.id, auction.suffix),
        auctionID = auction.auctionID,
        buyoutAmount = auction.buyout > 0 and auction.buyout or nil,
        minBid = auction.bid,
        containsOwnerItem = auction.own or false,
        containsAccountItem = false,
        owners = { "Seller" },
        quantity = auction.quantity,
    }
end
-- A buyout takes one item. A line of several (a seller's auctions at one price, `quantity`)
-- is one shorter for it.
function C_AuctionHouse.PlaceBid(auctionID, amount)
    A.calls.bids[#A.calls.bids + 1] = { auctionID = auctionID, amount = amount }
    -- failBid: someone else was faster. The auction house says so with an error and nothing else.
    if A.failBid then
        C_Timer.After(0.2, function() W.Fire("AUCTION_HOUSE_SHOW_ERROR", 4) end)
        return
    end
    for i = #A.auctions, 1, -1 do
        local auction = A.auctions[i]
        if auction.auctionID == auctionID then
            -- What is bought comes by mail, a letter of its own.
            W.mail.inbox[#W.mail.inbox + 1] = { items = { W.Link(auction.id, auction.suffix) } }
            auction.quantity = auction.quantity - 1
            if auction.quantity <= 0 then table.remove(A.auctions, i) end
        end
    end
    -- The gold is gone with the bid.
    W.player.money = W.player.money - amount
    C_Timer.After(0.2, function()
        W.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID)
        W.Fire("PLAYER_MONEY")
    end)
end
function C_AuctionHouse.SearchForFavorites() end
function C_AuctionHouse.SearchForItemKeys() end
function C_AuctionHouse.SupportsCopperValues() return W.AH.copper ~= false end

---------------------------------------------------------------------------
-- Bags and the mailbox
---------------------------------------------------------------------------
-- W.bags[bag][slot] = { link = item link, bound = soulbound, locked = attached to a letter }
W.bags = { [0] = {} }
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
ATTACHMENTS_MAX_SEND, ATTACHMENTS_MAX_RECEIVE = 12, 16
-- The letter being written, the letters sent ({ to, subject, items = { link, ... } }) and the
-- mail in the mailbox ({ items = { link, ... } }). inboxTotal: how many letters there are when
-- the game lists fewer than all; failSend: the next letter does not go.
W.mail = { sendPage = false, attached = {}, sent = {}, inbox = {} }

-- Into the first empty slot of the backpack; returns that slot.
function W.PutInBags(link, opts)
    local bag = W.bags[0]
    local slot = 1
    while bag[slot] do slot = slot + 1 end
    bag[slot] = { link = link, bound = opts and opts.bound or false }
    W.Fire("BAG_UPDATE", 0)
    return slot
end

C_Container = {}
function C_Container.GetContainerNumSlots(bag)
    return W.bags[bag] and 16 or 0
end
function C_Container.GetContainerItemInfo(bag, slot)
    local item = W.bags[bag] and W.bags[bag][slot]
    if not item then return nil end
    return {
        hyperlink = item.link, itemID = tonumber(item.link:match("item:(%d+)")), stackCount = 1,
        isBound = item.bound, isLocked = item.locked or false,
    }
end
-- A right-click on an item. With the Send Mail page up it goes into the letter's first empty
-- place; anything else a right-click would do (putting gear on, say) is not what a test means.
function C_Container.UseContainerItem(bag, slot)
    local item = assert(W.bags[bag] and W.bags[bag][slot], "an item to right-click")
    assert(MailFrame:IsShown() and W.mail.sendPage, "the Send Mail page is up when an item is right-clicked")
    assert(not item.bound and not item.locked, "an item that can be attached")
    for i = 1, ATTACHMENTS_MAX_SEND do
        if not W.mail.attached[i] then
            W.mail.attached[i] = { bag = bag, slot = slot, link = item.link }
            item.locked = true
            return
        end
    end
    error("the letter is full")
end
function CursorHasItem() return false end
function GetSendMailItem(index)
    local attached = W.mail.attached[index]
    if not attached then return nil end
    return attached.link:match("%[(.-)%]"), tonumber(attached.link:match("item:(%d+)")), 134400, 1
end
function GetSendMailItemLink(index)
    local attached = W.mail.attached[index]
    return attached and attached.link
end

-- The mailbox as the game lists it: how many letters it shows, and how many there are.
function GetInboxNumItems()
    return #W.mail.inbox, W.mail.inboxTotal or #W.mail.inbox
end
function GetInboxItemLink(index, attachment)
    local letter = W.mail.inbox[index]
    return letter and letter.items[attachment]
end
-- The player takes an item out of the mail: it goes into the bags.
function W.TakeFromMail(link, opts)
    for i, letter in ipairs(W.mail.inbox) do
        for j, item in ipairs(letter.items) do
            if item == link then
                table.remove(letter.items, j)
                if #letter.items == 0 then table.remove(W.mail.inbox, i) end
                W.Fire("MAIL_INBOX_UPDATE")
                return W.PutInBags(link, opts)
            end
        end
    end
    error("no such item in the mail: " .. link)
end

-- How many of an item the character has: in the bags, and with includeBank in the bank too
-- (W.bank: { [item ID] = count }).
function C_Item.GetItemCount(item, includeBank)
    local id, count = tonumber(item), 0
    for _, bag in pairs(W.bags) do
        for _, held in pairs(bag) do
            if tonumber(held.link:match("item:(%d+)")) == id then count = count + 1 end
        end
    end
    if includeBank then count = count + ((W.bank or {})[id] or 0) end
    return count
end

MailFrame = Widget("Frame", "MailFrame")
MailFrame:Hide()
MailFrameTab2 = Widget("Button", "MailFrameTab2", MailFrame)
-- (The tab is the game's own: what a click on it does outlasts a logout of the addon.)
function MailFrameTab2:Click() W.mail.sendPage = true end
SendMailNameEditBox = Widget("EditBox", "SendMailNameEditBox", MailFrame)
SendMailSubjectEditBox = Widget("EditBox", "SendMailSubjectEditBox", MailFrame)
SendMailNameEditBox:SetText("")
SendMailSubjectEditBox:SetText("")

-- late: the game's mail window comes up a moment after the game says a mailbox is open (true:
-- a tenth of a second; a number: that many seconds). (It is brought up by another event than
-- MAIL_SHOW, and which of the two comes first is not written down.) The game then lists the
-- mail.
function W.OpenMailbox(late)
    W.mail.sendPage = false
    if late then
        C_Timer.After(type(late) == "number" and late or 0.1, function() MailFrame:Show() end)
    else
        MailFrame:Show()
    end
    W.Fire("MAIL_SHOW")
    C_Timer.After(0.2, function() W.Fire("MAIL_INBOX_UPDATE") end)
end
-- The player takes an item out of the letter again.
function W.Detach(index)
    local attached = assert(W.mail.attached[index], "an item in the letter")
    W.bags[attached.bag][attached.slot].locked = false
    W.mail.attached[index] = nil
end
function W.CloseMailbox()
    for i = 1, ATTACHMENTS_MAX_SEND do
        if W.mail.attached[i] then W.Detach(i) end
    end
    MailFrame:Hide()
    W.Fire("MAIL_CLOSED")
end
-- The game's send. The items stay in the letter (and locked in the bags) until the mail
-- system answers a moment later: then the letter is gone and so are they, or it failed.
function SendMail(to, subject)
    assert(to ~= "", "a letter with a name on it")
    local fail = W.mail.failSend
    W.mail.failSend = nil
    C_Timer.After(0.2, function()
        if fail then
            W.Fire("MAIL_FAILED")
            return
        end
        local letter = { to = to, subject = subject, items = {} }
        for i = 1, ATTACHMENTS_MAX_SEND do
            local attached = W.mail.attached[i]
            if attached then
                letter.items[#letter.items + 1] = attached.link
                W.bags[attached.bag][attached.slot] = nil
                W.mail.attached[i] = nil
            end
        end
        W.mail.sent[#W.mail.sent + 1] = letter
        SendMailNameEditBox:SetText("")
        SendMailSubjectEditBox:SetText("")
        W.Fire("MAIL_SEND_SUCCESS")
        W.Fire("BAG_UPDATE", 0)
    end)
end
-- The player presses the game's own Send.
function W.SendLetter()
    SendMail(SendMailNameEditBox:GetText(), SendMailSubjectEditBox:GetText(), "")
end

-- The auction window, as far as LibAHTab and the addon touch it.
-- The game loads the window (the addon Blizzard_AuctionHouseUI) the first time it is needed.
function W.OpenAuctionHouse()
    if not AuctionHouseFrame then
        local frame = Widget("Frame", "AuctionHouseFrame")
        frame:SetSize(800, 538)
        frame.Tabs = { Widget("Button", nil, frame), Widget("Button", nil, frame), Widget("Button", nil, frame) }
        frame.SetDisplayMode = function(self, mode) self.displayMode = mode end
        -- The gold display at the foot of the window, the same on every tab: the game writes
        -- the character's gold into it when the window opens and whenever the gold changes.
        local purse = Widget("Frame", nil, frame)
        MoneyDisplayModel(purse)
        purse:RegisterEvent("PLAYER_MONEY")
        purse:SetScript("OnEvent", function(self) self:SetAmount(W.player.money) end)
        frame.MoneyFrameBorder = { MoneyFrame = purse }
        W.AddOnLoaded("Blizzard_AuctionHouseUI")
    end
    AuctionHouseFrame.MoneyFrameBorder.MoneyFrame:SetAmount(W.player.money)
    W.Fire("AUCTION_HOUSE_SHOW")
end
function W.CloseAuctionHouse()
    W.Fire("AUCTION_HOUSE_CLOSED")
end
function PanelTemplates_TabResize() end
function PanelTemplates_DeselectTab(tab) tab._selected = false end
function PanelTemplates_SelectTab(tab) tab._selected = true end

---------------------------------------------------------------------------
-- The bag window and the bank
---------------------------------------------------------------------------
-- The game's bag window, as one window for all the bags (ContainerFrameCombinedBags): a slot
-- button for each slot of the backpack, and its own copy of the function that draws the items
-- (UpdateItems). The game calls that function when the window opens and when the bags change
-- while it is open (W.DrawBags). The stand-in draws nothing itself.
local function DrawItems() end
ContainerFrameContainer = { ContainerFrames = {} }
ContainerFrameCombinedBags = Widget("Frame", "ContainerFrameCombinedBags", UIParent)
ContainerFrameCombinedBags:Hide()
ContainerFrameCombinedBags.Items = {}
for slot = 1, 16 do
    local button = Widget("ItemButton", nil, ContainerFrameCombinedBags)
    function button.GetBagID() return 0 end
    function button.GetID() return slot end
    ContainerFrameCombinedBags.Items[slot] = button
end
ContainerFrameCombinedBags.UpdateItems = DrawItems
function ContainerFrameCombinedBags:EnumerateValidItems() return ipairs(self.Items) end

function W.OpenBags()
    ContainerFrameCombinedBags:Show()
    ContainerFrameCombinedBags:UpdateItems()
end

function W.DrawBags()
    if ContainerFrameCombinedBags:IsShown() then ContainerFrameCombinedBags:UpdateItems() end
end

-- The bank: its slots are made when it opens, from a pool, and each calls the function of
-- BankPanelItemButtonMixin to read and draw its item, whatever was hooked into it since.
local function BankRefresh(self)
    self.itemInfo = C_Container.GetContainerItemInfo(self._bag, self._slot)
end
BankPanelItemButtonMixin = { Refresh = BankRefresh }
BankPanel = Widget("Frame", "BankPanel", UIParent)
BankPanel:Hide()
BankPanel._buttons = {}
-- As a frame pool's EnumerateActive: the slots are the keys.
function BankPanel:EnumerateValidItems() return pairs(self._buttons) end

-- The bank opens on the tab whose items are W.bags[bag].
function W.OpenBank(bag)
    BankPanel:Show()
    BankPanel._buttons = {}
    for slot = 1, 16 do
        local button = Widget("ItemButton", nil, BankPanel)
        button._bag, button._slot = bag, slot
        function button.Refresh(self) BankPanelItemButtonMixin.Refresh(self) end
        BankPanel._buttons[button] = true
        button:Refresh()
    end
end

-- A new session has the game's own functions, with nothing hooked into them (see W.Logout).
function W.ResetBags()
    ContainerFrameCombinedBags.UpdateItems = DrawItems
    ContainerFrameCombinedBags:Hide()
    BankPanelItemButtonMixin.Refresh = BankRefresh
    BankPanel:Hide()
end

---------------------------------------------------------------------------
-- Pawn, for the scenarios that have it installed (W.InstallPawn). Written after Pawn 2.14.3:
-- the functions the addon calls, each with what matters of how it behaves there.
--   * A scale has an internal name ("\"Classic\":WARRIOR1" for one Pawn made for a talent
--     tree, the name the player gave it for one made by hand) and a name it is shown by
--     ("Warrior: Arms"). PawnCommon.Scales keeps them for the whole account, and for each
--     the characters that have it switched on, by their full names.
--   * An item's value on a scale is the sum of its stats times the scale's weights. A weight
--     of PawnIgnoreStatValue rules the item out: it is worth nothing.
--   * Asked about a scale there is not, Pawn writes an error line in the chat. Here those
--     are kept in W.pawn.fails, and a scenario checks that there are none.
--   * Nothing is returned for an item the client has not loaded, nor for one without stats.
--   * Pawn writes into the game's own item tooltips, about the character being played, as
--     its two options say: a line for an upgrade (ShowUpgradesOnTooltips), or the item's
--     value where values are shown without one (ShowValuesForUpgradesOnly false). It colours
--     the tooltip's border green beside an upgrade and takes the colour back otherwise
--     (tooltip._border). Here it writes only where a scenario asks (W.pawn.writes), and
--     takes every item it reads for an upgrade.
-- An item's Pawn stats are made the way its game stats are (C_Item.GetItemStats): one named
-- after each profile it was given a score on ("TEST_S1"), which a scale of the tests weighs
-- as it likes, and whatever its `pawn` table adds under Pawn's own names.
---------------------------------------------------------------------------
PawnIgnoreStatValue = nil

-- The full name Pawn files a character's choices under: as the addon's cards are filed.
function W.PawnName(player)
    player = player or W.player
    return player.last and (player.name .. " " .. player.last) or (player.name .. "-" .. GetRealmName())
end

local function PawnFunctions(P)
    local function Fail(message) P.fails[#P.fails + 1] = message end

    local function Visible(name)
        local scale = PawnCommon.Scales[name]
        if not scale then Fail("ScaleName must be the name of an existing scale: " .. tostring(name)) return nil end
        local notes = scale.PerCharacterOptions[W.PawnName()]
        return notes and notes.Visible
    end

    local function Sum(stats, name)
        local scale = PawnCommon.Scales[name]
        if not stats or not scale then return nil end
        local total = 0
        for stat, amount in pairs(stats) do
            local weight = scale.Values[stat]
            if weight and weight <= PawnIgnoreStatValue then return 0 end
            total = total + amount * (weight or 0)
        end
        return total
    end

    function PawnIsReady() return P.ready or nil end

    -- Every scale, those the character being played has switched on first, among those the
    -- ones made by hand before a provider's, and then by the name shown.
    function PawnGetAllScalesEx()
        if not P.ready then Fail("Can't get scale list until Pawn is initialized") return end
        local out = {}
        for name, scale in pairs(PawnCommon.Scales) do
            out[#out + 1] = { Name = name, LocalizedName = scale.LocalizedName or name, IsVisible = Visible(name), IsProvider = scale.Provider ~= nil }
        end
        table.sort(out, function(a, b)
            local aShown, bShown = a.IsVisible and true or false, b.IsVisible and true or false
            if aShown ~= bShown then return aShown end
            if a.IsProvider ~= b.IsProvider then return b.IsProvider end
            return a.LocalizedName:lower() < b.LocalizedName:lower()
        end)
        return out
    end

    -- The kinds of item Pawn never reads: what is not worn, a shirt, a tabard, a bag.
    function PawnCanItemHaveStats(link)
        local item = ParseItem(link)
        local kind = item and item.equipLoc
        return not (kind == nil or kind == "" or kind == "INVTYPE_BODY" or kind == "INVTYPE_TABARD" or kind == "INVTYPE_BAG")
    end

    -- (pawnBlind: an item Pawn cannot read, whatever the game says it adds.)
    function PawnGetItemData(link)
        if not link then return end
        P.asked[#P.asked + 1] = link
        local item, id = ParseItem(link)
        if not item or not item.cached then return nil end
        local kind = item.equipLoc
        if not PawnCanItemHaveStats(link) or item.pawnBlind then return nil end
        local stats = {}
        if not item.noStats then
            if item.value then stats.TEST_S1 = item.value end
            if item.value2 then stats.TEST_S2 = item.value2 end
            for profile, value in pairs(item.values or {}) do stats["TEST_" .. profile] = value end
            for name, amount in pairs(item.pawn or {}) do stats[name] = amount end
        end
        if next(stats) == nil then return nil end
        -- The lines Pawn could not turn into a number, by their text: what the item does
        -- (its lines in the tooltip above), unless the scenario says what Pawn stumbled on
        -- (pawnUnknown, a list of texts; pawnCounts: it read the line of what the item does
        -- while worn). And what another addon wrote into the tooltip Pawn reads
        -- (W.pawn.foreign, a list of texts): Pawn cannot read that either. None: no table.
        local unknown = {}
        if item.pawnUnknown then
            for _, text in ipairs(item.pawnUnknown) do unknown[text] = 1 end
        else
            if item.effects then unknown[ITEM_SPELL_TRIGGER_ONUSE .. " Does something."] = 1 end
            if item.equipLine and not item.pawnCounts then unknown["Equip: Does something else."] = 1 end
            if item.procLine then unknown["Chance on hit: Does something rare."] = 1 end
        end
        for _, text in ipairs(P.foreign or {}) do unknown[text] = 1 end
        return {
            Link = link, ID = id, InvType = kind, Name = item.name, Level = item.level + 5,
            Stats = stats, UnenchantedStats = stats,
            UnknownLines = next(unknown) ~= nil and unknown or nil,
        }
    end

    -- Pawn returns (with enchantments, base item). The first is made wrong on purpose, so
    -- that the tests notice if the addon reads the enchanted number.
    function PawnGetSingleValueFromItem(record, name)
        if not PawnCommon.Scales[name] then
            Fail("ScaleName must be the name of an existing scale: " .. tostring(name))
            return nil
        end
        local base = Sum(record.UnenchantedStats, name)
        return base + 1000, base
    end

    function PawnGetAllStatValues(name)
        local scale = PawnCommon.Scales[name]
        if not scale then Fail("ScaleName must be the name of an existing scale: " .. tostring(name)) return nil end
        return scale.Values
    end

    -- The arguments after the stats are kept, for the tests to see how it was asked.
    function PawnGetItemValue(stats, level, socketBonus, name, debug, noNormalization, noReforging)
        P.calls[#P.calls + 1] = { stats = stats, level = level, socketBonus = socketBonus, scale = name,
            debug = debug, noNormalization = noNormalization, noReforging = noReforging }
        local total = Sum(stats, name)
        if total == nil then return nil end
        return total, 0, 0
    end

    -- Called by Pawn itself whenever its scales change (W.PawnChanged).
    function PawnResetTooltips() P.resets = P.resets + 1 end

    -- Called by Pawn's hooks on the game's tooltips (M:SetHyperlink).
    function PawnUpdateTooltip(name, method, link)
        if not P.writes or not PawnCanItemHaveStats(link) then return end
        local tooltip = _G[name]
        local upgrade = PawnCommon.ShowUpgradesOnTooltips and true or false
        if upgrade then
            tooltip:AddLine("Pawn: upgrade")
        elseif not PawnCommon.ShowValuesForUpgradesOnly then
            tooltip:AddLine("Pawn: value")
        end
        tooltip._border = upgrade and "green" or "white"
    end
end

-- Pawn is installed and has read its scales (W.pawn.ready = false: it has not yet). Its
-- scales are added with W.AddPawnScale.
function W.InstallPawn()
    W.pawn = { ready = true, asked = {}, calls = {}, fails = {}, resets = 0 }
    PawnIgnoreStatValue = -1000000
    PawnCommon = { Scales = {}, ShowUpgradesOnTooltips = true, ShowValuesForUpgradesOnly = true }
    PawnFunctions(W.pawn)
end

-- Pawn is taken away, or switched off: the next session has none of it.
function W.RemovePawn()
    W.pawn = nil
    PawnIgnoreStatValue, PawnCommon = nil, nil
    PawnIsReady, PawnGetAllScalesEx, PawnGetItemData, PawnGetSingleValueFromItem = nil, nil, nil, nil
    PawnCanItemHaveStats = nil
    PawnGetAllStatValues, PawnGetItemValue, PawnResetTooltips = nil, nil, nil
    PawnUpdateTooltip = nil
end

-- def: { name = the internal name, title = the name shown (the internal one if not given),
--        class = the class's number and spec = the talent tree's, for a scale Pawn made from
--          a class's template: it is then a provider's,
--        values = { [stat] = weight },
--        shown = { the full names of the characters that have it switched on } or true for
--          the character being played,
--        no1H, no2H = it is not to show upgrades for one-handed or two-handed weapons }
function W.AddPawnScale(def)
    local scale = {
        Values = def.values or {}, LocalizedName = def.title, ClassID = def.class, SpecID = def.spec,
        Provider = def.class and "Classic" or nil, ProviderActive = def.class and true or nil,
        DoNotShow1HUpgrades = def.no1H or false, DoNotShow2HUpgrades = def.no2H or false,
        PerCharacterOptions = {},
    }
    local shown = def.shown == true and { W.PawnName() } or def.shown or {}
    for _, who in ipairs(shown) do scale.PerCharacterOptions[who] = { Visible = true } end
    PawnCommon.Scales[def.name] = scale
    return scale
end

-- The player changed something about the scales in Pawn's own window: Pawn then resets its
-- tooltips, which is how an addon can tell.
function W.PawnChanged()
    PawnResetTooltips()
end

-- A new session has Pawn's own functions, with nothing hooked into them (see W.Logout).
function W.ResetPawn()
    if W.pawn then PawnFunctions(W.pawn) end
end

return W
