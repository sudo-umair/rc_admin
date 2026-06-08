Config = {}

-----------------------------------------------------------------------------
-- General
-----------------------------------------------------------------------------

Config.Debug = false      -- print diagnostics to server & client (F8) consoles

-- How the admin hub is opened.
Config.Command = 'adminmenu'  -- chat command, e.g. /adminmenu
Config.OpenKey = ''       -- optional keybind (e.g. 'F6'); '' = command only
                          -- players can rebind it under Settings > Key Bindings > FiveM

-----------------------------------------------------------------------------
-- Permissions (ESX `users.group`)
-- These are checked SERVER-SIDE on every action — the client never decides.
--
-- AdminGroups    : may open the hub and use standard actions
--                  (spawn for self / a player by server ID).
-- ElevatedGroups : additionally allowed to run high-impact actions
--                  (give to EVERYONE online, give to NEARBY players).
-----------------------------------------------------------------------------

Config.AdminGroups    = { 'admin', 'developer' }
Config.ElevatedGroups = { 'admin', 'developer' }

-----------------------------------------------------------------------------
-- Logging (admin actions)
-- Spawning weapons is abuse-sensitive, so every grant is recorded.
-----------------------------------------------------------------------------

Config.Logging = {
    console = true,                 -- print to the server console
    webhook = '',                   -- Discord webhook URL ('' disables Discord logging)
    botName = 'rc_admin',
    avatar  = '',                   -- optional Discord avatar URL
    color   = 3447003,              -- embed colour (blue)
}

-----------------------------------------------------------------------------
-- Weapon Spawner module
-----------------------------------------------------------------------------

Config.WeaponSpawner = {
    enabled = true,

    -- The catalog is built automatically from the ox_inventory item registry,
    -- classified by these (lowercase) name prefixes. Adjust to match the item
    -- names your server actually uses if the lists come up empty in-game.
    weaponPrefixes    = { 'weapon_' },          -- weapon_pistol, weapon_carbinerifle ...
    ammoPrefixes      = { 'ammo' },             -- ammo-9, ammo_rifle, ammo ...
    componentPrefixes = { 'component', 'at_' }, -- attachment/component items

    -- Weapons that never take ammo (melee / throwables). The ammo field is
    -- ignored for these. Compared in lowercase.
    noAmmoWeapons = {
        'weapon_unarmed', 'weapon_knife', 'weapon_bat', 'weapon_crowbar',
        'weapon_hammer', 'weapon_machete', 'weapon_hatchet', 'weapon_knuckle',
        'weapon_flashlight', 'weapon_nightstick', 'weapon_poolcue',
        'weapon_dagger', 'weapon_battleaxe', 'weapon_wrench', 'weapon_switchblade',
        'weapon_snowball', 'weapon_grenade', 'weapon_smokegrenade', 'weapon_bzgas',
        'weapon_molotov', 'weapon_proxmine', 'weapon_pipebomb', 'weapon_stickybomb',
        'weapon_flare', 'weapon_ball', 'weapon_petrolcan', 'weapon_fireextinguisher',
    },

    -- Items hidden from the catalog entirely (compared in lowercase).
    hidden = { 'weapon_unarmed' },

    -- Optional manual grouping: itemName(lowercase) -> category label.
    -- Anything not listed falls under Config.WeaponSpawner.defaultCategory.
    -- Leave empty to put every weapon under the default category.
    categories = {
        -- ['weapon_pistol']        = 'Handguns',
        -- ['weapon_carbinerifle']  = 'Rifles',
    },
    defaultCategory = 'Weapons',

    -- Server-side limits enforced on admin input.
    limits = {
        quantity   = { min = 1, max = 10   },   -- weapons given per action
        ammo       = { min = 0, max = 9999 },   -- ammo loaded / given
        durability = { min = 1, max = 100  },   -- weapon condition (%)
        radius     = { min = 1, max = 100  },   -- "nearby" radius (metres)
    },

    -- Defaults pre-filled in the give dialog.
    defaults = {
        quantity   = 1,
        ammo       = 250,
        durability = 100,
        radius     = 20,
    },
}
