-- PortableTerminalScanner.lua
-- SHARED SCANNER: One scan, shared by PowerMonitor, TemperatureMonitor, and FreezerClient.
-- Eliminates the redundant triple-scan that was causing massive lag spikes.
-- Only scans when actively needed (window open or freeze feature enabled).

PortableTerminalScanner = PortableTerminalScanner or {}
PortableTerminalScanner.SCAN_RADIUS = 80
PortableTerminalScanner.CACHE_TTL_MS = 15000         -- cache valid for 15s
PortableTerminalScanner.terminals = {}                -- cached IsoObject[]
PortableTerminalScanner.lastScan = 0

-- ============================================================================
-- isTerminal — check if an object is a Warehouse Terminal
-- ============================================================================

local function isTerminal(obj)
    if not obj then return false end
    local ok, v = pcall(function()
        return obj:getModData().WarehouseTerminal == true
    end)
    return ok and v
end

-- ============================================================================
-- scan — do the expensive grid scan ONCE, cache results
-- ============================================================================

function PortableTerminalScanner.scan(force)
    local now = getTimestampMs and getTimestampMs() or 0
    if not force and (now - PortableTerminalScanner.lastScan) < PortableTerminalScanner.CACHE_TTL_MS then
        return PortableTerminalScanner.terminals  -- return cached
    end

    local terminals, seen = {}, {}
    local player = getPlayer()
    if not player then
        PortableTerminalScanner.terminals = {}
        PortableTerminalScanner.lastScan = now
        return {}
    end

    local origin = player:getSquare()
    if not origin then
        PortableTerminalScanner.terminals = {}
        PortableTerminalScanner.lastScan = now
        return {}
    end

    local cell = getCell()
    if not cell then
        PortableTerminalScanner.terminals = {}
        PortableTerminalScanner.lastScan = now
        return {}
    end

    local cx, cy = origin:getX(), origin:getY()
    local r = PortableTerminalScanner.SCAN_RADIUS
    local rSq = r * r

    for x = cx - r, cx + r do
        for y = cy - r, cy + r do
            local dx, dy = x - cx, y - cy
            if dx * dx + dy * dy <= rSq then
                for z = 0, 7 do
                    local sq = cell:getGridSquare(x, y, z)
                    if sq then
                        -- Check regular objects
                        local okR, regList = pcall(function() return sq:getObjects() end)
                        if okR and regList then
                            for i = 0, regList:size() - 1 do
                                local obj = regList:get(i)
                                if obj and not seen[obj] then
                                    seen[obj] = true
                                    if isTerminal(obj) then
                                        table.insert(terminals, obj)
                                    end
                                end
                            end
                        end
                        -- Check special objects
                        local okS, specList = pcall(function() return sq:getSpecialObjects() end)
                        if okS and specList then
                            for i = 0, specList:size() - 1 do
                                local obj = specList:get(i)
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

    PortableTerminalScanner.terminals = terminals
    PortableTerminalScanner.lastScan = now
    return terminals
end

-- ============================================================================
-- isActive — returns true if any subsystem actually needs scan results
-- ============================================================================

function PortableTerminalScanner.isActive()
    -- Always return true for power/temp monitors when a PortableTerminal window is open
    if PortableTerminalWindow and PortableTerminalWindow.instance and PortableTerminalWindow.instance:isVisible() then
        return true
    end
    -- Freezer feature check
    if PortableTerminalFreezer and PortableTerminalFreezer.isEnabled and PortableTerminalFreezer.isEnabled() then
        return true
    end
    return false
end
