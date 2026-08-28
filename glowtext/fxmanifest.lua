fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'SnipeOPGaming / OpenAI'
description 'Standalone persistent glow-glyph text placement'
version '1.1.0'

dependencies {
    'glowglyphs',
    'oxmysql'
}

shared_script 'config.lua'
client_scripts {
    'client/dataview.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/config.lua',
    'server/main.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/styles.css',
    'web/app.js',
    'web/RobotoMono-Bold.ttf'
}
