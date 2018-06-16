"use strict";

function _classCallCheck(instance, Constructor) {
  if (!(instance instanceof Constructor)) {
    throw new TypeError("Cannot call a class as a function");
  }
}

var EVENTS = {
  join: "join",
  leave: "leave",
  message: "message"
};
var STALE_CONNECTION_THRESHOLD_SECONDS = 100;
var SOCKET_POLLING_RATE = 10000;

/**
 * Returns a numeric value for the current time
 */
var now = function now() {
  return new Date().getTime();
};

/**
 * Returns the difference between the current time and passed `time` in seconds
 * @param {Number|Date} time - A numeric time or date object
 */
var secondsSince = function secondsSince(time) {
  return (now() - time) / 1000;
};

var Amber = {
  /**
   * Class for channel related functions (joining, leaving, subscribing and sending messages)
   */
  Channel: (function() {
    /**
     * @param {String} topic - topic to subscribe to
     * @param {Socket} socket - A Socket instance
     */
    function Channel(topic, socket) {
      _classCallCheck(this, Channel);

      this.topic = topic;
      this.socket = socket;
      this.onMessageHandlers = [];
    }

    /**
     * Join a channel, subscribe to all channels messages
     */

    Channel.prototype.join = function join() {
      this.socket.ws.send(
        JSON.stringify({ event: EVENTS.join, topic: this.topic })
      );
    };

    /**
     * Leave a channel, stop subscribing to channel messages
     */

    Channel.prototype.leave = function leave() {
      this.socket.ws.send(
        JSON.stringify({ event: EVENTS.leave, topic: this.topic })
      );
    };

    /**
     * Calls all message handlers with a matching subject
     */

    Channel.prototype.handleMessage = function handleMessage(msg) {
      this.onMessageHandlers.forEach(function(handler) {
        if (handler.subject === msg.subject) handler.callback(msg.payload);
      });
    };

    /**
     * Subscribe to a channel subject
     * @param {String} subject - subject to listen for: `msg:new`
     * @param {function} callback - callback function when a new message arrives
     */

    Channel.prototype.on = function on(subject, callback) {
      this.onMessageHandlers.push({ subject: subject, callback: callback });
    };

    /**
    * Send a new message to the channel
    * @param {String} subject - subject to send message to: `msg:new`
    * @param {Object} payload - payload object: `{message: 'hello'}`
    */

    Channel.prototype.push = function push(subject, payload) {
      this.socket.ws.send(
        JSON.stringify({
          event: EVENTS.message,
          topic: this.topic,
          subject: subject,
          payload: payload
        })
      );
    };

    return Channel;
  })(),

  /**
   * Class for maintaining connection with server and maintaining channels list
   */
  Socket: (function() {
    /**
     * @param {String} endpoint - Websocket endpont used in routes.cr file
     */
    function Socket(endpoint) {
      _classCallCheck(this, Socket);

      this.endpoint = endpoint;
      this.ws = null;
      this.channels = [];
      this.lastPing = now();
      this.reconnectTries = 0;
      this.attemptReconnect = true;
    }

    /**
     * Returns whether or not the last received ping has been past the threshold
     */

    Socket.prototype._connectionIsStale = function _connectionIsStale() {
      return secondsSince(this.lastPing) > STALE_CONNECTION_THRESHOLD_SECONDS;
    };

    /**
     * Tries to reconnect to the websocket server using a recursive timeout
     */

    Socket.prototype._reconnect = function _reconnect() {
      var _this = this;

      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = setTimeout(function() {
        _this.reconnectTries++;
        _this.connect(_this.params);
        _this._reconnect();
      }, this._reconnectInterval());
    };

    /**
     * Returns an incrementing timeout interval based around the number of reconnection retries
     */

    Socket.prototype._reconnectInterval = function _reconnectInterval() {
      return [1000, 2000, 5000, 10000][this.reconnectTries] || 10000;
    };

    /**
     * Sets a recursive timeout to check if the connection is stale
     */

    Socket.prototype._poll = function _poll() {
      var _this2 = this;

      this.pollingTimeout = setTimeout(function() {
        if (_this2._connectionIsStale()) {
          _this2._reconnect();
        } else {
          _this2._poll();
        }
      }, SOCKET_POLLING_RATE);
    };

    /**
     * Clear polling timeout and start polling
     */

    Socket.prototype._startPolling = function _startPolling() {
      clearTimeout(this.pollingTimeout);
      this._poll();
    };

    /**
     * Sets `lastPing` to the curent time
     */

    Socket.prototype._handlePing = function _handlePing() {
      this.lastPing = now();
    };

    /**
     * Clears reconnect timeout, resets variables an starts polling
     */

    Socket.prototype._reset = function _reset() {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTries = 0;
      this.attemptReconnect = true;
      this._startPolling();
    };

    /**
     * Connect the socket to the server, and binds to native ws functions
     * @param {Object} params - Optional parameters
     * @param {String} params.location - Hostname to connect to, defaults to `window.location.hostname`
     * @param {String} parmas.port - Port to connect to, defaults to `window.location.port`
     * @param {String} params.protocol - Protocol to use, either 'wss' or 'ws'
     */

    Socket.prototype.connect = function connect(params) {
      var _this3 = this;

      this.params = params;

      var opts = {
        location: window.location.hostname,
        port: window.location.port,
        protocol: window.location.protocol === "https:" ? "wss:" : "ws:"
      };

      if (params) {
        Object.assign(opts, params);
      }

      if (opts.port) {
        opts.location += ":" + opts.port;
      }

      return new Promise(function(resolve, reject) {
        _this3.ws = new WebSocket(
          opts.protocol + "//" + opts.location + _this3.endpoint
        );
        _this3.ws.onmessage = function(msg) {
          _this3.handleMessage(msg);
        };
        _this3.ws.onclose = function() {
          if (_this3.attemptReconnect) _this3._reconnect();
        };
        _this3.ws.onopen = function() {
          _this3._reset();
          resolve();
        };
      });
    };

    /**
     * Closes the socket connection permanently
     */

    Socket.prototype.disconnect = function disconnect() {
      this.attemptReconnect = false;
      clearTimeout(this.pollingTimeout);
      clearTimeout(this.reconnectTimeout);
      this.ws.close();
    };

    /**
     * Adds a new channel to the socket channels list
     * @param {String} topic - Topic for the channel: `chat_room:123`
     */

    Socket.prototype.channel = function channel(topic) {
      var channel = new Channel(topic, this);
      this.channels.push(channel);
      return channel;
    };

    /**
     * Message handler for messages received
     * @param {MessageEvent} msg - Message received from ws
     */

    Socket.prototype.handleMessage = function handleMessage(msg) {
      if (msg.data === "ping") {
        return this._handlePing();
      }

      var parsed_msg = JSON.parse(msg.data);
      this.channels.forEach(function(channel) {
        if (channel.topic === parsed_msg.topic) {
          channel.handleMessage(parsed_msg);
        }
      });
    };

    return Socket;
  })()

  /**
   * Load functions when DOM is ready
   */
};
document.addEventListener("DOMContentLoaded", function(event) {
  watchAnchorButtons();
});

/**
 * Allows links to post for security and ease of use similar to Rails jquery_ujs
 */
function watchAnchorButtons() {
  document.querySelectorAll("a[data-method]").forEach(function(element) {
    var method = element.getAttribute("data-method");
    element.addEventListener("click", function(event) {
      event.preventDefault();
      var message = element.getAttribute("data-confirm") || "Are you sure?";
      if (confirm(message)) {
        var form = document.createElement("form");
        var input = document.createElement("input");
        form.setAttribute("action", element.getAttribute("href"));
        form.setAttribute("method", "POST");
        input.setAttribute("type", "hidden");
        input.setAttribute("name", "_method");
        input.setAttribute("value", method);
        form.appendChild(input);
        document.body.appendChild(form);
        form.submit();
      }
    });
  });
}

/**
 * Allows to convert Date to Granite Model format
 */
Object.assign(Date.prototype, {
  toGranite: function toGranite() {
    var pad = function pad(number) {
      if (number < 10) {
        return "0" + number;
      }
      return number;
    };
    return (
      this.getUTCFullYear() +
      "-" +
      pad(this.getUTCMonth() + 1) +
      "-" +
      pad(this.getUTCDate()) +
      " " +
      pad(this.getUTCHours()) +
      ":" +
      pad(this.getUTCMinutes()) +
      ":" +
      pad(this.getUTCSeconds())
    );
  }
});
