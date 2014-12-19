fibrous = require 'fibrous'

module.exports = ({users, connect})->

  it 'should get undelivered messages on signing in', (done) ->
    ## user0's device connecting to server
    client0 = connect()

    ## sign in as user0
    client0.emit('user signed in', users[0]._id)

    client0.on 'undelivered message', (conversation, messages)->
      messages.length.should.equal 1
      messages[0].should.equal "fp:user1:0002"

      client0.disconnect()
      done()


  it 'should get incoming messages on signing in', (done)->
    ## user1's device connecting to server
    client1 = connect()

    ## sign in as user1
    client1.emit 'user signed in', users[1]._id

    client1.on 'incoming message', (conversation, messages)->
      messages.length.should.equal 1
      messages[0].client_fingerprint.should.equal "fp:user1:0002"
      messages[0].body.should.equal 'you will see this later'

      client1.disconnect()
      done()