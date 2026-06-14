-- PortableTerminalFreezerClient.lua
-- SINGLE-PLAYER: Prevents rot + thaw for items in freezers connected to a
-- Warehouse Terminal network, as long as the freezer has power.
-- Items follow normal freezing progression first (not instantly frozen).
-- Controlled by the Sandbox option: PortableTerminal.FreezerForeverFrozen
--
-- APPROACH (mirrors mod 2870368509 ice gem):
--   Every ~30s: scan for warehouse terminals → find connected freezers →
--     for each frozen Food item: save original offAgeMax/rottenTime/offAge,
--     call setFrozen(true) + setRotten(false) + setFreezingTime(100) +
--     setHeat(-100).  Mark modData.frozenLocked = true.
--
--   Every ~2s: for ALL locked items in ALL connected powered freezers:
--     setOffAge(lastKnownOffAge)       ← oscillation (prevents rot counter
--     setOffAgeMax(originalOffAgeMax)     from decreasing - this IS the
--     setRottenTime(originalRottenTime)   rot prevention mechanism)
--     setFrozen(true), setRotten(false)
--
--   Because oscillation runs on ALL locked items constantly (not just
--   the viewed container), offAge never advances.  No huge thresholds
--   needed — the steady setOffAge() reset is what stops rot, exactly
--   like the ice gem does every tick in mod 2870368509.

require "WarehouseTerminal/WarehouseTerminalVariant"
require "WarehouseTerminal/WarehouseTerminalUI"

PortableTerminalFreezer = PortableTerminalFreezer or {}
PortableTerminalFreezer.SCAN_INTERVAL_TICKS = 1800       -- ~30 sec
PortableTerminalFreezer.OSCILLATE_INTERVAL_TICKS = 120   -- ~2 sec
PortableTerminalFreezer.DEFAULT_RADIUS = 12
PortableTerminalFreezer.MAX_RADIUS = 30
PortableTerminalFreezer.LOCKED_KEY = "frozenLocked"
PortableTerminalFreezer.knownFreezers = {}

-- ============================================================================
-- Helpers
-- ============================================================================

local function isFrozen(item)
    if not item or not instanceof(item, "Food") then return false end
    local ok, f = pcall(function() return item:isFrozen() end)
    return ok and f
end

local function hasFreezingTime(item)
    if not item or not instanceof(item, "Food") then return false end
    local ok, ft = pcall(function() return item:getFreezingTime() end)
    return ok and ft and ft > 0
end

local function isPerishable(item)
    -- Only items that can actually go stale or rot (have an expiration).
    -- Canned food, chips, etc. have no offAgeMax/rottenTime and never expire.
    if not item or not instanceof(item, "Food") then return false end
    local okMax, offAgeMax = pcall(function() return item:getOffAgeMax() end)
    if okMax and offAgeMax and offAgeMax > 0 then return true end
    local okRot, rottenTime = pcall(function() return item:getRottenTime() end)
    if okRot and rottenTime and rottenTime > 0 then return true end
    return false
end

local function shouldLock(item)
    -- Only lock items that: are Food, can freeze, can expire, and are frozen.
    return hasFreezingTime(item) and isPerishable(item) and isFrozen(item)
end

local function shouldOscillate(item)
    -- Only oscillate items that: are Food, can freeze, can expire.
    return hasFreezingTime(item) and isPerishable(item)
end

local function forEachItem(container, fn)
    if not container then return end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        pcall(function() fn(item) end)
        if instanceof(item, "InventoryContainer") and item:getInventory() then
            forEachItem(item:getInventory(), fn)
        end
    end
end

-- ============================================================================
-- Feature enabled check
-- ============================================================================

local function isEnabled()
    if SandboxVars and SandboxVars.PortableTerminal and SandboxVars.PortableTerminal.FreezerForeverFrozen == true then
        return true
    end
    if getSandboxOptions then
        local ok, opt = pcall(function()
            return getSandboxOptions():getOptionByName("PortableTerminal.FreezerForeverFrozen")
        end)
        if ok and opt then
            local okV, v = pcall(function() return opt:getValue() end)
            if okV and v == true then return true end
        end
    end
    return false
end

-- ============================================================================
-- Lock one frozen item (one-time).
-- Uses getAge()/setAge() like mod 2870368509 ice gem.
-- Also sets offAgeMax huge as fallback (prevents actual staleness even if
-- the oscillation setAge() doesn't fully stop the UI counter).
-- ============================================================================

PortableTerminalFreezer.HUGE_AGE = 99999999

local function lockItem(item)
    if not isFrozen(item) then return end
    local md = item:getModData()
    if md[PortableTerminalFreezer.LOCKED_KEY] then return end

    pcall(function()
        if md.frozenAge == nil then
            md.frozenAge = item:getAge()
        end

        item:setFrozen(true)
        item:setRotten(false)
        item:setFreezingTime(100)
        item:setHeat(-100)
        -- Fallback: if setAge() oscillation doesn't stop the UI counter,
        -- the huge offAgeMax prevents actual staleness regardless.
        item:setOffAgeMax(PortableTerminalFreezer.HUGE_AGE)
        item:setRottenTime(PortableTerminalFreezer.HUGE_AGE)

        md[PortableTerminalFreezer.LOCKED_KEY] = true
    end)
end

-- ============================================================================
-- Oscillate one locked item every ~2s.
-- setAge(frozenAge) is the primary rot-prevention (like ice gem).
-- setFrozen(true) + setRotten(false) are belt-and-suspenders.
-- ============================================================================

local function oscillateItem(item)
    local md = item:getModData()
    if not md[PortableTerminalFreezer.LOCKED_KEY] then return end

    pcall(function()
        if md.frozenAge == nil then
            md.frozenAge = item:getAge()
        end
        item:setAge(md.frozenAge)
        item:setFrozen(true)
        item:setRotten(false)
    end)
end

-- ============================================================================
-- Find warehouse terminals — same scan pattern the WarehouseTerminal mod
-- uses in findWarehouseTerminalsForPacker().  Scans 80 tiles around player.
-- ============================================================================

local TERMINAL_SCAN_RADIUS = 80

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
    for x = cx - TERMINAL_SCAN_RADIUS, cx + TERMINAL_SCAN_RADIUS do
        for y = cy - TERMINAL_SCAN_RADIUS, cy + TERMINAL_SCAN_RADIUS do
            if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= TERMINAL_SCAN_RADIUS * TERMINAL_SCAN_RADIUS then
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
-- doScan: use WarehouseTerminal.scanContainers() (the PROVEN scan) to find
-- connected freezers.  This function already filters by power and cold type.
-- ============================================================================

local function doScan()
    if not isEnabled() then
        PortableTerminalFreezer.knownFreezers = {}
        return
    end

    local terminals = findTerminals()
    if #terminals == 0 then
        PortableTerminalFreezer.knownFreezers = {}
        return
    end

    local seen, newList = {}, {}
    local totalFreezers = 0
    local totalLocked = 0

    for _, term in ipairs(terminals) do
        -- Use WarehouseTerminal's own proven scan — returns containers
        -- with coldType already checked (nil if not powered/cold).
        local radius = tonumber(term:getModData().WarehouseTerminalRadius)
            or PortableTerminalFreezer.DEFAULT_RADIUS
        local containers = WarehouseTerminal.scanContainers(term, radius)

        for _, cInfo in ipairs(containers or {}) do
            if cInfo.coldType == "freezer" and cInfo.container and not seen[cInfo.container] then
                seen[cInfo.container] = true
                totalFreezers = totalFreezers + 1

                -- DEBUG: flag the freezer object so we can verify in-game
                if cInfo.object then
                    pcall(function()
                        cInfo.object:getModData().warehouseConnectedFreezer = true
                    end)
                end

                local info = { container = cInfo.container, square = cInfo.square }
                table.insert(newList, info)

                -- Lock frozen, perishable items
                forEachItem(cInfo.container, function(item)
                    if shouldLock(item) then
                        lockItem(item)
                        totalLocked = totalLocked + 1
                    end
                end)
            end
        end
    end

    -- DEBUG (uncomment to check scan):
    -- print("PortableTerminal: " .. #terminals .. " terminals, " .. totalFreezers .. " freezers, " .. totalLocked .. " items locked")

    PortableTerminalFreezer.knownFreezers = newList
end

-- ============================================================================
-- doOscillation: pin offAge on ALL locked items in ALL connected freezers
-- ============================================================================

local function doOscillation()
    if not isEnabled() then return end
    for _, info in ipairs(PortableTerminalFreezer.knownFreezers or {}) do
        -- Quick power re-check (power could have gone out since last scan)
        local powered = info.container and pcall(function()
            return info.container:isPowered() == true
        end)
        if powered then
            forEachItem(info.container, function(item)
                if shouldOscillate(item) then oscillateItem(item) end
            end)
        end
    end
end

-- ============================================================================
-- Tick counters
-- ============================================================================

local scanCounter, oscCounter = 0, 0

local function onTick()
    scanCounter = scanCounter + 1
    if scanCounter >= PortableTerminalFreezer.SCAN_INTERVAL_TICKS then
        scanCounter = 0
        doScan()
    end

    oscCounter = oscCounter + 1
    if oscCounter >= PortableTerminalFreezer.OSCILLATE_INTERVAL_TICKS then
        oscCounter = 0
        doOscillation()
    end
end

Events.OnTick.Add(onTick)
