var webpack = require('webpack')

module.exports = {
  entry: './amber.js',
  output: {
    filename: 'amber.min.js',
    library: 'Amber'
  },
  module: {
    loaders: [
      {
        test: /\.js?$/,
        exclude: /node_modules/,
        loader: 'babel',
        query: {
          presets: ['es2015']
        }
      }
    ]
  },
  plugins: [
    new webpack.optimize.UglifyJsPlugin({
      compress: { warnings: false }
    })
  ]
};
