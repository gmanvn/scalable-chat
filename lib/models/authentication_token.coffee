fibrous = require 'fibrous'
logger = require('log4js').getLogger('M/authToken')

module.exports = (connection) ->

  schema = connection.Schema {
    CustomerId: String
    AuthenticationKey: String
  }

  connection.model 'authToken', schema, 'AuthenticationToken'