const webpack = require('webpack');
const merge = require('webpack-merge');
const common = require('./common.js');

module.exports = merge(common, {
  devtool: 'cheap-module-source-map'
});
