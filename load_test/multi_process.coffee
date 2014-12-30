cluster = require 'cluster'
_ = require 'lodash'
io = require('socket.io-client')

PROCESS_USER = 50
MAX_FRIENDS = 20
NUMBER_PROCESS = 4
TOTAL_USER = PROCESS_USER * NUMBER_PROCESS


keys = [
  {
    private: '-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAix4jatNPZZW5NYM+nIT0oPaRoJGP8DA9J8ZmD5SA0eZAC9+W\nP+m/0SJz74qkw6xnwrP/i+9GK0JQiAu2XAL24vtTpkvuL+8bXk5DGqsL38evjax+\nRwqa5j2oHSnIas3jsb3OxERt9BrOYGYTYp7DVaOt5fhmGy90/+pYUREGRbl3ZVPD\nUtaOVSvhjX1rDt5mbZgbxnEQcKI0GmWp0suXz/0Ms0XZG5q4XITLsYhBqbRCXbIB\nl9DT6wrEbJhxlXXfah7Y/HrP350De1qSuDyI2b+Yno+Ykqfo+WaEls//S4EsUBA/\n8MGC6WmPnUMd/bn785hVxGOzmdFst3N5kf/ppwIDAQABAoIBACme16vDEnLq62E2\nJcpAAMwTWJg4VF7gn7tBoREyNaQWhbzHpLT0Yt3Xt+XHjem4r8ZRgbfE2zJgAaXi\nEynN/T0FQg5zkwwmNgLt2SemWsQVgtEY9SKd6p/NfHlVIc/KTz/C8JRJgLfSOUIf\n59bOdtQtRv6RZULm3NMfslJ2jHDZTWY4awGQ0yASda8bE07y+AgWHy308iuTdJaZ\nP9dWZYL/nYPE+ooRrXgJLJ4rUTg1SJ0qgIgc2a851247P6kF73w49vDwR5cjaoPC\nDborxLpivLgSyVsrt5eaiwFuTsXmZwiragUuXaBFX8gY92debsmeFg2cIq7cB3O4\nuHJr5gECgYEA0nsnye8DBXpgu01vx8oYd3Qz3M4lmHe/818wOCpQKbR6lf2+Zh8e\n3QQEF/AYOqPhpEu1bCgzvDjBmcb0YefsaCv6KnnQAOXXzo3TkpsDdItsNsQCac02\n/LvxW+vq8sifhQH0793Td6CYfVJ6fRbrhoMi98wLb1VCgoqSnFKgxwECgYEAqTQZ\ntID1LB2BQ/j9UyCM98y5HDMCLjV4nC3Bj645U6L7m9zwvw2cdw/frhxWlpKhlE+m\nuky4tbgQIIBKTH3mG8eLb0dchwqnAu6XLyrE6pnuIJLJOWZcvY8FLYZibamULUBd\nhtNM2aybpLBurOIVBwTwd/g85XN8v76nEt52GKcCgYEAi0GwMYpRFW7CUSoKqsSr\nK11WcuBxP077UKnJ3V8hanZeJJ6dOjOc192wV6YiYanLwEfW4Jg4om9qp7NaPOyV\nHNb7zN6LIAzxm1d6g6TLxG/6SMGmVxnPJ6exKIAOElNqNzX0OD8rihpWyZOoNtrT\nOUvJ9uipKB/gwT2tgn+ooAECgYA4KCGL5ez5GkXHwICbMUd4Css5D7jei0KfWxRN\n0n4WQxaM0VRZpHPUlEEhsSgPy1SzO4hTdpkrPo6jqtB9+J8Bg0XExgNwklmBwJwO\nvHwkfLgquWztjwqiozANvvc1/D1Ak4c28zQjXoU9sIza9iISdVI2Dv5vDNhPb0BW\nI91AKwKBgBb8DJD2CiJVqUfLLeSxPTW7/lfTm+FtdimQmkxyeCBWve/u1+0sfa8k\nWABg0QCe8BAmXQ6WsfMVcCtt4C/93AfW3DZk8fz0fsDDcdXvIkn02YvcRV2pwDPu\n6i7LkCwwwy9kygjpNB215vsL+7IgtgsHEiiq4cXgMmpqlr7Roe8S\n-----END RSA PRIVATE KEY-----'
    public: '-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAix4jatNPZZW5NYM+nIT0\noPaRoJGP8DA9J8ZmD5SA0eZAC9+WP+m/0SJz74qkw6xnwrP/i+9GK0JQiAu2XAL2\n4vtTpkvuL+8bXk5DGqsL38evjax+Rwqa5j2oHSnIas3jsb3OxERt9BrOYGYTYp7D\nVaOt5fhmGy90/+pYUREGRbl3ZVPDUtaOVSvhjX1rDt5mbZgbxnEQcKI0GmWp0suX\nz/0Ms0XZG5q4XITLsYhBqbRCXbIBl9DT6wrEbJhxlXXfah7Y/HrP350De1qSuDyI\n2b+Yno+Ykqfo+WaEls//S4EsUBA/8MGC6WmPnUMd/bn785hVxGOzmdFst3N5kf/p\npwIDAQAB\n-----END PUBLIC KEY-----'
  }
]


everyone = [1..TOTAL_USER]

if cluster.isMaster

  for i in [1..NUMBER_PROCESS]
    everyone = _.shuffle(everyone)
    env =
      start: (i - 1) * PROCESS_USER + 1
      end: i * PROCESS_USER

    cluster.fork env

if cluster.isWorker
  {start, end} = process.env
  console.log 'env', {start, end}

  server = 'http://localhost'
#  server = 'http://dchat-170377.apse1.nitrousbox.com'
  options =
    transports: ['websocket'],
    'force new connection': true


  connect = ->
    port = 3001 + ~~(Math.random() * 8)
    io.connect [server, port].join(':'), options


  stat =
    count: 0
    totalTime: 0
    average: 0
    max: 0
    min: Infinity

  round2 = (number)->
    ~~(number * 100) / 100

  incoming = 0

  ## init
  devices = [start..end].map (customerId) ->
    socket = connect()
    return {
    socket
    customerId: String customerId
    privateKey: keys[0].private
    token: 'token'
    counter: 0
    timers: {}
    friends: _.shuffle(everyone)[0..MAX_FRIENDS]
    received: {}
    }

  ## add listener
  devices.forEach (device)->

    ## incoming message
    device.socket.on 'incoming message', (conversationId, messages) ->
      messages = [messages] unless messages.length
      for message in messages
        continue if device.received[message._id]
        device.received[message._id] = Date.now()
        incoming++
        device.socket.emit 'incoming message received', conversationId, message

    ## delivered
    device.socket.on 'outgoing message delivered', (conversationId, fingerprint)->
      send device

      sent = device.timers[fingerprint]
      return unless sent
      time = Date.now() - sent
      delete device.timers[fingerprint]


      stat.count++
      stat.totalTime += time
      stat.average = round2 stat.totalTime / stat.count
      stat.max = if time > stat.max then time else stat.max
      stat.min = if time < stat.min then time else stat.min

      console.log 'time: %sms  \tavg: %sms \tmax: %sms \tmin: %sms \t received: %s \t sent: %s \t incoming: %s', time, stat.average, stat.max, stat.min, stat.count, sent_count, incoming



  ## signin
  devices.forEach (device)->
    device.socket.emit 'user signed in', device.customerId, device.token, device.privateKey

  sent_count = 0

  send = (device)->
    sender = device.customerId
    receiver = String _.sample device.friends
    body = 'load test'
    fgp = [sender, device.counter++].join ':'
    device.timers[fgp] = Date.now()

#    console.log '%s -> %s', sender, receiver
    device.socket.emit 'outgoing message', {
      sender, body, client_fingerprint: fgp
    }, receiver
    sent_count++




  setTimeout ->
    console.log 'start sending'
    devices.forEach (device, index)->
      delay = index % 4
      setInterval ->
        send device
      , 2000
  , 10000


