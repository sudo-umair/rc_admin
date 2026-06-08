-- NUI bridge for the weapon spawner. Each callback forwards the request to the
-- server (which validates everything) and returns the result to the UI.

RegisterNUICallback('weapons:give', function(data, cb)
    cb(lib.callback.await('rc_admin:weapons:give', false, data)
        or { success = false, message = 'Request failed.' })
end)

RegisterNUICallback('weapons:giveAmmo', function(data, cb)
    cb(lib.callback.await('rc_admin:weapons:giveAmmo', false, data)
        or { success = false, message = 'Request failed.' })
end)

RegisterNUICallback('resolvePlayer', function(data, cb)
    cb(lib.callback.await('rc_admin:resolvePlayer', false, data and data.id) or false)
end)
