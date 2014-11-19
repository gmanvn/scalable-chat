SocketServer = require 'socket.io'
RedisAdapter = require 'socket.io-redis'

log4js = require 'log4js'
logger = log4js.getLogger('socket');

class ScalableChatSocket

  constructor: (@scalableChatServer) ->
    @app = scalableChatServer.app


  start: (redisClient) ->
    httpServer = @scalableChatServer.httpServer
    throw new Error 'http is not started' unless httpServer
    io = new SocketServer httpServer

    io.adapter RedisAdapter {
      pubClient: redisClient
      subClient: redisClient
    }


    io.sockets.on 'connection', (socket)->
      logger.info 'new connection %s at %s', socket.handshake.address.bold, socket.handshake.time


module.exports = ScalableChatSocket