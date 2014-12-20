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

logError = (err)-> logger.warn err if err


class ScalableChatSocket

  constructor: (@scalableChatServer) ->
    @app = scalableChatServer.app
    @ModelFactory = scalableChatServer.models

    ## init service
    @chatService = new ChatService @ModelFactory



  start: (redisPubClient, redisSubClient, key) ->
    httpServer = @scalableChatServer.httpServer
    throw new Error 'http is not started' unless httpServer
    io = new SocketServer httpServer

    io.adapter RedisAdapter {
      key
      pubClient: redisPubClient
      subClient: redisSubClient
    }


    Conversation = @ModelFactory.models.conversation

    chatService = @chatService


    io.sockets.on 'connection', (socket)->
      socket.conversations = {}
      ip = socket.handshake.headers['x-forwarded-for'] or socket.handshake.address

      ## forcefully close socket if it hasn't signed in after 2s
      setTimeout ->
        socket.disconnect() unless chatService.isSignedIn(socket)
      , 2000

      socket.on 'disconnect', ->
        logger.info '%s disconnected', socket.username or 'an unsigned in user'
        io.emit 'user leave'

      socket.on 'user signed in', autoSpread (username, token)->
        logger.trace 'user [%s] signed in on ip: %s', username, ip
        chatService.newSocket socket, username, token, logError

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

      socket.on 'start typing', autoSpread (conversationId, username, participants, isTyping=true)->
        if isTyping
          logger.info '%s is typing in conversation %s', username, conversationId
        else
          logger.info '%s has stop typing in conversation %s', username, conversationId

        chatService.typing io, socket, conversationId, username, participants, isTyping, logError


module.exports = ScalableChatSocket
