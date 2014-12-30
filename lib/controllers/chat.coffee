fibrous = require 'fibrous'
should = require 'should'
logger = require('log4js').getLogger('CHAT')
_ = require 'lodash'
Encryption = require './encryption'
Notification = require './notification'

logger.setLevel 'ERROR'

logError = (err)-> logger.warn err if err

## maximum time amount for receiver to mark messages as delivery
## after this timeout, message will be stored in mongo
DELIVERY_TIMEOUT = 500

delay = (ms, cb)-> setTimeout cb, ms

sleep = (ms) -> delay.sync ms

module.exports = class ChatService

  constructor: (@server, @ModelFactory, config) ->
    @encryption = new Encryption server, @ModelFactory
    @notification = new Notification config, @ModelFactory
    queue = @queue = {}

    server.on 'outgoing message delivered', (message)->
      logger.debug 'message', message._id
      delete queue[message._id]



  newSocket: fibrous (io, socket, username, token, privateKey, deviceId)->
    return socket.disconnect() unless 'string' is typeof username
    return socket.disconnect() unless token?.length

    auth = @ModelFactory.models.authentication_token.sync.findOne {
      CustomerId: username
      AuthenticationKey: token
    }

    unless auth
      logger.warn 'invalid user/token: %s %s', username.bold.cyan, token.bold.cyan
      return socket.disconnect()

    ## preload public key of this user for encryption
    socket.publicKey = @ModelFactory.models.customer.sync.findById(username)?.PublicKey

    unless socket.publicKey
      logger.warn '%s has no public key', username.bold.cyan

    logger.debug '%s signed in with token=%s', username.bold.cyan, token.bold.cyan
    socket.username = username
    socket.join "user-#{ username }"
    socket.privateKey = privateKey

    @server.emit 'user signed in', {username}

    #TODO: test private/public matching

    @pushNotification socket, username, privateKey, logError

    ## device id
    return unless deviceId
    @ModelFactory.models
    .customer.sync
    .update {
      LastDeviceId: deviceId
    }, {
      LastDeviceId: null
    }, {
      multi: true
    }

    ## update latest device id and reset unread number to 0
    @ModelFactory.models
    .customer.sync
    .findByIdAndUpdate username, {
      LastDeviceId: deviceId
      Badge: 0
    }

  isSignedIn: (socket)->
    'string' is typeof socket.username

  pushNotification: fibrous (socket, username)->
    Conversation = @ModelFactory.models.conversation

    ## get all conversations that involves this user and has undelivered msg
    unreadConversations = Conversation.sync.find({
      participants: username
#      undelivered_count: $gte: 1
    })

    ## filter out those are only new for the other party and sent undelivered msg to this user
    unreadConversations.forEach (conv) =>
      newMessages = conv.newMessageFor username
      undeliveredMessages = conv.undeliveredOf username

      newMessages = newMessages.map (msg)=>
        msg.body = @encryption.descryptByPrivateKey socket.privateKey, msg.body
        return msg

      undeliveredMessages = undeliveredMessages.map (msg)->
        msg.client_fingerprint

      socket.emit 'incoming message', conv._id, newMessages if newMessages.length
      socket.emit 'undelivered message', conv._id, undeliveredMessages


  directMessage: fibrous (io, socket, sender, receiver, message)->
    unless sender and receiver
      throw new Error 'Lacking from or to'

    Conversation = @ModelFactory.models.conversation

    ## find the conversation between these 2
    participants = if sender > receiver then [receiver, sender] else [sender, receiver]
    convId = participants.join '..'


    #    ## check if conversation is read-only
    #    if conversation and conversation.readOnly
    #      throw new {
    #      code: 'READONLY'
    #      name: 'MSG_NOT_SENT'
    #      message: 'This conversation is read-only'
    #      }

    ## now, participants are allow to send message to each other
    message.sender = sender
    message.sent_timestamp = Date.now()
    message._id = @ModelFactory.objectId()

    socket.emit "outgoing message sent", convId, message.client_fingerprint

    roomName = "user-#{ receiver }"
    room = io.sockets.adapter.rooms[roomName]
    isOtherOnline = room? and !!Object.keys(room).length

    encrypt = (text) =>
      @encryption.sync.encryptByPublicKey receiver, text

    push = =>
      @notification.queue receiver

    storeAndResend = fibrous ->
      try

        logger.debug 'encrypting message'
        message.body = encrypt message.body
        logger.debug 'done encryption'


        ## create a new one and save if no conversation found (they haven't chatted)
        conversation = Conversation.sync.findOneAndUpdate {
          _id: convId
        }, {
          $setOnInsert:
            #_id: convId
            participants: [sender, receiver]
        }, {
          new: true
          upsert: true
        }


        io.to(roomName).emit('incoming message', convId, message)
        logger.debug 'about to store msg', message._id
        conversation.sync.pushMessage message

        ## queue the push
        push()

      catch err
        logger.error "Cannot save message %s in conversation %s", message._id, convId, err


    unless isOtherOnline
      storeAndResend ->
      return


    ## add message to queue
    @queue[message._id] = message

    ## we will signal immediately to the destination about this message
    io.to("user-#{ receiver }").emit('incoming message', convId, message)

    ## 1st retry
    sleep DELIVERY_TIMEOUT
    return unless @queue[message._id]
    io.to("user-#{ receiver }").emit('incoming message', convId, message)

    ## 2nd retry
    sleep DELIVERY_TIMEOUT
    return unless @queue[message._id]
    io.to("user-#{ receiver }").emit('incoming message', convId, message)

    ## save to db
    return unless @queue[message._id]
    setTimeout ->
      storeAndResend ->
    , 1

  markDelivered: (io, socket, conversationId, message, cb) ->
    io.to("user-#{ message.sender }").emit('outgoing message delivered', conversationId, message.client_fingerprint)

    ## try to remove message in queue if it's on a same server
    ## broadcast removal request otherwise
    unless delete @queue[message._id]
      @server.emit 'outgoing message delivered', {_id: message._id}

    Conversation = @ModelFactory.models.conversation
    Conversation.findById conversationId, (err, conv)->
      logError(err)

      if conv
        conv.markDelivered message._id, cb

  typing: fibrous (io, socket, conversationId, username, participants, isTyping)->
    participants.forEach (other)->
      io.to("user-#{ other }").emit('other is typing', conversationId, username, isTyping)
