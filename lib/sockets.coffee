SocketServer = require 'socket.io'
RedisAdapter = require 'socket.io-redis'

log4js = require 'log4js'
logger = log4js.getLogger('socket');

class ScalableChatSocket

  constructor: (@scalableChatServer) ->
    @app = scalableChatServer.app


  start: (redisPubClient,redisSubClient) ->
    httpServer = @scalableChatServer.httpServer
    throw new Error 'http is not started' unless httpServer
    io = new SocketServer httpServer

    io.adapter RedisAdapter {
      pubClient: redisPubClient
      subClient: redisSubClient
    }


    io.sockets.on 'connection', (socket)->
      logger.info 'new connection %s at %s', socket.handshake.address.bold, socket.handshake.time

      io.emit('new user')

      socket.on 'disconnect', ->
        logger.info 'disconnected'
        io.emit 'user leave'

      socket.on 'chat message', (message)->
        logger.info 'new chat message', message

        io.emit 'chat message', message


module.exports = ScalableChatSocket