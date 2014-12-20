fibrous = require 'fibrous'
should = require('should')
io = require('socket.io-client')
config = require 'config'

URL = 'http://0.0.0.0:3000'
options =
  transports: ['websocket'],
  'force new connection': true

connect = ->
  io.connect URL, options

users = [
  '5492509f94c6a10f00228402'
  '5492584b94c6a10f0022853a'
  '54925eb894c6a10f00229262'
  '549275c894c6a10f00229474'
]

params = {
  users
  connect
}


Server = require '../lib/server'
server = new Server config


## init test data
rsa = require 'node-rsa'
{keys} = require './keypairs'
###------------##
  Customer
##------------###

before fibrous ->
  params.Customer = Customer = server.models.models.customer
  AuthToken = server.models.models.authentication_token

  ## remove data
  Customer.sync.remove({})

  for userId, index in users
    customer = new Customer {_id: userId}
    customer.PublicKey = keys[index].public
    customer.sync.save()

    ## private properties (for testing purpose only)
    customer._conversations = {}
    customer._private_key = keys[index].private
    users[index] = customer

    ## set auth token
    auth = new AuthToken {
      CustomerId: customer._id
      AuthenticationKey: 'key:'+customer._id
    }
    auth.sync.save()


###------------##
  Conversation
##------------###
before fibrous ->

  ## const
  user0 = users[0]._id
  user1 = users[1]._id

  now = Date.now()
  HOUR = 60 * 60 * 1000
  yesterday = now - 24 * HOUR

  params.Conversation = Conversation = server.models.models.conversation

  ## reset data
  Conversation.sync.remove()

  ## helper
  makeMessage = (sender, body, client_fingerprint, sent_timestamp = Date.now(), delivered = false)->
    msg = {sender, body, sent_timestamp, client_fingerprint}
    if delivered
      msg.delivered = true
      msg.delivery_timestamp = delivered

    return msg


  ## create new convesations
  conv0_1 = new Conversation {
    participants: [user0, user1]
    history: [
      makeMessage user0, "hello from u0", "fp:user1:0001", yesterday, yesterday + HOUR
      makeMessage user1, "hi there, i'm u1", "fp:user2:0001", yesterday + 2 * HOUR, yesterday + 2 * HOUR
      makeMessage user0, "you will see this later", "fp:user1:0002", yesterday + 3 * HOUR
    ]
    undelivered_count: 1
  }

  conv0_1.sync.save()

  users[0]._conversations[user1] = conv0_1
  users[1]._conversations[user0] = conv0_1

before fibrous ->
  server.start 'test', 3000

describe "user sign in", -> require('./signin')(params)
describe "direct message", -> require('./direct-message')(params)
