Workflowy = require '../'
_ = require 'lodash'
utils = require './utils'


###
# request proxy that emulates a workflowy server by intercepting requests
###
module.exports = (workflowy) ->
  meta = {}
  dateJoinedTimestampInSeconds = 1405704621
  clientId = Date.now()
  mostRecentTransaction = "793489242"
  ownerId = 895479
  rootProject = null
  tree = []

  response = (statusCode=200) ->
    {
      statusCode
      headers:
        location: "https://workflowy.com/"
    }

  request = -> throw new Error "unhandled use"

  ##
  # populates the internal outline representation
  # expects a string outline similar to workflowy exports
  #     - foo
  #       - <b>bold</b> #today
  #         - and another
  #         - and another
  #     - bar
  #       - [COMPLETE] baz
  ##
  request.populate = (outline, tab = "  ") ->
    tree = []
    parents = []
    makeNode = (line) ->
      m = line.match ///^((#{tab})*)-\x20(\[COMPLETE\]\x20)?(.*$)///
      depth = m[1].length//tab.length
      node =
        lm: 67919370,
        id: utils.makeNodeId()
        nm: m[4]
      node.cp = 67919370 if m[3]

      if depth is 0
        tree.push node
      else
        (parents[depth-1].ch ||= []).push node
      parents.length = depth
      parents[depth] = node
      node

    makeNode(line) for line in outline.split(/\r?\n/g)
    return

  request.treeToOutline = (roots=tree, tab="  ") ->
    lines = []
    addLines = (nodes, depth) ->
      for node in nodes
        lines.push _.repeat(tab, depth) + "- " + (if node.cp then "[COMPLETE] " else "") + node.nm
        addLines node.ch, depth+1 if node.ch
      return
    addLines roots, 0
    lines.join '\n'

  findNode = (id) ->
    parents = [{ch: tree}]
    i = 0
    while (parent = parents[i])
      for child, j in parent.ch
        if child.id is id
          return {parent: parent, index: j}
        else if child.ch
          parents.push child
      ++i
    null

  update = (operations, cb) ->
    for {type, data: {projectid, name}} in operations
      mostRecentTransaction = utils.getTimestamp(meta)

      switch type
        when "delete"
          if (path = findNode(projectid))
            path.parent.ch.splice(path.index,1)
        when "edit"
          if (path = findNode(projectid))
            path.parent.ch[path.index].nm = name
            path.parent.ch[path.index].lm = mostRecentTransaction
        when "complete"
          if (path = findNode(projectid))
            path.parent.ch[path.index].cp = mostRecentTransaction
    {
      new_most_recent_operation_transaction_id: mostRecentTransaction
    }

  request.get = ({url}, cb) ->
    cb new Error "Unhandled get url: #{url}" unless url is Workflowy.urls.meta
    cb null, response(), meta = 
      projectTreeData: {
        clientId
        mainProjectTreeInfo: {
          dateJoinedTimestampInSeconds
          initialMostRecentOperationTransactionId: mostRecentTransaction
          ownerId
          rootProject
          rootProjectChildren: tree
        }
        settings: {}
      }

  request.post = ({url, form}, cb) ->
    switch url
      when Workflowy.urls.login
        if (form.username is process.env.WORKFLOWY_USERNAME) and (form.password is process.env.WORKFLOWY_PASSWORD)
          cb null, response(), ""
        else
          cb null, response(500, "bad user/pass")
      when Workflowy.urls.update
        results = (update data.operations for data in JSON.parse(form.push_poll_data))
        cb null, response(), { results }
      else return cb new Error "Unhandled post url: #{url}"

  workflowy.request = request
  workflowy
