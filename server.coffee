config = require 'config'
Server = require './lib/server'

server = new Server config

server.start process.env.NODE_ENV or 'development', process.env.PORT or 3000