module.exports = (connection) ->
  schema = connection.Schema {

    ## user-id of participants
    participants: [String]
  }

  connection.model 'conversation', schema