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
/******/ 	__webpack_require__.p = "/dist";
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
//# sourceMappingURL=data:application/json;charset=utf-8;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbIndlYnBhY2s6Ly8vd2VicGFjay9ib290c3RyYXAgNjJjY2I0MDUzN2Y2N2JmMmY0NDciLCJ3ZWJwYWNrOi8vLy4vc3JjL2Fzc2V0cy9qYXZhc2NyaXB0cy9tYWluLmpzIiwid2VicGFjazovLy8uLi9hbWJlci9hc3NldHMvanMvYW1iZXIuanMiLCJ3ZWJwYWNrOi8vLy4vc3JjL2Fzc2V0cy9pbWFnZXMgXlxcLlxcLy4qJCIsIndlYnBhY2s6Ly8vLi9zcmMvYXNzZXRzL2ltYWdlcy9sb2dvLnBuZyIsIndlYnBhY2s6Ly8vLi9zcmMvYXNzZXRzL2ZvbnRzIF5cXC5cXC8uKiQiXSwibmFtZXMiOlsiY29udGV4dCIsIkVWRU5UUyIsImpvaW4iLCJsZWF2ZSIsIm1lc3NhZ2UiLCJTVEFMRV9DT05ORUNUSU9OX1RIUkVTSE9MRF9TRUNPTkRTIiwiU09DS0VUX1BPTExJTkdfUkFURSIsIm5vdyIsIkRhdGUiLCJnZXRUaW1lIiwic2Vjb25kc1NpbmNlIiwidGltZSIsIkNoYW5uZWwiLCJ0b3BpYyIsInNvY2tldCIsIm9uTWVzc2FnZUhhbmRsZXJzIiwid3MiLCJzZW5kIiwiSlNPTiIsInN0cmluZ2lmeSIsImV2ZW50IiwibXNnIiwiZm9yRWFjaCIsImhhbmRsZXIiLCJzdWJqZWN0IiwiY2FsbGJhY2siLCJwYXlsb2FkIiwicHVzaCIsIlNvY2tldCIsImVuZHBvaW50IiwiY2hhbm5lbHMiLCJsYXN0UGluZyIsInJlY29ubmVjdFRyaWVzIiwiYXR0ZW1wdFJlY29ubmVjdCIsImNsZWFyVGltZW91dCIsInJlY29ubmVjdFRpbWVvdXQiLCJzZXRUaW1lb3V0IiwiY29ubmVjdCIsInBhcmFtcyIsIl9yZWNvbm5lY3QiLCJfcmVjb25uZWN0SW50ZXJ2YWwiLCJwb2xsaW5nVGltZW91dCIsIl9jb25uZWN0aW9uSXNTdGFsZSIsIl9wb2xsIiwiX3N0YXJ0UG9sbGluZyIsIm9wdHMiLCJsb2NhdGlvbiIsIndpbmRvdyIsImhvc3RuYW1lIiwicG9ydCIsInByb3RvY29sIiwiT2JqZWN0IiwiYXNzaWduIiwiUHJvbWlzZSIsInJlc29sdmUiLCJyZWplY3QiLCJXZWJTb2NrZXQiLCJvbm1lc3NhZ2UiLCJoYW5kbGVNZXNzYWdlIiwib25jbG9zZSIsIm9ub3BlbiIsIl9yZXNldCIsImNsb3NlIiwiY2hhbm5lbCIsImRhdGEiLCJfaGFuZGxlUGluZyIsInBhcnNlZF9tc2ciLCJwYXJzZSIsIm1vZHVsZSIsImV4cG9ydHMiXSwibWFwcGluZ3MiOiI7QUFBQTtBQUNBOztBQUVBO0FBQ0E7O0FBRUE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FBRUE7QUFDQTs7QUFFQTtBQUNBOztBQUVBO0FBQ0E7QUFDQTs7O0FBR0E7QUFDQTs7QUFFQTtBQUNBOztBQUVBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0EsYUFBSztBQUNMO0FBQ0E7O0FBRUE7QUFDQTtBQUNBO0FBQ0EsbUNBQTJCLDBCQUEwQixFQUFFO0FBQ3ZELHlDQUFpQyxlQUFlO0FBQ2hEO0FBQ0E7QUFDQTs7QUFFQTtBQUNBLDhEQUFzRCwrREFBK0Q7O0FBRXJIO0FBQ0E7O0FBRUE7QUFDQTs7Ozs7Ozs7OztBQzNEQTs7OztBQUZBLElBQUlBLFVBQVUsc0JBQWQsQyxDQUFpRDs7O0FBQ2pELElBQUlBLFVBQVUsc0JBQWQsQyxDQUFnRCw2Rjs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7QUNEaEQsSUFBTUMsU0FBUztBQUNiQyxRQUFNLE1BRE87QUFFYkMsU0FBTyxPQUZNO0FBR2JDLFdBQVM7QUFISSxDQUFmO0FBS0EsSUFBTUMscUNBQXFDLEdBQTNDO0FBQ0EsSUFBTUMsc0JBQXNCLEtBQTVCO0FBRUE7Ozs7QUFHQSxJQUFJQyxNQUFNLFNBQU5BLEdBQU0sR0FBTTtBQUNkLFNBQU8sSUFBSUMsSUFBSixHQUFXQyxPQUFYLEVBQVA7QUFDRCxDQUZEO0FBSUE7Ozs7OztBQUlBLElBQUlDLGVBQWUsU0FBZkEsWUFBZSxDQUFDQyxJQUFELEVBQVU7QUFDM0IsU0FBTyxDQUFDSixRQUFRSSxJ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dXJjZXNDb250ZW50IjpbIiBcdC8vIFRoZSBtb2R1bGUgY2FjaGVcbiBcdHZhciBpbnN0YWxsZWRNb2R1bGVzID0ge307XG5cbiBcdC8vIFRoZSByZXF1aXJlIGZ1bmN0aW9uXG4gXHRmdW5jdGlvbiBfX3dlYnBhY2tfcmVxdWlyZV9fKG1vZHVsZUlkKSB7XG5cbiBcdFx0Ly8gQ2hlY2sgaWYgbW9kdWxlIGlzIGluIGNhY2hlXG4gXHRcdGlmKGluc3RhbGxlZE1vZHVsZXNbbW9kdWxlSWRdKSB7XG4gXHRcdFx0cmV0dXJuIGluc3RhbGxlZE1vZHVsZXNbbW9kdWxlSWRdLmV4cG9ydHM7XG4gXHRcdH1cbiBcdFx0Ly8gQ3JlYXRlIGEgbmV3IG1vZHVsZSAoYW5kIHB1dCBpdCBpbnRvIHRoZSBjYWNoZSlcbiBcdFx0dmFyIG1vZHVsZSA9IGluc3RhbGxlZE1vZHVsZXNbbW9kdWxlSWRdID0ge1xuIFx0XHRcdGk6IG1vZHVsZUlkLFxuIFx0XHRcdGw6IGZhbHNlLFxuIFx0XHRcdGV4cG9ydHM6IHt9XG4gXHRcdH07XG5cbiBcdFx0Ly8gRXhlY3V0ZSB0aGUgbW9kdWxlIGZ1bmN0aW9uXG4gXHRcdG1vZHVsZXNbbW9kdWxlSWRdLmNhbGwobW9kdWxlLmV4cG9ydHMsIG1vZHVsZSwgbW9kdWxlLmV4cG9ydHMsIF9fd2VicGFja19yZXF1aXJlX18pO1xuXG4gXHRcdC8vIEZsYWcgdGhlIG1vZHVsZSBhcyBsb2FkZWRcbiBcdFx0bW9kdWxlLmwgPSB0cnVlO1xuXG4gXHRcdC8vIFJldHVybiB0aGUgZXhwb3J0cyBvZiB0aGUgbW9kdWxlXG4gXHRcdHJldHVybiBtb2R1bGUuZXhwb3J0cztcbiBcdH1cblxuXG4gXHQvLyBleHBvc2UgdGhlIG1vZHVsZXMgb2JqZWN0IChfX3dlYnBhY2tfbW9kdWxlc19fKVxuIFx0X193ZWJwYWNrX3JlcXVpcmVfXy5tID0gbW9kdWxlcztcblxuIFx0Ly8gZXhwb3NlIHRoZSBtb2R1bGUgY2FjaGVcbiBcdF9fd2VicGFja19yZXF1aXJlX18uYyA9IGluc3RhbGxlZE1vZHVsZXM7XG5cbiBcdC8vIGRlZmluZSBnZXR0ZXIgZnVuY3Rpb24gZm9yIGhhcm1vbnkgZXhwb3J0c1xuIFx0X193ZWJwYWNrX3JlcXVpcmVfXy5kID0gZnVuY3Rpb24oZXhwb3J0cywgbmFtZSwgZ2V0dGVyKSB7XG4gXHRcdGlmKCFfX3dlYnBhY2tfcmVxdWlyZV9fLm8oZXhwb3J0cywgbmFtZSkpIHtcbiBcdFx0XHRPYmplY3QuZGVmaW5lUHJvcGVydHkoZXhwb3J0cywgbmFtZSwge1xuIFx0XHRcdFx0Y29uZmlndXJhYmxlOiBmYWxzZSxcbiBcdFx0XHRcdGVudW1lcmFibGU6IHRydWUsXG4gXHRcdFx0XHRnZXQ6IGdldHRlclxuIFx0XHRcdH0pO1xuIFx0XHR9XG4gXHR9O1xuXG4gXHQvLyBnZXREZWZhdWx0RXhwb3J0IGZ1bmN0aW9uIGZvciBjb21wYXRpYmlsaXR5IHdpdGggbm9uLWhhcm1vbnkgbW9kdWxlc1xuIFx0X193ZWJwYWNrX3JlcXVpcmVfXy5uID0gZnVuY3Rpb24obW9kdWxlKSB7XG4gXHRcdHZhciBnZXR0ZXIgPSBtb2R1bGUgJiYgbW9kdWxlLl9fZXNNb2R1bGUgP1xuIFx0XHRcdGZ1bmN0aW9uIGdldERlZmF1bHQoKSB7IHJldHVybiBtb2R1bGVbJ2RlZmF1bHQnXTsgfSA6XG4gXHRcdFx0ZnVuY3Rpb24gZ2V0TW9kdWxlRXhwb3J0cygpIHsgcmV0dXJuIG1vZHVsZTsgfTtcbiBcdFx0X193ZWJwYWNrX3JlcXVpcmVfXy5kKGdldHRlciwgJ2EnLCBnZXR0ZXIpO1xuIFx0XHRyZXR1cm4gZ2V0dGVyO1xuIFx0fTtcblxuIFx0Ly8gT2JqZWN0LnByb3RvdHlwZS5oYXNPd25Qcm9wZXJ0eS5jYWxsXG4gXHRfX3dlYnBhY2tfcmVxdWlyZV9fLm8gPSBmdW5jdGlvbihvYmplY3QsIHByb3BlcnR5KSB7IHJldHVybiBPYmplY3QucHJvdG90eXBlLmhhc093blByb3BlcnR5LmNhbGwob2JqZWN0LCBwcm9wZXJ0eSk7IH07XG5cbiBcdC8vIF9fd2VicGFja19wdWJsaWNfcGF0aF9fXG4gXHRfX3dlYnBhY2tfcmVxdWlyZV9fLnAgPSBcIi9kaXN0XCI7XG5cbiBcdC8vIExvYWQgZW50cnkgbW9kdWxlIGFuZCByZXR1cm4gZXhwb3J0c1xuIFx0cmV0dXJuIF9fd2VicGFja19yZXF1aXJlX18oX193ZWJwYWNrX3JlcXVpcmVfXy5zID0gMCk7XG5cblxuXG4vLyBXRUJQQUNLIEZPT1RFUiAvL1xuLy8gd2VicGFjay9ib290c3RyYXAgNjJjY2I0MDUzN2Y2N2JmMmY0NDciLCJ2YXIgY29udGV4dCA9IHJlcXVpcmUuY29udGV4dCgnLi4vaW1hZ2VzJywgdHJ1ZSkgLy8gTmVjZXNzYXJ5IGZvciBhc3NldCBoZWxwZXIuICBIYXMgd2VicGFjayBpbXBvcnQgYWxsIHRoZSBpbWFnZXMgcmVnYXJkbGVzcyBvZiB1c2UgaW4ganMvY3NzLlxudmFyIGNvbnRleHQgPSByZXF1aXJlLmNvbnRleHQoJy4uL2ZvbnRzJywgdHJ1ZSkgLy8gTmVjZXNzYXJ5IGZvciBhc3NldCBoZWxwZXIuICBIYXMgd2VicGFjayBpbXBvcnQgYWxsIHRoZSBmb250cyByZWdhcmRsZXNzIG9mIHVzZSBpbiBqcy9jc3MuXG5pbXBvcnQgQW1iZXIgZnJvbSAnYW1iZXInXG5cblxuXG4vLyBXRUJQQUNLIEZPT1RFUiAvL1xuLy8gLi9zcmMvYXNzZXRzL2phdmFzY3JpcHRzL21haW4uanMiLCJjb25zdCBFVkVOVFMgPSB7XG4gIGpvaW46ICdqb2luJyxcbiAgbGVhdmU6ICdsZWF2ZScsXG4gIG1lc3NhZ2U6ICdtZXNzYWdlJ1xufVxuY29uc3QgU1RBTEVfQ09OTkVDVElPTl9USFJFU0hPTERfU0VDT05EUyA9IDEwMFxuY29uc3QgU09DS0VUX1BPTExJTkdfUkFURSA9IDEwMDAwXG5cbi8qKlxuICogUmV0dXJucyBhIG51bWVyaWMgdmFsdWUgZm9yIHRoZSBjdXJyZW50IHRpbWVcbiAqL1xubGV0IG5vdyA9ICgpID0+IHtcbiAgcmV0dXJuIG5ldyBEYXRlKCkuZ2V0VGltZSgpXG59XG5cbi8qKlxuICogUmV0dXJucyB0aGUgZGlmZmVyZW5jZSBiZXR3ZWVuIHRoZSBjdXJyZW50IHRpbWUgYW5kIHBhc3NlZCBgdGltZWAgaW4gc2Vjb25kc1xuICogQHBhcmFtIHtOdW1iZXJ8RGF0ZX0gdGltZSAtIEEgbnVtZXJpYyB0aW1lIG9yIGRhdGUgb2JqZWN0XG4gKi9cbmxldCBzZWNvbmRzU2luY2UgPSAodGltZSkgPT4ge1xuICByZXR1cm4gKG5vdygpIC0gdGltZSkgLyAxMDAwXG59XG5cbi8qKlxuICogQ2xhc3MgZm9yIGNoYW5uZWwgcmVsYXRlZCBmdW5jdGlvbnMgKGpvaW5pbmcsIGxlYXZpbmcsIHN1YnNjcmliaW5nIGFuZCBzZW5kaW5nIG1lc3NhZ2VzKVxuICovXG5leHBvcnQgY2xhc3MgQ2hhbm5lbCB7XG4gIC8qKlxuICAgKiBAcGFyYW0ge1N0cmluZ30gdG9waWMgLSB0b3BpYyB0byBzdWJzY3JpYmUgdG9cbiAgICogQHBhcmFtIHtTb2NrZXR9IHNvY2tldCAtIEEgU29ja2V0IGluc3RhbmNlXG4gICAqL1xuICBjb25zdHJ1Y3Rvcih0b3BpYywgc29ja2V0KSB7XG4gICAgdGhpcy50b3BpYyA9IHRvcGljXG4gICAgdGhpcy5zb2NrZXQgPSBzb2NrZXRcbiAgICB0aGlzLm9uTWVzc2FnZUhhbmRsZXJzID0gW11cbiAgfVxuXG4gIC8qKlxuICAgKiBKb2luIGEgY2hhbm5lbCwgc3Vic2NyaWJlIHRvIGFsbCBjaGFubmVscyBtZXNzYWdlc1xuICAgKi9cbiAgam9pbigpIHtcbiAgICB0aGlzLnNvY2tldC53cy5zZW5kKEpTT04uc3RyaW5naWZ5KHsgZXZlbnQ6IEVWRU5UUy5qb2luLCB0b3BpYzogdGhpcy50b3BpYyB9KSlcbiAgfVxuXG4gIC8qKlxuICAgKiBMZWF2ZSBhIGNoYW5uZWwsIHN0b3Agc3Vic2NyaWJpbmcgdG8gY2hhbm5lbCBtZXNzYWdlc1xuICAgKi9cbiAgbGVhdmUoKSB7XG4gICAgdGhpcy5zb2NrZXQud3Muc2VuZChKU09OLnN0cmluZ2lmeSh7IGV2ZW50OiBFVkVOVFMubGVhdmUsIHRvcGljOiB0aGlzLnRvcGljIH0pKVxuICB9XG5cbiAgLyoqXG4gICAqIENhbGxzIGFsbCBtZXNzYWdlIGhhbmRsZXJzIHdpdGggYSBtYXRjaGluZyBzdWJqZWN0XG4gICAqL1xuICBoYW5kbGVNZXNzYWdlKG1zZykge1xuICAgIHRoaXMub25NZXNzYWdlSGFuZGxlcnMuZm9yRWFjaCgoaGFuZGxlcikgPT4ge1xuICAgICAgaWYgKGhhbmRsZXIuc3ViamVjdCA9PT0gbXNnLnN1YmplY3QpIGhhbmRsZXIuY2FsbGJhY2sobXNnLnBheWxvYWQpXG4gICAgfSlcbiAgfVxuXG4gIC8qKlxuICAgKiBTdWJzY3JpYmUgdG8gYSBjaGFubmVsIHN1YmplY3RcbiAgICogQHBhcmFtIHtTdHJpbmd9IHN1YmplY3QgLSBzdWJqZWN0IHRvIGxpc3RlbiBmb3I6IGBtc2c6bmV3YFxuICAgKiBAcGFyYW0ge2Z1bmN0aW9ufSBjYWxsYmFjayAtIGNhbGxiYWNrIGZ1bmN0aW9uIHdoZW4gYSBuZXcgbWVzc2FnZSBhcnJpdmVzXG4gICAqL1xuICBvbihzdWJqZWN0LCBjYWxsYmFjaykge1xuICAgIHRoaXMub25NZXNzYWdlSGFuZGxlcnMucHVzaCh7IHN1YmplY3Q6IHN1YmplY3QsIGNhbGxiYWNrOiBjYWxsYmFjayB9KVxuICB9XG5cbiAgLyoqXG4gICAqIFNlbmQgYSBuZXcgbWVzc2FnZSB0byB0aGUgY2hhbm5lbFxuICAgKiBAcGFyYW0ge1N0cmluZ30gc3ViamVjdCAtIHN1YmplY3QgdG8gc2VuZCBtZXNzYWdlIHRvOiBgbXNnOm5ld2BcbiAgICogQHBhcmFtIHtPYmplY3R9IHBheWxvYWQgLSBwYXlsb2FkIG9iamVjdDogYHttZXNzYWdlOiAnaGVsbG8nfWBcbiAgICovXG4gIHB1c2goc3ViamVjdCwgcGF5bG9hZCkge1xuICAgIHRoaXMuc29ja2V0LndzLnNlbmQoSlNPTi5zdHJpbmdpZnkoeyBldmVudDogRVZFTlRTLm1lc3NhZ2UsIHRvcGljOiB0aGlzLnRvcGljLCBzdWJqZWN0OiBzdWJqZWN0LCBwYXlsb2FkOiBwYXlsb2FkIH0pKVxuICB9XG59XG5cbi8qKlxuICogQ2xhc3MgZm9yIG1haW50YWluaW5nIGNvbm5lY3Rpb24gd2l0aCBzZXJ2ZXIgYW5kIG1haW50YWluaW5nIGNoYW5uZWxzIGxpc3RcbiAqL1xuZXhwb3J0IGNsYXNzIFNvY2tldCB7XG4gIC8qKlxuICAgKiBAcGFyYW0ge1N0cmluZ30gZW5kcG9pbnQgLSBXZWJzb2NrZXQgZW5kcG9udCB1c2VkIGluIHJvdXRlcy5jciBmaWxlXG4gICAqL1xuICBjb25zdHJ1Y3RvcihlbmRwb2ludCkge1xuICAgIHRoaXMuZW5kcG9pbnQgPSBlbmRwb2ludFxuICAgIHRoaXMud3MgPSBudWxsXG4gICAgdGhpcy5jaGFubmVscyA9IFtdXG4gICAgdGhpcy5sYXN0UGluZyA9IG5vdygpXG4gICAgdGhpcy5yZWNvbm5lY3RUcmllcyA9IDBcbiAgICB0aGlzLmF0dGVtcHRSZWNvbm5lY3QgPSB0cnVlXG4gIH1cblxuICAvKipcbiAgICogUmV0dXJucyB3aGV0aGVyIG9yIG5vdCB0aGUgbGFzdCByZWNlaXZlZCBwaW5nIGhhcyBiZWVuIHBhc3QgdGhlIHRocmVzaG9sZFxuICAgKi9cbiAgX2Nvbm5lY3Rpb25Jc1N0YWxlKCkge1xuICAgIHJldHVybiBzZWNvbmRzU2luY2UodGhpcy5sYXN0UGluZykgPiBTVEFMRV9DT05ORUNUSU9OX1RIUkVTSE9MRF9TRUNPTkRTXG4gIH1cblxuICAvKipcbiAgICogVHJpZXMgdG8gcmVjb25uZWN0IHRvIHRoZSB3ZWJzb2NrZXQgc2VydmVyIHVzaW5nIGEgcmVjdXJzaXZlIHRpbWVvdXRcbiAgICovXG4gIF9yZWNvbm5lY3QoKSB7XG4gICAgY2xlYXJUaW1lb3V0KHRoaXMucmVjb25uZWN0VGltZW91dClcbiAgICB0aGlzLnJlY29ubmVjdFRpbWVvdXQgPSBzZXRUaW1lb3V0KCgpID0+IHtcbiAgICAgIHRoaXMucmVjb25uZWN0VHJpZXMrK1xuICAgICAgdGhpcy5jb25uZWN0KHRoaXMucGFyYW1zKVxuICAgICAgdGhpcy5fcmVjb25uZWN0KClcbiAgICB9LCB0aGlzLl9yZWNvbm5lY3RJbnRlcnZhbCgpKVxuICB9XG5cbiAgLyoqXG4gICAqIFJldHVybnMgYW4gaW5jcmVtZW50aW5nIHRpbWVvdXQgaW50ZXJ2YWwgYmFzZWQgYXJvdW5kIHRoZSBudW1iZXIgb2YgcmVjb25uZWN0aW9uIHJldHJpZXNcbiAgICovXG4gIF9yZWNvbm5lY3RJbnRlcnZhbCgpIHtcbiAgICByZXR1cm4gWzEwMDAsIDIwMDAsIDUwMDAsIDEwMDAwXVt0aGlzLnJlY29ubmVjdFRyaWVzXSB8fCAxMDAwMFxuICB9XG5cbiAgLyoqXG4gICAqIFNldHMgYSByZWN1cnNpdmUgdGltZW91dCB0byBjaGVjayBpZiB0aGUgY29ubmVjdGlvbiBpcyBzdGFsZVxuICAgKi9cbiAgX3BvbGwoKSB7XG4gICAgdGhpcy5wb2xsaW5nVGltZW91dCA9IHNldFRpbWVvdXQoKCkgPT4ge1xuICAgICAgaWYgKHRoaXMuX2Nvbm5lY3Rpb25Jc1N0YWxlKCkpIHtcbiAgICAgICAgdGhpcy5fcmVjb25uZWN0KClcbiAgICAgIH0gZWxzZSB7XG4gICAgICAgIHRoaXMuX3BvbGwoKVxuICAgICAgfVxuICAgIH0sIFNPQ0tFVF9QT0xMSU5HX1JBVEUpXG4gIH1cblxuICAvKipcbiAgICogQ2xlYXIgcG9sbGluZyB0aW1lb3V0IGFuZCBzdGFydCBwb2xsaW5nXG4gICAqL1xuICBfc3RhcnRQb2xsaW5nKCkge1xuICAgIGNsZWFyVGltZW91dCh0aGlzLnBvbGxpbmdUaW1lb3V0KVxuICAgIHRoaXMuX3BvbGwoKVxuICB9XG5cbiAgLyoqXG4gICAqIFNldHMgYGxhc3RQaW5nYCB0byB0aGUgY3VyZW50IHRpbWVcbiAgICovXG4gIF9oYW5kbGVQaW5nKCkge1xuICAgIHRoaXMubGFzdFBpbmcgPSBub3coKVxuICB9XG5cbiAgLyoqXG4gICAqIENsZWFycyByZWNvbm5lY3QgdGltZW91dCwgcmVzZXRzIHZhcmlhYmxlcyBhbiBzdGFydHMgcG9sbGluZ1xuICAgKi9cbiAgX3Jlc2V0KCkge1xuICAgIGNsZWFyVGltZW91dCh0aGlzLnJlY29ubmVjdFRpbWVvdXQpXG4gICAgdGhpcy5yZWNvbm5lY3RUcmllcyA9IDBcbiAgICB0aGlzLmF0dGVtcHRSZWNvbm5lY3QgPSB0cnVlXG4gICAgdGhpcy5fc3RhcnRQb2xsaW5nKClcbiAgfVxuXG4gIC8qKlxuICAgKiBDb25uZWN0IHRoZSBzb2NrZXQgdG8gdGhlIHNlcnZlciwgYW5kIGJpbmRzIHRvIG5hdGl2ZSB3cyBmdW5jdGlvbnNcbiAgICogQHBhcmFtIHtPYmplY3R9IHBhcmFtcyAtIE9wdGlvbmFsIHBhcmFtZXRlcnNcbiAgICogQHBhcmFtIHtTdHJpbmd9IHBhcmFtcy5sb2NhdGlvbiAtIEhvc3RuYW1lIHRvIGNvbm5lY3QgdG8sIGRlZmF1bHRzIHRvIGB3aW5kb3cubG9jYXRpb24uaG9zdG5hbWVgXG4gICAqIEBwYXJhbSB7U3RyaW5nfSBwYXJtYXMucG9ydCAtIFBvcnQgdG8gY29ubmVjdCB0bywgZGVmYXVsdHMgdG8gYHdpbmRvdy5sb2NhdGlvbi5wb3J0YFxuICAgKiBAcGFyYW0ge1N0cmluZ30gcGFyYW1zLnByb3RvY29sIC0gUHJvdG9jb2wgdG8gdXNlLCBlaXRoZXIgJ3dzcycgb3IgJ3dzJ1xuICAgKi9cbiAgY29ubmVjdChwYXJhbXMpIHtcbiAgICB0aGlzLnBhcmFtcyA9IHBhcmFtc1xuXG4gICAgbGV0IG9wdHMgPSB7XG4gICAgICBsb2NhdGlvbjogd2luZG93LmxvY2F0aW9uLmhvc3RuYW1lLFxuICAgICAgcG9ydDogd2luZG93LmxvY2F0aW9uLnBvcnQsXG4gICAgICBwcm90b2NvbDogd2luZG93LmxvY2F0aW9uLnByb3RvY29sID09PSAnaHR0cHM6JyA/ICd3c3M6JyA6ICd3czonLFxuICAgIH1cblxuICAgIGlmIChwYXJhbXMpIE9iamVjdC5hc3NpZ24ob3B0cywgcGFyYW1zKVxuICAgIGlmIChvcHRzLnBvcnQpIG9wdHMubG9jYXRpb24gKz0gYDoke29wdHMucG9ydH1gXG5cbiAgICByZXR1cm4gbmV3IFByb21pc2UoKHJlc29sdmUsIHJlamVjdCkgPT4ge1xuICAgICAgdGhpcy53cyA9IG5ldyBXZWJTb2NrZXQoYCR7b3B0cy5wcm90b2NvbH0vLyR7b3B0cy5sb2NhdGlvbn0ke3RoaXMuZW5kcG9pbnR9YClcbiAgICAgIHRoaXMud3Mub25tZXNzYWdlID0gKG1zZykgPT4geyB0aGlzLmhhbmRsZU1lc3NhZ2UobXNnKSB9XG4gICAgICB0aGlzLndzLm9uY2xvc2UgPSAoKSA9PiB7XG4gICAgICAgIGlmICh0aGlzLmF0dGVtcHRSZWNvbm5lY3QpIHRoaXMuX3JlY29ubmVjdCgpXG4gICAgICB9XG4gICAgICB0aGlzLndzLm9ub3BlbiA9ICgpID0+IHtcbiAgICAgICAgdGhpcy5fcmVzZXQoKVxuICAgICAgICByZXNvbHZlKClcbiAgICAgIH1cbiAgICB9KVxuICB9XG5cbiAgLyoqXG4gICAqIENsb3NlcyB0aGUgc29ja2V0IGNvbm5lY3Rpb24gcGVybWFuZW50bHlcbiAgICovXG4gIGRpc2Nvbm5lY3QoKSB7XG4gICAgdGhpcy5hdHRlbXB0UmVjb25uZWN0ID0gZmFsc2VcbiAgICBjbGVhclRpbWVvdXQodGhpcy5wb2xsaW5nVGltZW91dClcbiAgICBjbGVhclRpbWVvdXQodGhpcy5yZWNvbm5lY3RUaW1lb3V0KVxuICAgIHRoaXMud3MuY2xvc2UoKVxuICB9XG5cbiAgLyoqXG4gICAqIEFkZHMgYSBuZXcgY2hhbm5lbCB0byB0aGUgc29ja2V0IGNoYW5uZWxzIGxpc3RcbiAgICogQHBhcmFtIHtTdHJpbmd9IHRvcGljIC0gVG9waWMgZm9yIHRoZSBjaGFubmVsOiBgY2hhdF9yb29tOjEyM2BcbiAgICovXG4gIGNoYW5uZWwodG9waWMpIHtcbiAgICBsZXQgY2hhbm5lbCA9IG5ldyBDaGFubmVsKHRvcGljLCB0aGlzKVxuICAgIHRoaXMuY2hhbm5lbHMucHVzaChjaGFubmVsKVxuICAgIHJldHVybiBjaGFubmVsXG4gIH1cblxuICAvKipcbiAgICogTWVzc2FnZSBoYW5kbGVyIGZvciBtZXNzYWdlcyByZWNlaXZlZFxuICAgKiBAcGFyYW0ge01lc3NhZ2VFdmVudH0gbXNnIC0gTWVzc2FnZSByZWNlaXZlZCBmcm9tIHdzXG4gICAqL1xuICBoYW5kbGVNZXNzYWdlKG1zZykge1xuICAgIGlmIChtc2cuZGF0YSA9PT0gXCJwaW5nXCIpIHJldHVybiB0aGlzLl9oYW5kbGVQaW5nKClcblxuICAgIGxldCBwYXJzZWRfbXNnID0gSlNPTi5wYXJzZShtc2cuZGF0YSlcbiAgICB0aGlzLmNoYW5uZWxzLmZvckVhY2goKGNoYW5uZWwpID0+IHtcbiAgICAgIGlmIChjaGFubmVsLnRvcGljID09PSBwYXJzZWRfbXNnLnRvcGljKSBjaGFubmVsLmhhbmRsZU1lc3NhZ2UocGFyc2VkX21zZylcbiAgICB9KVxuICB9XG59XG5cbm1vZHVsZS5leHBvcnRzID0ge1xuICBTb2NrZXQ6IFNvY2tldFxufVxuXG5cblxuLy8gV0VCUEFDSyBGT09URVIgLy9cbi8vIC4uL2FtYmVyL2Fzc2V0cy9qcy9hbWJlci5qcyIsInZhciBtYXAgPSB7XG5cdFwiLi9sb2dvLnBuZ1wiOiAzXG59O1xuZnVuY3Rpb24gd2VicGFja0NvbnRleHQocmVxKSB7XG5cdHJldHVybiBfX3dlYnBhY2tfcmVxdWlyZV9fKHdlYnBhY2tDb250ZXh0UmVzb2x2ZShyZXEpKTtcbn07XG5mdW5jdGlvbiB3ZWJwYWNrQ29udGV4dFJlc29sdmUocmVxKSB7XG5cdHZhciBpZCA9IG1hcFtyZXFdO1xuXHRpZighKGlkICsgMSkpIC8vIGNoZWNrIGZvciBudW1iZXIgb3Igc3RyaW5nXG5cdFx0dGhyb3cgbmV3IEVycm9yKFwiQ2Fubm90IGZpbmQgbW9kdWxlICdcIiArIHJlcSArIFwiJy5cIik7XG5cdHJldHVybiBpZDtcbn07XG53ZWJwYWNrQ29udGV4dC5rZXlzID0gZnVuY3Rpb24gd2VicGFja0NvbnRleHRLZXlzKCkge1xuXHRyZXR1cm4gT2JqZWN0LmtleXMobWFwKTtcbn07XG53ZWJwYWNrQ29udGV4dC5yZXNvbHZlID0gd2VicGFja0NvbnRleHRSZXNvbHZlO1xubW9kdWxlLmV4cG9ydHMgPSB3ZWJwYWNrQ29udGV4dDtcbndlYnBhY2tDb250ZXh0LmlkID0gMjtcblxuXG4vLy8vLy8vLy8vLy8vLy8vLy9cbi8vIFdFQlBBQ0sgRk9PVEVSXG4vLyAuL3NyYy9hc3NldHMvaW1hZ2VzIF5cXC5cXC8uKiRcbi8vIG1vZHVsZSBpZCA9IDJcbi8vIG1vZHVsZSBjaHVua3MgPSAwIiwibW9kdWxlLmV4cG9ydHMgPSBfX3dlYnBhY2tfcHVibGljX3BhdGhfXyArIFwiaW1hZ2VzL2xvZ28tYzMyMWEwNWRlYjVlNmUwOTdhNDBlY2ZmYmY5MGRlNDUucG5nXCI7XG5cblxuLy8vLy8vLy8vLy8vLy8vLy8vXG4vLyBXRUJQQUNLIEZPT1RFUlxuLy8gLi9zcmMvYXNzZXRzL2ltYWdlcy9sb2dvLnBuZ1xuLy8gbW9kdWxlIGlkID0gM1xuLy8gbW9kdWxlIGNodW5rcyA9IDAiLCJmdW5jdGlvbiB3ZWJwYWNrRW1wdHlDb250ZXh0KHJlcSkge1xuXHR0aHJvdyBuZXcgRXJyb3IoXCJDYW5ub3QgZmluZCBtb2R1bGUgJ1wiICsgcmVxICsgXCInLlwiKTtcbn1cbndlYnBhY2tFbXB0eUNvbnRleHQua2V5cyA9IGZ1bmN0aW9uKCkgeyByZXR1cm4gW107IH07XG53ZWJwYWNrRW1wdHlDb250ZXh0LnJlc29sdmUgPSB3ZWJwYWNrRW1wdHlDb250ZXh0O1xubW9kdWxlLmV4cG9ydHMgPSB3ZWJwYWNrRW1wdHlDb250ZXh0O1xud2VicGFja0VtcHR5Q29udGV4dC5pZCA9IDQ7XG5cblxuLy8vLy8vLy8vLy8vLy8vLy8vXG4vLyBXRUJQQUNLIEZPT1RFUlxuLy8gLi9zcmMvYXNzZXRzL2ZvbnRzIF5cXC5cXC8uKiRcbi8vIG1vZHVsZSBpZCA9IDRcbi8vIG1vZHVsZSBjaHVua3MgPSAwIl0sInNvdXJjZVJvb3QiOiIifQ==