rsa = require 'node-rsa'
fs = require 'fs'
total = 1000


## create file
file = fs.openSync 'key_pairs.coffee', 'w'

fs.writeSync file, 'keys = []\n\n', null, 'utf8'

startAll = start = Date.now()
for i in [1..total]
  key = new rsa b:128
  pair = key.generateKeyPair()
  pub = pair.exportKey 'public'
  pri = pair.exportKey 'private'

  str = [
    'keys.push \n  public: "', pub, '"\n  private: "', pri, '"\n\n'
  ].join ''

  fs.writeSync file, str, null, 'utf8'

  ## stat
  now = Date.now()
  time = now - start
  timeAll = now - startAll
  start = now
  avg = ~~(timeAll/i)
  left = avg * (total - i) / 1000
  s = String(left % 3600 + 100).substr 1
  m = String(~~(left / 60) % 60 + 100).substr 1
  h = String(~~(left / 3600) + 100).substr 1

  console.log '%s/%s\t:%sms\t(avg: %sms)\tEst: %s:%s:%s', i, total, time, avg, h,m,s

fs.writeSync file, 'exports.keys = keys'
fs.close file