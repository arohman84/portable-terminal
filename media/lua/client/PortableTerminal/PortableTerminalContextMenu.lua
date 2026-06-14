-- PortableTerminalContextMenu.lua
-- Adds "Use Portable Terminal" to the inventory right-click menu.
-- The device is a craftable inventory item that connects to a Warehouse Packer IP.

require "PortableTerminal/PortableTerminalUI"
require "WarehouseTerminal/WarehouseTerminalUI"
require "ISUI/ISTextBox"
require "TimedActions/ISBaseTimedAction"

PortableTerminalContextMenu = PortableTerminalContextMenu or {}

-- ============================================================================
-- Timed action: recharge the portable terminal at a running generator.
-- Takes ~1-2 in-game hours at normal speed (~1-2 real minutes).
-- ============================================================================
PortableTerminalRechargeAction = ISBaseTimedAction:derive("PortableTerminalRechargeAction")

function PortableTerminalRechargeAction:new(character, deviceItem)
    local o = ISBaseTimedAction:new(character)
    setmetatable(o, self)
    self.__index = self
    o.character = character
    o.deviceItem = deviceItem
    -- Read sandbox recharge time (default 6000 = ~1 in-game hour at normal speed)
    o.maxTime = 6000
    if SandboxVars and SandboxVars.PortableTerminal then
        local sbTime = tonumber(SandboxVars.PortableTerminal.RechargeTime)
        if sbTime and sbTime > 0 then
            o.maxTime = sbTime
        end
    end
    o.stopOnWalk = true
    o.stopOnRun = true
    -- Allow performing while standing near the generator
    o.ignoreAxe = false
    return o
end

function PortableTerminalRechargeAction:isValid()
    if not self.deviceItem then return false end
    local battery = PortableTerminal.getDeviceBattery(self.deviceItem)
    return battery < PortableTerminal.BATTERY_MAX
end

function PortableTerminalRechargeAction:perform()
    PortableTerminal.setDeviceBattery(self.deviceItem, PortableTerminal.BATTERY_MAX)
    if self.character and self.character.Say then
        self.character:Say("Portable Terminal fully charged")
    end
    ISBaseTimedAction.perform(self)
end

--- Safely extract actual InventoryItem objects from the event parameter.
--- The items parameter can be a single item, a table of items, or a
--- wrapper that needs ISInventoryPane.getActualItems().
local function collectActualItems(items)
    if not items then
        return {}
    end
    if instanceof(items, "InventoryItem") then
        return { items }
    end
    if ISInventoryPane and ISInventoryPane.getActualItems then
        local ok, result = pcall(ISInventoryPane.getActualItems, items)
        if ok and result then
            return result
        end
    end
    -- Fallback: assume it's already a table of items
    if type(items) == "table" then
        return items
    end
    return {}
end

local function isDeviceItem(item)
    if not item then return false end
    if not instanceof(item, "InventoryItem") then return false end
    local fullType = item:getFullType()
    return fullType == "Base.PortableTerminal"
end

-- ============================================================================
-- Find a running generator within 3 tiles of the player
-- ============================================================================
local function findNearbyRunningGenerator(playerObj)
    if not playerObj then return nil end
    local origin = playerObj:getSquare()
    if not origin then return nil end
    local cell = getCell()
    if not cell then return nil end

    local cx, cy = origin:getX(), origin:getY()
    for x = cx - 3, cx + 3 do
        for y = cy - 3, cy + 3 do
            for z = 0, 7 do
                local sq = cell:getGridSquare(x, y, z)
                if sq then
                    for _, listName in ipairs({ "getObjects", "getSpecialObjects" }) do
                        local okL, list = pcall(function() return sq[listName](sq) end)
                        if okL and list then
                            for i = 0, list:size() - 1 do
                                local obj = list:get(i)
                                if obj and instanceof(obj, "IsoGenerator") then
                                    local okA, active = pcall(function() return obj:isActivated() end)
                                    if okA and active then
                                        return sq
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

local function addUseOption(player, context, items)
    local actualItems = collectActualItems(items)
    if not actualItems or #actualItems == 0 then return end

    local deviceItem = nil
    for _, item in ipairs(actualItems) do
        if isDeviceItem(item) then
            deviceItem = item
            break
        end
    end
    if not deviceItem then return end

    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

    -- Open device option
    context:addOption(
        getText("ContextMenu_OpenPortableTerminal"),
        deviceItem,
        function()
            PortableTerminal.openFromItem(player, deviceItem)
        end
    )

    -- Set PIN option
    local pinText = "Set Device PIN"
    if PortableTerminal.hasDevicePIN(deviceItem) then
        pinText = "Change Device PIN"
    end
    context:addOption(
        pinText,
        deviceItem,
        function()
            local pin = PortableTerminal.getDevicePIN(deviceItem) or ""
            local title = "Set Device PIN (" .. (pin == "" and "none" or pin) .. ")"
            local modal = ISTextBox:new(
                0, 0, 360, 150,
                title, "",
                nil,
                function(_target, button)
                    if button.internal ~= "OK" then return end
                    local text = button.parent and button.parent.entry and button.parent.entry:getText() or ""
                    PortableTerminal.setDevicePIN(deviceItem, text)
                end,
                playerObj:getPlayerNum(),
                deviceItem
            )
            modal.maxChars = 4
            modal:initialise()
            modal:setOnlyNumbers(true)
            modal:setValidateFunction(PortableTerminal, PortableTerminal.validatePIN, true)
            modal:setValidateTooltipText("Enter 4-digit PIN (empty to clear)")
            modal:addToUIManager()
        end
    )

    -- Recharge option (only if battery < 100% and near a running generator)
    local battery = PortableTerminal.getDeviceBattery(deviceItem)
    if battery < PortableTerminal.BATTERY_MAX then
        local genSquare = findNearbyRunningGenerator(playerObj)
        if genSquare then
            context:addOption(
                "Recharge Portable Terminal (" .. math.floor(battery) .. "%)",
                deviceItem,
                function()
                    ISTimedActionQueue.add(PortableTerminalRechargeAction:new(playerObj, deviceItem))
                end
            )
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(addUseOption)
