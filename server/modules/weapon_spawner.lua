local ESX = exports['es_extended']:getSharedObject()
local CFG = Config.WeaponSpawner

if not CFG.enabled then return end

-----------------------------------------------------------------------------
-- Classification helpers
-----------------------------------------------------------------------------

local function startsWithAny(name, prefixes)
    for _, p in ipairs(prefixes) do
        if name:sub(1, #p) == p then return true end
    end
    return false
end

local function inSet(name, list)
    for _, v in ipairs(list) do
        if v == name then return true end
    end
    return false
end

local function categorize(name)
    return CFG.categories[name] or CFG.defaultCategory
end

-- Resolve an item's image to an ox_inventory NUI path. Honours a custom
-- client.image when set, otherwise falls back to the (lowercased) item name.
local function imageFor(name, data)
    local img = data and data.client and data.client.image
    if img and img ~= '' then
        if img:find('://') then return img end
        return ('nui://ox_inventory/web/images/%s'):format(img)
    end
    return ('nui://ox_inventory/web/images/%s.png'):format(name:lower())
end

-----------------------------------------------------------------------------
-- Catalog — built once from the ox_inventory item registry and cached.
-- weapons:    { name, label, category, ammoname, takesAmmo }
-- ammo:       { name, label }
-- components: { name, label }
-----------------------------------------------------------------------------

local catalog
local weaponSet, ammoSet, componentSet   -- name -> entry, for fast validation

local function buildCatalog()
    local items = exports.ox_inventory:Items()
    local weapons, ammo, components = {}, {}, {}
    weaponSet, ammoSet, componentSet = {}, {}, {}

    for name, data in pairs(items) do
        local lname = name:lower()
        local label = (data and data.label) or name

        if startsWithAny(lname, CFG.weaponPrefixes) and not inSet(lname, CFG.hidden) then
            local entry = {
                name      = name,
                label     = label,
                category  = categorize(lname),
                ammoname  = data and data.ammoname or nil,
                takesAmmo = not inSet(lname, CFG.noAmmoWeapons),
                image     = imageFor(name, data),
            }
            weapons[#weapons + 1] = entry
            weaponSet[name] = entry
        elseif startsWithAny(lname, CFG.ammoPrefixes) then
            local entry = { name = name, label = label, image = imageFor(name, data) }
            ammo[#ammo + 1] = entry
            ammoSet[name] = entry
        elseif startsWithAny(lname, CFG.componentPrefixes) then
            local entry = { name = name, label = label, image = imageFor(name, data) }
            components[#components + 1] = entry
            componentSet[name] = entry
        end
    end

    local byLabel = function(a, b) return a.label:lower() < b.label:lower() end
    table.sort(weapons, byLabel)
    table.sort(ammo, byLabel)
    table.sort(components, byLabel)

    -- ordered, de-duplicated category list for the NUI filter chips
    local seen, categories = {}, {}
    for _, w in ipairs(weapons) do
        if not seen[w.category] then
            seen[w.category] = true
            categories[#categories + 1] = w.category
        end
    end
    table.sort(categories)

    catalog = { weapons = weapons, ammo = ammo, components = components, categories = categories }

    if Config.Debug then
        print(('[rc_admin] weapon catalog: %d weapons, %d ammo, %d components')
            :format(#weapons, #ammo, #components))
    end
end

local function getCatalog()
    if not catalog then buildCatalog() end
    return catalog
end

-- ox_inventory items aren't ready the instant the resource starts; defer.
CreateThread(function()
    Wait(1000)
    buildCatalog()
end)

-----------------------------------------------------------------------------
-- Module registration — exposes the catalog to the NUI on open.
-----------------------------------------------------------------------------

Admin.registerModule({
    id    = 'weapon_spawner',
    label = 'Weapon Spawner',
    icon  = '🔫',
    getContext = function()
        local c = getCatalog()
        return {
            weapons    = c.weapons,
            ammo       = c.ammo,
            components = c.components,
            categories = c.categories,
            limits     = CFG.limits,
            defaults   = CFG.defaults,
        }
    end,
})

-----------------------------------------------------------------------------
-- Targeting — resolve a target descriptor into a list of player sources.
-- target = { mode = 'self'|'id'|'nearby'|'everyone', id = number, radius = number }
-- Returns (sources[], errorMessage).
-----------------------------------------------------------------------------

local function clamp(v, lim, fallback)
    v = tonumber(v)
    if not v then return fallback end
    if v < lim.min then return lim.min end
    if v > lim.max then return lim.max end
    return v
end

local function resolveTargets(adminSrc, target)
    local mode = target and target.mode or 'self'

    if mode == 'self' then
        return { adminSrc }
    end

    if mode == 'id' then
        local id = tonumber(target.id)
        if not id then return nil, 'Invalid server ID.' end
        if not ESX.GetPlayerFromId(id) then
            return nil, ('No online player with server ID %s.'):format(id)
        end
        return { id }
    end

    -- elevated-only modes
    if not Admin.isElevated(adminSrc) then
        return nil, 'You are not authorized for that target.'
    end

    if mode == 'everyone' then
        local out = {}
        for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
            out[#out + 1] = xPlayer.source
        end
        return out
    end

    if mode == 'nearby' then
        local radius = clamp(target.radius, CFG.limits.radius, CFG.defaults.radius)
        local adminPed = GetPlayerPed(adminSrc)
        if adminPed == 0 then return nil, 'Could not locate you in the world.' end
        local origin = GetEntityCoords(adminPed)
        local out = {}
        for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
            local ped = GetPlayerPed(xPlayer.source)
            if ped ~= 0 and #(GetEntityCoords(ped) - origin) <= radius then
                out[#out + 1] = xPlayer.source
            end
        end
        return out
    end

    return nil, 'Unknown target mode.'
end

local function describeTarget(target, count)
    local mode = target and target.mode or 'self'
    if mode == 'self' then return 'themselves' end
    if mode == 'id' then return ('player %s'):format(target.id) end
    if mode == 'everyone' then return ('everyone online (%d)'):format(count) end
    if mode == 'nearby' then return ('%d nearby player(s)'):format(count) end
    return 'unknown'
end

-----------------------------------------------------------------------------
-- Give weapon
-----------------------------------------------------------------------------

lib.callback.register('rc_admin:weapons:give', function(src, payload)
    if not Admin.isAdmin(src) then return { success = false, message = 'Not authorized.' } end
    if type(payload) ~= 'table' then return { success = false, message = 'Bad request.' } end

    getCatalog()
    local weapon = weaponSet[payload.weapon]
    if not weapon then return { success = false, message = 'Unknown weapon.' } end

    local quantity   = clamp(payload.quantity, CFG.limits.quantity, CFG.defaults.quantity)
    local durability = clamp(payload.durability, CFG.limits.durability, CFG.defaults.durability)
    local ammo       = weapon.takesAmmo and clamp(payload.ammo, CFG.limits.ammo, CFG.defaults.ammo) or 0

    -- validate requested attachments against the catalog
    local components = {}
    if type(payload.components) == 'table' then
        for _, compName in ipairs(payload.components) do
            if componentSet[compName] then components[#components + 1] = compName end
        end
    end

    local targets, err = resolveTargets(src, payload.target)
    if not targets then return { success = false, message = err } end
    if #targets == 0 then return { success = false, message = 'No valid targets.' } end

    local metadata = { durability = durability }
    if #components > 0 then metadata.components = components end

    local given, failed = 0, 0
    for _, targetSrc in ipairs(targets) do
        local ok = false
        if exports.ox_inventory:CanCarryItem(targetSrc, weapon.name, quantity) then
            local success, added = pcall(function()
                return exports.ox_inventory:AddItem(targetSrc, weapon.name, quantity, metadata)
            end)
            ok = success and added ~= false
            -- load ammo as its matching ammo item, if any
            if ok and ammo > 0 and weapon.ammoname then
                pcall(function()
                    exports.ox_inventory:AddItem(targetSrc, weapon.ammoname, ammo)
                end)
            end
        end
        if ok then
            given = given + 1
            if targetSrc ~= src then
                Admin.notify(targetSrc, ('You received %dx %s from an admin.')
                    :format(quantity, weapon.label), 'success')
            end
        else
            failed = failed + 1
        end
    end

    Admin.log('Weapon Spawned', src,
        ('Gave %dx %s (ammo %d, durability %d%%, %d attachment(s)) to %s — %d ok, %d failed')
        :format(quantity, weapon.label, ammo, durability, #components,
            describeTarget(payload.target, #targets), given, failed),
        {
            { name = 'Weapon',  value = weapon.label,                 inline = true },
            { name = 'Qty/Ammo', value = ('%d / %d'):format(quantity, ammo), inline = true },
            { name = 'Targets', value = describeTarget(payload.target, #targets), inline = true },
        })

    if given == 0 then
        return { success = false, message = 'Could not give the weapon (inventory full?).' }
    end
    return {
        success = true,
        message = ('Gave %dx %s to %s.'):format(quantity, weapon.label, describeTarget(payload.target, #targets)),
    }
end)

-----------------------------------------------------------------------------
-- Give ammo (standalone ammo item)
-----------------------------------------------------------------------------

lib.callback.register('rc_admin:weapons:giveAmmo', function(src, payload)
    if not Admin.isAdmin(src) then return { success = false, message = 'Not authorized.' } end
    if type(payload) ~= 'table' then return { success = false, message = 'Bad request.' } end

    getCatalog()
    local ammoItem = ammoSet[payload.ammo]
    if not ammoItem then return { success = false, message = 'Unknown ammo item.' } end

    local amount = clamp(payload.amount, CFG.limits.ammo, CFG.defaults.ammo)
    if amount <= 0 then return { success = false, message = 'Amount must be greater than zero.' } end

    local targets, err = resolveTargets(src, payload.target)
    if not targets then return { success = false, message = err } end
    if #targets == 0 then return { success = false, message = 'No valid targets.' } end

    local given, failed = 0, 0
    for _, targetSrc in ipairs(targets) do
        local ok = false
        if exports.ox_inventory:CanCarryItem(targetSrc, ammoItem.name, amount) then
            local success, added = pcall(function()
                return exports.ox_inventory:AddItem(targetSrc, ammoItem.name, amount)
            end)
            ok = success and added ~= false
        end
        if ok then
            given = given + 1
            if targetSrc ~= src then
                Admin.notify(targetSrc, ('You received %dx %s from an admin.')
                    :format(amount, ammoItem.label), 'success')
            end
        else
            failed = failed + 1
        end
    end

    Admin.log('Ammo Spawned', src,
        ('Gave %dx %s to %s — %d ok, %d failed')
        :format(amount, ammoItem.label, describeTarget(payload.target, #targets), given, failed))

    if given == 0 then
        return { success = false, message = 'Could not give ammo (inventory full?).' }
    end
    return {
        success = true,
        message = ('Gave %dx %s to %s.'):format(amount, ammoItem.label, describeTarget(payload.target, #targets)),
    }
end)
