-- NUI bridge for the weapon spawner. Each request is forwarded to the server
-- (which validates everything) and the result returned to the UI.

AdminBridge('weapons:give')
AdminBridge('weapons:giveAmmo')
AdminBridge('weapons:giveArmor')
