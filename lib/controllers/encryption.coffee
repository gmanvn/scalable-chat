fibrous = require 'fibrous'
rsa = require 'node-rsa'
logger = require('log4js').getLogger('encryption')

class EncryptManager

  constructor: (@ModelFactory)->
    @Customer = @ModelFactory.models.customer
    @_public_keys = {}

  getPublicKey: (customerId)->
    return @_public_keys[customerId] if @_public_keys[customerId]

    customer = @Customer.sync.findById customerId
    return unless customer

    return @_public_keys[customerId] = customer.PublicKey

  encryptByPublicKey: fibrous (customerId, text)->
    try
      keyStr = @getPublicKey customerId

      key = new rsa keyStr, 'public'
      key.encrypt text, 'base64'
    catch ex
      logger.error 'invalid public key', ex
      return 'UNABLE TO ENCRYPT'

  descryptByPrivateKey: (privateKey, encrypted)->
    logger.debug 'privateKey', privateKey
    try
      key = new rsa privateKey, 'private'
      key.decrypt encrypted, 'utf8'
    catch ex
      logger.error 'invalid private key', ex
      return 'UNABLE TO DECRYPT'

module.exports = EncryptManager