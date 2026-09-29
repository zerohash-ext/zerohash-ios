// Built-ins the web SDK bundles call without a fallback that WebKit only ships
// from iOS 15.4. Injected into every frame at document start, below 15.4 only.
(function () {
  function define(target, name, value) {
    if (target && typeof target[name] !== 'function') {
      Object.defineProperty(target, name, { value: value, writable: true, configurable: true, enumerable: false });
    }
  }

  function at(index) {
    var length = this.length >>> 0;
    var relative = Math.trunc(index) || 0;
    var k = relative >= 0 ? relative : length + relative;
    return k < 0 || k >= length ? undefined : this[k];
  }

  define(Array.prototype, 'at', at);
  define(String.prototype, 'at', at);
  if (typeof Int8Array === 'function') {
    define(Object.getPrototypeOf(Int8Array.prototype), 'at', at);
  }

  define(Object, 'hasOwn', function (object, key) {
    if (object == null) {
      throw new TypeError('Cannot convert undefined or null to object');
    }
    return Object.prototype.hasOwnProperty.call(Object(object), key);
  });

  if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') {
    define(Object.getPrototypeOf(crypto), 'randomUUID', function () {
      var bytes = crypto.getRandomValues(new Uint8Array(16));
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      var hex = [];
      for (var i = 0; i < 16; i++) {
        hex.push((bytes[i] + 0x100).toString(16).slice(1));
      }
      return (
        hex.slice(0, 4).join('') + '-' + hex.slice(4, 6).join('') + '-' + hex.slice(6, 8).join('') + '-' +
        hex.slice(8, 10).join('') + '-' + hex.slice(10, 16).join('')
      );
    });
  }
})();
