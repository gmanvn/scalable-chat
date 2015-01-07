fibrous = require 'fibrous'
should = require 'should'
logger = require('log4js').getLogger('CHAT')
_ = require 'lodash'
Encryption = require './encryption'
Notification = require './notification'

logger.setLevel 'DEBUG'

logError = (err)-> logger.warn err if err

## maximum time amount for receiver to mark messages as delivery
## after this timeout, message will be stored in mongo
DELIVERY_TIMEOUT = 3000

delay = (ms, cb)-> setTimeout cb, ms

sleep = (ms) -> delay.sync ms

module.exports = class ChatService

  constructor: (@server, @ModelFactory, config) ->
    @encryption = new Encryption server, ModelFactory
    @notification = new Notification server, config, ModelFactory
    queue = @queue = {}

    server.on 'outgoing message delivered', (message)->
      logger.debug 'message', message._id
      delete queue[message._id]

    commands =
      saveObj: 'hmset'
      addToSet: 'sadd'
      retrieveObj: 'hgetall'
      removeFromSet: 'srem'
      del: 'del'
      retrieveSet: 'smembers'
      getMultipleHash: 'hmget'
      removeFromHash: 'hdel'

    for key,value of commands
      ((key, value) =>
        @[key] = (redisKey, params...) ->
          server.redisData[value] [server.env, redisKey].join('$'), params...
      )(key, value)

  kick: (namespace, socketId) ->
    local = namespace.sockets.connected[socketId]
    if local
      local.disconnect()
    else
      logger.info 'kick socket from other process', socketId
      @server.emit 'kick', {socketId}

  newSocket: fibrous (io, socket, username, token, privateKey, deviceId)->
    try
      logger.debug 'username, token, privateKey[0..20], deviceId', username, token, privateKey?[0..20], deviceId
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

      ## check duplicated connection
      roomName = "user-#{ username }"
      room = io.sockets.adapter.rooms[roomName]
      hasOtherConnection = room? and !!Object.keys(room).length

      logger.debug 'room', room
      if hasOtherConnection
        others = Object.keys(room)
        @kick io, other for other in others


      socket.username = username
      socket.join roomName
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
    catch ex
      logger.warn 'sign in exception', ex

  isSignedIn: (socket)->
    'string' is typeof socket.username

  pushNotification: fibrous (socket, username)->
    console.time 'query redis'
    futures = [
      @retrieveSet.future "undelivered:#{ username }"
      @retrieveSet.future "conversations:#{ username }"
    ]

    ###incoming = @retrieveSet.sync "incoming:#{ username }"

    console.timeEnd 'query redis'

    #logger.debug '[incoming, undelivered]', [incoming, undelivered]

    if incoming?.length
      ## going to get all messages
      array = @getMultipleHash.sync 'messages', incoming...

      #logger.debug 'array', array

      ## we need to parse because messages are stored as JSON strings
      array = array.map (json)->
        try
          m = JSON.parse json

          ## JSON doesn't support datetime so we store it as timestamp
          ## device expect datetime so we parse it here
          m.sent_timestamp = new Date m.sent_timestamp
          return m


      ## now we have an array of all messages,
      ## we need to group them by sender before sending back to client
      conversations = _.groupBy array, (m)-> m.conversation

      logger.debug 'conversations', conversations

      logger.info 'messages leaving server'
      console.time 'emit'
      for conv,messages of conversations
        socket.emit 'incoming message', conv, _.sortBy messages, 'sent_timestamp'

      console.timeEnd 'emit'###


    ## undelivered report
    [undelivered, allConversations] = fibrous.wait futures

    if undelivered?.length
      ## undelivered is already an array of [conversation::fingerprint]
      ## we need to split them and group the result by conversation

      array = undelivered.map (value) -> value.split '::'
      conversations = _.groupBy array, (pair)-> pair[0]
    else
      conversations = {}

    ## conversations is a hash of
    ## key: conversation id
    ## value: [conversation id, message fingerprint]

    ## we need to add empty conversations here
    ## empty conversations are conversations that have all msg delivered
    conversations[convId] = [] for convId in allConversations when !conversations[convId]

    logger.debug 'UNDELIVERED conversations', conversations

    for conv,messages of conversations
      socket.emit 'undelivered message', conv, messages.map (pair)-> pair[1]



  directMessage: fibrous (io, socket, sender, receiver, message)->
    unless sender and receiver
      throw new Error 'Lacking from or to'

    ## helper functions
    push = =>
      @notification.queue receiver

    ## find the conversation between these 2
    participants = if sender > receiver then [receiver, sender] else [sender, receiver]
    convId = participants.join '..'

    ## add server-specific information
    message.sender = sender
    message.sent_timestamp = new Date
    message._id = @ModelFactory.objectId()

    ## response to client
    socket.emit "outgoing message sent", convId, message.client_fingerprint

    ## socket.io: find destination
    roomName = "user-#{ receiver }"
    room = io.sockets.adapter.rooms[roomName]
    isOtherOnline = room? and !!Object.keys(room).length

    ## add message to queue
    ## right now we don't need this
    # @queue[message._id] = message

    ## we will signal immediately to the destination about this message
    io.to("user-#{ receiver }").emit('incoming message', convId, message)


    ## we will store message in a hash
    ## hash name: messages
    ## key: message _id
    ## value: message in JSON
    ## why? it's much faster to retrieve multiple json value using hmget
    ## why not mget? http://redis.io/topics/memory-optimization

    messageToStore = {
      _id: message._id
      sender: sender
      receiver: receiver
      body: message.body
      client_fingerprint: message.client_fingerprint
      sent_timestamp: Date.now()
      conversation: convId
    }

    data = {}
    data[message._id] = JSON.stringify messageToStore

    ## parallel
    futures = [
      @saveObj.future "messages", data
      @addToSet.future "incoming:#{ receiver }", message._id
      @addToSet.future "undelivered:#{ sender }", [convId, message.client_fingerprint].join '::'
      ## it's here to know that which conversation is completely delivered
      @addToSet.future "conversations:#{ sender }", convId
    ]

    fibrous.wait futures
    logger.trace "saved. pushing"
    push()




  markDelivered: (io, socket, conversationId, message) ->
    io.to("user-#{ message.sender }").emit('outgoing message delivered', conversationId, message.client_fingerprint)

    ## try to remove message in queue if it's on a same server
    ## broadcast removal request otherwise
    unless delete @queue[message._id]
      @server.emit 'outgoing message delivered', {_id: message._id}

    futures = [
      @removeFromHash.future "messages", message._id
      @removeFromSet.future "incoming:#{ socket.username }", message._id
      @removeFromSet.future "undelivered:#{ message.sender }", [conversationId, message.client_fingerprint].join '::'
    ]

  typing: fibrous (io, socket, conversationId, username, participants, isTyping)->
    participants.forEach (other)->
      io.to("user-#{ other }").emit('other is typing', conversationId, username, isTyping)
