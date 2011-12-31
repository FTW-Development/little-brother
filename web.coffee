util = require("util")
datetime = require("datetime")
_ = require("underscore")
express = require("express")
hogan = require('hogan.js')
http = require('http')


#
#redis setup
#
redis = null
if process.env.REDISTOGO_URL
  rtg = require("url").parse(process.env.REDISTOGO_URL)
  redis = require("redis").createClient(rtg.port, rtg.hostname)
  redis.auth rtg.auth.split(":")[1]
else
  redis = require("redis").createClient()


#app setup
app = express.createServer()
app.configure ->
  app.use express.logger()
  app.use app.router
  app.use express.methodOverride()
  app.use express.bodyParser()
  #compile less and coffeescript
  app.use express.compiler(
    src: __dirname + '/public'
    enable: ['coffeescript','less']
  )
  #serve static assets
  app.use express.static(__dirname + '/public')
  #show stack trace since internal
  app.use express.errorHandler({ dumpExceptions: true, showStack: true })
  #use mustache for view engine
  app.set 'views', __dirname + '/views'
  #view engine has to match file extension
  app.set 'view engine', 'mustache'
  #setup mustache to be rendered by hogan
	app.register('mustache',require('./hogan-express.js').init(hogan))


#socket setup
io = require("socket.io").listen(app)
io.set "log level", 0

#
#lib
record_tattle = (json) ->
  msg = JSON.stringify json
  
  #INC @TATTLEID
  redis.incr "little-brother:next-tattle-id", (error,id) ->
    #SET TATTLE:@TATTLEID to msg
    redis.set "little-brother:tattle:#{id}", msg, -> 
      #RPUSH @TATTLEID into TATTLES
      prefix = "little-brother:tattles"
      redis.rpush "#{prefix}", id
      
      #RPUSH @TATTLEID into tattles list for each sort
      redis.rpush "#{prefix}:by-session-id:#{json.SessionId}", id
      redis.rpush "#{prefix}:by-category:#{json.Category}", id
      redis.rpush "#{prefix}:by-path:#{json.Path}", id
      redis.rpush( "#{prefix}:by-territory:#{json.Territory.TerritoryName}", id) if json.Territory?
      redis.rpush( "#{prefix}:by-restaurant:#{json.Restaurant.Name}", id) if json.Restaurant?
      
      if json.Customer?
        redis.rpush "#{prefix}:by-customer:#{json.Customer.Email}", id
        #CORRELATE SESSIONID w/ USER if USER SET
        redis.sadd "little-brother:sessions-for-customer:#{json.Customer.Email}",json.SessionId
      
      #broadcast to connected clients
      io.sockets.emit "little-brother:new-tattle", json

#routes
#
app.get "/", (req, res) ->

  #get last 50
  redis.lrange "little-brother:tattles",-50,-1, (err,tattle_ids) ->
    redis.mget _.map(tattle_ids, (id) -> "little-brother:tattle:#{id}"), (err,tattles_strings) ->
      tattles=_.map(tattles_strings, (tattle_str) -> JSON.parse(tattle_str))
      console.log(tattles)
      res.render "app", 
         title: "Little Brother"
         tattles: tattles
       

#
#sockets
#
io.sockets.on "connection", (socket) ->
  socket.on "little-brother:tattle-received", (json) ->
    record_tattle json

#start http app
port = process.env.PORT or 5000
app.listen port, ->
  console.log "http listening on " + port

#start the udp listener
udp = require("dgram").createSocket "udp4"
udp.on "listening", ->
  address = udp.address()
  console.log "udp listening on #{address.address}:#{address.port}"
  
  udp.on "message",(msg, rinfo) ->
    console.log "got message: #{msg}"
    json = JSON.parse msg
    record_tattle json
    

udp.bind 11000
  