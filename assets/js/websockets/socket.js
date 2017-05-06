import { Channel } from './channel'

export class Socket {
  constructor (endpoint) {
    this.endpoint = endpoint
    this.ws = null
    this.channels = []
  }

  connect (params) {
    this.ws = new WebSocket(`ws://localhost:8080${this.endpoint}`)
    this.ws.onmessage = (msg) => { this.handleMessage(msg) }
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
