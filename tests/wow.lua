-- A small stand-in for the World of Warcraft client, enough to run Upgrade Scout outside the
-- game: frames, events, timers, an item database, an auction house server with paging and a
-- request throttle, and a fake Pawn. Widget methods are a fixed list on purpose: calling a
-- method that is not on the list fails the test, which catches misspelled API calls.
local W = {}

W.now = 1000
W.frames = {}
W.texts = {}            -- every font string, so tests can read what the tab says
W.timers = {}
W.printed = {}
W.popups = {}
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
--        red, unique, effects, noStats, uncached, classCant,
--        values = { [scale] = score } for scales other than the two the tests began with,
--        stats = { IsMail = 1, ... } as Pawn reads them off the tooltip,
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

function W.Link(id, suffix)
    local item = W.items[id .. ":" .. (suffix or 0)]
    return "|cff1eff00|Hitem:" .. id .. "::::::" .. ((suffix or 0) ~= 0 and suffix or "") .. "::::|h[" .. item.name .. "]|h|r"
end

local function ParseItem(info)
    if type(info) == "number" then return W.items[info .. ":0"], info, 0 end
    local id = tonumber(info:match("item:(%d+)"))
    if not id then return nil end
    local suffix = tonumber(info:match("item:%d+:%-?%d*:%-?%d*:%-?%d*:%-?%d*:%-?%d*:(%-?%d*)")) or 0
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
    "SetPoint", "ClearAllPoints", "SetAllPoints", "SetJustifyH", "SetWordWrap", "SetSpacing",
    "SetColorTexture", "SetBlendMode", "SetTexCoord", "SetVertexColor", "SetAlpha",
    "SetFontObject", "SetTextColor", "SetShadowColor", "SetShadowOffset",
    "SetHitRectInsets", "SetTitle", "UnregisterEvent",
    "SetFrameStrata", "EnableMouse",
    -- edit boxes
    "SetAutoFocus", "SetNumeric", "SetMaxLetters", "SetFocus", "ClearFocus", "HighlightText",
}) do
    M[name] = noop
end

-- Edit boxes. What the addon writes into one and what the player types (W.Type) both reach the
-- box's OnTextChanged, as in the game; the second argument says which of the two it was.
function M:SetNumber(number)
    assert(self._kind == "EditBox" and type(number) == "number", "a number for an edit box")
    self._text = tostring(number)
    if self._scripts.OnTextChanged then self._scripts.OnTextChanged(self, false) end
end
function M:GetNumber() return tonumber(self._text) or 0 end
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
function M:GetTexture() return self._texture end
function M:SetFont(file, size, flags)
    assert(type(file) == "string" and type(size) == "number" and type(flags) == "string", "a font file, a size and flags")
    self._font = file
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
function M:CreateTexture() return Widget("Texture", nil, self) end
function M:CreateFontString() return Widget("FontString", nil, self) end
function M:SetText(text)
    -- The game refuses to write with no font. (The tab of the window gets its font from a template.)
    if self._kind == "FontString" then assert(self._font, "a font is set before the text") end
    self._text = text
end
function M:GetText() return self._text end
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
function M:ClearLines() self._lines = {} end
-- As in the game, giving a tooltip an owner empties it.
function M:SetOwner(owner) self._owner = owner self:ClearLines() end
function M:IsOwned(frame) return self._owner == frame end
function M:NumLines() return self._lines and #self._lines or 0 end
function M:AddLine(text, r, g, b)
    self._lines = self._lines or {}
    self._lines[#self._lines + 1] = { text = text, r = r, g = g, b = b }
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
local function AddRequirements(lines, item)
    local function Line(text, met)
        lines[#lines + 1] = { leftText = text, leftColor = met and HIGHLIGHT_FONT_COLOR or RED_FONT_COLOR }
    end
    if item.level > 1 then
        Line("Requires Level " .. item.level, item.level <= W.player.level)
    end
    if item.classes then
        Line(ITEM_CLASSES_ALLOWED:format(item.classes),
            item.classes:find(LOCALIZED_CLASS_NAMES_MALE[W.player.class] or "?", 1, true) ~= nil)
    end
    if item.races then
        Line(ITEM_RACES_ALLOWED:format(item.races), item.races:find(W.player.race or "Human", 1, true) ~= nil)
    end
    if item.skill then
        Line(ITEM_MIN_SKILL:format(item.skill[1], item.skill[2]), (PlayerSkill(item.skill[1]) or 0) >= item.skill[2])
    end
    if item.reputation then
        Line(ITEM_REQ_REPUTATION:format("Argent Dawn", "Revered"), false)
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
        { leftText = "Chest", leftColor = HIGHLIGHT_FONT_COLOR, rightText = "Mail",
            rightColor = item.red and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR },
    }
    AddRequirements(lines, item)
    return lines
end

C_TooltipInfo = {}
function C_TooltipInfo.GetHyperlink(link)
    W.tooltipReads = (W.tooltipReads or 0) + 1
    return { lines = TooltipLines(link) }
end

function M:SetHyperlink(link)
    self:ClearLines()
    for _, line in ipairs(TooltipLines(link)) do
        self:AddLine(line.leftText, line.leftColor:GetRGB())
    end
    self._shown = true
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

-- MoneyDisplayFrameTemplate: gold, silver and copper as coins.
local function MoneyDisplayModel(money)
    money.CopperDisplay = {}
    function money.CopperDisplay:SetForcedHidden(hidden) money._copperHidden = hidden end
    function money:SetAmount(copper)
        assert(type(copper) == "number" and copper >= 0 and copper == math.floor(copper), "a whole number of copper")
        self._amount = copper
    end
    function money:GetAmount() return self._amount end
    function money:SetFontObject(font)
        assert(font ~= nil, "a font object")
        self._font = font
    end
end

-- WowStyle1DropdownTemplate: shows the ticked line of its menu, or the default text. The menu
-- is described by a generator function, which runs again every time the menu opens.
local function DropdownModel(dropdown)
    dropdown.radios = {}
    local function ShowSelection(self)
        local text
        for _, radio in ipairs(self.radios) do
            if radio.isSelected(radio.data) then text = radio.text end
        end
        self._text = text or self._default
    end
    function dropdown:SetDefaultText(text)
        self._default = text
        ShowSelection(self)
    end
    function dropdown:SetTooltip(tooltipFunc) self._tooltip = tooltipFunc end
    function dropdown:GenerateMenu()
        assert(not self._open, "the menu is not rebuilt while it is open")
        local root = { radios = {}, dividers = 0 }
        function root:CreateRadio(text, isSelected, setSelected, data)
            self.radios[#self.radios + 1] = { text = text, isSelected = isSelected, setSelected = setSelected, data = data }
        end
        -- A line across the menu; `after` says which radio each one follows.
        function root:CreateDivider()
            self.dividers = self.dividers + 1
            self.after = self.after or {}
            self.after[#self.after + 1] = #self.radios
        end
        function root:SetScrollMode(extent)
            assert(type(extent) == "number" and extent > 0, "a height in pixels")
            self.scroll = extent
        end
        self._generator(self, root)
        self.radios = root.radios
        self.dividers, self.dividersAfter, self.scroll = root.dividers, root.after or {}, root.scroll
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
-- Where a frame's right edge is on the screen: unknown unless a test says (frame._right).
function M:GetRight() return self._right end

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
-- Lua functions the game also offers under short global names (LibStub uses them).
strmatch, strfind, strsub, format, tinsert, tremove = string.match, string.find, string.sub, string.format, table.insert, table.remove
WOW_PROJECT_MAINLINE, WOW_PROJECT_CAMELOT = 1, 99
WOW_PROJECT_ID = WOW_PROJECT_CAMELOT
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    W.printed[#W.printed + 1] = table.concat(parts, " ")
end
function hooksecurefunc(tbl, name, hook)
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
function IsPlayerSpell(spell) return W.player.spells ~= nil and W.player.spells[spell] == true end
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
function UnitPowerMax(_, power) return power == 0 and (W.player.mana or 0) or 0 end
function GetInventoryItemLink(_, slot) return W.equipped[slot] end
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
ACCEPT, CANCEL, NONE = "Accept", "Cancel", "None"
BUYOUT_AUCTION_CONFIRMATION = "Buyout auction for:"
SECONDS_ABBR, MINUTES_ABBR, HOURS_ABBR, DAYS_ABBR = "%d Sec", "%d Min", "%d Hr", "%d Days"
-- The colours of the classes, as the game's ColorMixin objects.
RAID_CLASS_COLORS = { WARRIOR = Color(0.78, 0.61, 0.43), DRUID = Color(1, 0.49, 0.04), MAGE = Color(0.25, 0.78, 0.92) }
PriceFontWhite, PriceFontRed = { name = "PriceFontWhite" }, { name = "PriceFontRed" }
-- The font files the tab writes with: the standard one, and the one behind the game's number fonts.
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
Number13FontWhite = { GetFont = function() return "Fonts\\ARIALN.TTF", 13, "" end }
ITEM_QUALITY_COLORS = { [2] = { color = Color(0.118, 1, 0) }, [3] = { color = Color(0, 0.44, 0.87) } }
ColorManager = {}
function ColorManager.GetColorDataForItemQuality(quality) return ITEM_QUALITY_COLORS[quality] end

function Clamp(value, low, high) return math.max(low, math.min(high, value)) end
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
    awaitingAddOn = {}
    W.charSaved[W.player.name] = UpgradeScoutCharDB
    UpgradeScoutCharDB = nil
    AuctionHouseFrame, LibStub = nil, nil
    W.equipped = {}
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
-- Confirmation boxes. One of a kind is up at a time; a box that goes away runs its OnHide.
StaticPopupDialogs = {}
local function HidePopup(popup)
    if not popup.shown then return end
    popup.shown = false
    local info = StaticPopupDialogs[popup.which]
    if info.OnHide then info.OnHide(popup.dialog, popup.data) end
end
function StaticPopup_Hide(which)
    for _, popup in ipairs(W.popups) do
        if popup.which == which then HidePopup(popup) end
    end
end
function StaticPopup_Show(which, arg1, arg2, data)
    local info = assert(StaticPopupDialogs[which], "a registered dialog")
    StaticPopup_Hide(which)
    if info.hasItemFrame then
        assert(type(data) == "table" and data.link and data.useLinkForItemInfo, "an item for the box to show")
    end
    local dialog = Widget("Frame")
    dialog.which, dialog.data = which, data
    dialog.MoneyFrame = Widget("Frame", nil, dialog)
    local popup = { which = which, arg1 = arg1, arg2 = arg2, data = data, dialog = dialog, shown = true }
    dialog._popup = popup
    W.popups[#W.popups + 1] = popup
    if info.OnShow then info.OnShow(dialog, data) end
    return dialog
end
-- After "Accept" the box stays up, buttons greyed, until one of the events says it may go.
function StaticPopup_OnAcceptWithSpinner(onAccept, onEvent, events, spinnerDelay, dialog)
    assert(type(spinnerDelay) == "number" and dialog and dialog._popup, "called by the box, with its arguments in order")
    onAccept(dialog)
    for _, event in ipairs(events) do dialog:RegisterEvent(event) end
    dialog:SetScript("OnEvent", function(self, event, ...)
        if onEvent(self, event, ...) then
            self:SetScript("OnEvent", nil)
            HidePopup(self._popup)
        end
    end)
    return true
end
-- The player presses the first button.
function W.AcceptPopup(popup)
    assert(popup.shown, "the box is up")
    local stays = StaticPopupDialogs[popup.which].OnAccept(popup.dialog, popup.data)
    if not stays then HidePopup(popup) end
end

Enum = {
    ItemClass = { Consumable = 0, Weapon = 2, Armor = 4 },
    PowerType = { Mana = 0, Rage = 1, Energy = 3 },
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
        item.equipLoc, 134400, 100, item.classID, item.subClassID
end
-- The spell an item casts when it is used: consumables have one, and say what it does (`use`).
function C_Item.GetItemSpell(info)
    local item = ParseItem(info)
    if item and item.use then return "Spell of " .. item.name, 100000 + item.id end
end
-- The game's names for the subcategories of Consumables it knows.
W.subNames = { [1] = "Potions", [2] = "Elixirs", [5] = "Food & Drink", [7] = "Bandages" }
function C_Item.GetItemSubClassInfo(classID, subClassID)
    if classID == 0 then return W.subNames[subClassID] end
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
    -- quantity: for things sold by the piece, how many pieces the seller put up at this price.
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
    A.results[KeyText(key)] = list
    A.loaded[KeyText(key)] = math.min(#list, A.itemPageSize)
    local copy = { itemID = key.itemID, itemLevel = key.itemLevel, itemSuffix = key.itemSuffix, battlePetSpeciesID = 0 }
    C_Timer.After(0.2, function() W.Fire("ITEM_SEARCH_RESULTS_UPDATED", copy) end)
end

---------------------------------------------------------------------------
-- Things sold by the piece ("commodities"): every consumable that stacks. All sellers' pieces
-- of an item are one pile; a purchase takes the cheapest pieces first.
---------------------------------------------------------------------------
function W.IsCommodity(itemID)
    local item = W.items[itemID .. ":0"]
    return item ~= nil and item.classID == 0 and (item.stack or 1) > 1
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
-- The game takes both of these only from a click; the tests call them from one.
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
            W.Fire("COMMODITY_PURCHASE_FAILED")
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
function C_AuctionHouse.PlaceBid(auctionID, amount)
    A.calls.bids[#A.calls.bids + 1] = { auctionID = auctionID, amount = amount }
    for i = #A.auctions, 1, -1 do
        if A.auctions[i].auctionID == auctionID then table.remove(A.auctions, i) end
    end
    C_Timer.After(0.2, function() W.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID) end)
end
function C_AuctionHouse.SearchForFavorites() end
function C_AuctionHouse.SearchForItemKeys() end
function C_AuctionHouse.SupportsCopperValues() return W.AH.copper ~= false end

-- The auction window, as far as LibAHTab and the addon touch it.
-- The game loads the window (the addon Blizzard_AuctionHouseUI) the first time it is needed.
function W.OpenAuctionHouse()
    if not AuctionHouseFrame then
        local frame = Widget("Frame", "AuctionHouseFrame")
        frame:SetSize(800, 538)
        frame.Tabs = { Widget("Button", nil, frame), Widget("Button", nil, frame), Widget("Button", nil, frame) }
        frame.SetDisplayMode = function(self, mode) self.displayMode = mode end
        W.AddOnLoaded("Blizzard_AuctionHouseUI")
    end
    W.Fire("AUCTION_HOUSE_SHOW")
end
function W.CloseAuctionHouse()
    W.Fire("AUCTION_HOUSE_CLOSED")
end
function PanelTemplates_TabResize() end
function PanelTemplates_DeselectTab(tab) tab._selected = false end
function PanelTemplates_SelectTab(tab) tab._selected = true end

---------------------------------------------------------------------------
-- Pawn
---------------------------------------------------------------------------
W.pawnReady = true
function PawnIsReady() return W.pawnReady end
-- Every scale Pawn has, those it shows for the character being played first. A test that
-- plays another class puts that class's scales here.
W.pawnScales = {
    { Name = "S1", LocalizedName = "Arms", IsVisible = true },
    { Name = "S2", LocalizedName = "Protection", IsVisible = true },
    { Name = "S3", LocalizedName = "Hidden", IsVisible = false },
}
function PawnGetAllScalesEx()
    local out = {}
    for i, scale in ipairs(W.pawnScales) do out[i] = scale end
    return out
end
-- What Pawn saves for the whole account: every scale, and for each the characters that have
-- it switched on. Scales made from a class's template know their class.
PawnCommon = { Scales = { S1 = { PerCharacterOptions = {} }, S2 = { PerCharacterOptions = {} }, S3 = { PerCharacterOptions = {} } } }
-- The kinds of item a class never wears, as Pawn lists them by class number.
PawnNeverUsableStats = { [1] = { "IsWand" }, [8] = { "IsMail", "IsPlate", "IsShield" }, [11] = { "IsMail", "IsPlate", "IsShield" } }
function PawnGetItemData(link)
    local item, id = ParseItem(link)
    if not item or not item.cached or item.noStats then return nil end
    return {
        Link = link, ID = id, InvType = item.equipLoc, Name = item.name,
        CanEquip = not item.classCant,
        Stats = item.stats,
        UnknownLines = item.effects and { ["Use: Does something."] = 1 } or nil,
        _item = item,
    }
end
function PawnGetSingleValueFromItem(record, scale)
    local item = record._item
    local value
    if item.values and item.values[scale] ~= nil then
        value = item.values[scale]
    elseif scale == "S1" then
        value = item.value
    else
        -- A scale the item was given no score on values nothing of it.
        value = scale == "S2" and item.value2 or 0
    end
    -- Pawn returns (with enchantments, base item); make the first one wrong on purpose so the
    -- tests notice if the addon reads the enchanted number.
    return value + 1000, value
end
function PawnGetItemDataForInventorySlot(slot)
    local link = W.equipped[slot]
    if not link then return nil, false end
    return PawnGetItemData(link), true
end
function PawnIsArmorBestTypeForPlayer(record) return not record._item.wrongArmor end

-- What each scale gives a point of a stat. Scoring a bare set of stats, as the addon does for
-- what a consumable adds, is Pawn's own sum over these.
W.pawnWeights = {
    S1 = { Strength = 1.5, Agility = 1, Stamina = 0.5, Ap = 0.4, CritRating = 8, Health = 0.05 },
    S2 = { Intellect = 1, Stamina = 0.5, SpellDamage = 0.8 },
}
W.pawnCalls = {}        -- the arguments of every PawnGetItemValue call after the stats
function PawnGetAllStatValues(scale) return W.pawnWeights[scale] end
function PawnGetItemValue(stats, level, socketBonus, scale, debug, noNormalization, noReforging)
    W.pawnCalls[#W.pawnCalls + 1] = { level = level, socketBonus = socketBonus, scale = scale,
        debug = debug, noNormalization = noNormalization, noReforging = noReforging }
    local weights = W.pawnWeights[scale]
    if not stats or not weights then return nil end
    local total = 0
    for name, amount in pairs(stats) do total = total + amount * (weights[name] or 0) end
    return total, 0, 0
end
function PawnGetShowUpgradesForWeapons() return true end

return W
