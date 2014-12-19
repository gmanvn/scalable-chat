fibrous = require 'fibrous'

module.exports = ({users, connect})->
  user0 = ''
  user1 = ''

  before ->
    user0 = users[0]._id
    user1 = users[1]._id

  it 'should get undelivered messages on signing in', (done) ->
    ## user0's device connecting to server
    client0 = connect()

    ## sign in as user0
    console.log 'user0', user0
    client0.emit 'user signed in', user0, 'key:' + user0

    client0.on 'undelivered message', (conversation, messages)->
      messages.length.should.equal 1
      messages[0].should.equal "fp:user1:0002"

      client0.disconnect()
      done()


  it 'should get incoming messages on signing in', (done)->
    ## user1's device connecting to server
    client1 = connect()

    ## sign in as user1
    client1.emit 'user signed in', user1, 'key:' + user1

    client1.on 'incoming message', (conversation, messages)->
      messages.length.should.equal 1
      messages[0].client_fingerprint.should.equal "fp:user1:0002"
      messages[0].body.should.equal 'you will see this later'

      client1.disconnect()
      done()


  it 'should not allow invalid user/token pair to receive incoming messages', (done)->
    ## user1's device connecting to server
    client1 = connect()

    ## sign in as user1
    client1.emit 'user signed in', user1, 'fake_key:' + user1

    client1.on 'incoming message', (conversation, messages)->
      throw new Error 'Should not be here'

    client1.on 'disconnect', ->
      console.log 'dis', arguments...
      done()

  it 'should not allow invalid user/token pair to receive undelivered messages', (done)->
    ## user1's device connecting to server
    client1 = connect()

    ## sign in as user1
    client1.emit 'user signed in', user0, 'fake_key:' + user0

    client1.on 'undelivered message', (conversation, messages)->
      throw new Error 'Should not be here'

    client1.on 'disconnect', ->
      console.log 'dis', arguments...
      done()