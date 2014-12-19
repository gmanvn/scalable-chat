fibrous = require 'fibrous'
logger = require('log4js').getLogger('M/customer')

module.exports = (connection) ->

  schema = connection.Schema {
    PublicKey: String
  }

  connection.model 'customer', schema, 'Customer'