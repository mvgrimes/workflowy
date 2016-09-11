module.exports = function (interval) {
  function throttle(method) {
    var queue = [];
    var head = 0, tail = 0;
    var timerId = null;

    function timeoutExpired() {
      timerId = null;
      checkQueue();
    }

    function checkQueue() {
      if (head === tail) { return; }
      if (timerId === null) {
        // run now and set a time out to clear the timerId and check the queue
        var args = queue[head++];
        console.log(Date.now());
        method.apply(args[0], args.slice(1));
        timerId = setTimeout(timeoutExpired, interval);
      }
    };

    return function () {
      queue[tail++] = [].concat.apply([this],arguments);
      checkQueue();
    };
  }

  return function (request) {
    request.Request.prototype.init = throttle(request.Request.prototype.init);
  };
}


