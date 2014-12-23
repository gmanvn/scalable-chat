fibrous = require 'fibrous'

module.exports = (params)->

  users = params.users
  connect = params.connect

  it 'should send direct message from one user to another', (done)->
    Conversation = params.Conversation

    ## establish conenctions for user2 and user3 devices
    sender = connect()
    receiver = connect()
    conversation = ''

    ## cache user_id for user2, 3
    user2 = users[2]._id
    user3 = users[3]._id

    ## signin respectively
    sender.emit 'user signed in', user2, 'key:' + user2, users[2]._private_key
    receiver.emit 'user signed in', user3, 'key:' + user3, users[3]._private_key

    message =
      sender: String user2
      body: 'hello from user2'
      client_fingerprint: 'fg:user2:0001'


    receiver.on 'incoming message', (_conversation, incomingMessage) ->
      ## cached for testing purpose
      conversation.should.equal _conversation

      incomingMessage.should.not.be.a.string

      incomingMessage.sender.should.equal String user2
      incomingMessage.body.should.equal 'hello from user2'
      incomingMessage.client_fingerprint.should.equal 'fg:user2:0001'

      reply = {
        _id: incomingMessage._id
        sender: incomingMessage.sender
        client_fingerprint: incomingMessage.client_fingerprint
      }

      ## reply
      receiver.emit 'incoming message received', conversation, reply

    sender.on 'outgoing message sent', (_conversation, fingerprint)->
      conversation = _conversation
      fingerprint.should.equal 'fg:user2:0001'

    sender.on 'outgoing message delivered', (_conversation, fingerprint)->
      conversation.should.equal _conversation
      fingerprint.should.equal 'fg:user2:0001'

      sender.disconnect()
      receiver.disconnect()

      fibrous.run ->
        conv = Conversation.sync.findById(_conversation)
        conv.undelivered_count.should.equal 0
        conv.history.length.should.equal 0
        done()


    ## wait 300ms for both client connected
    setTimeout ->
      ## actually send
      sender.emit 'outgoing message', message, user3
    , 100

  it 'should not store message if receiver is online', (done)->
    Conversation = params.Conversation

    ## establish conenctions for user2 and user3 devices
    sender = connect()
    receiver = connect()
    conversation = ''

    ## cache user_id for user2, 3
    user2 = users[2]._id
    user3 = users[3]._id

    ## signin respectively
    sender.emit 'user signed in', user2, 'key:' + user2, users[2]._private_key

    message =
      sender: String user2
      body: 'are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? '
      client_fingerprint: 'fg:user2:0002'

    sender.on 'outgoing message sent', (_conversation, fingerprint)->
      conversation = _conversation
      fingerprint.should.equal 'fg:user2:0002'

    setTimeout ->
      sender.emit 'outgoing message', message, user3
    , 100

    setTimeout ->
      receiver.emit 'user signed in', user3, 'key:' + user3, users[3]._private_key
    , 300

    receiver.on 'incoming message', (_conversation, incomingMessages) ->
      conversation.should.equal _conversation
      incomingMessages = [incomingMessages] unless incomingMessages.length

      incomingMessage = incomingMessages[0]
      ## should be object
      console.log 'incomingMessage', incomingMessage

      incomingMessage.should.not.be.a.string

      incomingMessage.sender.should.equal String user2
      incomingMessage.body.should.equal 'are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? '
      incomingMessage.client_fingerprint.should.equal 'fg:user2:0002'



      ## reply
      receiver.emit 'incoming message received', conversation, incomingMessage
      done()