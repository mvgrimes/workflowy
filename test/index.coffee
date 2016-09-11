assert = require 'assert'
fs = require 'fs'
Q = require 'q'
path = require 'path'
Workflowy = require '../'
FileCookieStore = require 'tough-cookie-filestore'
proxy = require '../lib/proxy'

username = 'mikerobe@me.com'
password = 'test'
cookiesPath = path.join(__filename, '../cookies.json')

useProxy = true || process.env.WORKFLOWY_PROXY

initialList = """
  - foo
    - <b>bold</b> #today
      - and another
      - or another
      - a final entry
  - bar
    - [COMPLETE] baz
    - [COMPLETE] boo
  - [COMPLETE] top complete
    - not complete
  """

fc = null
workflowy = null

workflowyMatchesOutline = (outline) ->
  workflowy.find().then (nodes) ->
    # find the root nodes in the flat list
    nodes = nodes.filter (node) -> node.parentId is 'None'
    assert.equal(workflowy.request.treeToOutline(nodes),outline)

describe 'Workflowy', ->

  beforeEach ->
    Q.ninvoke fs, 'unlink', cookiesPath
    .then Q, Q
    .then ->
      fc = new FileCookieStore('cookies.json')

  describe.skip '#constructor', ->
    it 'with empty cookies, should make 3 initial requests (meta, login, meta) then 1 with cookies present', ->
      workflowy = new Workflowy username, password, fc
      workflowy.nodes.then ->
        assert.equal(workflowy._requests,3)
        workflowy = new Workflowy username, password, fc
        workflowy.nodes.then ->
          assert.equal(workflowy._requests, 1)

  describe.skip '#update', ->
    it 'should reflect an empty tree after deleting all top level nodes', ->
      workflowy = new Workflowy username, password, fc
      workflowy.nodes.then ->
        workflowy.find().then (nodes) ->
          workflowy.delete(nodes).then ->
            workflowy.nodes.then (nodes) ->
              assert.equal(nodes.length, 0)
              assert(workflowy._requests, 7)

  describe 'using proxy', ->
    beforeEach ->
      workflowy = proxy new Workflowy username, password, fc
      workflowy.request.populate initialList

    describe '#find', ->
      it 'should reflect an initialized tree with empty search', ->
        workflowy.find().then (nodes) -> assert.equal(nodes.length, 10)

      it 'should find nodes that match a string', ->
        workflowy.find('another').then (nodes) ->
          assert.equal(nodes.length, 2)
          assert.equal(nodes[0].nm, 'and another')
          assert.equal(nodes[1].nm, 'or another')

      it 'should find nodes that are complete', ->
        workflowy.find(null, true).then (nodes) ->
          assert.equal(nodes.length, 3)
          assert.equal(nodes[0].nm, 'baz')
          assert.equal(nodes[1].nm, 'boo')
          assert.equal(nodes[2].nm, 'top complete')

      it 'should find nodes that are not complete', ->
        workflowy.find(null, false).then (nodes) ->
          assert.equal(nodes.length, 7)
          assert.equal(nodes[0].nm, 'foo')
          assert.equal(nodes[1].nm, '<b>bold</b> #today')
          assert.equal(nodes[2].nm, 'and another')
          assert.equal(nodes[3].nm, 'or another')
          assert.equal(nodes[4].nm, 'a final entry')
          assert.equal(nodes[5].nm, 'bar')
          assert.equal(nodes[6].nm, 'not complete')

    describe '#complete', -> 
      it 'should mark as complete the passed nodes', ->
        workflowy.find('another').then (nodes) ->
          workflowy.complete(nodes).then -> workflowyMatchesOutline """
            - foo
              - <b>bold</b> #today
                - [COMPLETE] and another
                - [COMPLETE] or another
                - a final entry
            - bar
              - [COMPLETE] baz
              - [COMPLETE] boo
            - [COMPLETE] top complete
              - not complete
            """

      it 'should mark as not complete the passed nodes', ->
        workflowy.find('top', true).then (nodes) ->
          workflowy.complete(nodes, false).then ->
            workflowyMatchesOutline """
              - foo
                - <b>bold</b> #today
                  - and another
                  - or another
                  - a final entry
              - bar
                - [COMPLETE] baz
                - [COMPLETE] boo
              - top complete
                - not complete
              """


    describe '#delete', ->
      it 'should only delete the selected nodes, including children', ->
        workflowy.find('#today').then (nodes) ->
          workflowy.delete(nodes).then -> workflowyMatchesOutline """
            - foo
            - bar
              - [COMPLETE] baz
              - [COMPLETE] boo
            - [COMPLETE] top complete
              - not complete
            """


