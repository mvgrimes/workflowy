_ = require 'lodash'

module.exports = utils =
  parseShareId: (shareId) ->
    return unless shareId
    shareId = match[1] if match = ///^http.*/([a-zA-Z0-9]*)///.exec shareId
    throw new Error "Invalid shareId [#{shareId}]" unless ///^[a-zA-Z0-9]*$///.test shareId
    shareId

  getTimestamp: (meta) ->
    Math.floor (Date.now() - meta.projectTreeData.mainProjectTreeInfo.dateJoinedTimestampInSeconds) / 60

  makePollId: ->
    _.sampleSize('0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 8).join('')

  checkForErrors: ([resp, body]) ->
    if 300 <= resp.statusCode < 600
      throw new Error "Error with request #{resp.request.uri.href}: #{resp.statusCode}"
    if error = body.error
      throw new Error "Error with request #{resp.request.uri.href}: #{error}"
    return

  makeNodeId: () ->
    hex = '0123456789abcdef'
    [
      _.sampleSize(hex, 8).join('')
      _.sampleSize(hex, 4).join('')
      _.sampleSize(hex, 4).join('')
      _.sampleSize(hex, 4).join('')
      _.sampleSize(hex, 12).join('')
    ].join('-')

  treeToOutline: (roots, tab="  ") ->
    lines = []
    addLines = (nodes, depth) ->
      for node in nodes
        lines.push _.repeat(tab, depth) + "- " + (if node.cp then "[COMPLETE] " else "") + node.nm
        addLines node.ch, depth+1 if node.ch
      return
    addLines roots, 0
    lines.join '\n'

  flattenTree: (roots) ->
    result = []
    addChildren = (arr, parentId) ->
      for child in arr
        child.parentId = parentId
        result.push child
        addChildren children, child.id if children = child.ch
      return
    addChildren roots, 'None'
    result

  applyToTree: (roots, method) ->
    for root in roots
      continue if method.call(null,root) is false
      if root.ch
        utils.applyToTree root.ch, method
    return

  makeBold: (name='', tf=true) ->
    if tf
      if /^<b>/.test(name)
        name
      else
        "<b>#{name}</b>"
    else
      name.replace(/^<b>(.*?)<\/b>/,'$1')

