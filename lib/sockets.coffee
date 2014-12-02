SocketServer = require 'socket.io'
RedisAdapter = require 'socket.io-redis'
fibrous = require 'fibrous'
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

    Conversation = @scalableChatServer.models.models.conversation


    io.sockets.on 'connection', (socket)->
      logger.info 'new connection %s at %s', socket.handshake.address.bold, socket.handshake.time
      socket.conversations = {}

      socket.on 'disconnect', ->
        logger.info 'disconnected'
        io.emit 'user leave'

      socket.emit 'online users', {
        online: [
          'user-0001',
          'user-0002',
          'user-0003'
        ]
      }

      socket.on 'user signed in', (username)->
        return unless 'string' is typeof username
        logger.debug '%s signed in', username.bold.cyan
        socket.username = username

      socket.on 'conversation started', (other) ->
        participants = [socket.username, other]
        logger.info 'Start conversation between %s and %s', participants...

        fibrous.run ->
          ## get conversation of both participants
          conv = Conversation.sync.findOne({
            participants: $all: participants
          })

          ## if no conversation found (they haven't chatted), create a new one
          unless conv
            conv = new Conversation {
              participants
            }

            conv.sync.save()

          socket.conversations[other] = conv._id
          socket.emit 'incoming conversation', conv.toObject()

      socket.on 'request: update conversation', (id)->
        fibrous.run ->
          conv = Conversation.sync.findById id

          if conv
            socket.emit 'updated conversation', conv.toObject()
            return

          socket.emit 'conversation not found', id




      socket.on 'new user', (user)->
        logger.debug 'new user', user.username
        socket.broadcast.emit 'new user', user


      socket.on 'chat message', (message)->
        logger.info 'new chat message', message

        io.emit 'chat message', message


module.exports = ScalableChatSocket