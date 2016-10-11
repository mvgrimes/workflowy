debug = require('debug')('workflowy-request')
util = require 'util'

debugId = 1

module.exports = (request, options) ->
  original = request.Request.prototype.init
  request.Request.prototype.init = ->
    unless @._debugId
      @_debugId = ++debugId
      @on 'request', (req) -> debug "#{@_debugId}: #{@method} on #{@uri.href}"
      @on 'complete', (res) -> debug "#{@_debugId}: #{res.statusCode} #{util.inspect(res.body)}"
    original.apply this, arguments
