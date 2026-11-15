-- Read by luacheck (https://github.com/lunarmodules/luacheck), which finds what a test does not
-- run into: a name that is not the game's, a variable nobody reads, a name that hides another.
--   luacheck UpgradeScout tests
std = "lua51"
max_line_length = false
exclude_files = { "UpgradeScout/Libs" }     -- other people's libraries

-- What the addon reads of the game. A name luacheck does not find here is a slip of
-- the pen, or something new: to be looked up in the client's own interface source (the branch
-- `forever` of Gethe/wow-ui-source on GitHub) and added.
read_globals = {
    -- functions of the game
    "CanDualWield", "Clamp", "CreateDataProvider", "CreateFontFamily", "CreateFrame", "CreateScrollBoxListLinearView", "CursorHasItem",
    "FormatPercentage", "GetCursorPosition", "GetInventoryItemLink", "GetLocale", "GetMoney", "GetMoneyString",
    "GetInboxItemLink", "GetInboxNumItems", "GetProfessionInfo", "GetProfessions", "GetRealmName", "GetSendMailItem",
    "GetSendMailItemLink", "GetTime", "HandleModifiedItemClick", "InCombatLockdown",
    "IsModifiedClick", "PlaySound", "ResetCursor", "SendMail", "ShowInspectCursor", "UnitClass", "UnitFactionGroup", "UnitLevel", "UnitName",
    "UnitPowerMax", "UnitRace", "debugprofilestop", "hooksecurefunc", "issecretvalue", "securecallfunction", "time",
    "GameTooltip_AddBlankLineToTooltip", "GameTooltip_AddColoredLine", "GameTooltip_AddDisabledLine",
    "GameTooltip_AddErrorLine", "GameTooltip_AddHighlightLine", "GameTooltip_AddNormalLine", "GameTooltip_Hide",
    "GameTooltip_SetTitle", "GameTooltip_ShowCompareItem",
    -- its tables of functions and of numbers
    "AnchorUtil",
    "C_AuctionHouse", "C_ClassTalents", "C_Container", "C_Item", "C_SpellBook", "C_Timer", "C_TooltipInfo", "C_Traits",
    "ColorManager", "Constants", "Settings",
    "Enum", "EventUtil", "TooltipDataProcessor", "TooltipUtil", "MoneyStringConstants", "PixelUtil", "SOUNDKIT", "ScrollBoxConstants", "ScrollUtil",
    "BankPanelItemButtonMixin",
    -- its frames, fonts and colours
    "AuctionHouseFrame", "GameTooltip", "MailFrame", "MailFrameTab2", "Minimap", "SendMailNameEditBox", "SendMailSubjectEditBox",
    "ItemRefTooltip", "ShoppingTooltip1", "UIParent", "UISpecialFrames", "BankPanel", "ContainerFrameCombinedBags", "ContainerFrameContainer", "GameFontNormal", "Number13FontWhite", "PriceFontGray", "PriceFontRed", "PriceFontWhite", "STANDARD_TEXT_FONT",
    "GRAY_FONT_COLOR", "GREEN_FONT_COLOR", "HIGHLIGHT_FONT_COLOR", "NORMAL_FONT_COLOR", "RED_FONT_COLOR", "RAID_CLASS_COLORS",
    -- its words
    "CANCEL", "DAYS_ABBR", "HOURS_ABBR", "MINUTES_ABBR", "SECONDS_ABBR", "NONE",
    "ITEM_CLASSES_ALLOWED", "ITEM_MIN_SKILL", "ITEM_RACES_ALLOWED", "ITEM_REQ_REPUTATION", "ITEM_SPELL_TRIGGER_ONUSE",
    "ITEM_UNIQUE_EQUIPPABLE", "ITEM_UNSELLABLE", "LARGE_NUMBER_SEPERATOR", "LOCALIZED_CLASS_NAMES_FEMALE", "LOCALIZED_CLASS_NAMES_MALE",
    "RETRIEVING_ITEM_INFO", "SELL_PRICE", "SHIELD_BLOCK_TEMPLATE",
    -- its numbers
    "ATTACHMENTS_MAX_RECEIVE", "ATTACHMENTS_MAX_SEND", "NUM_TOTAL_EQUIPPED_BAG_SLOTS",
    -- the libraries that come with the addon
    "LibStub",
    -- what other addons define, where they are installed: the shape one gave the minimap
    "GetMinimapShape",
    -- and Pawn, for a player who has it and chose it to score (Pawn.lua)
    "PawnCanItemHaveStats",
    "PawnGetAllScalesEx", "PawnGetItemData", "PawnGetItemValue", "PawnGetSingleValueFromItem", "PawnIsReady",
    "PawnResetTooltips",
    -- (its two options for what it writes into a tooltip are set for the length of a call
    -- and put back: Pawn.Hushed)
    PawnCommon = {
        other_fields = true,
        fields = {
            ShowUpgradesOnTooltips = { read_only = false },
            ShowValuesForUpgradesOnly = { read_only = false },
        },
    },
}

-- What the addon writes: its saved variables and its slash command.
globals = {
    "UpgradeScoutCharDB", "UpgradeScoutDB", "SLASH_UPGRADESCOUT1", "SLASH_UPGRADESCOUT2", "SlashCmdList",
}

-- The tests stand in for the game. They define its globals, which is their job, with the game's
-- own arguments whether they have a use for them or not.
files["tests"] = { global = false, self = false, unused_args = false, ignore = { "432" } }
