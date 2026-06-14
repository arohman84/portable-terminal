-- PortableTerminalTemperatureMonitor.lua
-- Monitors temperature status of fridges/freezers connected to Warehouse
-- Terminals. Provides early warning when a cold container loses power or
-- starts warming up.
--
-- Published data (PortableTerminalTemperature):
--   .containers[] = { label, coldType, powered, status, squareX, squareY }
--     status: "frozen" | "cold" | "warming" | "unpowered" | "room"
--   .warnings[]   = { label, message, severity }  -- "danger" | "warning"
--
-- Works in both SP and MP. Temperature data is read-only (no item manipulation).

require "WarehouseTerminal/WarehouseTerminalVariant"
require "WarehouseTerminal/WarehouseTerminalUI"

PortableTerminalTemperature = PortableTerminalTemperature or {}
PortableTerminalTemperature.SCAN_INTERVAL_MS = 20000         -- ~20 sec
PortableTerminalTemperature.TERMINAL_SCAN_RADIUS = 80
PortableTerminalTemperature.DEFAULT_RADIUS = 12
PortableTerminalTemperature.containers = {}
PortableTerminalTemperature.warnings = {}
PortableTerminalTemperature.lastScan = 0

print("[PortableTerminal] TemperatureMonitor loaded")

-- ============================================================================
-- Helpers
-- ============================================================================

local function isTerminal(obj)
    if not obj then return false end
    local ok, v = pcall(function()
        return obj:getModData().WarehouseTerminal == true
    end)
    return ok and v
end

local function findTerminals()
    local terminals, seen = {}, {}
    local player = getPlayer()
    if not player then return terminals end
    local origin = player:getSquare()
    if not origin then return terminals end
    local cell = getCell()
    if not cell then return terminals end

    local cx, cy = origin:getX(), origin:getY()
    local r = PortableTerminalTemperature.TERMINAL_SCAN_RADIUS
    for x = cx - r, cx + r do
        for y = cy - r, cy + r do
            if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r then
                for z = 0, 7 do
                    local sq = cell:getGridSquare(x, y, z)
                    if sq then
                        for _, listName in ipairs({ "getObjects", "getSpecialObjects" }) do
                            local okL, list = pcall(function() return sq[listName](sq) end)
                            if okL and list then
                                for i = 0, list:size() - 1 do
                                    local obj = list:get(i)
                                    if obj and not seen[obj] then
                                        seen[obj] = true
                                        if isTerminal(obj) then
                                            table.insert(terminals, obj)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return terminals
end

-- ============================================================================
-- Determine temperature status from coldType and power
-- ============================================================================

local function getTempStatus(coldType, container)
    -- coldType is only set by scanContainers() if powered
    if coldType == "freezer" then
        return "frozen"
    elseif coldType == "fridge" then
        return "cold"
    end

    -- If coldType is nil, container is either unpowered or non-cold.
    -- scanContainers() only sets coldType when powered, so nil = unpowered or room-temp.
    if container then
        local okP, powered = pcall(function() return container:isPowered() end)
        if okP and powered == false then
            return "unpowered"
        end
    end

    return "room"
end

-- ============================================================================
-- doScan
-- ============================================================================

local function doScan()
    local terminals = findTerminals()
    if #terminals == 0 then
        if #(PortableTerminalTemperature.containers or {}) > 0 then
            -- DEBUG: uncomment to see when containers clear
            -- print("[TempMonitor] No terminals, clearing " .. #PortableTerminalTemperature.containers .. " containers")
        end
        PortableTerminalTemperature.containers = {}
        PortableTerminalTemperature.warnings = {}
        return
    end

    local containers = {}
    local warnings = {}
    local seen = {}

    for _, term in ipairs(terminals) do
        local radius = tonumber(term:getModData().WarehouseTerminalRadius)
            or PortableTerminalTemperature.DEFAULT_RADIUS
        local scanResult = WarehouseTerminal.scanContainers(term, radius)

        for _, cInfo in ipairs(scanResult or {}) do
            if cInfo.container and not seen[cInfo.container] then
                seen[cInfo.container] = true

                local coldType = cInfo.coldType  -- nil if unpowered
                local status = getTempStatus(coldType, cInfo.container)
                local okP, powered = pcall(function() return cInfo.container:isPowered() end)
                local isPowered = (okP and powered) == true

                local sq = cInfo.square
                local sqX, sqY = sq and sq:getX() or 0, sq and sq:getY() or 0
                local label = cInfo.label or (coldType or "container") .. " [" .. sqX .. "," .. sqY .. "]"

                local entry = {
                    label = label,
                    coldType = coldType,
                    powered = isPowered,
                    status = status,
                    squareX = sqX,
                    squareY = sqY,
                }

                table.insert(containers, entry)

                -- Generate warnings for unpowered or warming containers
                if status == "unpowered" then
                    table.insert(warnings, {
                        label = label,
                        message = "UNPOWERED - food will spoil!",
                        severity = "danger",
                    })
                elseif status == "warming" then
                    table.insert(warnings, {
                        label = label,
                        message = "Warming up - check power",
                        severity = "warning",
                    })
                end
            end
        end
    end

    PortableTerminalTemperature.containers = containers
    PortableTerminalTemperature.warnings = warnings
    print("[TempMonitor] " .. #terminals .. " terminals, " .. #containers .. " containers, " .. #warnings .. " warnings")
    PortableTerminalTemperature.lastScan = getTimestampMs and getTimestampMs() or 0
end

-- ============================================================================
-- onTick
-- ============================================================================

local function onTick()
    local now = getTimestampMs and getTimestampMs() or 0
    if now - PortableTerminalTemperature.lastScan >= PortableTerminalTemperature.SCAN_INTERVAL_MS then
        doScan()
    end
end

Events.OnTick.Add(onTick)
