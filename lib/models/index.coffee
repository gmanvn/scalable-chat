mongoose = require 'mongoose'
logger = require('log4js').getLogger('MODEL')

class Model
  constructor: (connection) ->
    logger.info 'connecting to ', connection
    @_connection = mongoose.connect connection

    ## model loading
    @models = {}
    logger.info 'Loading Models =================='
    @loadModel 'conversation'
    @loadModel 'customer'
    @loadModel 'authentication_token'
    logger.info '=================================\n'

  loadModel: (modelName) ->
    ## load model file and pass-in connection obj
    try
      model = require("./#{modelName}") @_connection
      @models[modelName] = model
      logger.info '  * Model %s\t loaded!', modelName.bold.blue
    catch ex
      logger.fatal "Cannot load model %s", modelName.bold.cyan, ex


  ## static methods
  objectId: -> mongoose.Types.ObjectId()


module.exports = Model
