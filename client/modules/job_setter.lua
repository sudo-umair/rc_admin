-- NUI bridge for the job setter. The server validates everything.

RegisterNUICallback('jobs:set', function(data, cb)
    cb(lib.callback.await('rc_admin_menu:jobs:set', false, data)
        or { success = false, message = 'Request failed.' })
end)
