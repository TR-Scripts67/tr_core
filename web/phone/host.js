// For a resource's own page (ui_page): TR.phone.send's messages go on to its app's page in the phone's frame.
// Both pages are on https://cfx-nui-<resource>, so a BroadcastChannel reaches it whichever phone holds it.
(() => {
  const channels = {};
  window.addEventListener('message', (event) => {
    const message = event.data;
    if (!message || typeof message.trPhone !== 'string') return;
    channels[message.trPhone] ??= new BroadcastChannel(`tr_phone:${message.trPhone}`);
    channels[message.trPhone].postMessage({ action: message.action, data: message.data });
  });
})();
