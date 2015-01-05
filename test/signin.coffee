fibrous = require 'fibrous'

module.exports = ({users, connect})->
  user0 = ''
  user1 = ''

  before ->
    user0 = users[0]._id
    user1 = users[1]._id

  it 'should get undelivered messages on signing in', (done) ->
    ## sign in as user0
    console.log 'user0', user0

    ## user0's device connecting to server
    client0 = connect {
      username: user0
      token: 'key:' + user0
      privatekey:  users[0]._private_key
      deviceid: '00000'
    }

    client0.on 'undelivered message', (conversation, messages)->
      messages.length.should.equal 1
      messages[0].should.equal "fp:user1:0002"

      client0.disconnect()
      done()


  it 'should get incoming messages on signing in', (done)->
    ## user1's device connecting to server
    client1 = connect {
      username: user1
      token: 'key:' + user1
      privatekey:  users[1]._private_key
      deviceid: '00000'
    }

    client1.on 'incoming message', (conversation, messages)->
      messages.length.should.equal 1
      messages[0].client_fingerprint.should.equal "fp:user1:0002"
      messages[0].body.should.equal 'you will see this later'

      client1.disconnect()
      done()


  it 'should not allow invalid user/token pair to receive incoming messages', (done)->
    ## user1's device connecting to server
    client1 = connect {
      username: user1
      token: 'fake'
      privatekey:  users[1]._private_key
      deviceid: '00000'
    }

    client1.on 'incoming message', (conversation, messages)->
      throw new Error 'Should not be here'

    client1.on 'disconnect', ->
      console.log 'dis', arguments...
      done()

  it 'should not allow invalid user/token pair to receive undelivered messages', (done)->
    ## user1's device connecting to server
    client1 = connect {
      username: user0
      token: 'fake'
      privatekey:  users[0]._private_key
      deviceid: '00000'
    }

    client1.on 'undelivered message', (conversation, messages)->
      throw new Error 'Should not be here'

    client1.on 'disconnect', ->
      console.log 'dis', arguments...
      done()

  it.only 'should allow only one connection to a user', (done)->
    client1 = connect {
      username: user0
      token: 'key:' + user0
      deviceid: '00000'
    }

    client2 = connect {
      username: user0
      token: 'key:' + user0
      deviceid: '00000'
    }

    client1.on 'disconnect', ->
      done()


