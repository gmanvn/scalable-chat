fibrous = require 'fibrous'
logger = require('log4js').getLogger('M/conversation')

module.exports = (connection) ->
  messageSchema = connection.Schema {

    sender:
      type: String
      required: true

    client_fingerprint: String

    body:
      type: String
      required: true

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
      $inc: undelivered_count: 1
      $push: history: message

  schema.methods.markDelivered = fibrous (messageId)->

    Conversation.sync.findOneAndUpdate {
      _id: @_id
      'history._id': connection.Types.ObjectId messageId
    }, {
      'history.$.delivered': true
      'history.$.delivery_timestamp': Date.now()
      $inc: undelivered_count: -1
    }


  Conversation = connection.model 'conversation', schema