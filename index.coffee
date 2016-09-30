_ = require 'lodash'
Q = require 'q'
debug = require('debug')
request = require('request')
utils = require './lib/utils'

# decorate request module
request.use = (modules) ->
  module(this) for module in modules
  this
request.use [
  # require('request-debug')
  require('./lib/request-throttle')(1000)
]

module.exports = class Workflowy
  @clientVersion: 18

  @urls:
    login: 'https://workflowy.com/accounts/login/'
    meta: "https://workflowy.com/get_initialization_data?client_version=#{Workflowy.clientVersion}"
    update: 'https://workflowy.com/push_and_poll'

  constructor: (@username, @password, jar) ->
    @jar = if jar then request.jar(jar) else request.jar()
    @request = request.defaults {@jar, json: true}
    @_lastTransactionId = null

  login: ->
    Q.ninvoke @request,
      'post'
      url: Workflowy.urls.login
      form: {@username, @password}
    .then ([resp, body]) ->
      unless (resp.statusCode is 302) and (resp.headers.location is "https://workflowy.com/")
        utils.checkForErrors arguments...
      return
    .fail (err) ->
      console.error "Error logging in: ", err
      throw err

  refresh: ->
    meta = =>
      Q.ninvoke @request,
        'get'
        url: Workflowy.urls.meta
      .then ([resp,body]) ->
        utils.checkForErrors arguments...
        body

    @meta = meta().fail (err) =>
      @login().then meta
      .fail (err) ->
        console.error "Error fetching document root:", err
        throw err

    @outline = @meta.then (body) =>
      meta = body.projectTreeData.mainProjectTreeInfo
      @_lastTransactionId = meta.initialMostRecentOperationTransactionId
      meta.rootProjectChildren

    @nodes = @outline.then (outline) =>
      result = []

      addChildren = (arr, parentId) ->
        for child in arr
          child.parentId = parentId
          result.push child
          addChildren children, child.id if children = child.ch
        return

      addChildren outline, 'None'
      result

  _update: (operations) ->
    @meta.then (meta) =>
      timestamp = utils.getTimestamp meta
      {clientId} = meta.projectTreeData

      operation.client_timestamp = timestamp for operation in operations

      Q.ninvoke @request,
        'post'
        url: Workflowy.urls.update
        form:
          client_id: clientId
          client_version: Workflowy.clientVersion
          push_poll_id: utils.makePollId()
          push_poll_data: JSON.stringify [
            most_recent_operation_transaction_id: @_lastTransactionId
            operations: operations
          ]
      .then ([resp, body]) =>
        utils.checkForErrors arguments...
        @_lastTransactionId = body.results[0].new_most_recent_operation_transaction_id
        [resp, body, timestamp]

  ###
  # @search [optional]
  # @returns an array of nodes that match the given string, regex or function
  ###
  find: (search, completed) ->
    @meta || @refresh()

    unless !!search
      condition = -> true
    else if _.isString search
      condition = (node) -> node.nm.indexOf(search) isnt -1
    else if _.isRegExp search
      condition = (node) -> search.test node.nm
    else if _.isFunction search
      condition = search
    else
      (deferred = Q.defer()).reject new Error 'unknown search type'
      return deferred

    if completed?
      originalCondition = condition
      condition = (node) ->
        (node.cp? is !!completed) and originalCondition node

    @nodes.then (nodes) ->
      nodes = _.filter nodes, condition if condition
      nodes

  delete: (nodes) ->
    @meta || @refresh()

    nodes = [nodes] unless _.isArray nodes

    operations = for node in nodes
      type: 'delete'
      data: projectid: node.id
      undo_data:
        previous_last_modified: node.lm
        parentid: node.parentId
        priority: 5

    @_update operations
    .then =>
      # just fetch the nodes again
      @refresh()
      return

  ###
  # makes the given nodes bold or not bold
  ###
  bold: (nodes, tf=true) ->
    @meta || @refresh()
    nodes = [nodes] unless _.isArray nodes
    nodes = nodes.filter (node) -> /^<b>/.test(node.nm||'') isnt tf

    operations = for node in nodes
      type: 'edit'
      data:
        name: utils.makeBold(node.nm,tf)
        projectid: node.id
      undo_data:
        previous_last_modified: node.lm
        previous_completed: if tf then false else node.cp

    @_update operations
    .then ([resp,body,timestamp]) =>
      # now update the nodes
      for node, i in nodes
        node.nm = operations[i].data.name
        node.lm = timestamp

  complete: (nodes, tf=true) ->
    @meta || @refresh()
    nodes = [nodes] unless _.isArray nodes
    nodes = nodes.filter (node) -> node.cp? isnt tf

    operations = for node in nodes
      type: if tf then 'complete' else 'uncomplete'
      data: projectid: node.id
      undo_data:
        previous_last_modified: node.lm
        previous_completed: if tf then false else node.cp

    @_update operations
    .then ([resp,body,timestamp]) =>
      # now update the nodes
      for node, i in nodes
        if tf
          node.cp = timestamp
        else
          delete node.cp
        node.lm = timestamp

      return

  update: (nodes, newNames) ->
    @meta || @refresh()

    unless _.isArray nodes
      nodes = [nodes]
      newNames = [newNames]

    operations = for node, i in nodes
      type: 'edit',
      data:
        projectid: node.id
        name: newNames[i]
      undo_data:
        previous_last_modified: node.lm
        previous_name: node.nm

    if operations.length > 0
      @_update operations
      .then ([resp,body,timestamp]) =>
        for node, i in nodes
          node.nm = newNames[i]
          node.lm = timestamp
        return
    else
      @meta
