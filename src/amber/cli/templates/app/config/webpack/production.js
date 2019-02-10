const webpack = require('webpack');
const merge = require('webpack-merge');
const common = require('./common.js');
const MiniCssExtractPlugin = require('mini-css-extract-plugin');

module.exports = merge(common, {
  output: {
    filename: '[name]-[hash].bundle.js',
  },
  mode: 'production',
  optimization: {
    minimize: true
  },
  module: {
    rules: [
      {
        test: /\.(png|svg|jpg|gif)$/,
        exclude: /node_modules/,
        use: [
          'file-loader?name=images/[name]-[hash].[ext]'
        ]
      },
      {
        test: /\.(woff|woff2|eot|ttf|otf)$/,
        exclude: /node_modules/,
        use: [
          'file-loader?name=[name]-[hash].[ext]'
        ]
      },
    ]
  },
  plugins: [
    new MiniCssExtractPlugin({
      filename: '[name]-[hash].bundle.css'
    })
  ]
});
