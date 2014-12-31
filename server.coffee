require('nodetime').profile({
  accountKey: 'e07aa096509a8dec1f83cd907423a1ee7f82cc3f',
  appName: 'Node.js Application'
});

config = require 'config'
Server = require './lib/server'

server = new Server config

server.start process.env.NODE_ENV or 'development', process.env.PORT or 3000
