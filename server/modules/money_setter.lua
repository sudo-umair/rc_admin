local CFG = Config.MoneySetter or {
    enabled = true,
    accounts = { esx = { { name = 'money', label = 'Cash' } }, qb = { { name = 'cash', label = 'Cash' } } },
    operations = { 'add', 'remove', 'set' },
    limits = { amount = { min = 1, max = 10000000 } },
    radius = { min = 1, max = 100, default = 20 },
}

if not CFG.enabled then return end

-----------------------------------------------------------------------------
-- Lookup sets built from config, for fast server-side validation.
-- accountSet : framework account name -> display label (lazy — the account
--              list depends on which framework the bridge detects)
-- opSet      : operation name -> true (only the configured ops are allowed)
-----------------------------------------------------------------------------

local function getAccounts()
    return CFG.accounts[Bridge.Framework] or {}
end

local accountSet
local function getAccountSet()
    if not accountSet and Bridge.Framework ~= 'none' then
        accountSet = {}
        for _, a in ipairs(getAccounts()) do accountSet[a.name] = a.label or a.name end
    end
    return accountSet or {}
end

local opSet = {}
for _, op in ipairs(CFG.operations or {}) do opSet[op] = true end

-- Format a whole-number amount with thousands separators (1234567 -> 1,234,567).
local function fmtMoney(n)
    local s = tostring(math.floor(n))
    local sign = ''
    if s:sub(1, 1) == '-' then sign, s = '-', s:sub(2) end
    while true do
        local rep
        s, rep = s:gsub('^(%d+)(%d%d%d)', '%1,%2')
        if rep == 0 then break end
    end
    return sign .. s
end

-----------------------------------------------------------------------------
-- Module registration — exposes the account list & operations to the NUI.
-----------------------------------------------------------------------------

Admin.registerModule({
    id    = 'money_setter',
    label = 'Manage Money',
    icon  = '💵',
    getContext = function()
        return {
            accounts   = getAccounts(),
            operations = CFG.operations,
            limits     = CFG.limits,
            radius     = CFG.radius,
        }
    end,
})

-----------------------------------------------------------------------------
-- Apply a money operation (add / remove / set) on one player. Returns true on
-- success. `remove` is capped at the player's current balance so it can never
-- push an account negative.
-----------------------------------------------------------------------------

local function applyMoney(targetSrc, account, op, amount, accountLabel, isSelf)
    if not Bridge.PlayerExists(targetSrc) then return false end

    local ok, result = pcall(function()
        if op == 'add' then
            return Bridge.AddMoney(targetSrc, account, amount)
        elseif op == 'set' then
            return Bridge.SetMoney(targetSrc, account, amount)
        else -- remove
            local take = math.min(amount, Bridge.GetMoney(targetSrc, account))
            if take > 0 then return Bridge.RemoveMoney(targetSrc, account, take) end
            return true
        end
    end)
    ok = ok and result ~= false

    if ok and not isSelf then
        local msg
        if op == 'add' then
            msg = ('An admin added $%s to your %s.'):format(fmtMoney(amount), accountLabel)
        elseif op == 'remove' then
            msg = ('An admin removed $%s from your %s.'):format(fmtMoney(amount), accountLabel)
        else
            msg = ('An admin set your %s to $%s.'):format(accountLabel, fmtMoney(amount))
        end
        Admin.notify(targetSrc, msg, op == 'remove' and 'warning' or 'inform')
    end

    return ok
end

-----------------------------------------------------------------------------
-- Set / add / remove money
-----------------------------------------------------------------------------

lib.callback.register('rc_admin_menu:money:set', function(src, payload)
    if not Admin.isAdmin(src) then return { success = false, message = 'Not authorized.' } end
    if type(payload) ~= 'table' then return { success = false, message = 'Bad request.' } end

    local accountLabel = getAccountSet()[payload.account]
    if not accountLabel then return { success = false, message = 'Unknown account.' } end

    local op = payload.operation
    if not opSet[op] then return { success = false, message = 'Operation not allowed.' } end

    local lim = CFG.limits.amount
    local amount = tonumber(payload.amount)
    if not amount then return { success = false, message = 'Invalid amount.' } end
    amount = math.floor(amount)
    if amount < 0 then amount = 0 end
    if amount > lim.max then amount = lim.max end
    if (op == 'add' or op == 'remove') and amount < lim.min then
        return { success = false, message = ('Amount must be at least $%s.'):format(fmtMoney(lim.min)) }
    end

    local targets, err = Admin.resolveTargets(src, payload.target, CFG.radius)
    if not targets then return { success = false, message = err } end
    if #targets == 0 then return { success = false, message = 'No valid targets.' } end

    local done, failed = 0, 0
    for _, targetSrc in ipairs(targets) do
        if applyMoney(targetSrc, payload.account, op, amount, accountLabel, targetSrc == src) then
            done = done + 1
        else
            failed = failed + 1
        end
    end

    local verb = (op == 'add' and 'Added') or (op == 'remove' and 'Removed') or 'Set'
    local phrase
    if op == 'set' then
        phrase = ('Set %s to $%s'):format(accountLabel, fmtMoney(amount))
    elseif op == 'add' then
        phrase = ('Added $%s to %s'):format(fmtMoney(amount), accountLabel)
    else
        phrase = ('Removed $%s from %s'):format(fmtMoney(amount), accountLabel)
    end

    Admin.log('Money Changed', src,
        ('%s for %s — %d ok, %d failed')
        :format(phrase, Admin.describeTarget(payload.target, #targets), done, failed),
        {
            { name = 'Operation', value = verb,                                     inline = true },
            { name = 'Account',   value = accountLabel,                             inline = true },
            { name = 'Amount',    value = ('$%s'):format(fmtMoney(amount)),         inline = true },
            { name = 'Targets',   value = Admin.describeTarget(payload.target, #targets), inline = true },
        })

    if done == 0 then
        return { success = false, message = 'Could not change the balance.' }
    end
    return {
        success = true,
        message = ('%s for %s.'):format(phrase, Admin.describeTarget(payload.target, #targets)),
    }
end)
