local isOpen = false

-----------------------------------------------------------------------------
-- Open / close
-----------------------------------------------------------------------------

local function open()
    if isOpen then return end

    local ctx = lib.callback.await('rc_admin:getContext', false)
    if not ctx then
        lib.notify({ title = 'Admin', description = 'Not authorized.', type = 'error' })
        return
    end

    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = ctx })
end

local function close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNetEvent('rc_admin:open', open)

RegisterNUICallback('close', function(_, cb)
    close()
    cb('ok')
end)

-- Generic: resolve a server ID to a player name (shared by feature modules).
RegisterNUICallback('resolvePlayer', function(data, cb)
    cb(lib.callback.await('rc_admin:resolvePlayer', false, data and data.id) or false)
end)

-- Shared toast helper so feature modules can surface results from the NUI.
function AdminToast(kind, message)
    SendNUIMessage({ action = 'toast', data = { type = kind, message = message } })
end

-----------------------------------------------------------------------------
-- Optional keybind (relayed to the server so the group check stays authoritative)
-----------------------------------------------------------------------------

if Config.OpenKey and Config.OpenKey ~= '' then
    lib.addKeybind({
        name        = 'rc_admin_open',
        description = 'Open admin menu',
        defaultKey  = Config.OpenKey,
        onPressed   = function()
            if isOpen then close() else TriggerServerEvent('rc_admin:requestOpen') end
        end,
    })
end

-- Safety net: close the panel if the resource stops while it's open.
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and isOpen then
        SetNuiFocus(false, false)
    end
end)
