-- PortableTerminalPowerMonitor.lua
-- Scans for IsoGenerator objects near Warehouse Terminals and reports
-- fuel level, condition, and running status to the Portable Terminal UI.
-- Works in both SP and MP (each client scans independently).
--
-- Data is published to PortableTerminalPower.generators table.
-- The PortableTerminalUI reads this to show a "Power" status line.

require "WarehouseTerminal/WarehouseTerminalVariant"

PortableTerminalPower = PortableTerminalPower or {}
PortableTerminalPower.SCAN_INTERVAL_MS = 15000          -- ~15 sec
PortableTerminalPower.TERMINAL_SCAN_RADIUS = 80          -- tiles around player
PortableTerminalPower.GENERATOR_SCAN_RADIUS = 30         -- tiles around each terminal
PortableTerminalPower.generators = {}                    -- { {fuel, condition, running, distance, x, y}, ... }
PortableTerminalPower.lastScan = 0

print("[PortableTerminal] PowerMonitor loaded")

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
    local r = PortableTerminalPower.TERMINAL_SCAN_RADIUS
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
-- doScan: find terminals, find generators near them, publish results
-- ============================================================================

local function doScan()
    local terminals = findTerminals()
    if #terminals == 0 then
        if #(PortableTerminalPower.generators or {}) > 0 then
            -- DEBUG: uncomment to see when generators clear
            -- print("[PowerMonitor] No terminals found, clearing " .. #PortableTerminalPower.generators .. " generators")
        end
        PortableTerminalPower.generators = {}
        return
    end

    local genList = findGeneratorsNearTerminals(terminals)
    print("[PowerMonitor] " .. #terminals .. " terminals, " .. #genList .. " generators found")
    PortableTerminalPower.generators = genList
    PortableTerminalPower.lastScan = getTimestampMs and getTimestampMs() or 0
end

-- ============================================================================
-- onTick
-- ============================================================================

local function onTick()
    local now = getTimestampMs and getTimestampMs() or 0
    if now - PortableTerminalPower.lastScan >= PortableTerminalPower.SCAN_INTERVAL_MS then
        doScan()
    end
end

Events.OnTick.Add(onTick)
