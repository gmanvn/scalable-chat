logger = require('log4js').getLogger 'notification'
fibrous = require 'fibrous'
apn = require 'apn'
_ = require 'lodash'

HOUR = 3600e3

## amount of time in ms between the last undeliverable message and the actual push
NOTIFICATION_DEBOUNCE = 1000

class NotificationManager

  constructor: (@server, config, @ModelFactory)->
    @Customer = @ModelFactory.models.customer

    @conn = apn.Connection config.apn

    @_deviceIdHash = {}

  count: (key, cb)->
    @server.redisData.scard [@server.env, key].join('$'), cb

  actualGetDeviceId: (customerId)->
    user = @Customer.sync.findById customerId
    return false unless user

    token = user.LastDeviceId
    return false unless token

    return token

  getDeviceId: fibrous (customerId)->

    ## read from cache
    return @_deviceIdHash[customerId] if @_deviceIdHash[customerId]

    token = @actualGetDeviceId customerId
    ## clear cache after 1 day
    setTimeout =>
      delete @_deviceIdHash[customerId]
    , 1000 * 60 * 60 * 24

    return  @_deviceIdHash[customerId] = token

  send: (username)->
    fibrous.run =>
      badge = @sync.count 'incoming:' + username
      return unless badge

      token = @sync.getDeviceId username
      console.log 'token', token
      return unless typeof token is 'string'

      message = new apn.Notification
      message.expiry = ~~((24 * HOUR + Date.now()) / 1000)
      message.alert = 'You have a new message.'
      message.badge = badge

      try
        device = new apn.Device token

        logger.debug 'pushing message to device [%s] badge=%s', token.bold, String(badge).bold
        @conn.pushNotification message, device
      catch ex
        logger.warn 'cannot push message to device [%s]', ex

  queue: (username)->
    @send username


module.exports = NotificationManager