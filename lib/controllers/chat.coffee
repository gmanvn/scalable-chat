fibrous = require 'fibrous'
should = require 'should'
logger = require('log4js').getLogger('CHAT')
Table = require 'cli-table'
_ = require 'lodash'
Encryption = require './encryption'
Notification = require './notification'

logger.setLevel 'DEBUG'

logError = (err)-> logger.warn err if err

## maximum time amount for receiver to mark messages as delivery
## after this timeout, message will be stored in mongo
DELIVERY_TIMEOUT = 3000

## all of commands sequences from client
COMMANDS = [
  "\u200B" ## block
  "\u202F" ## unblock
]

delay = (ms, cb)-> setTimeout cb, ms

sleep = (ms) -> delay.sync ms

timeStart = ()->
  start = Date.now()

  return (level, message, params...)->
    end = Date.now()
    duration = end - start
    str = String(duration + 'ms').bold

    color =
      switch
        when duration > 0   then 'green'
        when duration > 30  then 'yellow'
        when duration > 200 then 'red'


    str = str[color]
    params.push str


    message += ': %s'
    logger[level] message, params...

module.exports = class ChatService

  constructor: (@server, @ModelFactory, config) ->
    @encryption = new Encryption server, ModelFactory
    @notification = new Notification server, config, ModelFactory
    queue = @queue = {}

    server.on 'outgoing message delivered', (message)->
      logger.debug '%s ->\t message', socket.username, message._id
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
      increaseInHash: 'hincrby'

    for key,value of commands
      ((key, value) =>
        @[key] = (redisKey, params...) ->
          server.redisData[value] [server.env, redisKey].join('$'), params...)(key, value)

  kick: (namespace, socketId) ->
    local = namespace.sockets.connected[socketId]
    if local
      local.disconnect()
    else
      logger.info '%s ->\t kick socket from other process', socket.username, socketId
      @server.emit 'kick', {socketId}

  newSocket: fibrous (io, socket, username, token, privateKey, deviceId)->
    try

      logger.debug 'username, token, privateKey[0..20], deviceId', username, token, privateKey?[0..20], deviceId
      unless 'string' is typeof username
        return socket.disconnect()

      return socket.disconnect() unless token?.length

      logger.debug '%s ->\t %s started', username.bold.cyan, 'SIGN IN'.bold.underline

      logger.debug '%s ->\t  ├──── checking authentication...', username.bold.cyan

      auth = @ModelFactory.models.authentication_token.sync.findOne {
        CustomerId: username
        AuthenticationKey: token
      }

      if auth
        logger.debug '%s ->\t  ├──── %s authenticated', username.bold.cyan, 'OK'.bold.green
      else
        logger.warn ' %s ->\t  ├──── %s %s: %s', username.bold.cyan, 'NOT OK'.bold.red, 'invalid token'.bold, token.bold.cyan
        return socket.disconnect()


      ## preload public key of this user for encryption
      # socket.publicKey = @ModelFactory.models.customer.sync.findById(username)?.PublicKey
      #
      # unless socket.publicKey
      #  logger.warn '%s ->\t has no public key', username.bold.cyan

      ## check duplicated connection
      logger.debug '%s ->\t  ├──── checking duplicated connection...', username.bold.cyan
      roomName = "user-#{ username }"
      room = io.sockets.adapter.rooms[roomName]
      hasOtherConnection = room? and !!Object.keys(room).length

      if hasOtherConnection
        logger.debug '%s ->\t  ├──── %s existing connections', username.bold.cyan, 'NOT OK'.bold.red, room
        others = Object.keys(room)
        @kick io, other for other in others
      else
        logger.debug '%s ->\t  ├──── %s no duplicated connections', username.bold.cyan, 'OK'.bold.green


      socket.username = username
      socket.join roomName
      #socket.privateKey = privateKey


      @server.emit 'user signed in', {username}
      logger.debug '%s ->\t  ├──── SOCKET >> "%s"', username.bold.cyan, 'user signed in'.blue


      ## device id
      deviceId = false if typeof deviceId is 'string' and deviceId is 'false'


      futures = [
        @future.pushNotification socket, username, privateKey
        @future.updateDeviceToken deviceId, username
      ]

      fibrous.wait futures
      @setForeground io, socket, true


    catch ex
      logger.warn '%s ->\t sign in exception', username, ex
    finally
      logger.debug '%s ->\t  └──── Done signing in', username.bold.cyan
      logger.debug '%s ->', username.bold.cyan

  setForeground: (io, socket, onForeground) ->
    obj = {}
    obj[socket.username] = !!onForeground

    logger.debug '%s ->\t set foreground %s', socket.username.bold.cyan, onForeground, obj

    fibrous.run =>
      @saveObj 'online', obj

  isSignedIn: (socket)->
    'string' is typeof socket.username

  updateDeviceToken: fibrous (deviceId, username)->
    unless deviceId
      logger.debug '%s ->\t  ├──── no device token. skip updating!', username.bold.cyan
      return

    logger.debug '%s ->\t  ├──── updating device token... (%s)', username.bold.cyan, deviceId.bold


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

  pushNotification: fibrous (socket, username)->
    logger.debug '%s ->\t  ├──── %s', username.bold.cyan, 'BROADCAST OFFLINE DETAIL'.bold.underline
    futures = [
      @retrieveSet.future "undelivered:#{ username }"
      @retrieveSet.future "conversations:#{ username }"
    ]

### skip sending incoming messages
    end = timeStart()

    incoming = @retrieveSet.sync "incoming:#{ username }"

    end 'debug', '%s ->\t  │      ├──── query redis', username.bold.cyan

    if incoming?.length
      ## going to get all messages
      array = @getMultipleHash.sync 'messages', incoming...

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

      logger.debug '%s ->\t  │      ├──── INCOMING', username.bold.cyan, conversations

      logger.info ' %s ->\t  │      ├──── messages leaving server', username.bold.cyan
      console.time 'emit'
      for conv,messages of conversations
        socket.emit 'incoming message', conv, _.sortBy messages, 'sent_timestamp'

      console.timeEnd 'emit'
    else
      logger.debug '%s ->\t  │      ├──── INCOMING: empty', username.bold.cyan

###

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

    logger.debug '%s ->\t  │      ├──── UNDELIVERED', username.bold.cyan, conversations

    for conv,messages of conversations
      socket.emit 'undelivered message', conv, messages.map (pair)-> pair[1]

    logger.debug '%s ->\t  │      └──── Done broadcasting offline details', username.bold.cyan


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

    ## if it's not a command, increase the unread count
    futures.push @increaseInHash.future "incoming_count", receiver, 1 unless message.body in COMMANDS


    fibrous.wait futures
    logger.trace "%s ->\t saved. pushing", socket.username.bold.cyan

    ## check real online status
    [online] = @getMultipleHash.sync 'online', receiver


    logger.debug '%s ->\t %s is online=%s', socket.username.bold.cyan, receiver, online

    if online isnt 'true'
      logger.debug '%s -> \t PUSH TO APPLE', socket.username
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

    fibrous.run =>
      results = fibrous.wait futures
      if results[1] and message.body not in COMMANDS
        ## if it's not a command, increase the unread count
        @increaseInHash.sync "incoming_count", socket.username, -1


  typing: fibrous (io, socket, conversationId, username, participants, isTyping)->
    participants.forEach (other)->
      io.to("user-#{ other }").emit('other is typing', conversationId, username, isTyping)

  destroy: (io, socket)->
    @setForeground io, socket, false