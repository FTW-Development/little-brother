socket = io.connect(document.location.protocol + "//" + document.location.hostname)

socket.on "little-brother:new-tattle", (tattle)->
  console.log "got", tattle
