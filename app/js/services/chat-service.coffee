app = angular.module 'scalable-chat'
app.factory 'socket', (socketFactory)->
  ioSocket = io.connect '/', {transports: ['websocket']}
  socketFactory({ioSocket})

app.service 'chat', ($rootScope, socket, $http, $state, @makeFingerprint)->
  chat = this
  conversations = {}
  @signIn = ->
    username = @getUsername()
    socket.emit 'user signed in', username if username

  @getUsername = ->
    $rootScope.username = localStorage.getItem 'username'


  @setUsername = (username)->
    localStorage.setItem('username', $rootScope.username = username)
    socket.emit('user signed in', username)


  @getList = ->
    ## get a list of online users
    $http.get '/api/users/online'

  @logOut = ->
    socket.emit 'user signed out'
    localStorage.removeItem 'username'
    $rootScope.username = false
    $state.transitionTo('home')

  @startConversation = (other)->
    socket.emit 'conversation started', other


  @signIn()

  socket.on 'online users', (data) =>
    @online = data.online.filter (user)->
      return user != chat.getUsername()

  socket.on 'incoming conversation', (conv) ->
    $state.transitionTo('list.conversation', {id: conv._id})
    handleIncomingConversation conv

  socket.on 'updated conversation', (conv)->
    handleIncomingConversation conv

  handleIncomingConversation = (conv)->
    participants = conv.participants

    ## find the other participant
    others = participants.filter (username)-> username != $rootScope.username
    other = others[0]
    conv.other = other

    conversations[conv._id] = conversations[conv._id] or {}

    angular.extend conversations[conv._id], conv

  @updateConversation = (id) ->
    socket.emit 'request: update conversation', id

  @getConversation = (id)->
    conv = conversations[id]

    unless conv
      conv = conversations[id] = {}

    #@updateConversation id
    return conv

  @directMessage = (body, conversation)->
    return false unless body
    destination = conversation.other
    message = {
      sender: $rootScope.username
      body
      client_fingerprint: @makeFingerprint()
    }

    socket.emit 'outgoing message', message, destination
    message.status = 'sending...'

    conversation.history ?= []
    conversation.history.push message


  socket.on 'outgoing message sent', (conversationId, messageFingerprint)->
    conv = conversations[conversationId]
    for message in conv.history when message.client_fingerprint is messageFingerprint
      message.status = 'sent'
      break


  socket.on 'incoming message', (conversationId, messages) ->
    conv = conversations[conversationId]
    conv.history ?= []
    messages = [messages] unless Array.isArray messages

    messages.forEach (message)->
      conv.history.push message

      ## acknowledge back for delivery status
      socket.emit 'incoming message received',
        conversationId, message._id

  socket.on 'outgoing message delivered', (conversationId, messageFingerprint) ->
    conv = conversations[conversationId]
    for message in conv.history when message.client_fingerprint is messageFingerprint
      message.status = 'delivered'
      break

  return