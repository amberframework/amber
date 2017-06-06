import { Channel } from './channel'

export class Socket {
  constructor (endpoint) {
    this.endpoint = endpoint
    this.ws = null
    this.channels = []
  }

  connect (params) {
    return new Promise((resolve, reject) => {
      let location = window.location.hostname
      if (window.location.port) location += `:${window.location.port}`
      this.ws = new WebSocket(`ws://${location}${this.endpoint}`)
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
