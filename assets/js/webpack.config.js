module.exports = {
  entry: './launch.js',
  output: {
    filename: 'launch.min.js',
    library: 'Launch',
    path: __dirname
  },
  optimization: {
    minimize: true
  },
  mode: 'production',
  module: {
    rules: [
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
  }
};
