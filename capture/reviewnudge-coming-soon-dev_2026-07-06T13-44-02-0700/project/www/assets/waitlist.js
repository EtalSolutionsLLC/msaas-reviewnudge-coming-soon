(function () {
  "use strict";

  var form = document.querySelector("[data-waitlist-form]");
  var status = document.querySelector("[data-waitlist-status]");

  if (!form || !status) return;

  function setStatus(message, state) {
    status.textContent = message || "";
    if (state) {
      status.setAttribute("data-state", state);
    } else {
      status.removeAttribute("data-state");
    }
  }

  function endpointIsConfigured(endpoint) {
    return endpoint && endpoint.indexOf("REPLACE_WITH_DEPLOYMENT_ID") === -1;
  }

  form.addEventListener("submit", function (event) {
    event.preventDefault();

    var emailField = form.querySelector('input[name="email"]');
    var button = form.querySelector('button[type="submit"]');
    var endpoint = window.REVIEWNUDGE_WAITLIST_ENDPOINT || "";
    var email = emailField ? emailField.value.trim() : "";

    if (!emailField || !emailField.checkValidity()) {
      if (emailField) emailField.reportValidity();
      setStatus("Please enter a valid email address.", "error");
      return;
    }

    if (!endpointIsConfigured(endpoint)) {
      setStatus("Waitlist endpoint is not configured yet.", "error");
      return;
    }

    if (button) button.disabled = true;
    setStatus("Adding you to the early access list…");

    fetch(endpoint, {
      method: "POST",
      mode: "cors",
      headers: { "Content-Type": "text/plain;charset=utf-8" },
      body: JSON.stringify({
        email: email,
        source: "reviewnudge-coming-soon",
        page: window.location.href,
        submittedAt: new Date().toISOString()
      })
    })
      .then(function (response) {
        if (!response.ok) throw new Error("Waitlist request failed.");
        return response.json().catch(function () { return { ok: true }; });
      })
      .then(function (payload) {
        if (payload && payload.ok === false) {
          throw new Error(payload.error || "Waitlist request failed.");
        }
        form.reset();
        setStatus("You’re on the list. I’ll send a note when founding access opens.", "success");
      })
      .catch(function () {
        setStatus("Something went wrong. Please try again in a minute.", "error");
      })
      .finally(function () {
        if (button) button.disabled = false;
      });
  });
})();
