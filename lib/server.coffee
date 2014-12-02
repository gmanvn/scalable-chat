express = require 'express'
fibrous = require 'fibrous'
log4js = require 'log4js'
cookieParser = require 'cookie-parser'
session = require 'express-session'
RedisStore = require('connect-redis')(session)

redis = require 'redis'

logger = log4js.getLogger('server')
colors = require 'colors'

ScalableChatSocket = require './sockets'

class ScalableChatServer

  constructor: (config)->
    @app = express()

    ## setup
    @setupRedis config
    @setupMiddleware config

    ## init model
    Model = require('./models/index')
    @models = new Model config.mongo

    ## init Socket Server
    @ws = new ScalableChatSocket this



  start: (env, port)->
    logger.debug 'about to start listening on port %s', port
    @httpServer = @app.listen(port)
    logger.info 'ScalableChatServer start listening!\nconfiguration:\n  port: %s\n  env:  %s', String(port).bold.cyan, env.bold.cyan

    @ws.start(@redisPubClient, @redisSubClient)

  setupMiddleware: (config)->
    ## static
    @app.use express.static './app'

    ## cookie
    @app.use cookieParser config.cookie.secret, config.cookie

    ## session
    sessionConfig = config.session
    sessionConfig.store = new RedisStore {
      client: @redisStoreClient
    }

    @app.use session sessionConfig

  setupRedis: (config)->
    @redisPubClient = redis.createClient(config.redis.port, config.redis.host)
    @redisSubClient = redis.createClient(config.redis.port, config.redis.host)
    @redisStoreClient = redis.createClient(config.redis.port, config.redis.host)


module.exports = ScalableChatServer