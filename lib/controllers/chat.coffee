fibrous = require 'fibrous'
should = require 'should'
logger = require('log4js').getLogger('CHAT')

logError = (err)-> logger.warn err if err

module.exports = class ChatService

  constructor: (@ModelFactory) ->

  newSocket: fibrous (socket, username, token)->
    return socket.disconnect() unless 'string' is typeof username
    return socket.disconnect() unless token?.length
    logger.debug '%s signed in with token=%s', username.bold.cyan, token.bold.cyan

    auth = @ModelFactory.models.authentication_token.sync.findOne {
      CustomerId: username
      AuthenticationKey: token
    }

    return socket.disconnect() unless auth

    socket.username = username
    socket.join "user-#{ username }"



    @pushNotification socket, username, logError

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
    unreadConversations.forEach (conv)->
      newMessages = conv.newMessageFor username
      undeliveredMessages = conv.undeliveredOf username

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

    ## async, no need to wait
    conversation.pushMessage message, (err)->
      if err
        logger.error "Cannot save message %s in conversation %s", message._id, conversation._id
        return

      socket.emit "outgoing message sent", conversation._id, message.client_fingerprint

    ## we will signal immediately to the destination about this message
    io.to("user-#{ to }").emit('incoming message', conversation._id, message)

  markDelivered: fibrous (io, socket, conversationId, messageId) ->
    Conversation = @ModelFactory.models.conversation
    conv = Conversation.sync.findById conversationId

    return unless conv
    message = conv.history.id messageId
    conv.markDelivered messageId, ->

    io.to("user-#{ message.sender }").emit('outgoing message delivered', conversationId, message.client_fingerprint)

  typing: fibrous (io, socket, conversationId, username, participants, isTyping)->

    participants.forEach (other)->
      io.to("user-#{ other }").emit('other is typing', conversationId, username, isTyping)
