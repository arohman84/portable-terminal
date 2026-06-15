-- PortableTerminalUI.lua
-- UI for the Portable Terminal - a portable inventory item that remotely
-- connects to a Warehouse Packer IP to browse and transfer items.
-- REQUIRES: WarehouseTerminal_Balanced mod
-- Style matches WarehouseTerminal_Balanced's two-panel layout.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISTextBox"
require "ISUI/ISMouseDrag"
require "ISUI/ISInventoryPane"
require "TimedActions/ISInventoryTransferAction"
require "WarehouseTerminal/WarehouseTerminalVariant"
require "WarehouseTerminal/WarehouseTerminalUI"
require "PortableTerminal/PortableTerminalPowerMonitor"
require "PortableTerminal/PortableTerminalTemperatureMonitor"

PortableTerminal = PortableTerminal or {}
PortableTerminal.USE_RADIUS = 3
PortableTerminal.SCAN_INTERVAL_MS = 30000
PortableTerminal.MAX_SCAN_FAILURES = 5
PortableTerminal.SCAN_BACKOFF_MULTIPLIER = 2
PortableTerminal.FAST_REFRESH_INTERVAL_MS = 800
PortableTerminal.FAST_REFRESH_MIN_COUNT = 3
PortableTerminal.FAST_REFRESH_MAX_COUNT = 15

-- Battery system (drains per item transferred via the terminal)
-- Defaults can be overridden via Sandbox options.
PortableTerminal.BATTERY_MAX = 100
PortableTerminal.BATTERY_DRAIN_PER_ITEM = 2.0
PortableTerminal.BATTERY_KEY = "DeviceBattery"

-- Read sandbox overrides (applied once on first load)
if not PortableTerminal._sandboxInitialized then
    PortableTerminal._sandboxInitialized = true
    if SandboxVars and SandboxVars.PortableTerminal then
        local sbMax = tonumber(SandboxVars.PortableTerminal.BatteryMax)
        if sbMax and sbMax > 0 then
            PortableTerminal.BATTERY_MAX = math.floor(sbMax)
        end
        local sbDrain = tonumber(SandboxVars.PortableTerminal.BatteryDrainPerItem)
        if sbDrain and sbDrain > 0 then
            PortableTerminal.BATTERY_DRAIN_PER_ITEM = sbDrain
        end
    end
end

function PortableTerminal.getDeviceBattery(item)
    if not item then return PortableTerminal.BATTERY_MAX end
    local val = tonumber(item:getModData()[PortableTerminal.BATTERY_KEY])
    if val == nil then return PortableTerminal.BATTERY_MAX end
    return math.max(0, math.min(PortableTerminal.BATTERY_MAX, val))
end

function PortableTerminal.setDeviceBattery(item, value)
    if not item then return end
    value = math.max(0, math.min(PortableTerminal.BATTERY_MAX, math.floor(value or PortableTerminal.BATTERY_MAX)))
    if value >= PortableTerminal.BATTERY_MAX then
        item:getModData()[PortableTerminal.BATTERY_KEY] = nil
    else
        item:getModData()[PortableTerminal.BATTERY_KEY] = value
    end
end

PortableTerminalWindow = ISCollapsableWindow:derive("PortableTerminalWindow")
PortableTerminalItemList = ISScrollingListBox:derive("PortableTerminalItemList")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

-- ============================================================================
-- Color Scheme (matches WarehouseTerminal dark theme)
-- ============================================================================
PortableTerminal.Colors = {
    window      = { r = 0.015, g = 0.025, b = 0.026, a = 0.90 },
    border      = { r = 0.18, g = 0.58, b = 0.54, a = 1.00 },
    list        = { r = 0.012, g = 0.025, b = 0.026, a = 0.62 },
    input       = { r = 0.010, g = 0.035, b = 0.034, a = 0.82 },
    inputBorder = { r = 0.18, g = 0.58, b = 0.54, a = 1.00 },
    rowAlt      = { r = 0.025, g = 0.060, b = 0.060, a = 0.55 },
    rowSelected = { r = 0.030, g = 0.240, b = 0.205, a = 0.86 },
    rowBorder   = { r = 0.125, g = 0.350, b = 0.340, a = 0.55 },
    header      = { r = 0.025, g = 0.075, b = 0.073, a = 0.58 },
    text        = { r = 0.88, g = 0.95, b = 0.92, a = 1.00 },
    textDim     = { r = 0.56, g = 0.74, b = 0.72, a = 1.00 },
    accent      = { r = 0.22, g = 0.86, b = 0.62, a = 1.00 },
    cold        = { r = 0.42, g = 0.78, b = 1.00, a = 1.00 },
    amber       = { r = 0.95, g = 0.72, b = 0.28, a = 1.00 },
    danger      = { r = 0.82, g = 0.24, b = 0.22, a = 1.00 }
}

-- ============================================================================
-- Styling helpers
-- ============================================================================
local function drawClippedText(ui, text, x, y, maxWidth, r, g, b, a, font)
    text = tostring(text or "")
    font = font or UIFont.Small
    if maxWidth and getTextManager():MeasureStringX(font, text) > maxWidth then
        while getTextManager():MeasureStringX(font, text .. "...") > maxWidth and #text > 0 do
            text = string.sub(text, 1, -2)
        end
        text = text .. "..."
    end
    ui:drawText(text, x, y, r, g, b, a, font)
end

local function normalizePIN(value, allowEmpty)
    value = tostring(value or ""):gsub("%s+", "")
    if value == "" and allowEmpty then return "" end
    if value:match("^%d%d%d%d$") then return value end
    return nil
end

function PortableTerminal.applyInputStyle(entry)
    if not entry then return end
    local c = PortableTerminal.Colors
    entry.backgroundColor = c.input
    entry.borderColor = c.inputBorder
end

function PortableTerminal.applyListStyle(list)
    if not list then return end
    local c = PortableTerminal.Colors
    list.backgroundColor = c.list
    list.borderColor = c.border
    list.drawBorder = true
end

function PortableTerminal.applyButtonStyle(button, kind, active)
    if not button then return end
    local c = PortableTerminal.Colors
    local base   = { r = 0.018, g = 0.052, b = 0.052, a = 0.90 }
    local over   = { r = 0.045, g = 0.145, b = 0.130, a = 1.00 }
    local border = { r = 0.18, g = 0.58, b = 0.54, a = 1.00 }
    local text   = c.text

    if kind == "take" then
        base   = { r = 0.030, g = 0.080, b = 0.120, a = 0.92 }
        over   = { r = 0.055, g = 0.150, b = 0.210, a = 1.00 }
        border = { r = 0.28, g = 0.62, b = 0.86, a = 1.00 }
    elseif kind == "store" then
        base   = { r = 0.025, g = 0.110, b = 0.080, a = 0.92 }
        over   = { r = 0.040, g = 0.180, b = 0.120, a = 1.00 }
        border = { r = 0.22, g = 0.78, b = 0.48, a = 1.00 }
    elseif kind == "config" then
        base   = { r = 0.095, g = 0.075, b = 0.030, a = 0.92 }
        over   = { r = 0.160, g = 0.120, b = 0.045, a = 1.00 }
        border = { r = 0.82, g = 0.62, b = 0.26, a = 1.00 }
    elseif kind == "danger" then
        base   = { r = 0.150, g = 0.035, b = 0.030, a = 0.92 }
        over   = { r = 0.240, g = 0.060, b = 0.050, a = 1.00 }
        border = { r = c.danger.r, g = c.danger.g, b = c.danger.b, a = 1.00 }
    elseif active then
        base   = { r = 0.025, g = 0.180, b = 0.145, a = 0.96 }
        over   = { r = 0.040, g = 0.240, b = 0.180, a = 1.00 }
        border = { r = 0.24, g = 0.86, b = 0.62, a = 1.00 }
    end

    button.backgroundColor         = base
    button.backgroundColorMouseOver = over
    button.borderColor             = border
    button.borderColorEnabled      = border
    button.textColor               = { r = text.r, g = text.g, b = text.b, a = text.a }
end

-- ============================================================================
-- PIN helpers (stored on the device item's modData)
-- ============================================================================
function PortableTerminal.getDevicePIN(item)
    if not item then return nil end
    local pin = item:getModData().DevicePIN
    return normalizePIN(pin, false)
end

function PortableTerminal.setDevicePIN(item, pin)
    if not item then return false end
    local normalized = normalizePIN(pin, true)
    if normalized == nil then return false end
    if normalized == "" then
        item:getModData().DevicePIN = nil
    else
        item:getModData().DevicePIN = normalized
    end
    return true
end

function PortableTerminal.hasDevicePIN(item)
    return PortableTerminal.getDevicePIN(item) ~= nil
end

-- ============================================================================
-- PortableTerminal Helper Functions
-- ============================================================================
function PortableTerminal.isDeviceItem(item)
    if not item then return false end
    local ok, fullType = pcall(function() return item:getFullType() end)
    return ok and fullType == "Base.PortableTerminal"
end

function PortableTerminal.getDevicePackerIP(item)
    if not item then return nil end
    return WarehouseTerminal.normalizePackerIP(item:getModData().DevicePackerIP)
end

function PortableTerminal.setDevicePackerIP(item, ip)
    if not item then return false end
    local normalized = WarehouseTerminal.normalizePackerIP(ip)
    if not normalized and tostring(ip or "") ~= "" then return false end
    if tostring(ip or "") == "" then
        item:getModData().DevicePackerIP = nil
    else
        item:getModData().DevicePackerIP = normalized
    end
    return true
end

function PortableTerminal.getFastRefreshCount(itemCount)
    -- 2 refreshes per item covers typical transfer time (~1s per item via timed actions).
    return math.min(PortableTerminal.FAST_REFRESH_MAX_COUNT,
        math.max(PortableTerminal.FAST_REFRESH_MIN_COUNT,
            math.ceil((itemCount or 1) * 2)))
end

function PortableTerminal.findPackerForItem(item, playerObj)
    local ip = PortableTerminal.getDevicePackerIP(item)
    if not ip then return nil end
    if not playerObj or not playerObj:getSquare() then return nil end

    local ok, remembered = pcall(function()
        return WarehouseTerminal.getRememberedPacker(ip, playerObj:getSquare())
    end)
    if ok and remembered then return remembered end

    local origin = playerObj:getSquare()
    local cell = getCell()
    if not cell then return nil end
    local radius = WarehouseTerminal.PACKER_SCAN_RADIUS or 80
    for x = origin:getX() - radius, origin:getX() + radius do
        for y = origin:getY() - radius, origin:getY() + radius do
            local dx = x - origin:getX()
            local dy = y - origin:getY()
            if dx * dx + dy * dy <= radius * radius then
                for z = 0, 7 do
                    local square = cell:getGridSquare(x, y, z)
                    if square then
                        local objCount = square:getObjects():size()
                        for i = 0, objCount - 1 do
                            local obj = square:getObjects():get(i)
                            if obj then
                                local okP, isP = pcall(WarehouseTerminal.isPackerObject, obj)
                                if okP and isP then
                                    local okIp, objIp = pcall(WarehouseTerminal.getPackerIP, obj)
                                    if okIp and objIp == ip then
                                        pcall(WarehouseTerminal.rememberPacker, obj)
                                        return obj
                                    end
                                end
                            end
                        end
                        local specCount = square:getSpecialObjects():size()
                        for i = 0, specCount - 1 do
                            local obj = square:getSpecialObjects():get(i)
                            if obj then
                                local okP, isP = pcall(WarehouseTerminal.isPackerObject, obj)
                                if okP and isP then
                                    local okIp, objIp = pcall(WarehouseTerminal.getPackerIP, obj)
                                    if okIp and objIp == ip then
                                        pcall(WarehouseTerminal.rememberPacker, obj)
                                        return obj
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- ============================================================================
-- Open from inventory (with PIN check)
-- ============================================================================
function PortableTerminal.openFromItem(player, item)
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end
    if not PortableTerminal.isDeviceItem(item) then return end

    -- Battery check: prevent opening if battery is dead
    if PortableTerminal.getDeviceBattery(item) <= 0 then
        if playerObj and playerObj.Say then
            playerObj:Say("Portable Terminal battery is dead - recharge at a generator")
        end
        return
    end

    -- PIN check: if device has a PIN set, show PIN dialog first
    if PortableTerminal.hasDevicePIN(item) then
        PortableTerminal.showPINPrompt(player, item)
        return
    end

    PortableTerminal.createWindow(playerObj, item)
end

function PortableTerminal.createWindow(playerObj, item)
    local window = PortableTerminalWindow:new(100, 100, 780, 520, playerObj, item)
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)

    if PortableTerminalWindow.instance then
        PortableTerminalWindow.instance:setVisible(false)
        PortableTerminalWindow.instance:removeFromUIManager()
    end
    PortableTerminalWindow.instance = window

    -- Start background monitors only when the terminal is actually open
    if PortableTerminalPower and PortableTerminalPower.start then
        PortableTerminalPower.start()
    end
    if PortableTerminalTemperature and PortableTerminalTemperature.start then
        PortableTerminalTemperature.start()
    end

    return window
end

-- ============================================================================
-- PIN Prompt Dialog (shown when device has a PIN set)
-- ============================================================================
function PortableTerminal.showPINPrompt(player, item)
    local playerObj = getSpecificPlayer(player)
    if not playerObj or not item then return end

    local pin = PortableTerminal.getDevicePIN(item)
    if not pin then
        PortableTerminal.createWindow(playerObj, item)
        return
    end

    local modal = ISTextBox:new(
        0, 0, 320, 150,
        "Enter Device PIN",
        "",
        nil,
        function(_target, button)
            if button.internal ~= "OK" then return end
            local entered = button.parent and button.parent.entry and button.parent.entry:getText() or ""
            local norm = normalizePIN(entered, false)
            local correctPin = PortableTerminal.getDevicePIN(item)
            if norm and norm == correctPin then
                PortableTerminal.createWindow(playerObj, item)
            end
        end,
        playerObj:getPlayerNum(),
        item
    )
    modal.maxChars = 4
    modal:initialise()
    modal:setOnlyNumbers(true)
    modal:setValidateFunction(PortableTerminal, PortableTerminal.validatePIN, true)
    modal:setValidateTooltipText("Enter a 4-digit numeric PIN")
    modal:addToUIManager()
end

function PortableTerminal.validatePIN(_target, value, allowEmpty)
    return normalizePIN(value, allowEmpty) ~= nil
end

-- ============================================================================
-- PortableTerminalWindow Constructor
-- ============================================================================
function PortableTerminalWindow:new(x, y, width, height, playerObj, item)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.playerObj        = playerObj
    o.deviceItem       = item
    o.connectedIP      = PortableTerminal.getDevicePackerIP(item)
    o.packer           = nil
    o.terminals        = {}
    o.containers       = {}
    o.entries          = {}
    o.totalItems       = 0
    o.storageWeight    = 0
    o.storageCapacity  = 0
    o.viewMode         = "name"
    o.lastScan         = 0
    o.scanFailCount    = 0
    o.scanStopped      = false
    o.selectedTypes    = {}
    o.selectedEntry    = nil
    o.lastSelectedIndex = nil
    o.resizable        = false
    o.pin              = true
    o.minimumWidth     = 680
    o.minimumHeight    = 420
    o.backgroundColor  = PortableTerminal.Colors.window
    o.borderColor      = PortableTerminal.Colors.border
    -- lastBatteryDrain starts nil; autoRefresh initializes it on first tick.

    return o
end

-- ============================================================================
-- createChildren – TWO-PANEL layout (left=list, right=info+buttons)
-- ============================================================================
function PortableTerminalWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local th = self:titleBarHeight()
    local pad = 12
    local rightWidth = 230
    self.rightPanelWidth = rightWidth
    local buttonHeight = 25
    local listWidth = self.width - rightWidth - pad * 3

    -- ── Top bar: IP entry + Connect + Disconnect ──
    local topY = th + 16
    self.ipEntry = ISTextEntryBox:new("", pad, topY, 180, buttonHeight)
    self.ipEntry:initialise()
    self.ipEntry:instantiate()
    self.ipEntry:setText(self.connectedIP or "")
    PortableTerminal.applyInputStyle(self.ipEntry)
    self:addChild(self.ipEntry)

    self.connectBtn = self:addStyledButton(pad + 190, topY, 90, buttonHeight, "Connect", "config",
        function() self:onConnect() end)

    self.disconnectBtn = self:addStyledButton(pad + 288, topY, 98, buttonHeight, "Disconnect", "danger",
        function() self:onDisconnect() end)

    -- ── Search entry (full left width) ──
    self.searchEntry = ISTextEntryBox:new("", pad, topY + 50, listWidth, 22)
    self.searchEntry:initialise()
    self.searchEntry:instantiate()
    self.searchEntry:setClearButton(true)
    PortableTerminal.applyInputStyle(self.searchEntry)
    self.searchEntry.onTextChange = function() self:refreshItemList() end
    self:addChild(self.searchEntry)

    -- ── Tab buttons ──
    local tabY = topY + 78
    local tabW = math.floor(listWidth / 4)
    self.nameTabBtn     = self:addSearchTab(pad,              tabY, tabW, buttonHeight, "Names",      "name")
    self.categoryTabBtn = self:addSearchTab(pad + tabW,       tabY, tabW, buttonHeight, "Categories", "category")
    self.fridgeTabBtn   = self:addSearchTab(pad + tabW * 2,   tabY, tabW, buttonHeight, "Fridges",    "fridge")
    self.freezerTabBtn  = self:addSearchTab(pad + tabW * 3,   tabY, listWidth - tabW * 3, buttonHeight, "Freezers",  "freezer")

    -- ── Item list ──
    self.itemList = PortableTerminalItemList:new(pad, tabY + 54, listWidth, self.height - tabY - 70, self)
    self.itemList:initialise()
    self.itemList:instantiate()
    self.itemList.itemheight = 28
    self.itemList.font = UIFont.Small
    PortableTerminal.applyListStyle(self.itemList)
    self.itemList.terminalWindow = self
    self.itemList.anchorRight = true
    self.itemList.anchorBottom = true
    self.itemList.doDrawItem = PortableTerminalWindow.drawItemRow
    self:addChild(self.itemList)

    -- ── Right panel buttons ──
    local rightX = pad * 2 + listWidth
    local rightBtnW = rightWidth

    self.refreshBtn = self:addStyledButton(rightX, topY, 100, buttonHeight, "Refresh", "config",
        function() self:onRefresh() end)

    self.pinBtn = self:addStyledButton(rightX + 112, topY, rightBtnW - 112, buttonHeight, "PIN", "config",
        function() self:showDevicePINDialog() end)

    -- ── Right panel action buttons (bottom-anchored) ──
    local btnH = 30
    local btnGap = 8
    local bottomPad = 14
    local totalBtnH = 5 * btnH + 4 * btnGap
    local btnStartY = self.height - bottomPad - totalBtnH

    self.takeOneBtn  = self:addStyledButton(rightX, btnStartY, rightBtnW, btnH, "Take 1",               "take",
        function() self:takeItems("one") end)
    self.takeHalfBtn = self:addStyledButton(rightX, btnStartY + (btnH + btnGap), rightBtnW, btnH, "Take half",            "take",
        function() self:takeItems("half") end)
    self.takeAllBtn  = self:addStyledButton(rightX, btnStartY + (btnH + btnGap) * 2, rightBtnW, btnH, "Take all",             "take",
        function() self:takeItems("all") end)
    self.storeSelectedBtn = self:addStyledButton(rightX, btnStartY + (btnH + btnGap) * 3, rightBtnW, btnH, "Store selected type", "store",
        function() self:storeSelectedToNetwork() end)
    self.storeAllBtn = self:addStyledButton(rightX, btnStartY + (btnH + btnGap) * 4, rightBtnW, btnH, "Store all inventory",  "store",
        function() self:storeAllToNetwork() end)

    -- Anchor action buttons to bottom
    self.takeOneBtn.anchorBottom = true
    self.takeHalfBtn.anchorBottom = true
    self.takeAllBtn.anchorBottom = true
    self.storeSelectedBtn.anchorBottom = true
    self.storeAllBtn.anchorBottom = true

    self:updateSearchTabs()
    self:updateConnectionUI()
end

function PortableTerminalWindow:addStyledButton(x, y, w, h, title, kind, onClick)
    local btn = ISButton:new(x, y, w, h, title, self, onClick)
    btn:initialise()
    btn:instantiate()
    btn.anchorLeft = false
    btn.anchorRight = true
    PortableTerminal.applyButtonStyle(btn, kind)
    self:addChild(btn)
    return btn
end

function PortableTerminalWindow:addSearchTab(x, y, w, h, title, mode)
    local btn = ISButton:new(x, y, w, h, title, self, function() self:setViewMode(mode) end)
    btn:initialise()
    btn:instantiate()
    btn.searchMode = mode
    btn.anchorRight = true
    PortableTerminal.applyButtonStyle(btn, "neutral", false)
    self:addChild(btn)
    return btn
end

function PortableTerminalWindow:updateSearchTabs()
    local function apply(btn, active)
        if btn then PortableTerminal.applyButtonStyle(btn, "neutral", active) end
    end
    apply(self.nameTabBtn,     self.viewMode == "name")
    apply(self.categoryTabBtn, self.viewMode == "category")
    apply(self.fridgeTabBtn,   self.viewMode == "fridge")
    apply(self.freezerTabBtn,  self.viewMode == "freezer")
end

-- ============================================================================
-- Connection UI
-- ============================================================================
function PortableTerminalWindow:updateConnectionUI()
    local connected = self.connectedIP ~= nil and self.packer ~= nil

    self.disconnectBtn:setEnable(connected)
    self.refreshBtn.enable = true
    self.searchEntry:setEnabled(connected)
    -- Set enable directly (not setEnable) to preserve styled border colors.
    -- setEnable(false) forces a hardcoded red border via setBorderRGBA(0.7, 0.1, 0.1, 0.7).
    self.takeOneBtn.enable = connected
    self.takeHalfBtn.enable = connected
    self.takeAllBtn.enable = connected
    self.storeSelectedBtn.enable = connected
    self.storeAllBtn.enable = connected
end

function PortableTerminalWindow:setViewMode(mode)
    self.viewMode = mode
    self:updateSearchTabs()
    self:refreshItemList()
end

function PortableTerminalWindow:onConnect()
    local ip = self.ipEntry:getText()
    if ip == "" then
        self.connectedIP = nil
        self.packer = nil
        self.scanFailCount = 0
        self.scanStopped = false
        PortableTerminal.setDevicePackerIP(self.deviceItem, "")
        self:updateConnectionUI()
        self:refreshItemList()
        return
    end
    local normalized = WarehouseTerminal.normalizePackerIP(ip)
    if not normalized then return end
    PortableTerminal.setDevicePackerIP(self.deviceItem, normalized)
    self.connectedIP = normalized
    self.scanFailCount = 0
    self.scanStopped = false
    self:tryConnect()
end

function PortableTerminalWindow:refreshData()
    -- Lightweight refresh: re-scan containers + re-aggregate without re-finding
    -- the Packer (which requires an expensive 160x160x8 tile scan).
    if not self.packer then return end
    pcall(WarehouseTerminal.rememberPacker, self.packer)

    local okT, terminals = pcall(WarehouseTerminal.findWarehouseTerminalsForPacker, self.packer, true)
    self.terminals = (okT and terminals) and terminals or {}

    if WarehouseTerminal.scanPackerContainers then
        local okC, containers = pcall(WarehouseTerminal.scanPackerContainers, self.packer, self.terminals, true)
        self.containers = (okC and containers) and containers or {}
    else
        self.containers = {}
    end

    local okA, entries, total = pcall(WarehouseTerminal.aggregateItems, self.containers)
    if okA then self.entries = entries or {}; self.totalItems = total or 0
    else self.entries = {}; self.totalItems = 0 end

    if getTimestampMs then self.lastScan = getTimestampMs() end
    self:updateConnectionUI()
    self:refreshItemList()
end

function PortableTerminalWindow:tryConnect()
    if not self.connectedIP then
        self.packer = nil
        self.terminals = {}; self.containers = {}; self.entries = {}; self.totalItems = 0
        self.scanFailCount = 0; self.scanStopped = false
        self:updateConnectionUI()
        self:refreshItemList()
        return
    end
    if self.scanStopped then
        self:updateConnectionUI()
        return
    end

    local ok, packer = pcall(PortableTerminal.findPackerForItem, self.deviceItem, self.playerObj)
    if not ok then
        self.packer = nil
        self.terminals = {}; self.containers = {}; self.entries = {}; self.totalItems = 0
        self.scanFailCount = (self.scanFailCount or 0) + 1
        if self.scanFailCount >= PortableTerminal.MAX_SCAN_FAILURES then self.scanStopped = true end
        self:updateConnectionUI()
        self:refreshItemList()
        return
    end

    self.packer = packer
    if self.packer then
        self.scanFailCount = 0
        self.scanStopped = false
        self:refreshData()  -- handles updateConnectionUI + refreshItemList
    else
        self.terminals = {}; self.containers = {}; self.entries = {}; self.totalItems = 0
        self.scanFailCount = (self.scanFailCount or 0) + 1
        if self.scanFailCount >= PortableTerminal.MAX_SCAN_FAILURES then self.scanStopped = true end
        self:updateConnectionUI()
        self:refreshItemList()
    end
end

function PortableTerminalWindow:onDisconnect()
    self.connectedIP = nil
    self.packer = nil
    self.terminals = {}; self.containers = {}; self.entries = {}; self.totalItems = 0
    self.scanFailCount = 0; self.scanStopped = false
    PortableTerminal.setDevicePackerIP(self.deviceItem, "")
    self.ipEntry:setText("")
    self:updateConnectionUI()
    self:refreshItemList()
end

function PortableTerminalWindow:onRefresh()
    self:tryConnect()
end

-- ============================================================================
-- PIN Dialog for the device
-- ============================================================================
function PortableTerminalWindow:showDevicePINDialog()
    if not self.deviceItem then return end
    local pin = PortableTerminal.getDevicePIN(self.deviceItem) or ""
    local title = "Set Device PIN (" .. (pin == "" and "none" or pin) .. ")"
    local modal = ISTextBox:new(
        0, 0, 360, 150,
        title,
        "",
        self,
        function(_target, button)
            if button.internal ~= "OK" then return end
            local text = button.parent and button.parent.entry and button.parent.entry:getText() or ""
            PortableTerminal.setDevicePIN(self.deviceItem, text)
        end,
        self.playerObj:getPlayerNum(),
        self.deviceItem
    )
    modal.maxChars = 4
    modal:initialise()
    modal:setOnlyNumbers(true)
    modal:setValidateFunction(PortableTerminal, PortableTerminal.validatePIN, true)
    modal:setValidateTooltipText("Enter 4-digit PIN (empty to clear)")
    modal:addToUIManager()
end

-- ============================================================================
-- Item List
-- ============================================================================
function PortableTerminalWindow:refreshItemList()
    if not self.itemList then return end

    local previousSelection = self.selectedTypes or {}
    self.selectedTypes = {}
    self.itemList:clear()
    self.selectedEntry = nil
    self.lastSelectedIndex = nil

    local searchText = string.lower(tostring(self.searchEntry:getText() or ""))
    local firstSelectedRow = nil

    for _, entry in ipairs(self.entries or {}) do
        local show = true
        if self.viewMode == "fridge" and not entry.hasFridge then show = false
        elseif self.viewMode == "freezer" and not entry.hasFreezer then show = false end

        if show and searchText ~= "" then
            local name = entry.nameLower or string.lower(tostring(entry.displayName or ""))
            local fullType = entry.fullTypeLower or string.lower(tostring(entry.fullType or ""))
            local category = entry.categoryLower or string.lower(tostring(entry.categoryName or ""))
            if self.viewMode == "category" then
                show = string.find(category, searchText, 1, true) ~= nil
            else
                show = string.find(name, searchText, 1, true) ~= nil
                    or string.find(fullType, searchText, 1, true) ~= nil
            end
        end

        if show then
            local row = self.itemList:addItem(entry.displayName, entry)
            if previousSelection[entry.fullType] then
                self.selectedTypes[entry.fullType] = true
                if not firstSelectedRow then
                    firstSelectedRow = row.itemindex
                    self.itemList.selected = row.itemindex
                    self.selectedEntry = entry
                    self.lastSelectedIndex = row.itemindex
                end
            end
        end
    end

    if not firstSelectedRow then self.itemList.selected = -1 end
end

-- ============================================================================
-- prerender – right panel info + column headers
-- ============================================================================
function PortableTerminalWindow:prerender()
    ISCollapsableWindow.prerender(self)

    local th = self:titleBarHeight()
    local pad = 12
    local listWidth = self.itemList and self.itemList:getWidth() or 480
    local rightX = pad * 2 + listWidth
    local colors = PortableTerminal.Colors

    -- Labels above inputs
    self:drawText("Packer IP:", pad, th + 2, colors.textDim.r, colors.textDim.g, colors.textDim.b, 1, UIFont.Small)
    self:drawText("Search:", pad, th + 48, colors.textDim.r, colors.textDim.g, colors.textDim.b, 1, UIFont.Small)

    -- Column headers
    local headerY = self.itemList and self.itemList:getY() - 20 or th + 110
    local categoryX = pad + math.floor(listWidth * 0.58)
    self:drawRect(pad, headerY, listWidth, 20, colors.header.a, colors.header.r, colors.header.g, colors.header.b)
    self:drawRectBorder(pad, headerY, listWidth, 20, 0.65, colors.border.r, colors.border.g, colors.border.b)
    self:drawText("Name", pad + 38, headerY + 4, colors.cold.r, colors.cold.g, colors.cold.b, 1, UIFont.Small)
    self:drawText("Category", categoryX, headerY + 4, colors.cold.r, colors.cold.g, colors.cold.b, 1, UIFont.Small)

    -- Right panel info (added top margin below buttons)
    local connected = self.connectedIP ~= nil and self.packer ~= nil
    local rpw = self.rightPanelWidth or 230
    local infoY = th + 58

    -- ── Battery bar ──
    if self.deviceItem then
        local battery = PortableTerminal.getDeviceBattery(self.deviceItem)
        local barW = rpw
        local barH = 8
        local barX = rightX
        local barY = infoY
        self:drawRect(barX, barY, barW, barH, 0.45, 0.06, 0.06, 0.06)
        local fillW = math.floor(barW * battery / PortableTerminal.BATTERY_MAX)
        local battColor = colors.accent
        if battery <= 15 then battColor = colors.danger
        elseif battery <= 35 then battColor = colors.amber
        elseif battery <= 60 then battColor = colors.cold
        end
        self:drawRect(barX, barY, fillW, barH, 1, battColor.r, battColor.g, battColor.b)
        local battText = "Battery: " .. math.floor(battery) .. "%"
        self:drawText(battText, barX + 4, barY - 14, colors.textDim.r, colors.textDim.g, colors.textDim.b, 1, UIFont.Small)
        infoY = infoY + 22
    end

    if connected then
        local containers = self.containers and #self.containers or 0
        local items = self.totalItems or 0
        local summary = "Containers: " .. tostring(containers) .. "   Items: " .. tostring(items)
        self:drawText(summary, rightX, infoY, colors.cold.r, colors.cold.g, colors.cold.b, 1, UIFont.Small)
        infoY = infoY + 18

        self:drawText("Packer: " .. (self.connectedIP or "?"), rightX, infoY, colors.text.r, colors.text.g, colors.text.b, 1, UIFont.Small)
        infoY = infoY + 16
    elseif self.scanStopped then
        self:drawText("Scanning stopped", rightX, infoY, colors.danger.r, colors.danger.g, colors.danger.b, 1, UIFont.Small)
        infoY = infoY + 18
        self:drawText("Click Connect to retry", rightX, infoY, colors.textDim.r, colors.textDim.g, colors.textDim.b, 1, UIFont.Small)
        infoY = infoY + 16
    elseif self.connectedIP then
        local attempt = (self.scanFailCount or 0) + 1
        self:drawText("Searching " .. self.connectedIP .. "...", rightX, infoY, colors.amber.r, colors.amber.g, colors.amber.b, 1, UIFont.Small)
        infoY = infoY + 18
        self:drawText("Attempt " .. attempt .. "/" .. PortableTerminal.MAX_SCAN_FAILURES, rightX, infoY, colors.textDim.r, colors.textDim.g, colors.textDim.b, 1, UIFont.Small)
        infoY = infoY + 16
    else
        self:drawText("Enter Packer IP to connect", rightX, infoY, colors.textDim.r, colors.textDim.g, colors.textDim.b, 1, UIFont.Small)
        infoY = infoY + 18
    end

    -- Selected item info
    if self.selectedEntry then
        self:drawText(self.selectedEntry.displayName, rightX, infoY, colors.accent.r, colors.accent.g, colors.accent.b, 1, UIFont.Small)
        infoY = infoY + 16
        self:drawText("x" .. tostring(self.selectedEntry.count), rightX, infoY, colors.cold.r, colors.cold.g, colors.cold.b, 1, UIFont.Small)
        infoY = infoY + 4
    else
        self:drawText("No item selected", rightX, infoY, colors.textDim.r, colors.textDim.g, colors.textDim.b, 1, UIFont.Small)
        infoY = infoY + 2
    end

    -- ── Power section: generator fuel + condition ──
    infoY = infoY + 8
    local generators = PortableTerminalPower and PortableTerminalPower.generators or {}
    self:drawRect(rightX, infoY, rpw, 1, 0.35, colors.border.r, colors.border.g, colors.border.b)
    infoY = infoY + 6
    self:drawText("⚡ Power", rightX, infoY, colors.amber.r, colors.amber.g, colors.amber.b, 1, UIFont.Small)
    infoY = infoY + 16

    if #generators > 0 then
        for _, gen in ipairs(generators) do
            local fuelVal = tonumber(gen.fuel) or 0
            local condVal = tonumber(gen.condition) or 0
            local fuelPct = math.floor(fuelVal)
            local condPct = math.floor(condVal)
            local running = gen.running == true

            -- Compact status line with fuel bar
            local barW = 44
            local barH = 7
            local barX = rightX
            local barY = infoY + 5
            self:drawRect(barX, barY, barW, barH, 0.5, 0.06, 0.06, 0.06)
            local fillW = math.max(0, math.min(barW, math.floor(barW * fuelVal / 100)))
            local barColor = running and colors.accent or colors.textDim
            if not running then barColor = colors.danger
            elseif fuelVal <= 20 then barColor = colors.danger
            elseif fuelVal <= 50 then barColor = colors.amber
            end
            self:drawRect(barX, barY, fillW, barH, 1, barColor.r, barColor.g, barColor.b)

            local statusStr = running and "ON" or "OFF"
            local statusColor = running and colors.accent or colors.danger
            local line = "Fuel:" .. fuelPct .. "%  Cond:" .. condPct .. "%"
            self:drawText(line, rightX + barW + 8, infoY, colors.text.r, colors.text.g, colors.text.b, 1, UIFont.Small)

            -- Status on same line, right-aligned
            local statusW = getTextManager():MeasureStringX(UIFont.Small, statusStr)
            self:drawText(statusStr, rightX + rpw - statusW - 4, infoY, statusColor.r, statusColor.g, statusColor.b, 1, UIFont.Small)
            infoY = infoY + 16
        end
    else
        self:drawText("No generators detected", rightX, infoY, colors.textDim.r, colors.textDim.g, colors.textDim.b, 1, UIFont.Small)
        infoY = infoY + 14
    end

    -- ── Temperature warnings ──
    infoY = infoY + 6
    local tempWarnings = PortableTerminalTemperature and PortableTerminalTemperature.warnings or {}
    self:drawRect(rightX, infoY, rpw, 1, 0.35, colors.border.r, colors.border.g, colors.border.b)
    infoY = infoY + 6
    self:drawText("🌡 Temperature", rightX, infoY, colors.cold.r, colors.cold.g, colors.cold.b, 1, UIFont.Small)
    infoY = infoY + 16

    if #tempWarnings > 0 then
        local maxWarns = 4
        for i, warn in ipairs(tempWarnings) do
            if i > maxWarns then
                self:drawText("+" .. (#tempWarnings - maxWarns) .. " more...", rightX, infoY, colors.textDim.r, colors.textDim.g, colors.textDim.b, 1, UIFont.Small)
                break
            end
            local wc = warn.severity == "danger" and colors.danger or colors.amber
            local icon = warn.severity == "danger" and "!! " or "!  "
            local msg = icon .. (warn.label or "?")
            local maxW = rpw - 10
            drawClippedText(self, msg, rightX, infoY, maxW, wc.r, wc.g, wc.b, 1, UIFont.Small)
            infoY = infoY + 12
        end
    else
        local containerCount = PortableTerminalTemperature and PortableTerminalTemperature.containers and #PortableTerminalTemperature.containers or 0
        if containerCount > 0 then
            self:drawText("All cold containers OK", rightX, infoY, colors.accent.r, colors.accent.g, colors.accent.b, 1, UIFont.Small)
        else
            self:drawText("No cold containers found", rightX, infoY, colors.textDim.r, colors.textDim.g, colors.textDim.b, 1, UIFont.Small)
        end
        infoY = infoY + 14
    end
end

-- ============================================================================
-- Item Row Drawing (matches WarehouseTerminal style)
-- ============================================================================
function PortableTerminalWindow.drawItemRow(list, y, item, alt)
    if not item.height then item.height = list.itemheight end

    local entry = item.item
    if not entry then return y + item.height end

    local window = list.terminalWindow
    local colors = PortableTerminal.Colors
    local isSelected = window and window:isEntrySelected(entry)
    local w = list:getWidth()
    local h = item.height

    -- Selection / alt row highlight
    if isSelected then
        list:drawRect(0, y, w, h - 1, colors.rowSelected.a, colors.rowSelected.r, colors.rowSelected.g, colors.rowSelected.b)
        list:drawRect(0, y, 3, h - 1, 1, colors.accent.r, colors.accent.g, colors.accent.b)
    elseif alt then
        list:drawRect(0, y, w, h - 1, colors.rowAlt.a, colors.rowAlt.r, colors.rowAlt.g, colors.rowAlt.b)
    end
    list:drawRectBorder(0, y, w, h, colors.rowBorder.a, colors.rowBorder.r, colors.rowBorder.g, colors.rowBorder.b)

    -- Item icon
    if entry.texture then
        list:drawTextureScaledAspect(entry.texture, 6, y + 4, 24, 24, 1, 1, 1, 1)
    end

    -- Name
    local categoryX = math.floor(w * 0.58)
    local nameR, nameG, nameB = colors.text.r, colors.text.g, colors.text.b
    if entry.hasCold then nameR, nameG, nameB = colors.cold.r, colors.cold.g, colors.cold.b end
    drawClippedText(list, item.text, 36, y + 7, categoryX - 42, nameR, nameG, nameB, 1, UIFont.Small)

    -- Category
    local catText = entry.categoryName or ""
    local catX = categoryX
    if entry.hasFreezer then
        catText = "❄ " .. catText
        catX = categoryX + 18
    end
    local countText = tostring(entry.count)
    local countW = getTextManager():MeasureStringX(UIFont.Small, countText)
    local catMaxW = w - 30 - countW - catX - 18
    drawClippedText(list, catText, catX, y + 7, math.max(1, catMaxW), colors.textDim.r, colors.textDim.g, colors.textDim.b, 1, UIFont.Small)

    -- Count (right-aligned)
    list:drawTextRight(countText, w - 30, y + 7, colors.cold.r, colors.cold.g, colors.cold.b, 1, UIFont.Small)

    return y + h
end

-- ============================================================================
-- Selection Logic
-- ============================================================================
function PortableTerminalWindow:isEntrySelected(entry)
    return entry ~= nil and self.selectedTypes ~= nil and self.selectedTypes[entry.fullType] == true
end

function PortableTerminalWindow:selectOnly(row, entry)
    self.selectedTypes = {}
    if entry then
        self.selectedTypes[entry.fullType] = true
        self.selectedEntry = entry
        self.lastSelectedIndex = row
        if self.itemList then self.itemList.selected = row or -1 end
    else
        self.selectedEntry = nil
        self.lastSelectedIndex = nil
    end
end

function PortableTerminalWindow:selectVisibleRange(firstRow, lastRow, keepCurrent)
    if not keepCurrent then self.selectedTypes = {} end
    local fromRow = math.min(firstRow, lastRow)
    local toRow = math.max(firstRow, lastRow)
    for row = fromRow, toRow do
        local listItem = self.itemList and self.itemList.items[row]
        local entry = listItem and listItem.item
        if entry then self.selectedTypes[entry.fullType] = true end
    end
end

function PortableTerminalWindow:onListMouseDown(row, entry)
    if not entry then return end
    self.selectedTypes = self.selectedTypes or {}
    local shiftHeld = isShiftKeyDown()
    local ctrlHeld = isCtrlKeyDown()
    if shiftHeld and self.lastSelectedIndex and self.itemList and self.itemList.items[self.lastSelectedIndex] then
        self:selectVisibleRange(self.lastSelectedIndex, row, ctrlHeld)
    elseif ctrlHeld then
        if self.selectedTypes[entry.fullType] then
            self.selectedTypes[entry.fullType] = nil
        else
            self.selectedTypes[entry.fullType] = true
        end
        self.lastSelectedIndex = row
    else
        self:selectOnly(row, entry)
        return
    end
    if self.itemList then self.itemList.selected = row end
    if entry and self.selectedTypes[entry.fullType] then self.selectedEntry = entry end
end

function PortableTerminalWindow:getSelectedEntries()
    local selected = {}
    if not self.selectedTypes then return selected end
    for _, entry in ipairs(self.entries or {}) do
        if self.selectedTypes[entry.fullType] then table.insert(selected, entry) end
    end
    return selected
end

-- ============================================================================
-- Battery drain helper — drains per item transferred via the terminal.
-- Returns true if the terminal still has power after the drain.
-- ============================================================================
function PortableTerminalWindow:drainBatteryForAction(itemCount)
    if not self.deviceItem then return true end
    if not itemCount or itemCount <= 0 then return true end

    local battery = PortableTerminal.getDeviceBattery(self.deviceItem)
    if battery <= 0 then
        self:closeDueToDeadBattery()
        return false
    end

    local drain = itemCount * PortableTerminal.BATTERY_DRAIN_PER_ITEM
    local newBattery = math.max(0, battery - drain)
    PortableTerminal.setDeviceBattery(self.deviceItem, newBattery)

    if newBattery <= 0 then
        self:closeDueToDeadBattery()
        return false
    end
    return true
end

function PortableTerminalWindow:closeDueToDeadBattery()
    if self.playerObj and self.playerObj.Say then
        self.playerObj:Say("Portable Terminal battery is dead - recharge at a generator")
    end
    self:setVisible(false)
    self:removeFromUIManager()
    PortableTerminalWindow.instance = nil

    -- Stop background monitors when terminal closes
    if PortableTerminalPower and PortableTerminalPower.stop then
        PortableTerminalPower.stop()
    end
    if PortableTerminalTemperature and PortableTerminalTemperature.stop then
        PortableTerminalTemperature.stop()
    end
end

-- ============================================================================
-- close override — called when user clicks X or presses Escape.
-- ============================================================================
function PortableTerminalWindow:close()
    -- Stop background monitors
    if PortableTerminalPower and PortableTerminalPower.stop then
        PortableTerminalPower.stop()
    end
    if PortableTerminalTemperature and PortableTerminalTemperature.stop then
        PortableTerminalTemperature.stop()
    end
    PortableTerminalWindow.instance = nil
    ISCollapsableWindow.close(self)
end

-- ============================================================================
-- Transfer Logic
-- ============================================================================
function PortableTerminalWindow:collectItemsForEntry(entry, mode)
    local items = {}
    local remaining = mode == "one" and 1 or (mode == "half" and math.max(1, math.floor(entry.count / 2)) or entry.count)
    for _, loc in ipairs(entry.locations or {}) do
        if remaining <= 0 then break end
        local container = loc.container
        if container then
            local containerItems = container:getItems()
            for j = 0, containerItems:size() - 1 do
                if remaining <= 0 then break end
                local item = containerItems:get(j)
                local ok, fullType = pcall(function() return item:getFullType() end)
                if ok and tostring(fullType) == entry.fullType then
                    table.insert(items, item)
                    remaining = remaining - 1
                end
            end
        end
    end
    return items
end

function PortableTerminalWindow:takeItems(mode)
    if not self.packer then return end
    local selectedEntries = self:getSelectedEntries()
    if #selectedEntries == 0 then return end
    local allItems = {}
    for _, entry in ipairs(selectedEntries) do
        for _, item in ipairs(self:collectItemsForEntry(entry, mode)) do
            table.insert(allItems, item)
        end
    end
    if #allItems == 0 then return end
    local fitItems = allItems
    if WarehouseTerminal.collectItemsForPlayer then
        fitItems = WarehouseTerminal.collectItemsForPlayer(self.playerObj, allItems)
    end
    local playerInv = self.playerObj:getInventory()
    for _, item in ipairs(fitItems) do
        ISTimedActionQueue.add(ISInventoryTransferAction:new(self.playerObj, item, item:getContainer(), playerInv))
    end
    self:drainBatteryForAction(#fitItems)
    self.fastRefreshCount = PortableTerminal.getFastRefreshCount(#fitItems)
    self.fastRefreshLastScan = getTimestampMs and getTimestampMs() or 0
end

function PortableTerminalWindow:storeItemsToNetwork(itemsToStore)
    if not self.packer or not self.terminals then return end
    if not itemsToStore or #itemsToStore == 0 then return end
    local itemCount = #itemsToStore
    if WarehouseTerminal.queueStoragePayloadMaybeConfirm then
        local forcedColdType = nil
        if self.viewMode == "fridge" then forcedColdType = "fridge"
        elseif self.viewMode == "freezer" then forcedColdType = "freezer" end
        WarehouseTerminal.queueStoragePayloadMaybeConfirm({
            playerObj = self.playerObj, items = itemsToStore,
            containers = self.containers, allowEquipped = true,
            fallbackContainer = nil, forcedColdType = forcedColdType,
            onComplete = function(queued)
                self:drainBatteryForAction(queued or itemCount)
                self.fastRefreshCount = PortableTerminal.getFastRefreshCount(queued or itemCount)
                self.fastRefreshLastScan = getTimestampMs and getTimestampMs() or 0
            end
        })
        return
    end
    local playerInv = self.playerObj:getInventory()
    for _, item in ipairs(itemsToStore) do
        if item and item:getContainer() == playerInv then
            local best = nil
            for _, ci in ipairs(self.containers or {}) do
                local c = ci.container
                if c and c ~= playerInv then
                    local ok, allowed = pcall(function() return c:isItemAllowed(item) and c:hasRoomFor(self.playerObj, item) end)
                    if ok and allowed then best = c; break end
                end
            end
            if best then
                ISTimedActionQueue.add(ISInventoryTransferAction:new(self.playerObj, item, playerInv, best))
            end
        end
    end
    self:drainBatteryForAction(itemCount)
    self.fastRefreshCount = PortableTerminal.getFastRefreshCount(itemCount)
    self.fastRefreshLastScan = getTimestampMs and getTimestampMs() or 0
end

function PortableTerminalWindow:storeSelectedToNetwork()
    if not self.packer then return end
    local selectedEntries = self:getSelectedEntries()
    if #selectedEntries == 0 then return end
    local selectedTypes = {}
    for _, entry in ipairs(selectedEntries) do selectedTypes[entry.fullType] = true end
    local itemsToStore = {}
    local playerInv = self.playerObj:getInventory()
    local invItems = playerInv:getItems()
    for i = 0, invItems:size() - 1 do
        local item = invItems:get(i)
        local ok, fullType = pcall(function() return item:getFullType() end)
        if ok and selectedTypes[tostring(fullType)] then table.insert(itemsToStore, item) end
    end
    self:storeItemsToNetwork(itemsToStore)
end

function PortableTerminalWindow:storeAllToNetwork()
    if not self.packer then return end
    local itemsToStore = {}
    local playerInv = self.playerObj:getInventory()
    local invItems = playerInv:getItems()
    for i = 0, invItems:size() - 1 do
        local item = invItems:get(i)
        if not instanceof(item, "InventoryContainer") then table.insert(itemsToStore, item) end
    end
    self:storeItemsToNetwork(itemsToStore)
end

-- ============================================================================
-- Auto-refresh timer (multi-refresh after transfers, then exponential backoff).
-- Battery no longer drains over time — it drains per item transferred instead.
-- ============================================================================
local function autoRefresh()
    local window = PortableTerminalWindow.instance
    if not window or not window:isVisible() then return end

    -- If battery somehow hit 0 (shouldn't happen from time, but drains from actions), close UI
    if window.deviceItem and PortableTerminal.getDeviceBattery(window.deviceItem) <= 0 then
        window:closeDueToDeadBattery()
        return
    end

    local now = getTimestampMs and getTimestampMs() or 0

    if not window.connectedIP then return end
    if window.scanStopped then return end

    -- Fast refresh: lightweight re-scan (no Packer hunt) after transfers
    if (window.fastRefreshCount or 0) > 0 then
        if now - (window.fastRefreshLastScan or 0) >= PortableTerminal.FAST_REFRESH_INTERVAL_MS then
            window.fastRefreshCount = window.fastRefreshCount - 1
            window.fastRefreshLastScan = now
            window:refreshData()
        end
        return
    end

    local backoffMultiplier = math.max(1, PortableTerminal.SCAN_BACKOFF_MULTIPLIER ^ (window.scanFailCount or 0))
    local effectiveInterval = PortableTerminal.SCAN_INTERVAL_MS * backoffMultiplier
    if effectiveInterval > 300000 then effectiveInterval = 300000 end
    if now - (window.lastScan or 0) >= effectiveInterval then window:tryConnect() end
end
Events.OnTick.Add(autoRefresh)

-- ============================================================================
-- Item List Mouse Events
-- ============================================================================
function PortableTerminalItemList:onMouseDown(x, y)
    if not self.terminalWindow then ISScrollingListBox.onMouseDown(self, x, y); return end
    if #self.items == 0 then return end
    local row = self:rowAt(x, y)
    if row > #self.items then row = #self.items end
    if row < 1 then row = 1 end
    getSoundManager():playUISound("UISelectListItem")
    self.selected = row
    local listItem = row and self.items[row]
    local entry = listItem and listItem.item
    if entry then self.terminalWindow:onListMouseDown(row, entry) end
end

function PortableTerminalItemList:onMouseDoubleClick(x, y)
    if self.terminalWindow then self.terminalWindow:takeItems("all") end
end
