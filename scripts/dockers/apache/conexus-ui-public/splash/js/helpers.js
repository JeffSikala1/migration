var easeInOutCubic = function(t) {
  return t < 0.5 ? 4 * t * t * t : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1;
};
var position = function(start, end, elapsed, duration) {
  if (elapsed > duration) {
    return end;
  }
  return start + (end - start) * easeInOutCubic(elapsed / duration);
};
Vue.use({
  install: function() {
    Vue.prototype.$helpers = {
      smoothScroll: function(end, duration, callback) {
        duration = duration || 500;
        var start = window.pageYOffset;
        var clock = Date.now();
        var requestAnimationFrame = window.requestAnimationFrame ||
          window.mozRequestAnimationFrame || window.webkitRequestAnimationFrame ||
          function(fn) {
            setTimeout(fn, 15);
          };
        var step = function() {
          var elapsed = Date.now() - clock;
          window.scroll(0, position(start, end, elapsed, duration));
          if (duration > elapsed) {
            requestAnimationFrame(step);
            return;
          }
          if (typeof callback === 'function') {
            callback();
          }
        };
        step();
      }
    }
  }
})
