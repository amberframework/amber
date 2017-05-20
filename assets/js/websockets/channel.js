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
    this.socket.ws.send(JSON.stringify({event: EVENTS.message, topic: this.topic}))
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
