SocketServer = require 'socket.io'
RedisAdapter = require 'socket.io-redis'
fibrous = require 'fibrous'
#############
log4js = require 'log4js'
logger = log4js.getLogger('socket');
#############
ChatService = require './controllers/chat'


class ScalableChatSocket

  constructor: (@scalableChatServer) ->
    @app = scalableChatServer.app
    @ModelFactory = scalableChatServer.models

    ## init service
    @chatService = new ChatService @ModelFactory



  start: (redisPubClient, redisSubClient) ->
    httpServer = @scalableChatServer.httpServer
    throw new Error 'http is not started' unless httpServer
    io = new SocketServer httpServer

    io.adapter RedisAdapter {
      pubClient: redisPubClient
      subClient: redisSubClient
    }


    Conversation = @ModelFactory.models.conversation

    chatService = @chatService


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
        chatService.newSocket socket, username

      socket.on 'conversation started', (other) ->
        participants = [socket.username, other]
        logger.info 'Start conversation between %s and %s', participants...


        fibrous.run ->
          ## get conversation of both participants
          conv = Conversation.sync.findOne({
            participants:
              $all: participants
          })

          ## if no conversation found (they haven't chatted), create a new one
          unless conv
            conv = new Conversation {
              participants
            }

            conv.sync.save()


          socket.join "conversation-#{conv._id}"
          socket.conversations[other] = conv._id
          socket.emit 'incoming conversation', conv.toObject()

      socket.on 'request: update conversation', (id)->
        fibrous.run ->
          conv = Conversation.sync.findById id

          if conv
            socket.emit 'updated conversation', conv.toObject()
            return

          socket.emit 'conversation not found', id


      socket.on 'outgoing message', (message, destination)->
        unless socket.username
          logger.warn "direct message without sender"
          socket.emit "!ERR: message not sent", message, {
            code: 'NO_SENDER'
            name: 'MSG_NOT_SENT'
            message: 'direct message without sender'
          }
          return

        unless destination
          logger.warn "direct message without destination"
          socket.emit "!ERR: message not sent", message, {
            code: 'NO_DESTINATION'
            name: 'MSG_NOT_SENT'
            message: 'direct message without destination'
          }
          return

        unless message.body
          logger.warn "direct message without body"
          socket.emit "!ERR: message not sent", message, {
            code: 'NO_BODY'
            name: 'MSG_NOT_SENT'
            message: 'direct message without body'
          }
          return

        logger.info "direct message: %s -> %s: %s",
          socket.username.bold.grey, destination.bold.grey,
          message.body.bold.yellow

        chatService.directMessage io, socket.username, destination, message, (ex)->
          if ex
            logger.warn "Error while attempt to send direct message", ex
            socket.emit "!ERR: message not send", message, ex

module.exports = ScalableChatSocket