// Injected by the AppBuilder WebView shell: saves <a download> blob:/data: links
// to the Downloads folder through the AppBuilderAndroid bridge.
(function () {
  if (window.__appBuilderDownloads || !window.AppBuilderAndroid) return;
  window.__appBuilderDownloads = true;

  function save(href, name) {
    fetch(href)
      .then(function (response) { return response.blob(); })
      .then(function (blob) {
        var reader = new FileReader();
        reader.onloadend = function () {
          window.AppBuilderAndroid.saveDataUrl(String(reader.result), name || 'download', blob.type || '');
        };
        reader.readAsDataURL(blob);
      })
      .catch(function (error) { console.error('AppBuilder download failed', error); });
  }

  function intercept(anchor) {
    if (!anchor || !anchor.hasAttribute || !anchor.hasAttribute('download')) return false;
    var href = anchor.href || '';
    if (href.indexOf('blob:') !== 0 && href.indexOf('data:') !== 0) return false;
    save(href, anchor.getAttribute('download'));
    return true;
  }

  document.addEventListener('click', function (event) {
    var anchor = event.target && event.target.closest ? event.target.closest('a[download]') : null;
    if (intercept(anchor)) event.preventDefault();
  }, true);

  var originalClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    if (intercept(this)) return;
    return originalClick.apply(this, arguments);
  };
})();
