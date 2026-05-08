fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mz_fuel'
author 'Mazus'
description 'Modular fuel system for the MZ ecosystem'
version '1.0.0'

ui_page 'web/index.html'

shared_scripts {
  'shared/config.lua'
}

client_scripts {
  'client/fuel.lua',
  'client/notify.lua',
  'client/menu.lua',
  'client/refuel.lua',
  'client/jerrycan.lua',
  'client/interactions.lua',
  'client/stations.lua',
  'client/main.lua'
}

server_scripts {
  'server/persistence.lua',
  'server/payment.lua',
  'server/logs.lua',
  'server/exports.lua',
  'server/main.lua',
  'server/jerrycan.lua',
  'server/menu.lua'
}

files {
  'web/index.html',
  'web/style.css',
  'web/script.js'
}

dependencies {
  'mz_core'
}
