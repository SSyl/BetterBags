-- interaction_bags_spec.lua -- What the backpack does at each interaction (core/hooks.lua,
-- .claude/rules/interaction-bags.md). The player picks, for each interaction BetterBags follows, whether its
-- window opens the backpack and closes it again (Open and Close, the default: what it always did), only opens
-- it (Open Only), or leaves it as it is (Leave Alone). Asked: #471 ("a toggle added to turn off bags closing
-- when leaving an NPC") and #755 (no auto open and no auto close on some interactions, trade among them). The
-- Character panel takes the same choices, left alone by default.

local addon = LibStub("AceAddon-3.0"):GetAddon("BetterBags")

describe("what the backpack does at an interaction", function()
  local aceAddon = LibStub("AceAddon-3.0")
  local moduleNames = { "Debug", "Events", "Context", "Items", "Constants", "Database" }
  local oldModules, oldAddons = {}, {}
  local savedBags, savedGameMenu, savedState
  local sent, later, choices, shown, bankNeedsRecalculation

  -- Every interaction BetterBags follows, by its name in Enum.PlayerInteractionType.
  local NAMES = { "TradePartner", "Banker", "AccountBanker", "Merchant", "MailInfo", "Auctioneer", "GuildBanker",
    "VoidStorageBanker", "ScrappingMachine", "ItemUpgrade" }

  before_each(function()
    for _, name in ipairs(moduleNames) do
      oldModules[name] = addon.modules[name]
      oldAddons[name] = aceAddon.addons["BetterBags_" .. name]
      addon.modules[name] = nil
      aceAddon.addons["BetterBags_" .. name] = nil
    end
    StubBetterBagsModule("Debug").Log = function() end
    sent, later = {}, {}
    local events = StubBetterBagsModule("Events")
    events.SendMessage = function(_, _, message, options)
      table.insert(sent, { message = message, options = options })
    end
    events.SendMessageLater = function(_, _, message)
      table.insert(later, message)
    end
    StubBetterBagsModule("Context")
    StubBetterBagsModule("Constants").BAG_KIND = { BACKPACK = 0, BANK = 1 }
    bankNeedsRecalculation = false
    StubBetterBagsModule("Items").NeedsInteractionRecalculation = function() return bankNeedsRecalculation end
    choices = {}
    for _, name in ipairs(NAMES) do
      choices[name] = "openClose"
    end
    choices.CharacterFrame = "none"
    StubBetterBagsModule("Database").GetInteractionBags = function(_, name)
      assert.is_not_nil(choices[name], "asked about " .. tostring(name))
      return choices[name]
    end

    savedGameMenu = _G.GameMenuFrame
    _G.GameMenuFrame = { IsShown = function() return false end }
    savedState = {
      atInteracting = addon.atInteracting,
      atWarbank = addon.atWarbank,
      atAuctionHouse = addon.atAuctionHouse,
      backpackShouldOpen = addon.backpackShouldOpen,
      backpackShouldClose = addon.backpackShouldClose,
      UpdateButtonHighlight = addon.UpdateButtonHighlight,
      hasWarbank = addon.hasWarbank,
    }
    addon.UpdateButtonHighlight = function() end
    addon.hasWarbank = true
    shown = false
    savedBags = addon.Bags
    addon.Bags = { Backpack = {
      Show = function() shown = true end,
      Hide = function() shown = false end,
      IsShown = function() return shown end,
    } }

    loadfile("core/hooks.lua")("BetterBags")
  end)

  after_each(function()
    addon.Bags = savedBags
    _G.GameMenuFrame = savedGameMenu
    for key, value in pairs(savedState) do
      addon[key] = value
    end
    for _, name in ipairs(moduleNames) do
      addon.modules[name] = oldModules[name]
      aceAddon.addons["BetterBags_" .. name] = oldAddons[name]
    end
  end)

  -- run sends the bags/OpenClose messages sent for later, as Events does a frame later.
  local function run()
    local pending = later
    later = {}
    for _, message in ipairs(pending) do
      assert.are.equal("bags/OpenClose", message)
      addon.OnUpdate(nil)
    end
  end

  local function open(name)
    addon.OpenInteractionWindow(nil, nil, Enum.PlayerInteractionType[name])
    run()
  end

  local function close(name)
    addon.CloseInteractionWindow(nil, nil, Enum.PlayerInteractionType[name])
    run()
  end

  local function rederives()
    local out = {}
    for _, s in ipairs(sent) do
      if s.message == "bags/Rederive" then
        out[#out + 1] = s.options
      end
    end
    return out
  end

  local RECALCULATION = { resetLayout = true, backpack = true, bank = false, categoriesUnchanged = true }

  it("opens the backpack with every interaction's window and closes it with it, until told otherwise", function()
    for _, name in ipairs(NAMES) do
      open(name)
      assert.is_true(shown, name .. " opens it")
      close(name)
      assert.is_false(shown, name .. " closes it")
    end
  end)

  it("closes the backpack after an interaction set to Open and Close, even one the player opened first", function()
    shown = true
    open("Merchant")
    close("Merchant")
    assert.is_false(shown)
  end)

  describe("Open Only", function()
    before_each(function()
      choices.Merchant = "open"
    end)

    it("opens the backpack, and leaves it open after", function()
      open("Merchant")
      assert.is_true(shown)
      close("Merchant")
      assert.is_true(shown, "still open")
      assert.is_false(addon.backpackShouldClose)
    end)

    it("recalculates the backpack as the window closes, so what dimmed for it does not stay dimmed", function()
      open("Merchant")
      sent = {}
      close("Merchant")
      assert.are.same({ RECALCULATION }, rederives())
      assert.is_false(addon.atInteracting)
    end)
  end)

  describe("Leave Alone", function()
    before_each(function()
      choices.Merchant = "none"
    end)

    it("neither opens a closed backpack nor closes an open one", function()
      open("Merchant")
      assert.is_false(shown, "not opened")
      assert.is_false(addon.backpackShouldOpen)
      close("Merchant")
      assert.is_false(shown)
      shown = true
      open("Merchant")
      close("Merchant")
      assert.is_true(shown, "not closed")
      assert.is_false(addon.backpackShouldClose)
    end)

    -- What opening the backpack did (addon.OnUpdate): the backpack dims what the window cannot take, and the bank
    -- unmerges at a shop, whether the backpack shows now or is opened later.
    it("recalculates the bags for the window as it opens and as it closes, once each", function()
      bankNeedsRecalculation = true
      open("Merchant")
      assert.is_true(addon.atInteracting)
      assert.are.same({ { resetLayout = true, backpack = true, bank = true, categoriesUnchanged = true } }, rederives())
      sent = {}
      close("Merchant")
      assert.is_false(addon.atInteracting)
      assert.are.same({ { resetLayout = true, backpack = true, bank = true, categoriesUnchanged = true } }, rederives())
    end)

    it("still knows the Auction House is open", function()
      choices.Auctioneer = "none"
      open("Auctioneer")
      assert.is_true(addon.atAuctionHouse)
      close("Auctioneer")
      assert.is_false(addon.atAuctionHouse)
    end)

    it("opens the backpack the player opens during the visit, recalculated for the window", function()
      open("Merchant")
      sent = {}
      addon:ToggleAllBags({})
      addon.OnUpdate(nil)
      assert.is_true(shown)
      assert.are.same({ RECALCULATION }, rederives())
      close("Merchant")
      assert.is_true(shown, "left open as it leaves")
    end)
  end)

  it("reads each interaction's own choice", function()
    for _, left in ipairs(NAMES) do
      for _, name in ipairs(NAMES) do
        choices[name] = name == left and "none" or "openClose"
      end
      for _, name in ipairs(NAMES) do
        shown = false
        open(name)
        assert.are.equal(name ~= left, shown, name .. " with " .. left .. " left alone")
        close(name)
        assert.is_false(shown, name .. " with " .. left .. " left alone")
      end
    end
  end)

  it("reads the choice as the window opens and again as it closes", function()
    open("Banker")
    assert.is_true(shown)
    choices.Banker = "open"
    close("Banker")
    assert.is_true(shown, "changed to Open Only during the visit")
  end)

  -- One window closing as the next opens, in the same frame (walking from a mailbox to a vendor): the closing
  -- window's choice closes the backpack, and only a next window that opens it keeps it open, whatever order the two
  -- events come in. Before the setting the next window always opened it, so it always stayed open.
  describe("one window handing over to the next in the same frame", function()
    local function handOver(from, to, closeFirst)
      shown = false
      open(from)
      assert.is_true(shown)
      if closeFirst then
        addon.CloseInteractionWindow(nil, nil, Enum.PlayerInteractionType[from])
        addon.OpenInteractionWindow(nil, nil, Enum.PlayerInteractionType[to])
      else
        addon.OpenInteractionWindow(nil, nil, Enum.PlayerInteractionType[to])
        addon.CloseInteractionWindow(nil, nil, Enum.PlayerInteractionType[from])
      end
      run()
      return shown
    end

    for _, closeFirst in ipairs({ true, false }) do
      local order = closeFirst and " (the hide first)" or " (the show first)"
      it("keeps the backpack open for a next window that opens it" .. order, function()
        assert.is_true(handOver("MailInfo", "Merchant", closeFirst))
        choices.Merchant = "open"
        assert.is_true(handOver("MailInfo", "Merchant", closeFirst))
      end)

      it("closes it as an Open and Close window hands over to one that leaves it alone" .. order, function()
        choices.Merchant = "none"
        assert.is_false(handOver("MailInfo", "Merchant", closeFirst))
      end)

      it("leaves it open as an Open Only window hands over to one that leaves it alone" .. order, function()
        choices.MailInfo, choices.Merchant = "open", "none"
        assert.is_true(handOver("MailInfo", "Merchant", closeFirst))
      end)
    end
  end)

  -- The Character panel (CharacterFrame, on any of its tabs) takes the same three choices, saved as "CharacterFrame",
  -- left alone until the player picks otherwise. Its window is no interaction: nothing in the
  -- bags dims for it, so it sends no recalculation and leaves atInteracting as it is.
  describe("the Character panel", function()
    -- Stands in for CharacterFrame, whose own shown flag stays set when only its parent hid it (a movie hides UIParent).
    local panel

    before_each(function()
      panel = { shown = false }
      function panel:IsShown() return self.shown end
    end)

    local function showPanel()
      panel.shown = true
      addon.OpenCharacterPanel(nil, panel)
      run()
    end

    local function hidePanel()
      panel.shown = false
      addon.CloseCharacterPanel(nil, panel)
      run()
    end

    -- The panel's OnHide and OnShow as its parent hides and shows it again, its own flag still set.
    local function parentHidesAndShows()
      addon.CloseCharacterPanel(nil, panel)
      run()
      addon.OpenCharacterPanel(nil, panel)
      run()
    end

    it("leaves the backpack alone until told otherwise", function()
      panel.shown = true
      addon.OpenCharacterPanel(nil, panel)
      assert.are.same({}, later, "nothing sent as it shows")
      assert.is_false(addon.backpackShouldOpen)
      run()
      assert.is_false(shown, "not opened")
      shown = true
      panel.shown = false
      addon.CloseCharacterPanel(nil, panel)
      assert.are.same({}, later, "nothing sent as it hides")
      assert.is_false(addon.backpackShouldClose)
      run()
      assert.is_true(shown, "not closed")
    end)

    it("opens the backpack with the panel and closes it with it, set to Open and Close", function()
      choices.CharacterFrame = "openClose"
      showPanel()
      assert.is_true(shown)
      hidePanel()
      assert.is_false(shown)
    end)

    it("closes the backpack the player opened first, set to Open and Close, as every interaction does", function()
      choices.CharacterFrame = "openClose"
      shown = true
      showPanel()
      hidePanel()
      assert.is_false(shown)
    end)

    it("opens the backpack, and leaves it open after, set to Open Only", function()
      choices.CharacterFrame = "open"
      showPanel()
      assert.is_true(shown)
      hidePanel()
      assert.is_true(shown, "still open")
      assert.is_false(addon.backpackShouldClose)
    end)

    it("reads the choice as the panel shows and again as it hides", function()
      choices.CharacterFrame = "openClose"
      showPanel()
      choices.CharacterFrame = "open"
      hidePanel()
      assert.is_true(shown, "changed to Open Only while it showed")
    end)

    it("sends no recalculation and leaves the interaction state as it is", function()
      choices.CharacterFrame = "openClose"
      addon.atInteracting = false
      showPanel()
      hidePanel()
      assert.are.same({}, rederives())
      assert.is_false(addon.atInteracting)
    end)

    -- What a BetterBags Next panel does when only a parent hid it (panelProto:OnHidden, hiddenByParent).
    it("neither closes nor opens the backpack when only the panel's parent hides and shows it", function()
      choices.CharacterFrame = "openClose"
      showPanel()
      assert.is_true(shown)
      parentHidesAndShows()
      assert.is_true(shown, "not closed by the parent's hide")
      shown = false
      parentHidesAndShows()
      assert.is_false(shown, "a backpack the player closed is not opened again")
    end)

    it("closes the backpack at the panel's own close after its parent showed it again", function()
      choices.CharacterFrame = "openClose"
      showPanel()
      parentHidesAndShows()
      hidePanel()
      assert.is_false(shown)
      showPanel()
      assert.is_true(shown, "and opens it at the next open")
    end)

    it("does not open the backpack again after its parent showed it, set to Open Only", function()
      choices.CharacterFrame = "open"
      showPanel()
      shown = false
      parentHidesAndShows()
      assert.is_false(shown)
    end)

    it("opens the backpack recalculated for a vendor the player is at", function()
      choices.CharacterFrame = "openClose"
      choices.Merchant = "none"
      open("Merchant")
      sent = {}
      showPanel()
      assert.is_true(shown)
      assert.are.same({ RECALCULATION }, rederives())
      assert.is_true(addon.atInteracting, "still at the vendor")
    end)
  end)

  it("asks nothing about an interaction it does not follow", function()
    addon.OpenInteractionWindow(nil, nil, Enum.PlayerInteractionType.Gossip)
    addon.CloseInteractionWindow(nil, nil, Enum.PlayerInteractionType.Gossip)
    assert.are.same({}, later)
    assert.are.same({}, sent)
  end)
end)
