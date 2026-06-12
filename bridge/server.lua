-----------------------------------------------------------------------------
-- Framework bridge — uniform player API over ESX and QBCore
--
-- Exposes (server-side global):
--   Bridge.Framework              -> 'esx' | 'qb' | 'none'
--   Bridge.IsInAnyGroup(src, cfg) -> boolean; cfg = { esx = {...}, qb = {...} }
--   Bridge.GetGroupDisplay(src)   -> readable group/permission string or nil
--   Bridge.PlayerExists(src)      -> true when a loaded character is online
--   Bridge.GetOnlinePlayers()     -> array of sources with loaded characters
--   Bridge.GetCharacterName(src)  -> RP character name or nil
--   Bridge.GetJobs()              -> map name -> { label, grades = { { grade, label, salary } } }
--   Bridge.SetJob(src, job, grade)-> boolean
--   Bridge.AddMoney / RemoveMoney / SetMoney(src, account, amount) -> boolean
--   Bridge.GetMoney(src, account) -> number
-----------------------------------------------------------------------------

Bridge = {
    Framework = 'none',
}

local ESX, QBCore

local function tryDetectFramework()
    local wantEsx = Config.Framework == 'esx' or Config.Framework == 'auto'
    local wantQb  = Config.Framework == 'qb' or Config.Framework == 'auto'

    if wantEsx and GetResourceState('es_extended') == 'started' then
        ESX = exports['es_extended']:getSharedObject()
        Bridge.Framework = 'esx'
        return true
    end

    if wantQb and GetResourceState('qb-core') == 'started' then
        QBCore = exports['qb-core']:GetCoreObject()
        Bridge.Framework = 'qb'
        return true
    end

    return false
end

-- the framework may start after rc_admin_menu — keep retrying for a while
CreateThread(function()
    for _ = 1, 60 do
        if tryDetectFramework() then
            print(('[rc_admin_menu] framework: %s'):format(Bridge.Framework))
            return
        end
        Wait(1000)
    end
    print('[rc_admin_menu] WARNING: no framework detected — the admin menu will not work')
end)

-----------------------------------------------------------------------------
-- Permissions
-----------------------------------------------------------------------------

-- cfg holds one group list per framework: { esx = { 'admin' }, qb = { 'god' } }
function Bridge.IsInAnyGroup(src, cfg)
    if Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            local group = xPlayer.getGroup()
            for _, allowed in ipairs(cfg.esx) do
                if group == allowed then return true end
            end
        end
    elseif Bridge.Framework == 'qb' then
        for _, allowed in ipairs(cfg.qb) do
            if QBCore.Functions.HasPermission(src, allowed) then return true end
        end
    end
    return false
end

-- Readable group/permission string, for /checkgroup output only.
function Bridge.GetGroupDisplay(src)
    if Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        return xPlayer and xPlayer.getGroup() or nil
    elseif Bridge.Framework == 'qb' then
        local perms = QBCore.Functions.GetPermission(src)
        if type(perms) == 'string' then return perms end
        if type(perms) == 'table' then
            local out = {}
            for name, has in pairs(perms) do
                if has then out[#out + 1] = name end
            end
            if #out > 0 then return table.concat(out, ', ') end
        end
        return nil
    end
    return nil
end

-----------------------------------------------------------------------------
-- Players
-----------------------------------------------------------------------------

function Bridge.PlayerExists(src)
    if Bridge.Framework == 'esx' then
        return ESX.GetPlayerFromId(src) ~= nil
    elseif Bridge.Framework == 'qb' then
        return QBCore.Functions.GetPlayer(src) ~= nil
    end
    return false
end

-- Sources of every online player with a loaded character.
function Bridge.GetOnlinePlayers()
    local out = {}
    if Bridge.Framework == 'esx' then
        for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
            out[#out + 1] = xPlayer.source
        end
    elseif Bridge.Framework == 'qb' then
        for _, src in ipairs(QBCore.Functions.GetPlayers()) do
            out[#out + 1] = src
        end
    end
    return out
end

function Bridge.GetCharacterName(src)
    if Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            return xPlayer.getName()
        end
    elseif Bridge.Framework == 'qb' then
        local player = QBCore.Functions.GetPlayer(src)
        if player then
            local info = player.PlayerData.charinfo
            return ('%s %s'):format(info.firstname, info.lastname)
        end
    end
    return nil
end

-----------------------------------------------------------------------------
-- Jobs
-----------------------------------------------------------------------------

-- Normalized job registry: name -> { label, grades = { { grade, label, salary } } }
-- (grades unsorted — the caller sorts).
function Bridge.GetJobs()
    local out = {}
    if Bridge.Framework == 'esx' then
        for name, job in pairs(ESX.GetJobs() or {}) do
            local grades = {}
            for gradeKey, g in pairs(job.grades or {}) do
                grades[#grades + 1] = {
                    grade  = tonumber(g.grade) or tonumber(gradeKey) or 0,
                    label  = g.label or g.name or ('Grade ' .. tostring(gradeKey)),
                    salary = g.salary,
                }
            end
            out[name] = { label = job.label or name, grades = grades }
        end
    elseif Bridge.Framework == 'qb' then
        for name, job in pairs(QBCore.Shared.Jobs or {}) do
            local grades = {}
            for gradeKey, g in pairs(job.grades or {}) do
                grades[#grades + 1] = {
                    grade  = tonumber(gradeKey) or 0,
                    label  = g.name or ('Grade ' .. tostring(gradeKey)),
                    salary = g.payment,
                }
            end
            out[name] = { label = job.label or name, grades = grades }
        end
    end
    return out
end

function Bridge.SetJob(src, job, grade)
    if Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end
        xPlayer.setJob(job, grade)
        return true
    elseif Bridge.Framework == 'qb' then
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.SetJob(job, grade) ~= false
    end
    return false
end

-----------------------------------------------------------------------------
-- Money — account names are framework-specific and come from
-- Config.MoneySetter.accounts[Bridge.Framework].
-----------------------------------------------------------------------------

function Bridge.AddMoney(src, account, amount)
    if Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end
        xPlayer.addAccountMoney(account, amount)
        return true
    elseif Bridge.Framework == 'qb' then
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.AddMoney(account, amount) ~= false
    end
    return false
end

function Bridge.RemoveMoney(src, account, amount)
    if Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end
        xPlayer.removeAccountMoney(account, amount)
        return true
    elseif Bridge.Framework == 'qb' then
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.RemoveMoney(account, amount) ~= false
    end
    return false
end

function Bridge.SetMoney(src, account, amount)
    if Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end
        xPlayer.setAccountMoney(account, amount)
        return true
    elseif Bridge.Framework == 'qb' then
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.SetMoney(account, amount) ~= false
    end
    return false
end

function Bridge.GetMoney(src, account)
    if Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            local acc = xPlayer.getAccount(account)
            return (acc and acc.money) or 0
        end
    elseif Bridge.Framework == 'qb' then
        local player = QBCore.Functions.GetPlayer(src)
        if player then
            return player.Functions.GetMoney(account) or 0
        end
    end
    return 0
end
