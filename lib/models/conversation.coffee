fibrous = require 'fibrous'
logger = require('log4js').getLogger('M/conversation')

logger.setLevel 'ERROR'

module.exports = (connection) ->
  messageSchema = connection.Schema {

    sender:
      type: String
      required: true

    client_fingerprint: String

    body: String

    content_type:
      type: String
      enum: [
        'plain-text'
        'private-key'
        'public-key'
      ]
      default: 'plain-text'

    delivered:
      type: Boolean
      default: false

    sent_timestamp:
      type: Date
      default: Date.now

    delivery_timestamp:
      type: Date
  }

  schema = connection.Schema {
    _id: String

  ## user-id of participants
    participants: [String]

    readOnly:
      type: Boolean
      default: false

    history: [
      messageSchema
    ]

    undelivered_count:
      type: Number
      default: 0
  }

  ## check if this conversation has undelivered messages to a user
  schema.methods.newMessageFor = (username, after = false)->
    if after
      fn = (msg)->
        msg.delivered is false and msg.sender isnt username and msg.timestamp > after
    else
      fn = (msg)->
        msg.delivered is false and msg.sender isnt username

    @history.filter fn

  schema.methods.pushMessage = fibrous (message)->
    Conversation.sync.findByIdAndUpdate @_id,
      $inc:
        undelivered_count: 1
      $push:
        history: message


    sender = message.sender
    Customer = connection.model 'customer'
    for receiver in @participants when receiver isnt sender
      logger.debug 'increase unread number for %s', receiver.bold
      Customer.sync.findByIdAndUpdate receiver, $inc: Badge: 1


  schema.methods.markDelivered = fibrous (messageId)->
    Conversation.sync.findOneAndUpdate {
      _id: @_id
      'history._id': connection.Types.ObjectId messageId
    }, {
      'history.$.delivered': true
      'history.$.delivery_timestamp': Date.now()
      $inc:
        undelivered_count: -1
    }

  schema.methods.undeliveredOf = (username) ->
    @history.filter (msg)->
      msg.sender is username and not msg.delivered

  Conversation = connection.model 'conversation', schema