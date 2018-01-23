const webpack = require('webpack');
const merge = require('webpack-merge');
const common = require('./common.js');
const CompressionPlugin = require('compression-webpack-plugin')

module.exports = merge(common, {
  plugins: [
    new webpack.optimize.ModuleConcatenationPlugin(),
    new webpack.optimize.UglifyJsPlugin({
      parallel: true,
      cache: true,
      sourceMap: true,
      uglifyOptions: {
        ie8: false,
        ecma: 8,
        warnings: false,
        mangle: {
          safari10: true
        },
        compress: {
          warnings: false ,
          comparisons: false
        },
        output: {
          ascii_only: true
        }
      }
    }),
    new CompressionPlugin({
      asset: '[path].gz[query]',
      algorithm: 'gzip',
      test: /\.(js|css|html|json|ico|svg|eot|otf|ttf)$/
    })
  ],
  devtool: 'nosources-source-map',
  stats: 'normal'
});
