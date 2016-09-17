assert = require 'assert'
fs = require 'fs'
Q = require 'q'
path = require 'path'
Workflowy = require '../'
FileCookieStore = require 'tough-cookie-filestore'
proxy = require '../lib/proxy'
utils = require '../lib/utils'

username = 'mikerobe@me.com'
password = 'test'
cookiesPath = path.join(__filename, '../cookies.json')

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
    assert.equal(utils.treeToOutline(nodes),outline)

addChildrenTest = (workflowy) ->
  workflowy.addChildren [{name: 'first'}, {name: 'second'}]
  .then ->
    workflowy.find().then (nodes) ->
      assert.equal(nodes[0].nm, 'first')
      assert.equal(nodes[1].nm, 'second')

      workflowy.addChildren [{name: 'underFirst1'}, {name: 'underFirst2'}], nodes[0]
      .then ->
        workflowy.find().then (nodes) ->
          assert.equal(nodes[0].nm, 'first')
          assert.equal(nodes[1].nm, 'underFirst1')
          assert.equal(nodes[2].nm, 'underFirst2')
          assert.equal(nodes[3].nm, 'second')

          assert.equal(nodes[1].parentId, nodes[0].id)
          assert.equal(nodes[2].parentId, nodes[0].id)

          workflowy.addChildren [{name: 'between underFirst1 and underFirst2 a'}, {name: 'between underFirst1 and underFirst2 b'}], nodes[0], 1
          .then ->
            workflowy.find().then (nodes) ->
              assert.equal(nodes[0].nm, 'first')
              assert.equal(nodes[1].nm, 'underFirst1')
              assert.equal(nodes[2].nm, 'between underFirst1 and underFirst2 a')
              assert.equal(nodes[3].nm, 'between underFirst1 and underFirst2 b')
              assert.equal(nodes[4].nm, 'underFirst2')
              assert.equal(nodes[5].nm, 'second')

              assert.equal(nodes[0].parentId, 'None')
              assert.equal(nodes[1].parentId, nodes[0].id)
              assert.equal(nodes[2].parentId, nodes[0].id)
              assert.equal(nodes[3].parentId, nodes[0].id)
              assert.equal(nodes[4].parentId, nodes[0].id)
              assert.equal(nodes[5].parentId, 'None')

describe 'Workflowy over the wire', ->

  beforeEach ->
    Q.ninvoke fs, 'unlink', cookiesPath
    .then Q, Q
    .then ->
      fc = new FileCookieStore('cookies.json')

  describe '#constructor', ->
    it 'with empty cookies, should make 3 initial requests (meta, login, meta) then 1 with cookies present', ->
      workflowy = new Workflowy username, password, fc
      workflowy.nodes.then ->
        assert.equal(workflowy._requests,3)
        workflowy = new Workflowy username, password, fc
        workflowy.nodes.then ->
          assert.equal(workflowy._requests, 1)

  describe '#update', ->
    it 'should reflect an empty tree after deleting all top level nodes', ->
      workflowy = new Workflowy username, password, fc
      workflowy.nodes.then ->
        workflowy.find().then (nodes) ->
          workflowy.delete(nodes).then ->
            workflowy.nodes.then (nodes) ->
              assert.equal(nodes.length, 0)
              assert(workflowy._requests, 7)

  describe '#addChildren', ->
    it 'should add child nodes where expected in the tree', ->
      addChildrenTest workflowy = new Workflowy username, password, fc


describe 'Workflowy with proxy', ->
  beforeEach ->
    workflowy = proxy new Workflowy username, password
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

  describe '#bold', ->
    it 'should make nodes not previously bold, bold', ->
      workflowy.find('top').then (nodes) ->
        workflowy.bold(nodes).then -> workflowyMatchesOutline """
          - foo
            - <b>bold</b> #today
              - and another
              - or another
              - a final entry
          - bar
            - [COMPLETE] baz
            - [COMPLETE] boo
          - [COMPLETE] <b>top complete</b>
            - not complete
          """

  describe '#delete', ->
    it 'should only delete the selected nodes, including children', ->
      workflowy.find('#today').then (nodes) ->
        workflowy.delete(nodes)
      .then -> workflowyMatchesOutline """
        - foo
        - bar
          - [COMPLETE] baz
          - [COMPLETE] boo
        - [COMPLETE] top complete
          - not complete
        """

  describe '#asText', ->
    it 'should return the same outline given', ->
      workflowy.asText().then (text) ->
        assert.equal text, initialList
    it 'should make expected modifications', ->
      workflowy.find('',true)
      .then (nodes) -> workflowy.delete(nodes)
      .then -> workflowy.asText()
      .then (text) -> assert.equal text, """
        - foo
          - <b>bold</b> #today
            - and another
            - or another
            - a final entry
        - bar
        """
  describe '#addChildren', ->
    it 'should add child nodes where expected in the tree', ->
      addChildrenTest workflowy

