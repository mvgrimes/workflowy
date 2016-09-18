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

workflowyMatchesOutline = (inst, outline) ->
  [outline, inst] = [inst, workflowy] if arguments.length <2
    
  inst.find().then (nodes) ->
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

shareIdTests = (useQuarantine) ->
  rootName = "Book list"
  shareId = 'https://workflowy.com/s/XrZbUcWcLL'
  fcSub = new FileCookieStore('cookies.json')
  workflowySub = null

  beforeEach ->
    # clean up all the nodes under the book list
    workflowy = new Workflowy username, password, jar: fc
    if useQuarantine
      workflowySub = workflowy.quarantine shareId
    workflowy.find(rootName)
    .then (nodes) ->
      assert.equal nodes.length, 1
      if (children = nodes[0].ch)?.length
        workflowy.delete(children)
        .then ->
          unless useQuarantine
            workflowySub = new Workflowy username, password, jar: fcSub, shareId: shareId
      else
        unless useQuarantine
          workflowySub = new Workflowy username, password, jar: fcSub, shareId: shareId

  describe '#find', ->
    it 'should return only nodes under the given Id', ->
      workflowySub.refresh()
      workflowyMatchesOutline workflowySub, ""

  describe '#addChildren', ->
    it 'should add children under the expected root node', ->
      newRootNode = "top level child #{Date.now()}"
      newShareNode = "share #{Date.now()}"

      Q.all([
        workflowy.addChildren name: newRootNode
        workflowySub.addChildren name: newShareNode
      ]).then ->
        workflowyMatchesOutline workflowySub, "- #{newShareNode}"
      .then ->
        workflowy.find().then (nodes) ->
          assert.equal nodes[0].nm, newRootNode



describe.skip 'Workflowy over the wire', ->
  username = process.env.WORKFLOWY_USERNAME
  password = process.env.WORKFLOWY_PASSWORD

  beforeEach ->
    (console.error "Workflowy username and password must be provided through environmental variables."; process.exit 1) unless username and password

    Q.ninvoke fs, 'unlink', cookiesPath
    .then Q, Q
    .then ->
      fc = new FileCookieStore('cookies.json')

  describe.skip '#constructor', ->
    it 'with empty cookies, should make 3 initial requests (meta, login, meta) then 1 with cookies present', ->
      workflowy = new Workflowy username, password, jar: fc
      workflowy.refresh()
      workflowy.nodes.then ->
        assert.equal(workflowy._requests,3)
        workflowy = new Workflowy username, password, jar: fc
        workflowy.nodes.then ->
          assert.equal(workflowy._requests, 1)

  describe.skip '#update', ->
    it 'should reflect an empty tree after deleting all top level nodes', ->
      workflowy = new Workflowy username, password, jar: fc
      workflowy.refresh()
      workflowy.nodes.then ->
        workflowy.find().then (nodes) ->
          workflowy.delete(nodes).then ->
            workflowy.nodes.then (nodes) ->
              assert.equal(nodes.length, 0)
              assert(workflowy._requests, 7)

  describe '#addChildren', ->
    it 'should add child nodes where expected in the tree', ->
      workflowy = new Workflowy username, password, jar: fc
      workflowy.refresh()
      addChildrenTest workflowy

  describe 'with a shareId in constructor', ->
    shareIdTests false

  describe '#quarantine', ->
    shareIdTests true

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

describe 'Workflowy utils', ->
  describe '#addTag', ->
    it 'should add a tag if it does not exist', ->
      name = 'foo bar'
      assert.equal(utils.addTag(name, 'today'), name + ' #today')
      name = 'foo bar #todays'
      assert.equal(utils.addTag(name, 'today'), name + ' #today')

    it 'should not add a tag if it does exist', ->
      name = '#today foo bar'
      assert.equal(utils.addTag(name, 'today'), name)
      name = 'foo bar #today'
      assert.equal(utils.addTag(name, 'today'), name)

    it 'should insert the tag within bold', ->
      name = '<b>foo bar</b>'
      assert.equal(utils.addTag(name, 'today'), '<b>foo bar #today</b>')

  describe '#removeTag', ->
    it 'should remove a tag if it exists', ->
      name = 'foo #today bar'
      assert.equal(utils.removeTag(name, 'today'), 'foo bar')
    it 'should do nothing if the tag does not exist', ->
      name = 'foo #todays bar'
      assert.equal(utils.removeTag(name, 'today'), name)
    it 'should remove spacing before and after as appropriate', ->
      name = 'foo #today bar'
      assert.equal(utils.removeTag(name, 'today'), 'foo bar')
      name = '#today bar'
      assert.equal(utils.removeTag(name, 'today'), 'bar')
      name = 'bar #today'
      assert.equal(utils.removeTag(name, 'today'), 'bar')
      name = '#today #week this was for this week'
      assert.equal(utils.removeTag(name, 'today'), '#week this was for this week')

  describe '#addContext', ->
    it 'should add a context if it does not exist', ->
      name = 'foo bar'
      assert.equal(utils.addContext(name, 'today'), name + ' @today')
      name = 'foo bar @todays'
      assert.equal(utils.addContext(name, 'today'), name + ' @today')

    it 'should not add a context if it does exist', ->
      name = '@today foo bar'
      assert.equal(utils.addContext(name, 'today'), name)
      name = 'foo bar @today'
      assert.equal(utils.addContext(name, 'today'), name)

    it 'should insert the context within bold', ->
      name = '<b>foo bar</b>'
      assert.equal(utils.addContext(name, 'today'), '<b>foo bar @today</b>')

  describe '#removeContext', ->
    it 'should remove a context if it exists', ->
      name = 'foo @today bar'
      assert.equal(utils.removeContext(name, 'today'), 'foo bar')
    it 'should do nothing if the context does not exist', ->
      name = 'foo @todays bar'
      assert.equal(utils.removeContext(name, 'today'), name)
    it 'should remove spacing before and after as appropriate', ->
      name = 'foo @today bar'
      assert.equal(utils.removeContext(name, 'today'), 'foo bar')
      name = '@today bar'
      assert.equal(utils.removeContext(name, 'today'), 'bar')
      name = 'bar @today'
      assert.equal(utils.removeContext(name, 'today'), 'bar')
      name = '@today #week this was for this week'
      assert.equal(utils.removeContext(name, 'today'), '#week this was for this week')


