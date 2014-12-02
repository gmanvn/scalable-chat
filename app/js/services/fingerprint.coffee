angular.module('scalable-chat')
.factory 'makeFingerprint', ->

  counter = 0

  makeFingerprint = ->
    prefix = 'web-demo'
    now = Date.now()
    _counter = String(1e4 + counter++).substr(1)
    random = String(1e8 + ~~(1e8 * Math.random())).substr(1)
    [prefix,now,_counter,random].join(':')

  return makeFingerprint

