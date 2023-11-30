let tryReload

export function initializeWebSockets() {
  console.log("initializeWebSockets has run...")
  
  tryReload = async function () {
    try {
      const response = await fetch(window.location.href);
      if (!response.ok) {
        setTimeout(tryReload, 1000);
      } else {
        window.location.reload();
      }
    } catch (error) {
      setTimeout(tryReload, 1000);
    }
  }

  if ('WebSocket' in window) {
    const protocol = window.location.protocol === 'http:' ? 'ws://' : 'wss://'
    const address = protocol + window.location.host + '/client-reload'
    const socket = new WebSocket(address)

    socket.onmessage = function (msg) {
      console.log(msg)
      if (msg.data == 'reload') {
        tryReload()
      }
    }

    socket.onclose = function () {
      setTimeout(tryReload, 1000)
    }
  }
}
