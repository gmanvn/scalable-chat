logger = require('log4js').getLogger 'notification'
fibrous = require 'fibrous'
apn = require 'apn'
_ = require 'lodash'

HOUR = 3600e3

## amount of time in ms between the last undeliverable message and the actual push
NOTIFICATION_DEBOUNCE = 1000

class NotificationManager

  constructor: (config, @ModelFactory)->
    @Customer = @ModelFactory.models.customer

    @conn = apn.Connection config.apn

  send: _.debounce (username)->
    fibrous.run =>
      user = @Customer.sync.findById username
      return unless user

      badge = user.Badge
      token = user.LastDeviceId

      message = new apn.Notification
      message.expiry = ~~((24 * HOUR + Date.now()) / 1000)
      message.alert = 'You have a new message.'
      message.badge = badge

      device = new apn.Device token

      logger.debug 'pushing message to device [%s] badge=%s', token.bold, String(badge).bold
      @conn.pushNotification message, device
  , NOTIFICATION_DEBOUNCE

  queue: (username)->
    @send username


module.exports = NotificationManager