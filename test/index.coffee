assert = require 'assert'
fs = require 'fs'
Q = require 'q'
path = require 'path'
Workflowy = require '../'
FileCookieStore = require 'tough-cookie-filestore'

username = 'mikerobe@me.com'
password = 'test'
cookiesPath = path.join(__filename, '../cookies.json')

describe 'Workflowy', ->
  fc = null
  workflowy = null

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

  describe.only '#update', ->
    it 'should reflect an empty tree after deleting all top level nodes', ->
      workflowy = new Workflowy username, password, fc
      workflowy.nodes.then ->
        workflowy.find().then (nodes) ->
          workflowy.delete(nodes).then ->
            workflowy.nodes.then (nodes) ->
              assert.equal(nodes.length, 0)
              assert(workflowy._requests, 6)

