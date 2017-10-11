const webpack = require('webpack');
const merge = require('webpack-merge');
const common = require('./common.js');
const CssoWebpackPlugin = require('csso-webpack-plugin').default;

module.exports = merge(common, {
  plugins: [
    new webpack.optimize.UglifyJsPlugin({
      compress: { warnings: false }
    }),
    new CssoWebpackPlugin(),
  ]
});
