const EVENTS = {
  join: 'join',
  leave: 'leave',
  message: 'message'
}

export class Channel {
  constructor (topic, socket) {
    this.topic = topic
    this.socket = socket
    this.onMessageHandlers = []
  }

  join () {
    this.socket.ws.send(JSON.stringify({event: EVENTS.join, topic: this.topic}))
  }

  leave () {
    this.socket.ws.send(JSON.stringify({event: EVENTS.leave, topic: this.topic}))
  }

  handleMessage (msg) {
    this.onMessageHandlers.forEach((handler) => {
      if (handler.subject === msg.subject) handler.callback(msg.payload)
    })
  }

  on (subject, callback) {
    this.onMessageHandlers.push({subject: subject, callback: callback})
  }

  push (subject, payload) {
    this.socket.ws.send(JSON.stringify({event: EVENTS.message, topic: this.topic, subject: subject, payload: payload}))
  }
}

export class Socket {
  constructor (endpoint) {
    this.endpoint = endpoint
    this.ws = null
    this.channels = []
  }

  connect (params) {
    let opts = {
      location: window.location.hostname,
      port: window.location.port,
      protocol: window.location.protocol === 'https:' ? 'wss:' : 'ws:',
    }

    if (params) Object.assign(opts, params)
    if (opts.port) opts.location += `:${opts.port}`

    return new Promise((resolve, reject) => {      
      this.ws = new WebSocket(`${opts.protocol}//${opts.location}${this.endpoint}`)
      this.ws.onmessage = (msg) => { this.handleMessage(msg) }
      this.ws.onopen = () => resolve()
    })
  }

  channel (topic) {
    let channel = new Channel(topic, this)
    this.channels.push(channel)
    return channel
  }

  handleMessage (msg) {
    msg = JSON.parse(msg.data)
    this.channels.forEach((channel) => {
      if (channel.topic === msg.topic) channel.handleMessage(msg)
    })
  }
}

module.exports = {
  Socket: Socket
}
