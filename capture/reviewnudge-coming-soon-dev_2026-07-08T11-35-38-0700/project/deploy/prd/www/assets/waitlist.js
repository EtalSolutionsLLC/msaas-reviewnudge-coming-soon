(function () {
  "use strict";

  var form = document.querySelector("[data-waitlist-form]");
  var status = document.querySelector("[data-waitlist-status]");

  if (!form || !status) return;

  var VERIFY_ATTEMPTS = 10;
  var VERIFY_DELAY_MS = 1500;
  var JSONP_TIMEOUT_MS = 10000;

  function setStatus(message, state) {
    status.textContent = message || "";
    if (state) {
      status.setAttribute("data-state", state);
    } else {
      status.removeAttribute("data-state");
    }
  }

  function logEvent(eventName, traceId, details) {
    var payload = Object.assign(
      {
        service: "reviewnudge-waitlist",
        event: eventName,
        traceId: traceId || "",
        timestamp: new Date().toISOString()
      },
      details || {}
    );

    if (eventName.indexOf("failed") >= 0 || eventName.indexOf("error") >= 0) {
      window.console.error("[ReviewNudge waitlist]", payload);
    } else {
      window.console.info("[ReviewNudge waitlist]", payload);
    }
  }

  function getEndpoint() {
    return String(window.REVIEWNUDGE_WAITLIST_ENDPOINT || "").trim();
  }

  function endpointIsConfigured(endpoint) {
    return Boolean(endpoint) && endpoint.indexOf("REPLACE_WITH_DEPLOYMENT_ID") === -1;
  }

  function createTraceId() {
    if (window.crypto && typeof window.crypto.randomUUID === "function") {
      return window.crypto.randomUUID();
    }

    return "rn-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 14);
  }

  function buildPayload(email, traceId) {
    return {
      email: email,
      traceId: traceId,
      source: "reviewnudge-coming-soon",
      page: window.location.href,
      referrer: document.referrer || "",
      userAgent: window.navigator.userAgent || "",
      submittedAt: new Date().toISOString()
    };
  }

  function appendQuery(endpoint, params) {
    var separator = endpoint.indexOf("?") >= 0 ? "&" : "?";
    return endpoint + separator + new URLSearchParams(params).toString();
  }

  function requestStatus(endpoint, traceId) {
    return new Promise(function (resolve, reject) {
      var callbackName = "__reviewNudgeWaitlistStatus_" + traceId.replace(/[^A-Za-z0-9_$]/g, "").slice(0, 16) + "_" + Date.now();
      var script = document.createElement("script");
      var timeoutId;
      var finished = false;

      function cleanup() {
        if (timeoutId) window.clearTimeout(timeoutId);
        if (script.parentNode) script.parentNode.removeChild(script);
        try {
          delete window[callbackName];
        } catch (error) {
          window[callbackName] = undefined;
        }
      }

      function finish(handler, value) {
        if (finished) return;
        finished = true;
        cleanup();
        handler(value);
      }

      window[callbackName] = function (response) {
        finish(resolve, response || {});
      };

      script.async = true;
      script.src = appendQuery(endpoint, {
        action: "status",
        traceId: traceId,
        callback: callbackName,
        _: String(Date.now())
      });
      script.onerror = function () {
        finish(reject, new Error("The waitlist verification endpoint could not be reached."));
      };

      timeoutId = window.setTimeout(function () {
        finish(reject, new Error("The waitlist verification request timed out."));
      }, JSONP_TIMEOUT_MS);

      document.head.appendChild(script);
    });
  }

  function delay(milliseconds) {
    return new Promise(function (resolve) {
      window.setTimeout(resolve, milliseconds);
    });
  }

  function pollForRecordedRow(endpoint, traceId, attemptsRemaining) {
    return requestStatus(endpoint, traceId).then(function (response) {
      logEvent("verification_response", traceId, {
        state: response.state || "unknown",
        recorded: Boolean(response.recorded),
        row: response.row || null
      });

      if (response.recorded) {
        return response;
      }

      if (response.ok === false && response.state && response.state !== "pending") {
        var detail = response.error || response.detail || response.state;
        throw new Error(detail);
      }

      if (attemptsRemaining <= 1) {
        return null;
      }

      return delay(VERIFY_DELAY_MS).then(function () {
        return pollForRecordedRow(endpoint, traceId, attemptsRemaining - 1);
      });
    });
  }

  function submitWaitlist(endpoint, payload) {
    logEvent("submission_started", payload.traceId, { source: payload.source });

    return fetch(endpoint, {
      method: "POST",
      mode: "no-cors",
      cache: "no-store",
      headers: { "Content-Type": "text/plain;charset=utf-8" },
      body: JSON.stringify(payload)
    }).then(function () {
      logEvent("post_dispatched", payload.traceId);
      return pollForRecordedRow(endpoint, payload.traceId, VERIFY_ATTEMPTS);
    });
  }

  form.addEventListener("submit", function (event) {
    event.preventDefault();

    var emailField = form.querySelector('input[name="email"]');
    var button = form.querySelector('button[type="submit"]');
    var endpoint = getEndpoint();
    var email = emailField ? emailField.value.trim() : "";
    var traceId = createTraceId();

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
    setStatus("Adding you to the early access list… This may take 10-15 seconds.");

    submitWaitlist(endpoint, buildPayload(email, traceId))
      .then(function (verification) {
        if (!verification || !verification.recorded) {
          logEvent("verification_failed", traceId, { reason: "row_not_confirmed" });
          setStatus(
            "I couldn’t confirm that Google recorded your signup. Please try again. Reference: " + traceId,
            "error"
          );
          return;
        }

        form.reset();
        logEvent("submission_confirmed", traceId, { row: verification.row || null });
        setStatus("You’re on the list. I’ll send a note when founding access opens.", "success");
      })
      .catch(function (error) {
        logEvent("submission_failed", traceId, {
          detail: error && error.message ? error.message : String(error || "Unknown error")
        });
        setStatus(
          "Google did not confirm the signup. Please try again. Reference: " + traceId,
          "error"
        );
      })
      .finally(function () {
        if (button) button.disabled = false;
      });
  });
})();
