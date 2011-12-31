util = require("util")
datetime = require("datetime")
_ = require("underscore")
express = require("express")
hogan = require('hogan.js')
http = require('http')
gravatar = require('gravatar')


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
    src: "#{__dirname}/public"
    enable: ['coffeescript','less']
  )
  #serve static assets
  app.use express.static "#{__dirname}/public"
  #show stack trace since internal
  app.use express.errorHandler({ dumpExceptions: true, showStack: true })
  #use mustache for view engine
  app.set 'views',  "#{__dirname}/views"
  #view engine has to match file extension
  app.set 'view engine', 'html'
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
      redis.lpush "#{prefix}", id
      
      #RPUSH @TATTLEID into tattles list for each sort
      redis.lpush "#{prefix}:by-session-id:#{json.SessionId}", id
      redis.lpush "#{prefix}:by-category:#{json.Category}", id
      redis.lpush "#{prefix}:by-path:#{json.Path}", id
      redis.lpush( "#{prefix}:by-territory:#{json.Territory.TerritoryName}", id) if json.Territory?
      redis.lpush( "#{prefix}:by-restaurant:#{json.Restaurant.Name}", id) if json.Restaurant?
      
      if json.Customer?
        redis.lpush "#{prefix}:by-customer:#{json.Customer.Email}", id
        #CORRELATE SESSIONID w/ USER if USER SET
        redis.sadd "little-brother:sessions-for-customer:#{json.Customer.Email}",json.SessionId
        redis.set "little-brother:customer-for-session:#{json.SessionId}", JSON.stringify json.Customer
      
      #broadcast to connected clients
      io.sockets.emit "little-brother:new-tattle", json

get_tattles = (fn) ->
  #get last 50
  redis.lrange "little-brother:tattles",0,50, (err,tattle_ids) ->
    redis.mget _.map(tattle_ids, (id) -> "little-brother:tattle:#{id}"), (err,tattles_strings) ->
      tattles=_.map tattles_strings, (tattle_str) -> tattle = JSON.parse(tattle_str)
      
      needCustomersForSessionIds = _(tattles).chain().filter( (t) -> not t.Customer? ).pluck("SessionId").uniq().value()
      needCustomersForSessionKeys = _.map(needCustomersForSessionIds, (sid)->"little-brother:customer-for-session:#{sid}" )
      
      redis.mget needCustomersForSessionKeys, (err,customers) ->
        lookup={}
        _.each(_.zip(needCustomersForSessionIds,customers), (pair) ->
          customer_str=pair[1]
          customer = if customer_str? then JSON.parse(customer_str) else null
          lookup[pair[0]] = customer
        )
        console.log(lookup)
        tattles=_.map tattles, (tattle) -> 
        
          #resolve people who logged in later
          if not tattle.Customer? and lookup[tattle.SessionId]?
            tattle.Customer = lookup[tattle.SessionId]
            tattle.LaterLoggedIn = true
        
          # gravatar hash email
          if tattle.Customer?
            tattle.Customer.ImageUrl = gravatar.url(tattle.Customer.Email, {s: '50', d: 'retro'})
          
          #TODO: fmt/parse date
          
          tattle
         
        fn(tattles)

#
#routes
#
app.get "/", (req, res) ->
  res.sendfile "#{__dirname}/views/app.html"

#
#sockets
#
io.sockets.on "connection", (socket) ->
  
  get_tattles (tattles) ->
    console.log 'got connection'
    _.each tattles, (tattle) ->
      socket.emit "little-brother:new-tattle", tattle
    

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
  