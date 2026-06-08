fx_version 'cerulean'
game 'gta5'

name 'rc_admin'
description 'ESX modular admin toolkit — a central admin menu with pluggable feature modules. First module: weapon/ammo/attachment spawner (ox_inventory).'
author 'sudo-umair'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/core.lua',
    'client/modules/weapon_spawner.lua',
    'client/modules/job_setter.lua'
}

server_scripts {
    'server/core.lua',
    'server/modules/weapon_spawner.lua',
    'server/modules/job_setter.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/logo.png'
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory'
}
