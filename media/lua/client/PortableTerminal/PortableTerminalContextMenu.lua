-- PortableTerminalContextMenu.lua
-- Adds "Use Portable Terminal" to the inventory right-click menu.
-- The device is a craftable inventory item that connects to a Warehouse Packer IP.

require "PortableTerminal/PortableTerminalUI"
require "WarehouseTerminal/WarehouseTerminalUI"
require "ISUI/ISTextBox"

PortableTerminalContextMenu = PortableTerminalContextMenu or {}

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
end

Events.OnFillInventoryObjectContextMenu.Add(addUseOption)
