// Runs inside a classic page rendered with ?embed=1 and reports to the embedding window.
(function () {
  if (window.parent === window || window.__reactiveadminBridge) return;
  window.__reactiveadminBridge = true;

  var origin = window.location.origin;
  var root = "/" + (window.location.pathname.split("/")[1] || "");

  function post(message) {
    window.parent.postMessage(message, origin);
  }

  function clean(url) {
    url.searchParams.delete("embed");
    return url.pathname + url.search + url.hash;
  }

  function sendHeight() {
    post({ type: "reactiveadmin:resize", height: Math.ceil(document.body.getBoundingClientRect().height) });
  }

  function flashes() {
    return Array.prototype.map
      .call(document.querySelectorAll(".flashes .flash"), function (el) {
        var kind = /flash_(\w+)/.exec(el.className);
        return { type: kind ? kind[1] : "notice", message: el.textContent.trim() };
      })
      .filter(function (flash) {
        return flash.message;
      });
  }

  // Links to other admin pages are the embedding app's to route; links that act stay with rails-ujs.
  document.addEventListener("click", function (event) {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    var link = event.target.closest && event.target.closest("a[href]");
    if (!link || link.target === "_blank" || link.hasAttribute("download")) return;
    if (link.dataset.method || link.dataset.remote || link.dataset.confirm) return;

    var url = new URL(link.href, window.location.href);
    var samePage = url.pathname === window.location.pathname && url.search === window.location.search;
    if (url.origin !== origin || samePage || url.pathname.indexOf(root) !== 0) return;

    event.preventDefault();
    post({ type: "reactiveadmin:navigate", url: clean(url) });
  });

  // Submits stay in the embed, so the redirect that follows does too.
  document.addEventListener(
    "submit",
    function (event) {
      var form = event.target;
      if (!form || form.tagName !== "FORM") return;
      var action = form.getAttribute("action") || window.location.href;
      var url = new URL(action, window.location.href);
      if (url.origin !== origin) return;
      if ((form.getAttribute("method") || "get").toLowerCase() === "get") {
        if (!form.querySelector("input[name=embed]")) {
          var input = document.createElement("input");
          input.type = "hidden";
          input.name = "embed";
          input.value = "1";
          form.appendChild(input);
        }
      } else {
        url.searchParams.set("embed", "1");
        form.setAttribute("action", url.pathname + url.search + url.hash);
      }
    },
    true
  );

  function ready() {
    var found = flashes();
    if (found.length) post({ type: "reactiveadmin:flash", flashes: found });

    var navigation = window.performance && performance.getEntriesByType && performance.getEntriesByType("navigation")[0];
    if (navigation && navigation.redirectCount > 0) {
      post({ type: "reactiveadmin:navigate", url: clean(new URL(window.location.href)), redirected: true });
    }

    sendHeight();
    if (window.ResizeObserver) new ResizeObserver(sendHeight).observe(document.body);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", ready);
  else ready();
  window.addEventListener("load", sendHeight);
})();
