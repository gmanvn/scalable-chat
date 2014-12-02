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
  }


  connection.model 'conversation', schema