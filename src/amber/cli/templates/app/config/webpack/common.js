const webpack = require('webpack');
const path = require('path');
const CleanWebpackPlugin = require('clean-webpack-plugin');
const ManifestPlugin = require('webpack-manifest-plugin');
const MiniCssExtractPlugin = require('mini-css-extract-plugin');

let config = {
  entry: {
    main: path.resolve(__dirname, 'entry.js')
  },
  output: {
    filename: '[name]-[hash].bundle.js',
    path: path.resolve(__dirname, '../../public/dist'),
    publicPath: '/dist/'
  },
  resolve: {
    alias: {
      amber: path.resolve(__dirname, '../../lib/amber/assets/js/amber.js')
    }
  },
  module: {
    rules: [
      {
        test: /\.(sass|scss|css)$/,
        exclude: /node_modules/,
        use: [
          MiniCssExtractPlugin.loader,
          'css-loader',
          'sass-loader'
        ]
      },
      {
        test: /\.js$/,
        exclude: /node_modules/,
        use: {
          loader: 'babel-loader',
          options: {
            presets: ['@babel/preset-env']
          }
        }
      }
    ]
  },
  plugins: [
    new CleanWebpackPlugin([path.resolve(__dirname, '../../public/dist')], {
      allowExternal: true
    }),
    new ManifestPlugin({
      fileName: '../../config/asset_manifest.json',
      publicPath: '/dist/',
      writeToFileEmit: true
    })
  ],
  // For more info about webpack logs see: https://webpack.js.org/configuration/stats/
  stats: 'errors-only'
};

module.exports = config;
