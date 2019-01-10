// This is the Webpack entrypoint and acts as a shim to load both the JavaScript
// and CSS source files into Webpack. It is mainly here to avoid requiring
// stylesheets from the javascripts asset directory and keep those concerns
// separate from each other within the src directory.
//
// This will be removed from Webpack 5 onward.
// See: https://github.com/webpack-contrib/mini-css-extract-plugin/issues/151

import '../../src/assets/javascripts/main.js';
import '../../src/assets/stylesheets/main.scss';
