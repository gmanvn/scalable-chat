fibrous = require 'fibrous'
should = require 'should'
logger = require('log4js').getLogger('CHAT')

module.exports = class ChatService

  constructor: (@ModelFactory) ->

  newSocket: (socket, username)->
    socket.username = username
    socket.join "user-#{ username }"

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
    message._id = @ModelFactory.objectId()
    message.sender = from
    conversation.history.push message

    ## async, no need to wait
    conversation.save (err)->
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
    message.delivery_timestamp = Date.now()
    message.delivered = true
    conv.save()

    io.to("user-#{ message.sender }").emit('outgoing message delivered', conversationId, message.client_fingerprint)