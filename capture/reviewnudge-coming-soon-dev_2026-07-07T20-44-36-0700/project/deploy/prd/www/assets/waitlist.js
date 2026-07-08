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

  function getEndpoint() {
    return String(window.REVIEWNUDGE_WAITLIST_ENDPOINT || "").trim();
  }

  function endpointIsConfigured(endpoint) {
    return Boolean(endpoint) && endpoint.indexOf("REPLACE_WITH_DEPLOYMENT_ID") === -1;
  }

  function buildPayload(email) {
    return {
      email: email,
      source: "reviewnudge-coming-soon",
      page: window.location.href,
      referrer: document.referrer || "",
      userAgent: window.navigator.userAgent || "",
      submittedAt: new Date().toISOString()
    };
  }

  form.addEventListener("submit", function (event) {
    event.preventDefault();

    var emailField = form.querySelector('input[name="email"]');
    var button = form.querySelector('button[type="submit"]');
    var endpoint = getEndpoint();
    var email = emailField ? emailField.value.trim() : "";

    if (!emailField || !emailField.checkValidity()) {
      if (emailField) emailField.reportValidity();
      setStatus("Please enter a valid email address.", "error");
      return;
    }

    if (!endpointIsConfigured(endpoint)) {
      setStatus("The waitlist is almost ready. Please check back shortly.", "error");
      return;
    }

    if (button) button.disabled = true;
    setStatus("Adding you to the early access list…");

    fetch(endpoint, {
      method: "POST",
      mode: "no-cors",
      headers: { "Content-Type": "text/plain;charset=utf-8" },
      body: JSON.stringify(buildPayload(email))
    })
      .then(function () {
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
