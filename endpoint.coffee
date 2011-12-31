dgram = require "dgram"

#
#redis setup TODO: refactor into own node_module
#
redis = null
if process.env.REDISTOGO_URL
  rtg = require("url").parse(process.env.REDISTOGO_URL)
  redis = require("redis").createClient(rtg.port, rtg.hostname)
  redis.auth rtg.auth.split(":")[1]
else
  redis = require("redis").createClient()

server = dgram.createSocket "udp4"

server.on "message",(msg, rinfo) ->
  json = JSON.parse msg
  
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

server.on "listening", ->
  address = server.address()
  console.log "server listening #{address.address}:#{address.port}"


server.bind 11000