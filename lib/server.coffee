express = require 'express'
fibrous = require 'fibrous'
log4js = require 'log4js'
cookieParser = require 'cookie-parser'
session = require 'express-session'
RedisStore = require('connect-redis')(session)

redis = require 'redis'
NRP = require('node-redis-pubsub')


logger = log4js.getLogger('server')
colors = require 'colors'

ScalableChatSocket = require './sockets'

class ScalableChatServer

  constructor: (config)->
    ## TODO: need to get env from runtime
    env = config.env or process.env.NODE_ENV
    @app = express()

    ## setup
    @setupRedis config
    @setupMiddleware config

    ## init model
    Model = require('./models/index')
    @models = new Model config.mongo


    @nrp = new NRP {
      port: config.redis.port
      host: config.redis.host
      auth: config.redis.auth
      scope: "scalable-chat.s2s.#{ env }"
    }


    ## init Socket Server
    @ws = new ScalableChatSocket this

  on: ->
    @nrp.on arguments...

  emit: ->
    @nrp.emit arguments...


  start: (env, port)->
    logger.debug 'about to start listening on port %s', port
    @httpServer = @app.listen(port)
    logger.info 'ScalableChatServer start listening!\nconfiguration:\n  port: %s\n  env:  %s', String(port).bold.cyan, env.bold.cyan

    @ws.start(@redisPubClient, @redisSubClient, "scalable-chat.#{ env }")


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
    opts = {
      return_buffers:true
      auth_pass: config.redis.auth or undefined
    }
    @redisPubClient = redis.createClient(config.redis.port, config.redis.host, opts)
    @redisSubClient = redis.createClient(config.redis.port, config.redis.host, opts)
    @redisStoreClient = redis.createClient(config.redis.port, config.redis.host, opts)


module.exports = ScalableChatServer