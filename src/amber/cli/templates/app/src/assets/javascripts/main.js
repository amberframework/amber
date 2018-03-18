var context = require.context('../images', true) // Necessary for asset helper.  Has webpack import all the images regardless of use in js/css.
var context = require.context('../fonts', true) // Necessary for asset helper.  Has webpack import all the fonts regardless of use in js/css.
import Amber from 'amber'

if (!Date.prototype.toGranite) {
  (function() {

    function pad(number) {
      if (number < 10) {
        return '0' + number;
      }
      return number;
    }

    Date.prototype.toGranite = function() {
      return this.getUTCFullYear() +
        '-' + pad(this.getUTCMonth() + 1) +
        '-' + pad(this.getUTCDate()) +
        ' ' + pad(this.getUTCHours()) +
        ':' + pad(this.getUTCMinutes()) +
        ':' + pad(this.getUTCSeconds())  ;
    };

  }());
}
