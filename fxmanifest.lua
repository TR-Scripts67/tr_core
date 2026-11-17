fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'tr_core'
author 'TR Scripts'
description 'Shared core library for TR Scripts'
version '1.8.0'

shared_script 'init.lua'
server_scripts {
    'server/main.lua',
    'server/versions.lua',
}
client_scripts {
    'client/main.lua',
    'client/interact.lua',
}

files {
    'init.lua',
    'config.lua',
    'modules/**/shared.lua',
    'modules/**/client.lua',
    'bridge/**/client.lua',
    'bridge/**/shared.lua',
    'web/interact/**',
    'web/phone/*.js',
}

dependencies {
    '/onesync',
}
