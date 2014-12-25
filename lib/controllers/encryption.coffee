fibrous = require 'fibrous'
rsa = require 'node-rsa'
ursa = require 'ursa'
logger = require('log4js').getLogger('encryption')

class EncryptManager

  constructor: (server, @ModelFactory)->
    @Customer = @ModelFactory.models.customer
    @_public_keys = {}

    server.on 'user signed in', ({username}) =>
      delete @_public_keys[username]

  getPublicKey: (customerId)->
    return @_public_keys[customerId] if @_public_keys[customerId]

    customer = @Customer.sync.findById customerId
    return unless customer

    return @_public_keys[customerId] = ursa.createPublicKey customer.PublicKey

  encryptByPublicKey: fibrous (customerId, text)->
    try
      key = @getPublicKey customerId
      chunks = text.match /(.{1,16})/g
      encryptedChunks = chunks.map (chunk)->
        key.encrypt chunk, 'utf8', 'base64'

      return encryptedChunks.join ','
    catch ex
      logger.error 'invalid public key', ex
      return 'UNABLE TO ENCRYPT'

  descryptByPrivateKey: (privateKey, encrypted)->
    try
      throw new Error 'empty private key' unless privateKey
      key = ursa.createPrivateKey privateKey
      encryptedChunks = encrypted.split ','
      chunks = encryptedChunks.map (chunk)->
        key.decrypt chunk, 'base64', 'utf8'
      return chunks.join ''
    catch ex
      logger.error 'invalid private key', ex
      return 'UNABLE TO DECRYPT'

module.exports = EncryptManager