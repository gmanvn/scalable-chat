SocketServer = require 'socket.io'
RedisAdapter = require 'socket.io-redis'
fibrous = require 'fibrous'
#############
log4js = require 'log4js'
logger = log4js.getLogger('socket');
#############
ChatService = require './controllers/chat'

## helpers
autoSpread = (fn, context = this)->
  return (first)->
    args = arguments
    args = first if args.length is 1 and Array.isArray first


    fn.apply context, args

logError = (err)-> logger.warn err if err


class ScalableChatSocket

  constructor: (@scalableChatServer, config) ->
    @app = scalableChatServer.app
    @ModelFactory = scalableChatServer.models

    ## init service
    @chatService = new ChatService scalableChatServer, @ModelFactory, config



  start: (redisPubClient, redisSubClient, key) ->
    httpServer = @scalableChatServer.httpServer
    throw new Error 'http is not started' unless httpServer
    io = new SocketServer httpServer

    io.adapter RedisAdapter {
      key
      pubClient: redisPubClient
      subClient: redisSubClient
    }


    @scalableChatServer.on 'kick', ({socketId})->
      local = namespace.sockets.connected[socketId]
      if local
        local.disconnect()


    Conversation = @ModelFactory.models.conversation

    chatService = @chatService


    io.sockets.on 'connection', (socket)->
      socket.conversations = {}
      ip = socket.handshake.headers['x-forwarded-for'] or socket.handshake.address
      query = socket.handshake.query or {}

      #logger.debug 'query', query

      logger.trace 'user [%s] signed in on ip: %s', query.username, ip
      chatService.newSocket io, socket, query.username, query.token, query.privatekey, query.deviceid, logError

      ## forcefully close socket if it hasn't signed in after 10s
      setTimeout ->
        socket.disconnect() unless chatService.isSignedIn(socket)
      , 10000

      socket.on 'disconnect', ->
        logger.info '%s disconnected', socket.username or 'an unsigned in user'
        io.emit 'user leave'

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

      socket.on 'incoming message received', autoSpread (conversationId, message) ->
        logger.info 'marking message %s in conversation %s as delivered', message.body, conversationId

        chatService.markDelivered io, socket, conversationId, message, (err)->
          if err
            logger.warn "Error while attempt to mark message %s as delivered", message?.bold, err

      socket.on 'start typing', autoSpread (conversationId, username, participants, isTyping = true)->
        if isTyping
          logger.info '%s is typing in conversation %s', username, conversationId
        else
          logger.info '%s has stop typing in conversation %s', username, conversationId

        chatService.typing io, socket, conversationId, username, participants, isTyping, logError


module.exports = ScalableChatSocket
