fibrous = require 'fibrous'
rsa = require 'node-rsa'
logger = require('log4js').getLogger('encryption')

class EncryptManager

  constructor: (@ModelFactory)->
    @Customer = @ModelFactory.models.customer
    @_public_keys = {}

  getPublicKey: fibrous (customerId)->
    return @_public_keys[customerId] if @_public_keys[customerId]

    customer = @Customer.sync.findById customerId
    return unless customer

    return @_public_keys[customerId] = customer.PublicKey

  encryptByPublicKey: fibrous (customerId, text)->
    keyStr = @sync.getPublicKey customerId

    key = new rsa keyStr
    key.encrypt text, 'base64'

  descryptByPrivateKey: (privateKey, encrypted)->
    key = new rsa privateKey
    try
      key.decrypt encrypted, 'utf8'
    catch ex
      logger.error 'invalid private key', ex
      return 'UNABLE TO DECRYPT'

module.exports = EncryptManager