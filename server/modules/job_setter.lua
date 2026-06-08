local ESX = exports['es_extended']:getSharedObject()
local CFG = Config.JobSetter or { enabled = true, radius = { min = 1, max = 100, default = 20 } }

if not CFG.enabled then return end

-----------------------------------------------------------------------------
-- Job catalog — built from ESX.GetJobs() and cached.
-- jobs:   { name, label, grades = { { grade, label, salary } } }
-- jobSet: name -> { entry, grades = { [gradeNumber] = true } } for fast validation
-----------------------------------------------------------------------------

local catalog
local jobSet

local function buildCatalog()
    local jobs = ESX.GetJobs() or {}
    local list = {}
    jobSet = {}

    for name, job in pairs(jobs) do
        local grades = {}
        for gradeKey, g in pairs(job.grades or {}) do
            grades[#grades + 1] = {
                grade  = tonumber(g.grade) or tonumber(gradeKey) or 0,
                label  = g.label or g.name or ('Grade ' .. tostring(gradeKey)),
                salary = g.salary,
            }
        end
        table.sort(grades, function(a, b) return a.grade < b.grade end)

        local entry = { name = name, label = job.label or name, grades = grades }
        list[#list + 1] = entry

        local gset = {}
        for _, gr in ipairs(grades) do gset[gr.grade] = true end
        jobSet[name] = { entry = entry, grades = gset }
    end

    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
    catalog = { jobs = list }

    if Config.Debug then
        print(('[rc_admin] job catalog: %d jobs'):format(#list))
    end
end

local function getCatalog()
    if not catalog then buildCatalog() end
    return catalog
end

-- ESX jobs aren't loaded the instant the resource starts; defer the first build.
CreateThread(function()
    Wait(1000)
    buildCatalog()
end)

-----------------------------------------------------------------------------
-- Module registration — exposes the job list to the NUI on open.
-----------------------------------------------------------------------------

Admin.registerModule({
    id    = 'job_setter',
    label = 'Set Job',
    icon  = '💼',
    getContext = function()
        local c = getCatalog()
        return { jobs = c.jobs, radius = CFG.radius }
    end,
})

-----------------------------------------------------------------------------
-- Targeting — resolve a target descriptor into a list of player sources.
-- target = { mode = 'self'|'id'|'nearby'|'everyone', id = number, radius = number }
-- nearby/everyone are gated to ElevatedGroups. Returns (sources[], errorMessage).
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
        local radius = clamp(target.radius, CFG.radius, CFG.radius.default)
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
-- Set job
-----------------------------------------------------------------------------

lib.callback.register('rc_admin:jobs:set', function(src, payload)
    if not Admin.isAdmin(src) then return { success = false, message = 'Not authorized.' } end
    if type(payload) ~= 'table' then return { success = false, message = 'Bad request.' } end

    getCatalog()
    local jdef = payload.job and jobSet[payload.job]
    if not jdef then return { success = false, message = 'Unknown job.' } end

    local grade = tonumber(payload.grade) or 0
    if not jdef.grades[grade] then return { success = false, message = 'Invalid grade for this job.' } end

    local targets, err = resolveTargets(src, payload.target)
    if not targets then return { success = false, message = err } end
    if #targets == 0 then return { success = false, message = 'No valid targets.' } end

    local jobLabel = jdef.entry.label
    local done, failed = 0, 0
    for _, targetSrc in ipairs(targets) do
        local xPlayer = ESX.GetPlayerFromId(targetSrc)
        if xPlayer then
            local ok = pcall(function() xPlayer.setJob(payload.job, grade) end)
            if ok then
                done = done + 1
                if targetSrc ~= src then
                    Admin.notify(targetSrc, ('Your job was set to %s by an admin.'):format(jobLabel), 'inform')
                end
            else
                failed = failed + 1
            end
        else
            failed = failed + 1
        end
    end

    Admin.log('Job Set', src,
        ('Set job %s (grade %d) for %s — %d ok, %d failed')
        :format(jobLabel, grade, describeTarget(payload.target, #targets), done, failed),
        {
            { name = 'Job',     value = jobLabel,                                inline = true },
            { name = 'Grade',   value = tostring(grade),                         inline = true },
            { name = 'Targets', value = describeTarget(payload.target, #targets), inline = true },
        })

    if done == 0 then
        return { success = false, message = 'Could not set the job.' }
    end
    return {
        success = true,
        message = ('Set %s (grade %d) for %s.'):format(jobLabel, grade, describeTarget(payload.target, #targets)),
    }
end)
