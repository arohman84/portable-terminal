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
--
-- PERFORMANCE: Uses PortableTerminalScanner for the expensive terminal scan.
-- Only runs scans when a PortableTerminal is actively in use.

require "WarehouseTerminal/WarehouseTerminalVariant"
require "WarehouseTerminal/WarehouseTerminalUI"
require "PortableTerminal/PortableTerminalScanner"

PortableTerminalTemperature = PortableTerminalTemperature or {}
PortableTerminalTemperature.DEFAULT_RADIUS = 12
PortableTerminalTemperature.containers = {}
PortableTerminalTemperature.warnings = {}
PortableTerminalTemperature.lastScan = 0

print("[PortableTerminal] TemperatureMonitor loaded")

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
-- doScan — uses shared scanner, gated on isActive()
-- ============================================================================

local function doScan()
    -- Gate: only scan when a Portable Terminal is actively in use
    if not PortableTerminalScanner.isActive() then
        PortableTerminalTemperature.containers = {}
        PortableTerminalTemperature.warnings = {}
        return
    end

    local terminals = PortableTerminalScanner.scan()
    if #terminals == 0 then
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
    -- print("[TempMonitor] " .. #terminals .. " terminals, " .. #containers .. " containers, " .. #warnings .. " warnings")
    PortableTerminalTemperature.lastScan = getTimestampMs and getTimestampMs() or 0
end

-- ============================================================================
-- onTick — lightweight: only calls doScan when cache likely expired (~20s)
-- ============================================================================

local function onTick()
    local now = getTimestampMs and getTimestampMs() or 0
    if now - PortableTerminalTemperature.lastScan >= 20000 then
        doScan()
    end
end

Events.OnTick.Add(onTick)
