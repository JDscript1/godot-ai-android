/* Godot AI host adaptation. Original code; the official Ziva bundle stays intact. */
(() => {
  if (window.__godotZivaMobile) return;
  window.__godotZivaMobile = true;
  const editable = node => node instanceof Element ? node.closest(
    'textarea,input:not([type]),input[type="text"],input[type="search"],input[type="password"],input[type="email"],input[type="url"],input[type="number"],input[type="tel"],[contenteditable="true"]') : null;
  let editing = false;
  let composing = false;
  let tabUntil = 0;
  // Do not replace HTMLElement.focus: Lexical and Android IME restore focus and
  // selection while composing. Authorize an editing session rather than a DOM
  // node, which can be replaced by the official frontend during a render.
  const blur = () => {
    editing = false;
    composing = false;
    tabUntil = 0;
    const active = editable(document.activeElement);
    if (active) active.blur();
  };
  window.__godotZivaDismissKeyboard = blur;
  document.addEventListener('pointerdown', event => {
    if (!event.isTrusted) return;
    const label = event.target instanceof Element ? event.target.closest('label') : null;
    const field = editable(event.target) || editable(label?.control);
    if (field) editing = true;
    else blur();
  }, true);
  document.addEventListener('keydown', event => {
    if (event.isTrusted && event.key === 'Tab') tabUntil = performance.now() + 1000;
  }, true);
  document.addEventListener('compositionstart', event => {
    if (editable(event.target) && editing) composing = true;
  }, true);
  document.addEventListener('compositionend', () => { composing = false; }, true);
  document.addEventListener('focusin', event => {
    const field = editable(event.target);
    if (field && !editing && !composing && performance.now() > tabUntil) field.blur();
  }, true);
  document.addEventListener('submit', blur, true);
  document.addEventListener('click', event => {
    const field = editable(event.target);
    if (event.isTrusted && field) {
      editing = true;
      if (document.activeElement !== field) field.focus({preventScroll:true});
    }
    if (event.target instanceof Element && event.target.closest(
      '[data-testid="composer-send"],[data-testid="open-settings-button"]')) blur();
  }, true);
  window.__godotZivaWantsKeyboard = () => !!editable(document.activeElement) &&
    (editing || composing || performance.now() <= tabUntil);
  blur();

  // The official frontend owns recording and transcription. The host only
  // releases its streams on tab hide/navigation/background, including a pending
  // getUserMedia promise which resolves after the user has left the tab.
  const media = typeof navigator !== 'undefined' ? navigator.mediaDevices : null;
  const streams = new Set();
  let captureEpoch = 0;
  if (media?.getUserMedia) {
    const getUserMedia = media.getUserMedia.bind(media);
    media.getUserMedia = async constraints => {
      const epoch = captureEpoch;
      const stream = await getUserMedia(constraints);
      if (epoch !== captureEpoch) {
        stream.getTracks().forEach(track => track.stop());
        throw new DOMException('Recording cancelled after leaving the tab.', 'AbortError');
      }
      streams.forEach(previous => {
        if (previous.getTracks().every(track => track.readyState === 'ended')) streams.delete(previous);
      });
      streams.add(stream);
      stream.getTracks().forEach(track => track.addEventListener('ended', () => {
        if (stream.getTracks().every(item => item.readyState === 'ended')) streams.delete(stream);
      }, {once:true}));
      return stream;
    };
  }
  window.__godotZivaReleaseMicrophone = () => {
    captureEpoch++;
    streams.forEach(stream => stream.getTracks().forEach(track => track.stop()));
    streams.clear();
  };

  const style = document.createElement('style');
  style.id = 'godot-ziva-mobile-style';
  style.textContent = `
    html, body, #root { height:100%; min-height:0; }
    @media (max-width:760px), (max-height:500px) {
      #root > .h-screen { height:100dvh; min-height:0; }
      [data-godot-ziva-header] { flex-wrap:nowrap!important; padding:2px 4px!important;
        gap:2px!important; overflow-x:auto; min-height:36px; scrollbar-width:thin; }
      [data-testid="chat-header-panels"] { max-height:0!important; overflow:hidden!important; flex-shrink:0; }
      [data-testid="chat-header-panels"][data-godot-expanded] { max-height:28dvh!important; }
      [data-testid="chat-header-panels"][data-godot-expanded] { overflow-y:auto!important; }
      #godot-ziva-panels-toggle { align-self:flex-end; flex-shrink:0; min-height:28px;
        padding:2px 8px; margin:0 4px; background:transparent; color:inherit;
        border:1px solid currentColor; border-radius:6px; font:inherit; font-size:12px; }
      [data-godot-ziva-composer-region] { min-height:0!important; max-height:38dvh;
        overflow-y:auto; flex-shrink:0; padding:2px 6px!important; }
      [data-godot-ziva-composer] { min-height:0!important; max-height:28dvh!important; }
      [data-godot-ziva-composer] [data-slot="input-group-control"] {
        height:auto!important; min-height:0!important; max-height:48px!important; overflow-y:auto!important; }
      [data-godot-ziva-composer]:focus-within [data-slot="input-group-control"] { max-height:18dvh!important; }
      [data-testid="composer-input"] { min-height:32px!important; padding:6px 8px!important; }
      [data-godot-ziva-composer] [aria-label="Resize input area"] { display:none!important; }
      [data-godot-ziva-composer] [data-slot="input-group-addon"] {
        padding:2px 6px!important; min-width:0; overflow-x:auto; flex-wrap:nowrap!important; }
      [data-godot-ziva-composer] button { flex-shrink:0; min-height:32px; }
      [data-godot-ziva-composer-region] [data-slot="collapsible-content"] {
        max-height:64px!important; overflow-y:auto!important; }
      [data-message-scroller-viewport] { min-height:0!important; touch-action:pan-y;
        overscroll-behavior-y:contain; }
    }
    @media (min-width:761px) and (min-height:501px) {
      #godot-ziva-panels-toggle { display:none; }
    }
  `;
  (document.head || document.documentElement).appendChild(style);
  let queued = false;
  function mark(node, attr) { if (!node.hasAttribute(attr)) node.setAttribute(attr, ''); }
  function adapt() {
    queued = false;
    const input = document.querySelector('[data-testid="composer-input"]');
    const form = input?.closest('form');
    if (form) {
      mark(form, 'data-godot-ziva-composer');
      // Composer parent contains notices/todos, never the conversation scroller.
      if (form.parentElement && !form.parentElement.querySelector('[data-message-scroller-viewport]'))
        mark(form.parentElement, 'data-godot-ziva-composer-region');
    }
    const settings = document.querySelector('[data-testid="open-settings-button"]');
    const header = settings?.closest('header');
    if (header) mark(header, 'data-godot-ziva-header');
    const panels = document.querySelector('[data-testid="chat-header-panels"]');
    let toggle = document.getElementById('godot-ziva-panels-toggle');
    if (panels && panels.childElementCount && !toggle) {
      toggle = document.createElement('button');
      toggle.id = 'godot-ziva-panels-toggle';
      toggle.type = 'button';
      toggle.textContent = 'Detalii ▾';
      toggle.setAttribute('aria-expanded', 'false');
      toggle.addEventListener('click', () => {
        const current = document.querySelector('[data-testid="chat-header-panels"]');
        if (!current) return;
        const expanded = current.toggleAttribute('data-godot-expanded');
        toggle.setAttribute('aria-expanded', String(expanded));
        toggle.textContent = expanded ? 'Restrânge ▴' : 'Detalii ▾';
      });
      panels.after(toggle);
    }
    if (toggle && (!panels || !panels.childElementCount)) toggle.remove();
  }
  const observer = new MutationObserver(() => {
    if (!queued) { queued = true; requestAnimationFrame(adapt); }
  });
  observer.observe(document.documentElement, {childList:true, subtree:true});
  adapt();
})();
