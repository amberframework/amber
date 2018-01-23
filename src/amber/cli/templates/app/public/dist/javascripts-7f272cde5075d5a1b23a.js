/******/ (function(modules) { // webpackBootstrap
/******/ 	// The module cache
/******/ 	var installedModules = {};
/******/
/******/ 	// The require function
/******/ 	function __webpack_require__(moduleId) {
/******/
/******/ 		// Check if module is in cache
/******/ 		if(installedModules[moduleId]) {
/******/ 			return installedModules[moduleId].exports;
/******/ 		}
/******/ 		// Create a new module (and put it into the cache)
/******/ 		var module = installedModules[moduleId] = {
/******/ 			i: moduleId,
/******/ 			l: false,
/******/ 			exports: {}
/******/ 		};
/******/
/******/ 		// Execute the module function
/******/ 		modules[moduleId].call(module.exports, module, module.exports, __webpack_require__);
/******/
/******/ 		// Flag the module as loaded
/******/ 		module.l = true;
/******/
/******/ 		// Return the exports of the module
/******/ 		return module.exports;
/******/ 	}
/******/
/******/
/******/ 	// expose the modules object (__webpack_modules__)
/******/ 	__webpack_require__.m = modules;
/******/
/******/ 	// expose the module cache
/******/ 	__webpack_require__.c = installedModules;
/******/
/******/ 	// define getter function for harmony exports
/******/ 	__webpack_require__.d = function(exports, name, getter) {
/******/ 		if(!__webpack_require__.o(exports, name)) {
/******/ 			Object.defineProperty(exports, name, {
/******/ 				configurable: false,
/******/ 				enumerable: true,
/******/ 				get: getter
/******/ 			});
/******/ 		}
/******/ 	};
/******/
/******/ 	// getDefaultExport function for compatibility with non-harmony modules
/******/ 	__webpack_require__.n = function(module) {
/******/ 		var getter = module && module.__esModule ?
/******/ 			function getDefault() { return module['default']; } :
/******/ 			function getModuleExports() { return module; };
/******/ 		__webpack_require__.d(getter, 'a', getter);
/******/ 		return getter;
/******/ 	};
/******/
/******/ 	// Object.prototype.hasOwnProperty.call
/******/ 	__webpack_require__.o = function(object, property) { return Object.prototype.hasOwnProperty.call(object, property); };
/******/
/******/ 	// __webpack_public_path__
/******/ 	__webpack_require__.p = "/dist/";
/******/
/******/ 	// Load entry module and return exports
/******/ 	return __webpack_require__(__webpack_require__.s = 0);
/******/ })
/************************************************************************/
/******/ ([
/* 0 */
/***/ (function(module, exports, __webpack_require__) {

"use strict";


var _amber = _interopRequireDefault(__webpack_require__(1));

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

var context = __webpack_require__(2); // Necessary for asset helper.  Has webpack import all the images regardless of use in js/css.


var context = __webpack_require__(4); // Necessary for asset helper.  Has webpack import all the fonts regardless of use in js/css.

/***/ }),
/* 1 */
/***/ (function(module, exports, __webpack_require__) {

"use strict";


Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.Socket = exports.Channel = void 0;

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } }

function _defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } }

function _createClass(Constructor, protoProps, staticProps) { if (protoProps) _defineProperties(Constructor.prototype, protoProps); if (staticProps) _defineProperties(Constructor, staticProps); return Constructor; }

var EVENTS = {
  join: 'join',
  leave: 'leave',
  message: 'message'
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
/**
 * Class for channel related functions (joining, leaving, subscribing and sending messages)
 */


var Channel =
/*#__PURE__*/
function () {
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


  _createClass(Channel, [{
    key: "join",
    value: function join() {
      this.socket.ws.send(JSON.stringify({
        event: EVENTS.join,
        topic: this.topic
      }));
    }
    /**
     * Leave a channel, stop subscribing to channel messages
     */

  }, {
    key: "leave",
    value: function leave() {
      this.socket.ws.send(JSON.stringify({
        event: EVENTS.leave,
        topic: this.topic
      }));
    }
    /**
     * Calls all message handlers with a matching subject
     */

  }, {
    key: "handleMessage",
    value: function handleMessage(msg) {
      this.onMessageHandlers.forEach(function (handler) {
        if (handler.subject === msg.subject) handler.callback(msg.payload);
      });
    }
    /**
     * Subscribe to a channel subject
     * @param {String} subject - subject to listen for: `msg:new`
     * @param {function} callback - callback function when a new message arrives
     */

  }, {
    key: "on",
    value: function on(subject, callback) {
      this.onMessageHandlers.push({
        subject: subject,
        callback: callback
      });
    }
    /**
     * Send a new message to the channel
     * @param {String} subject - subject to send message to: `msg:new`
     * @param {Object} payload - payload object: `{message: 'hello'}`
     */

  }, {
    key: "push",
    value: function push(subject, payload) {
      this.socket.ws.send(JSON.stringify({
        event: EVENTS.message,
        topic: this.topic,
        subject: subject,
        payload: payload
      }));
    }
  }]);

  return Channel;
}();
/**
 * Class for maintaining connection with server and maintaining channels list
 */


exports.Channel = Channel;

var Socket =
/*#__PURE__*/
function () {
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


  _createClass(Socket, [{
    key: "_connectionIsStale",
    value: function _connectionIsStale() {
      return secondsSince(this.lastPing) > STALE_CONNECTION_THRESHOLD_SECONDS;
    }
    /**
     * Tries to reconnect to the websocket server using a recursive timeout
     */

  }, {
    key: "_reconnect",
    value: function _reconnect() {
      var _this = this;

      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = setTimeout(function () {
        _this.reconnectTries++;

        _this.connect(_this.params);

        _this._reconnect();
      }, this._reconnectInterval());
    }
    /**
     * Returns an incrementing timeout interval based around the number of reconnection retries
     */

  }, {
    key: "_reconnectInterval",
    value: function _reconnectInterval() {
      return [1000, 2000, 5000, 10000][this.reconnectTries] || 10000;
    }
    /**
     * Sets a recursive timeout to check if the connection is stale
     */

  }, {
    key: "_poll",
    value: function _poll() {
      var _this2 = this;

      this.pollingTimeout = setTimeout(function () {
        if (_this2._connectionIsStale()) {
          _this2._reconnect();
        } else {
          _this2._poll();
        }
      }, SOCKET_POLLING_RATE);
    }
    /**
     * Clear polling timeout and start polling
     */

  }, {
    key: "_startPolling",
    value: function _startPolling() {
      clearTimeout(this.pollingTimeout);

      this._poll();
    }
    /**
     * Sets `lastPing` to the curent time
     */

  }, {
    key: "_handlePing",
    value: function _handlePing() {
      this.lastPing = now();
    }
    /**
     * Clears reconnect timeout, resets variables an starts polling
     */

  }, {
    key: "_reset",
    value: function _reset() {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTries = 0;
      this.attemptReconnect = true;

      this._startPolling();
    }
    /**
     * Connect the socket to the server, and binds to native ws functions
     * @param {Object} params - Optional parameters
     * @param {String} params.location - Hostname to connect to, defaults to `window.location.hostname`
     * @param {String} parmas.port - Port to connect to, defaults to `window.location.port`
     * @param {String} params.protocol - Protocol to use, either 'wss' or 'ws'
     */

  }, {
    key: "connect",
    value: function connect(params) {
      var _this3 = this;

      this.params = params;
      var opts = {
        location: window.location.hostname,
        port: window.location.port,
        protocol: window.location.protocol === 'https:' ? 'wss:' : 'ws:'
      };
      if (params) Object.assign(opts, params);
      if (opts.port) opts.location += ":".concat(opts.port);
      return new Promise(function (resolve, reject) {
        _this3.ws = new WebSocket("".concat(opts.protocol, "//").concat(opts.location).concat(_this3.endpoint));

        _this3.ws.onmessage = function (msg) {
          _this3.handleMessage(msg);
        };

        _this3.ws.onclose = function () {
          if (_this3.attemptReconnect) _this3._reconnect();
        };

        _this3.ws.onopen = function () {
          _this3._reset();

          resolve();
        };
      });
    }
    /**
     * Closes the socket connection permanently
     */

  }, {
    key: "disconnect",
    value: function disconnect() {
      this.attemptReconnect = false;
      clearTimeout(this.pollingTimeout);
      clearTimeout(this.reconnectTimeout);
      this.ws.close();
    }
    /**
     * Adds a new channel to the socket channels list
     * @param {String} topic - Topic for the channel: `chat_room:123`
     */

  }, {
    key: "channel",
    value: function channel(topic) {
      var channel = new Channel(topic, this);
      this.channels.push(channel);
      return channel;
    }
    /**
     * Message handler for messages received
     * @param {MessageEvent} msg - Message received from ws
     */

  }, {
    key: "handleMessage",
    value: function handleMessage(msg) {
      if (msg.data === "ping") return this._handlePing();
      var parsed_msg = JSON.parse(msg.data);
      this.channels.forEach(function (channel) {
        if (channel.topic === parsed_msg.topic) channel.handleMessage(parsed_msg);
      });
    }
  }]);

  return Socket;
}();

exports.Socket = Socket;
module.exports = {
  Socket: Socket
};

/***/ }),
/* 2 */
/***/ (function(module, exports, __webpack_require__) {

var map = {
	"./logo.png": 3
};
function webpackContext(req) {
	return __webpack_require__(webpackContextResolve(req));
};
function webpackContextResolve(req) {
	var id = map[req];
	if(!(id + 1)) // check for number or string
		throw new Error("Cannot find module '" + req + "'.");
	return id;
};
webpackContext.keys = function webpackContextKeys() {
	return Object.keys(map);
};
webpackContext.resolve = webpackContextResolve;
module.exports = webpackContext;
webpackContext.id = 2;

/***/ }),
/* 3 */
/***/ (function(module, exports, __webpack_require__) {

module.exports = __webpack_require__.p + "images/logo-c321a05deb5e6e097a40ecffbf90de45.png";

/***/ }),
/* 4 */
/***/ (function(module, exports) {

function webpackEmptyContext(req) {
	throw new Error("Cannot find module '" + req + "'.");
}
webpackEmptyContext.keys = function() { return []; };
webpackEmptyContext.resolve = webpackEmptyContext;
module.exports = webpackEmptyContext;
webpackEmptyContext.id = 4;

/***/ })
/******/ ]);
//# sourceMappingURL=javascripts-7f272cde5075d5a1b23a.js.map