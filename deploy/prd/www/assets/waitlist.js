import { copy } from './content.js';

export function bindWaitlist(root = globalThis.document, windowRef = globalThis.window) {
  const form = root?.querySelector?.('[data-waitlist-form]');
  const status = root?.querySelector?.('[data-waitlist-status]');

  if (!form || !status || !windowRef || form.dataset.waitlistBound === 'true') {
    return () => {};
  }

  form.dataset.waitlistBound = 'true';

  const JSONP_TIMEOUT_MS = 20000;

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
      action: 'subscribe',
      email,
      traceId,
      source: 'reviewnudge-coming-soon',
      page: String(windowRef.location.href || '').slice(0, 1000),
      referrer: String(root.referrer || '').slice(0, 1000),
      userAgent: String(windowRef.navigator.userAgent || '').slice(0, 1000),
      submittedAt: new Date().toISOString()
    };
  }

  function appendQuery(endpoint, params) {
    const separator = endpoint.includes('?') ? '&' : '?';
    return endpoint + separator + new URLSearchParams(params).toString();
  }

  function submitWaitlist(endpoint, payload) {
    return new Promise((resolve, reject) => {
      const callbackName = `__reviewNudgeWaitlist_${payload.traceId.replace(/[^A-Za-z0-9_$]/g, '').slice(0, 16)}_${Date.now()}`;
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
      script.src = appendQuery(endpoint, Object.assign({}, payload, {
        callback: callbackName,
        _: String(Date.now())
      }));
      script.onerror = () => finish(reject, new Error(copy('errors.waitlist.submissionFailed')));
      timeoutId = windowRef.setTimeout(
        () => finish(reject, new Error(copy('errors.waitlist.verificationTimeout'))),
        JSONP_TIMEOUT_MS
      );

      logEvent('submission_started', payload.traceId, { source: payload.source });
      root.head.appendChild(script);
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
      .then(result => {
        if (!result || result.ok !== true || result.recorded !== true) {
          const detail = result && (result.error || result.detail || result.state);
          throw new Error(detail || 'The waitlist registration was not confirmed.');
        }

        form.reset();
        logEvent('submission_confirmed', traceId, {
          row: result.row || null,
          duplicate: Boolean(result.duplicate),
          state: result.state || 'row_recorded'
        });

        const messageKey = result.state === 'email_already_registered'
          ? 'notifications.waitlist.alreadyRegistered'
          : 'notifications.waitlist.success';
        const successFallback = copy('notifications.waitlist.success');
        setStatus(copy(messageKey, {}, successFallback), 'success');
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
