-- NUI bridge for the weapon spawner. Each callback forwards the request to the
-- server (which validates everything) and returns the result to the UI.

RegisterNUICallback('weapons:give', function(data, cb)
    cb(lib.callback.await('rc_admin_menu:weapons:give', false, data)
        or { success = false, message = 'Request failed.' })
end)

RegisterNUICallback('weapons:giveAmmo', function(data, cb)
    cb(lib.callback.await('rc_admin_menu:weapons:giveAmmo', false, data)
        or { success = false, message = 'Request failed.' })
end)

RegisterNUICallback('weapons:giveArmor', function(data, cb)
    cb(lib.callback.await('rc_admin_menu:weapons:giveArmor', false, data)
        or { success = false, message = 'Request failed.' })
end)
