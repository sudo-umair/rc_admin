-- NUI bridge for the money manager. The server validates everything.

RegisterNUICallback('money:set', function(data, cb)
    cb(lib.callback.await('rc_admin_menu:money:set', false, data)
        or { success = false, message = 'Request failed.' })
end)
