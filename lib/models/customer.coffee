fibrous = require 'fibrous'
logger = require('log4js').getLogger('M/customer')

module.exports = (connection) ->

  schema = connection.Schema {
    _id: String
    PublicKey: String
    LastDeviceId: String
    Badge: Number
  }

  connection.model 'customer', schema, 'Customer'