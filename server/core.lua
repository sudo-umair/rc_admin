local ESX = exports['es_extended']:getSharedObject()

-- Shared table for feature modules (all server scripts share one Lua state,
-- and core.lua is loaded before the modules in fxmanifest.lua).
Admin = {}

-----------------------------------------------------------------------------
-- Permissions (ESX `users.group`) — enforced server-side on every action.
-----------------------------------------------------------------------------

local function inList(value, list)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

function Admin.getGroup(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and xPlayer.getGroup() or nil
end

function Admin.isAdmin(src)
    local g = Admin.getGroup(src)
    return g ~= nil and inList(g, Config.AdminGroups)
end

function Admin.isElevated(src)
    local g = Admin.getGroup(src)
    return g ~= nil and inList(g, Config.ElevatedGroups)
end

-----------------------------------------------------------------------------
-- Notifications
-----------------------------------------------------------------------------

function Admin.notify(src, msg, ntype, title)
    TriggerClientEvent('ox_lib:notify', src, {
        title       = title or 'Admin',
        description = msg,
        type        = ntype or 'inform',
        position    = 'top',
    })
end

-----------------------------------------------------------------------------
-- Logging (console + optional Discord webhook)
-----------------------------------------------------------------------------

function Admin.log(action, adminSrc, description, fields)
    local adminName = adminSrc and adminSrc ~= 0 and GetPlayerName(adminSrc) or 'CONSOLE'

    if Config.Logging.console then
        print(('[rc_admin] %s | by %s (id %s) | %s')
            :format(action, adminName, adminSrc or 0, description or ''))
    end

    local url = Config.Logging.webhook
    if url and url ~= '' then
        PerformHttpRequest(url, function() end, 'POST', json.encode({
            username   = Config.Logging.botName,
            avatar_url = (Config.Logging.avatar ~= '' and Config.Logging.avatar) or nil,
            embeds     = { {
                title       = action,
                description = description or '',
                color       = Config.Logging.color,
                fields      = fields,
                footer      = { text = ('%s (id %s)'):format(adminName, adminSrc or 0) },
            } },
        }), { ['Content-Type'] = 'application/json' })
    end
end

-----------------------------------------------------------------------------
-- Module registry
-- Each feature module calls Admin.registerModule{...}. The hub's NUI is built
-- from the modules the requesting admin is allowed to see, so new features
-- appear in the panel automatically.
--   id          : unique key, matched to a renderer in the NUI (script.js)
--   label       : sidebar label
--   icon        : optional emoji/glyph shown in the sidebar
--   elevated    : true = only ElevatedGroups may see/use it
--   getContext  : optional function(src) -> table, data sent to the NUI on open
-----------------------------------------------------------------------------

Admin.modules = {}

function Admin.registerModule(def)
    Admin.modules[#Admin.modules + 1] = def
end

-- Returns the full context the NUI needs to render for this admin.
lib.callback.register('rc_admin:getContext', function(src)
    if not Admin.isAdmin(src) then return false end

    local elevated = Admin.isElevated(src)
    local modules = {}

    for _, m in ipairs(Admin.modules) do
        if m.enabled ~= false and (not m.elevated or elevated) then
            modules[#modules + 1] = {
                id       = m.id,
                label    = m.label,
                icon     = m.icon,
                elevated = m.elevated or false,
                data     = m.getContext and m.getContext(src) or nil,
            }
        end
    end

    return { elevated = elevated, modules = modules }
end)

-----------------------------------------------------------------------------
-- Open the hub (command + optional keybind both route through here)
-----------------------------------------------------------------------------

local function openFor(src)
    if not Admin.isAdmin(src) then
        Admin.notify(src, 'You are not authorized to use this.', 'error')
        return
    end
    TriggerClientEvent('rc_admin:open', src)
end

RegisterCommand(Config.Command, function(source)
    if source == 0 then return end   -- the panel is a client UI; console can't open it
    openFor(source)
end, false)

-- Keybinds fire a client command that we relay here so the group check stays
-- server-authoritative.
RegisterNetEvent('rc_admin:requestOpen', function()
    openFor(source)
end)

-----------------------------------------------------------------------------
-- /checkgroup [id] — read-only lookup of a player's ESX group.
-- From the server console: `checkgroup <id>` (prints the result).
-- In-game: admins only; omit the id to check yourself.
-----------------------------------------------------------------------------

RegisterCommand('checkgroup', function(source, args)
    local id = tonumber(args[1])

    if source == 0 then   -- server console
        if not id then
            print('[rc_admin] usage: checkgroup <server id>')
            return
        end
        local xPlayer = ESX.GetPlayerFromId(id)
        print(('[rc_admin] [%d] group = %s'):format(id, xPlayer and xPlayer.getGroup() or 'not found / offline'))
        return
    end

    if not Admin.isAdmin(source) then
        Admin.notify(source, 'You are not authorized to use this.', 'error')
        return
    end

    id = id or source
    local xPlayer = ESX.GetPlayerFromId(id)
    if not xPlayer then
        Admin.notify(source, ('No online player with ID %s.'):format(id), 'error', 'Check Group')
        return
    end
    Admin.notify(source,
        ('[%d] %s — group: %s'):format(id, xPlayer.getName(), xPlayer.getGroup()),
        'inform', 'Check Group')
end, false)
