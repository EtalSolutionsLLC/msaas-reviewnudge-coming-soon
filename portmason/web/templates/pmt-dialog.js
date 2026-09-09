const DEFAULT_OPTIONS = Object.freeze({
  confirmLabel: 'Continue',
  cancelLabel: 'Cancel',
  tone: 'default'
});

const contexts = new WeakMap();

function clean(value) {
  return String(value ?? '').trim();
}

export function normalizePmDialogOptions(message, options = {}) {
  const normalizedMessage = clean(message);
  if (!normalizedMessage) throw new TypeError('pmConfirm requires a message.');

  return Object.freeze({
    message: normalizedMessage,
    confirmLabel: clean(options.confirmLabel) || DEFAULT_OPTIONS.confirmLabel,
    cancelLabel: clean(options.cancelLabel) || DEFAULT_OPTIONS.cancelLabel,
    tone: options.tone === 'danger' ? 'danger' : DEFAULT_OPTIONS.tone
  });
}

function setOpenState(documentRef, open) {
  documentRef.documentElement?.classList.toggle('pm-dialog-open', open);
  documentRef.body?.classList.toggle('pm-dialog-open', open);
}

function createContext(documentRef, windowRef) {
  const dialog = documentRef.createElement('dialog');
  dialog.className = 'pm-dialog';
  dialog.setAttribute('role', 'alertdialog');
  dialog.setAttribute('aria-labelledby', 'pmDialogMessage');

  const frame = documentRef.createElement('div');
  frame.className = 'pm-dialog__frame';

  const kicker = documentRef.createElement('p');
  kicker.className = 'pm-dialog__kicker';
  kicker.textContent = 'PORTMASON';

  const message = documentRef.createElement('h2');
  message.className = 'pm-dialog__message';
  message.id = 'pmDialogMessage';

  const form = documentRef.createElement('form');
  form.className = 'pm-dialog__actions';
  form.method = 'dialog';

  const cancelButton = documentRef.createElement('button');
  cancelButton.className = 'pm-dialog__button pm-dialog__button--cancel';
  cancelButton.type = 'button';

  const confirmButton = documentRef.createElement('button');
  confirmButton.className = 'pm-dialog__button pm-dialog__button--confirm';
  confirmButton.type = 'submit';

  form.append(cancelButton, confirmButton);
  frame.append(kicker, message, form);
  dialog.append(frame);
  documentRef.body.append(dialog);

  let resolvePending = null;
  let restoreTarget = null;

  function restoreFocus() {
    const target = restoreTarget;
    restoreTarget = null;
    const schedule = windowRef?.queueMicrotask?.bind(windowRef) || globalThis.queueMicrotask;
    schedule(() => {
      if (target?.isConnected) target.focus?.();
    });
  }

  function finish(accepted) {
    if (!resolvePending) return;
    const resolve = resolvePending;
    resolvePending = null;
    if (dialog.open) dialog.close();
    else dialog.removeAttribute('open');
    setOpenState(documentRef, false);
    restoreFocus();
    resolve(accepted);
  }

  form.addEventListener('submit', event => {
    event.preventDefault();
    finish(true);
  });
  cancelButton.addEventListener('click', () => finish(false));
  dialog.addEventListener('cancel', event => {
    event.preventDefault();
    finish(false);
  });
  dialog.addEventListener('click', event => {
    if (event.target === dialog) finish(false);
  });
  dialog.addEventListener('close', () => finish(false));

  function open(options) {
    return new Promise(resolve => {
      message.textContent = options.message;
      confirmButton.textContent = options.confirmLabel;
      cancelButton.textContent = options.cancelLabel;
      dialog.dataset.tone = options.tone;
      restoreTarget = documentRef.activeElement;
      resolvePending = resolve;
      setOpenState(documentRef, true);
      if (typeof dialog.showModal === 'function') dialog.showModal();
      else dialog.setAttribute('open', '');
      cancelButton.focus();
    });
  }

  return { open, queue: Promise.resolve() };
}

export function pmConfirm(message, options = {}) {
  const documentRef = options.documentRef || globalThis.document;
  const windowRef = options.windowRef || globalThis.window;
  if (!documentRef?.body) return Promise.resolve(false);

  const normalized = normalizePmDialogOptions(message, options);
  let context = contexts.get(documentRef);
  if (!context) {
    context = createContext(documentRef, windowRef);
    contexts.set(documentRef, context);
  }

  const request = context.queue.then(() => context.open(normalized));
  context.queue = request.then(() => undefined, () => undefined);
  return request;
}
