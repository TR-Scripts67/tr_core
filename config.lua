return {
    locale = 'en',
    logLevel = 'info', -- 'error', 'warn', 'info' or 'debug'

    framework = 'auto', -- 'esx', 'qb', 'qbx'
    inventory = 'auto', -- 'ox_inventory', 'qb_inventory'
    target = 'auto', -- 'ox_target', 'qb_target', 'tr_core'
    keys = 'auto', -- a keys script, or 'none'
    fuel = 'auto', -- a fuel script, or 'none'
    dispatch = 'auto', -- a dispatch script, or 'none'
    society = 'auto', -- the banking script with the job accounts, or 'none'
    phone = 'auto', -- a phone script, or 'none'

    accounts = {
        cash = 'auto',
        bank = 'auto',
        dirty = 'auto', -- auto on QBCore: markedbills bags, on Qbox: the black_money item
    },
}
