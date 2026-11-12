// Contact form: progressive enhancement over a plain POST to /api/contact.
// Without JavaScript the form still posts and the Worker redirects to /contact/sent/.
(function () {
  "use strict";
  var form = document.getElementById("contact-form");
  if (!form) return;
  var started = document.getElementById("started");
  var status = document.getElementById("status");
  var send = document.getElementById("send");
  var FALLBACK = "Your message wasn't sent. Please try again, or e-mail support@tally-app.dev.";
  var MESSAGES = {
    invalid: "Please check your e-mail address and message, then try again.",
    unavailable: "The contact form isn't available right now. Please e-mail support@tally-app.dev."
  };
  if (started) started.value = String(Date.now());

  function show(kind, text) {
    status.className = "status " + kind;
    status.textContent = text;
  }

  // A plain (non-fetch) form post that failed is redirected back here with ?error=...
  var error = new URLSearchParams(window.location.search).get("error");
  if (error) show("err", MESSAGES[error] || FALLBACK);

  form.addEventListener("submit", function (event) {
    if (!window.fetch || !window.FormData) return; // let the browser post it
    event.preventDefault();
    send.disabled = true;
    show("", "");
    var fields = {};
    new FormData(form).forEach(function (value, key) { fields[key] = String(value); });
    fetch(form.action, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Accept": "application/json" },
      body: JSON.stringify(fields)
    }).then(function (response) {
      return response.json().catch(function () { return { ok: false }; }).then(function (body) {
        if (response.ok && body.ok) {
          form.reset();
          if (started) started.value = String(Date.now());
          show("ok", "Thanks, your message is on its way. We'll reply to the e-mail address you gave.");
        } else {
          show("err", MESSAGES[body.error] || FALLBACK);
        }
      });
    }).catch(function () {
      show("err", FALLBACK);
    }).then(function () {
      send.disabled = false;
    });
  });
})();
