SocketServer = require 'socket.io'
RedisAdapter = require 'socket.io-redis'
fibrous = require 'fibrous'
#############
log4js = require 'log4js'
logger = log4js.getLogger('socket');
#############
ChatService = require './controllers/chat'

## helpers
autoSpread = (fn, context=this)->

  return (first)->
    args = arguments
    args = first if args.length is 1 and Array.isArray first

    fn.apply context, args



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
        logger.info '%s disconnected', socket.username
        io.emit 'user leave'

      socket.emit 'online users', {
        online: [
          'user-0001',
          'user-0002',
          'user-0003',
          '+841265752223'
          '+84906591398'
        ]
      }

      socket.on 'user signed in', (username)->
        logger.trace 'user signed in', username
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


      socket.on 'outgoing message', autoSpread (message, destination)->

        unless message.sender
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
          message.sender.bold.grey, destination.bold.grey,
          message.body.bold.yellow

        chatService.directMessage io, socket, message.sender, destination, message, (ex)->
          if ex
            logger.warn "Error while attempt to send direct message", ex
            socket.emit "!ERR: message not send", message, ex

      socket.on 'incoming message received', autoSpread (conversationId, messageId) ->
        logger.info 'marking message %s in conversation %s as delivered', messageId, conversationId

        chatService.markDelivered io, socket, conversationId, messageId, (err)->
          if err
            logger.warn "Error while attempt to mark message %s as delivered", messageId?.bold, err

      socket.on 'start typing', autoSpread (conversationId, username, participants)->
        logger.info '%s is typing in conversation %s', username, conversationId
        chatService.typing conversationId, username, participants


module.exports = ScalableChatSocket