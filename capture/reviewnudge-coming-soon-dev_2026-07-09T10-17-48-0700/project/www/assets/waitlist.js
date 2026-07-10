import { copy } from './content.js';

export function bindWaitlist(root = globalThis.document, windowRef = globalThis.window) {
  const form = root?.querySelector?.('[data-waitlist-form]');
  const status = root?.querySelector?.('[data-waitlist-status]');

  if (!form || !status || !windowRef || form.dataset.waitlistBound === 'true') {
    return () => {};
  }

  form.dataset.waitlistBound = 'true';

  const VERIFY_ATTEMPTS = 10;
  const VERIFY_DELAY_MS = 1500;
  const JSONP_TIMEOUT_MS = 10000;

  function setStatus(message, state) {
    status.textContent = message || '';
    if (state) status.setAttribute('data-state', state);
    else status.removeAttribute('data-state');
  }

  function logEvent(eventName, traceId, details) {
    const payload = Object.assign({
      service: 'reviewnudge-waitlist',
      event: eventName,
      traceId: traceId || '',
      timestamp: new Date().toISOString()
    }, details || {});

    if (eventName.includes('failed') || eventName.includes('error')) {
      windowRef.console.error('[ReviewNudge waitlist]', payload);
    } else {
      windowRef.console.info('[ReviewNudge waitlist]', payload);
    }
  }

  function getEndpoint() {
    return String(windowRef.REVIEWNUDGE_WAITLIST_ENDPOINT || '').trim();
  }

  function endpointIsConfigured(endpoint) {
    return Boolean(endpoint) && !endpoint.includes('REPLACE_WITH_DEPLOYMENT_ID');
  }

  function createTraceId() {
    if (windowRef.crypto && typeof windowRef.crypto.randomUUID === 'function') {
      return windowRef.crypto.randomUUID();
    }
    return `rn-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 14)}`;
  }

  function buildPayload(email, traceId) {
    return {
      email,
      traceId,
      source: 'reviewnudge-coming-soon',
      page: windowRef.location.href,
      referrer: root.referrer || '',
      userAgent: windowRef.navigator.userAgent || '',
      submittedAt: new Date().toISOString()
    };
  }

  function appendQuery(endpoint, params) {
    const separator = endpoint.includes('?') ? '&' : '?';
    return endpoint + separator + new URLSearchParams(params).toString();
  }

  function requestStatus(endpoint, traceId) {
    return new Promise((resolve, reject) => {
      const callbackName = `__reviewNudgeWaitlistStatus_${traceId.replace(/[^A-Za-z0-9_$]/g, '').slice(0, 16)}_${Date.now()}`;
      const script = root.createElement('script');
      let timeoutId;
      let finished = false;

      function cleanup() {
        if (timeoutId) windowRef.clearTimeout(timeoutId);
        if (script.parentNode) script.parentNode.removeChild(script);
        try { delete windowRef[callbackName]; }
        catch { windowRef[callbackName] = undefined; }
      }

      function finish(handler, value) {
        if (finished) return;
        finished = true;
        cleanup();
        handler(value);
      }

      windowRef[callbackName] = response => finish(resolve, response || {});
      script.async = true;
      script.src = appendQuery(endpoint, {
        action: 'status',
        traceId,
        callback: callbackName,
        _: String(Date.now())
      });
      script.onerror = () => finish(reject, new Error(copy('errors.waitlist.verificationEndpointUnreachable')));
      timeoutId = windowRef.setTimeout(
        () => finish(reject, new Error(copy('errors.waitlist.verificationTimeout'))),
        JSONP_TIMEOUT_MS
      );
      root.head.appendChild(script);
    });
  }

  function delay(milliseconds) {
    return new Promise(resolve => windowRef.setTimeout(resolve, milliseconds));
  }

  function pollForRecordedRow(endpoint, traceId, attemptsRemaining) {
    return requestStatus(endpoint, traceId).then(response => {
      logEvent('verification_response', traceId, {
        state: response.state || 'unknown',
        recorded: Boolean(response.recorded),
        row: response.row || null
      });

      if (response.recorded) return response;
      if (response.ok === false && response.state && response.state !== 'pending') {
        throw new Error(response.error || response.detail || response.state);
      }
      if (attemptsRemaining <= 1) return null;
      return delay(VERIFY_DELAY_MS).then(() => pollForRecordedRow(endpoint, traceId, attemptsRemaining - 1));
    });
  }

  function submitWaitlist(endpoint, payload) {
    logEvent('submission_started', payload.traceId, { source: payload.source });
    return windowRef.fetch(endpoint, {
      method: 'POST',
      mode: 'no-cors',
      cache: 'no-store',
      headers: { 'Content-Type': 'text/plain;charset=utf-8' },
      body: JSON.stringify(payload)
    }).then(() => {
      logEvent('post_dispatched', payload.traceId);
      return pollForRecordedRow(endpoint, payload.traceId, VERIFY_ATTEMPTS);
    });
  }

  const submitHandler = event => {
    event.preventDefault();

    const emailField = form.querySelector('input[name="email"]');
    const button = form.querySelector('button[type="submit"]');
    const endpoint = getEndpoint();
    const email = emailField ? emailField.value.trim() : '';
    const traceId = createTraceId();

    if (!emailField || !emailField.checkValidity()) {
      if (emailField) emailField.reportValidity();
      setStatus(copy('errors.waitlist.invalidEmail'), 'error');
      return;
    }

    if (!endpointIsConfigured(endpoint)) {
      setStatus(copy('errors.waitlist.unavailable'), 'error');
      return;
    }

    if (button) button.disabled = true;
    setStatus(copy('notifications.waitlist.submitting'));

    submitWaitlist(endpoint, buildPayload(email, traceId))
      .then(verification => {
        if (!verification || !verification.recorded) {
          logEvent('verification_failed', traceId, { reason: 'row_not_confirmed' });
          setStatus(copy('errors.waitlist.verificationFailed', { traceId }), 'error');
          return;
        }

        form.reset();
        logEvent('submission_confirmed', traceId, { row: verification.row || null });
        setStatus(copy('notifications.waitlist.success'), 'success');
      })
      .catch(error => {
        logEvent('submission_failed', traceId, {
          detail: error && error.message ? error.message : String(error || 'Unknown error')
        });
        setStatus(copy('errors.waitlist.submissionFailed', { traceId }), 'error');
      })
      .finally(() => {
        if (button) button.disabled = false;
      });
  };

  form.addEventListener('submit', submitHandler);
  return () => {
    form.removeEventListener('submit', submitHandler);
    delete form.dataset.waitlistBound;
  };
}
