fibrous = require 'fibrous'
should = require 'should'
logger = require('log4js').getLogger('CHAT')
_ = require 'lodash'
Encryption = require './encryption'

logError = (err)-> logger.warn err if err

## maximum time amount for receiver to mark messages as delivery
## after this timeout, message will be stored in mongo
DELIVERY_TIMEOUT = 500

module.exports = class ChatService

  constructor: (@ModelFactory) ->
    @encryption = new Encryption @ModelFactory

  newSocket: fibrous (socket, username, token, privateKey)->
    return socket.disconnect() unless 'string' is typeof username
    return socket.disconnect() unless token?.length

    auth = @ModelFactory.models.authentication_token.sync.findOne {
      CustomerId: username
      AuthenticationKey: token
    }

    unless auth
      logger.warn 'invalid user/token: %s %s',username.bold.cyan, token.bold.cyan
      return socket.disconnect()

    ## preload public key of this user for encryption
    socket.publicKey = @ModelFactory.models.customer.sync.findById(username)?.PublicKey

    unless socket.publicKey
      logger.warn '%s has no public key', username.bold.cyan

    logger.debug '%s signed in with token=%s', username.bold.cyan, token.bold.cyan
    socket.username = username
    socket.join "user-#{ username }"
    socket.privateKey = privateKey

    #TODO: test private/public matching

    @pushNotification socket, username, privateKey, logError

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


  directMessage: fibrous (io, socket, from, to, message)->
    unless from and to
      throw new Error 'Lacking from or to'

    Conversation = @ModelFactory.models.conversation

    ## find the conversation between these 2
    conversation = Conversation.sync.findOne {
      participants:
        $all: [from, to]
    }

    ## check if conversation is read-only
    if conversation and conversation.readOnly
      throw new {
      code: 'READONLY'
      name: 'MSG_NOT_SENT'
      message: 'This conversation is read-only'
      }

    ## create a new one and save if no conversation found (they haven't chatted)
    unless conversation
      conversation = new Conversation {
        participants: [from, to]
      }

      conversation.sync.save()

    ## now, participants are allow to send message to each other
    message.sender = from
    message._id = @ModelFactory.objectId()

    socket.emit "outgoing message sent", conversation._id, message.client_fingerprint

    roomName ="user-#{ to }"
    room = io.sockets.adapter.rooms[roomName]
    isOtherOnline = room? and !!Object.keys(room).length

    encrypt = (text) =>
      @encryption.sync.encryptByPublicKey to, text

    storeAndResend = fibrous ->
      try
        logger.debug 'encrypting message'
        enc = _.clone message
        enc.body = encrypt message.body

        logger.debug 'about to store msg', enc
        conversation.sync.pushMessage enc
        io.to(roomName).emit('incoming message', conversation._id, message)
      catch err
        logger.error "Cannot save message %s in conversation %s", message._id, conversation._id, err


    unless isOtherOnline
      storeAndResend.sync()
      return

    ## we will signal immediately to the destination about this message
    io.to("user-#{ to }").emit('incoming message', conversation._id, message)

    ## wait for a little then store to db and resend
    ## (resend to make sure receiver can get it without signing in again)
    ## setTimeout storeAndResend.sync, DELIVERY_TIMEOUT



    return {conversation, message}

  markDelivered: fibrous (io, socket, conversationId, message) ->
    Conversation = @ModelFactory.models.conversation
    conv = Conversation.sync.findById conversationId

    return unless conv

    conv.markDelivered message._id, ->

    io.to("user-#{ message.sender }").emit('outgoing message delivered', conversationId, message.client_fingerprint)

  typing: fibrous (io, socket, conversationId, username, participants, isTyping)->

    participants.forEach (other)->
      io.to("user-#{ other }").emit('other is typing', conversationId, username, isTyping)
