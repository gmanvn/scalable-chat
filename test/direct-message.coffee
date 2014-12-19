fibrous = require 'fibrous'

module.exports = ({users, connect, Conversation})->

  it 'should send direct message from one user to another', (done)->
    ## establish conenctions for user2 and user3 devices
    sender = connect()
    receiver = connect()
    conversation = ''

    ## cache user_id for user2, 3
    user2 = users[2]._id
    user3 = users[3]._id

    ## signin respectively
    sender.emit 'user signed in', user2, 'key:' + user2
    receiver.emit 'user signed in', user3, 'key:' + user3

    message =
      sender: String user2
      body: 'hello from user2'
      client_fingerprint: 'fg:user2:0001'


    receiver.on 'incoming message', (_conversation, incomingMessage) ->
      ## cached for testing purpose
      conversation = _conversation

      incomingMessage.should.not.be.a.string

      incomingMessage.sender.should.equal String user2
      incomingMessage.body.should.equal 'hello from user2'
      incomingMessage.client_fingerprint.should.equal 'fg:user2:0001'

      ## reply
      receiver.emit 'incoming message received', conversation, incomingMessage._id

    sender.on 'outgoing message sent', (_conversation, fingerprint)->
      conversation.should.equal _conversation
      fingerprint.should.equal 'fg:user2:0001'

    sender.on 'outgoing message delivered', (_conversation, fingerprint)->
      conversation.should.equal _conversation
      fingerprint.should.equal 'fg:user2:0001'

      sender.disconnect()
      receiver.disconnect()
      done()

    ## actually send
    sender.emit 'outgoing message', message, user3

  it.skip 'should not store message if receiver is online', (done)->
