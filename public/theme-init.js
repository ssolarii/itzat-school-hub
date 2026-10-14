(function () {
  var valid = ['light', 'dark', 'system'];
  function read() {
    var match = document.cookie.match(/(?:^|;\s*)school-theme=(light|dark|system)(?:;|$)/);
    return match ? match[1] : null;
  }
  function apply(value) {
    value = valid.indexOf(value) >= 0 ? value : 'system';
    var dark = value === 'dark' || value === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches;
    document.documentElement.dataset.accountTheme = dark ? 'dark' : 'light';
    document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
  }
  function save(value) {
    if (valid.indexOf(value) < 0) return;
    var path = location.pathname.slice(0, location.pathname.lastIndexOf('/') + 1) || '/';
    document.cookie = 'school-theme=' + value + '; Path=' + path + '; Max-Age=31536000; SameSite=Lax' + (location.protocol === 'https:' ? '; Secure' : '');
    apply(value);
  }
  window.scheduleTheme = { read: read, apply: apply, save: save };
  apply(read() || 'system');
})();
