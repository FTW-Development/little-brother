dgram = require 'dgram'


message = new Buffer "Here's somethign"
client = dgram.createSocket "udp4"
client.send message, 0, message.length, 11000, "localhost", (err, bytes) ->
  client.close()