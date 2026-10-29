-- tr_core settings, shared by every TR script. Restart the server after a change.
-- Discord webhooks go in server_config.lua: this file is sent to every player's game.

return {
    locale = 'en',      -- the language: a file in each script's locales/ folder ('en', 'sv', ...)
    logLevel = 'info',  -- what prints in the console: 'error', 'warn', 'info' or 'debug'

    -- The scripts tr_core works with. 'auto' finds them by itself.
    framework = 'auto', -- 'esx', 'qb', 'qbx'
    inventory = 'auto', -- 'ox_inventory', 'qb_inventory'
    target = 'auto',    -- 'ox_target', 'qb_target', or 'tr_core' for its own (a dot, then E)
    keys = 'auto',      -- your vehicle keys script, or 'none'
    fuel = 'auto',      -- your fuel script, or 'none'
    dispatch = 'auto',  -- your police dispatch script, or 'none'

    -- Your framework's money types. 'auto' uses its usual ones.
    accounts = {
        cash = 'auto',
        bank = 'auto',
        dirty = 'auto', -- QBCore and Qbox have none: put yours here, or dirty money reads as 0
    },
}
