const webpack = require('webpack');
const merge = require('webpack-merge');
const common = require('./common.js');

module.exports = merge(common, {
  plugins: [
    new webpack.optimize.UglifyJsPlugin({
      compress: { warnings: false }
    })
  ]
});
