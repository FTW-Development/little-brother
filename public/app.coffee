socket = io.connect(document.location.protocol + "//" + document.location.hostname)

template=null

$ ->
  template=$("#tattle").html()
  




socket.on "little-brother:new-tattle", (tattle)->
  console.log "got", tattle
  html = $.mustache(template,tattle)
  $('#tattles').prepend(html)

