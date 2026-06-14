-- PortableTerminalPowerMonitor.lua
-- Scans for IsoGenerator objects near Warehouse Terminals and reports
-- fuel level, condition, and running status to the Portable Terminal UI.
-- Works in both SP and MP (each client scans independently).
--
-- Data is published to PortableTerminalPower.generators table.
-- The PortableTerminalUI reads this to show a "Power" status line.
--
-- PERFORMANCE: Uses PortableTerminalScanner for the expensive terminal scan.
-- Only runs scans when a PortableTerminal is actively in use.

require "WarehouseTerminal/WarehouseTerminalVariant"
require "PortableTerminal/PortableTerminalScanner"

PortableTerminalPower = PortableTerminalPower or {}
PortableTerminalPower.GENERATOR_SCAN_RADIUS = 30         -- tiles around each terminal
PortableTerminalPower.generators = {}                    -- { {fuel, condition, running, distance, x, y}, ... }
PortableTerminalPower.lastScan = 0

print("[PortableTerminal] PowerMonitor loaded")

-- ============================================================================
-- Scan for generators around each terminal
-- ============================================================================

local function findGeneratorsNearTerminals(terminals)
    local generators, seen = {}, {}
    if not terminals or #terminals == 0 then return generators end

    for _, term in ipairs(terminals) do
        local termSquare = term:getSquare()
        if termSquare then
            local cx, cy = termSquare:getX(), termSquare:getY()
            local cell = getCell()
            if cell then
                local r = PortableTerminalPower.GENERATOR_SCAN_RADIUS
                for x = cx - r, cx + r do
                    for y = cy - r, cy + r do
                        local dx, dy = x - cx, y - cy
                        if dx * dx + dy * dy <= r * r then
                            for z = 0, 7 do
                                local sq = cell:getGridSquare(x, y, z)
                                if sq then
                                    for _, listName in ipairs({ "getObjects", "getSpecialObjects" }) do
                                        local okL, list = pcall(function() return sq[listName](sq) end)
                                        if okL and list then
                                            for i = 0, list:size() - 1 do
                                                local obj = list:get(i)
                                                if obj and not seen[obj] and instanceof(obj, "IsoGenerator") then
                                                    seen[obj] = true
                                                    local okF, fuel = pcall(function() return obj:getFuel() end)
                                                    local okC, cond = pcall(function() return obj:getCondition() end)
                                                    local okA, active = pcall(function() return obj:isActivated() end)
                                                    local dist = math.sqrt(dx * dx + dy * dy)

                                                    table.insert(generators, {
                                                        generator = obj,
                                                        fuel = (okF and fuel) and fuel or 0,
                                                        condition = (okC and cond) and cond or 0,
                                                        running = (okA and active) and true or false,
                                                        distance = math.floor(dist * 10) / 10,
                                                        x = x, y = y, z = z,
                                                    })
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
        end
    end
    return generators
end

-- ============================================================================
-- doScan: use shared scanner, find generators near terminals, publish results
-- ============================================================================

local function doScan()
    -- Gate: only scan when a Portable Terminal is actively in use
    if not PortableTerminalScanner.isActive() then
        PortableTerminalPower.generators = {}
        return
    end

    local terminals = PortableTerminalScanner.scan()
    if #terminals == 0 then
        PortableTerminalPower.generators = {}
        return
    end

    local genList = findGeneratorsNearTerminals(terminals)
    -- print("[PowerMonitor] " .. #terminals .. " terminals, " .. #genList .. " generators found")
    PortableTerminalPower.generators = genList
    PortableTerminalPower.lastScan = getTimestampMs and getTimestampMs() or 0
end

-- ============================================================================
-- onTick — lightweight: only calls doScan when cache likely expired (15s)
-- ============================================================================

local function onTick()
    local now = getTimestampMs and getTimestampMs() or 0
    if now - PortableTerminalPower.lastScan >= 15000 then
        doScan()
    end
end

Events.OnTick.Add(onTick)
