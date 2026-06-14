-- PortableTerminalFreezer.lua
-- Server stub: The actual freezer-forever-frozen logic is implemented
-- entirely client-side in PortableTerminalFreezerClient.lua (single-player).
-- This stub exists for multiplayer compatibility — in MP, the sandbox
-- option is still registered, but the freezing logic does not run on
-- the server (the client-side script handles everything in SP mode).

PortableTerminalFreezer = PortableTerminalFreezer or {}
-- No server-side logic needed for single-player.
