const EVENTS = {
  join: 'join',
  leave: 'leave',
  message: 'message'
}
const STALE_CONNECTION_THRESHOLD_SECONDS = 100
const SOCKET_POLLING_RATE = 10000

/**
 * Returns a numeric value for the current time
 */
let now = () => {
  return new Date().getTime()
}

/**
 * Returns the difference between the current time and passed `time` in seconds
 * @param {Number|Date} time - A numeric time or date object
 */
let secondsSince = (time) => {
  return (now() - time) / 1000
}

/**
 * Class for channel related functions (joining, leaving, subscribing and sending messages)
 */
export class Channel {
  /**
   * @param {String} topic - topic to subscribe to
   * @param {Socket} socket - A Socket instance
   */
  constructor(topic, socket) {
    this.topic = topic
    this.socket = socket
    this.onMessageHandlers = []
  }

  /**
   * Join a channel, subscribe to all channels messages
   */
  join() {
    this.socket.ws.send(JSON.stringify({ event: EVENTS.join, topic: this.topic }))
  }

  /**
   * Leave a channel, stop subscribing to channel messages
   */
  leave() {
    this.socket.ws.send(JSON.stringify({ event: EVENTS.leave, topic: this.topic }))
  }

  /**
   * Calls all message handlers with a matching subject
   */
  handleMessage(msg) {
    this.onMessageHandlers.forEach((handler) => {
      if (handler.subject === msg.subject) handler.callback(msg.payload)
    })
  }

  /**
   * Subscribe to a channel subject
   * @param {String} subject - subject to listen for: `msg:new`
   * @param {function} callback - callback function when a new message arrives
   */
  on(subject, callback) {
    this.onMessageHandlers.push({ subject: subject, callback: callback })
  }

  /**
   * Send a new message to the channel
   * @param {String} subject - subject to send message to: `msg:new`
   * @param {Object} payload - payload object: `{message: 'hello'}`
   */
  push(subject, payload) {
    this.socket.ws.send(JSON.stringify({ event: EVENTS.message, topic: this.topic, subject: subject, payload: payload }))
  }
}

/**
 * Class for maintaining connection with server and maintaining channels list
 */
export class Socket {
  /**
   * @param {String} endpoint - Websocket endpont used in routes.cr file
   */
  constructor(endpoint) {
    this.endpoint = endpoint
    this.ws = null
    this.channels = []
    this.lastPing = now()
    this.reconnectTries = 0
    this.attemptReconnect = true
  }

  /**
   * Returns whether or not the last received ping has been past the threshold
   */
  _connectionIsStale() {
    return secondsSince(this.lastPing) > STALE_CONNECTION_THRESHOLD_SECONDS
  }

  /**
   * Tries to reconnect to the websocket server using a recursive timeout
   */
  _reconnect() {
    clearTimeout(this.reconnectTimeout)
    this.reconnectTimeout = setTimeout(() => {
      this.reconnectTries++
      this.connect(this.params)
      this._reconnect()
    }, this._reconnectInterval())
  }

  /**
   * Returns an incrementing timeout interval based around the number of reconnection retries
   */
  _reconnectInterval() {
    return [1000, 2000, 5000, 10000][this.reconnectTries] || 10000
  }

  /**
   * Sets a recursive timeout to check if the connection is stale
   */
  _poll() {
    this.pollingTimeout = setTimeout(() => {
      if (this._connectionIsStale()) {
        this._reconnect()
      } else {
        this._poll()
      }
    }, SOCKET_POLLING_RATE)
  }

  /**
   * Clear polling timeout and start polling
   */
  _startPolling() {
    clearTimeout(this.pollingTimeout)
    this._poll()
  }

  /**
   * Sets `lastPing` to the curent time
   */
  _handlePing() {
    this.lastPing = now()
  }

  /**
   * Clears reconnect timeout, resets variables an starts polling
   */
  _reset() {
    clearTimeout(this.reconnectTimeout)
    this.reconnectTries = 0
    this.attemptReconnect = true
    this._startPolling()
  }

  /**
   * Connect the socket to the server, and binds to native ws functions
   * @param {Object} params - Optional parameters
   * @param {String} params.location - Hostname to connect to, defaults to `window.location.hostname`
   * @param {String} parmas.port - Port to connect to, defaults to `window.location.port`
   * @param {String} params.protocol - Protocol to use, either 'wss' or 'ws'
   */
  connect(params) {
    this.params = params

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
      this.ws.onclose = () => {
        if (this.attemptReconnect) this._reconnect()
      }
      this.ws.onopen = () => {
        this._reset()
        resolve()
      }
    })
  }

  /**
   * Closes the socket connection permanently
   */
  disconnect() {
    this.attemptReconnect = false
    clearTimeout(this.pollingTimeout)
    clearTimeout(this.reconnectTimeout)
    this.ws.close()
  }

  /**
   * Adds a new channel to the socket channels list
   * @param {String} topic - Topic for the channel: `chat_room:123`
   */
  channel(topic) {
    let channel = new Channel(topic, this)
    this.channels.push(channel)
    return channel
  }

  /**
   * Message handler for messages received
   * @param {MessageEvent} msg - Message received from ws
   */
  handleMessage(msg) {
    if (msg.data === "ping") return this._handlePing()

    let parsed_msg = JSON.parse(msg.data)
    this.channels.forEach((channel) => {
      if (channel.topic === parsed_msg.topic) channel.handleMessage(parsed_msg)
    })
  }
}

export default {
  Channel,
  Socket
};

/**
 * Allows delete links to post for security and ease of use similar to Rails jquery_ujs
 */
document.addEventListener("DOMContentLoaded", () => {
  let elements = document.querySelectorAll("a[data-method='delete']");
  for (let i = 0; i < elements.length; i++) {
    elements[i].addEventListener("click", (e) => {
      e.preventDefault();
      let message = elements[i].getAttribute("data-confirm") || "Are you sure?";
      if (confirm(message)) {
        let form = document.createElement("form");
        let input = document.createElement("input");
        form.setAttribute("action", elements[i].getAttribute("href"));
        form.setAttribute("method", "POST");
        input.setAttribute("type", "hidden");
        input.setAttribute("name", "_method");
        input.setAttribute("value", "DELETE");
        form.appendChild(input);
        document.body.appendChild(form);
        form.submit();
      }
      return false;
    })
  }
});

if (!Date.prototype.toGranite) {
  (function() {

    function pad(number) {
      if (number < 10) {
        return '0' + number;
      }
      return number;
    }

    Date.prototype.toGranite = function() {
      return this.getUTCFullYear() +
        '-' + pad(this.getUTCMonth() + 1) +
        '-' + pad(this.getUTCDate()) +
        ' ' + pad(this.getUTCHours()) +
        ':' + pad(this.getUTCMinutes()) +
        ':' + pad(this.getUTCSeconds())  ;
    };

  }());
}
