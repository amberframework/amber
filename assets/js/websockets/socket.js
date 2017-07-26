import { Channel } from './channel'

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
