express = require 'express'
fibrous = require 'fibrous'
log4js = require 'log4js'
cookieParser = require 'cookie-parser'
session = require 'express-session'

logger = log4js.getLogger('server')
colors = require 'colors'

ScalableChatSocket = require './sockets'

class ScalableChatServer

  constructor: (config)->
    @app = express()
    @app.use express.static './app'
    @app.use cookieParser config.cookie

    @ws = new ScalableChatSocket this


  start: (env, port)->
    logger.debug 'about to start listening on port %s', port
    @httpServer = @app.listen(port)
    logger.info 'ScalableChatServer start listening!\nconfiguration:\n  port: %s\n  env:  %s', String(port).bold.cyan, env.bold.cyan

    @ws.start()

module.exports = ScalableChatServer