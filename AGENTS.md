# Project Guidelines — Portable Terminal (Project Zomboid Mod)

## Workspace Layout

This is a **multi-root workspace** with three folders:

| Folder | Purpose |
|--------|---------|
| `portable-terminal/` | **Active mod** — the Portable Terminal mod you are developing. |
| `108600/` | **Reference mods** — other Project Zomboid Steam Workshop mods (App ID 108600). Each subfolder is a workshop ID containing a published mod. Use these for reference: patterns, APIs, item/recipe syntax, Lua conventions. **Never modify files in 108600/.** |
| `ProjectZomboid/` | **Game folder** — the authoritative source for base-game Lua APIs, classes, item definitions, and standard mod structures. Use this as the reference for PZ's core Lua APIs and item/recipe syntax. **Never modify files in ProjectZomboid/.** |

**Only reference folders in this workspace. Do not modify any reference folders.**

## Mod Overview

- **Name**: Portable Terminal
- **Mod ID**: `PortableTerminal`
- **Dependency**: `WarehouseTerminal_Balanced`
- **Concept**: A handheld device that remotely connects to an existing Warehouse Terminal network via Packer IP. Lets the player browse and transfer items from anywhere within range of a Warehouse Packer.

## Mod Structure (standard PZ mod layout)

```
media/
  lua/
    client/PortableTerminal/   — Client-side Lua (UI, context menu, scanner, monitors)
    server/PortableTerminal/   — Server-side Lua (freezer logic)
    shared/PortableTerminal/   — Shared Lua (variant/config)
  scripts/
    PortableTerminalItems.txt  — Item definitions
    PortableTerminalRecipes.txt — Recipe definitions
  textures/                    — Sprites and icons
  sandbox-options.txt          — Sandbox settings
  Translate/EN/                — English localization
```

## Lua Conventions (Project Zomboid Modding)

- **Modules are tables**: Mod code extends a global table matching the mod ID (e.g., `PortableTerminal = PortableTerminal or {}`).
- **Client/Server/Shared split**:
  - `client/` — UI rendering, input handling, context menus. Runs on each player's machine.
  - `server/` — Game logic, inventory manipulation, world state. Runs on the host/dedicated server.
  - `shared/` — Code needed by both sides (config, variant definitions).
- **Item/Recipe syntax**: Uses PZ's custom txt format (key = value blocks, `module Base { }` wrapping).
- **Localization**: `Translate/EN/` holds `.txt` files with key = value translation entries.
- **Sandbox options**: Declared in `sandbox-options.txt` with `option ModID.SettingName { }` blocks.

## Reference Mods (108600/)

When you need to look up how another mod implements a feature, API pattern, or txt syntax, explore the corresponding workshop folder under `108600/`. Each subfolder name is the Steam Workshop ID. Browse `mods/<ModName>/media/` inside each to find the mod's scripts and assets.

Common reference use cases:
- How other mods define custom items with batteries or UI
- How they implement networked inventory operations
- Recipe and item distribution patterns
- Sandbox option and translation setups

## Build / Test

This is a Lua-based Project Zomboid mod — there is no build step. The `ProjectZomboid/` folder is available in the workspace for reference. To test:
1. Copy/link the `portable-terminal` folder into the PZ mods directory (or use the existing setup if already configured)
2. Enable the mod in the game's Mods menu
3. Ensure `WarehouseTerminal_Balanced` is also enabled
