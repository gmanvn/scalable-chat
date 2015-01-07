fibrous = require 'fibrous'

module.exports = (params)->

  users = params.users
  connect = params.connect

  it 'should send direct message from one user to another', (done)->
    ## cache user_id for user2, 3
    user2 = users[2]._id
    user3 = users[3]._id

    ## establish conenctions for user2 and user3 devices
    sender = connect {
      username: user2
      token: 'key:' + user2
      privatekey:  users[2]._private_key
      deviceid: '00000'
    }
    receiver = connect {
      username: user3
      token: 'key:' + user3
      privatekey:  users[3]._private_key
      deviceid: '00000'
    }
    conversation = ''

    message =
      sender: String user2
      body: 'hello from user2'
      client_fingerprint: 'fg:user2:0001'


    receiver.on 'incoming message', (_conversation, incomingMessage) ->
      return if incomingMessage.length is 0

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

      done()


    ## wait 300ms for both client connected
    setTimeout ->
      ## actually send
      sender.emit 'outgoing message', message, user3
    , 100

  it 'should not store message if receiver is online', (done)->
    ## cache user_id for user2, 3
    user2 = users[2]._id
    user3 = users[3]._id

    ## establish conenctions for user2 and user3 devices
    sender = connect {
      username: user2
      token: 'key:' + user2
      privatekey:  users[2]._private_key
      deviceid: '00000'
    }
    receiver = null

    conversation = ''

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
      receiver = connect {
        username: user3
        token: 'key:' + user3
        privatekey:  users[3]._private_key
        deviceid: '00000'
      }

      receiver.on 'incoming message', (_conversation, incomingMessages) ->
        conversation.should.equal _conversation
        incomingMessages = [incomingMessages] unless incomingMessages.length

        incomingMessage = incomingMessages[0]
        ## should be object
        #      console.log 'incomingMessage', incomingMessage

        incomingMessage.should.not.be.a.string

        incomingMessage.sender.should.equal String user2
        incomingMessage.body.should.equal 'are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? are you there? '
        incomingMessage.client_fingerprint.should.equal 'fg:user2:0002'

        ## reply
        receiver.emit 'incoming message received', conversation, incomingMessage
        done()
    , 300
