config = require 'config'
Server = require './lib/server'

server = new Server config

server.start 'development', 3000