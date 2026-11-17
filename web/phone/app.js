// For an app's page in a phone (TR.phone.app): <script src="https://cfx-nui-tr_core/web/phone/app.js" data-app="<id>">.
// Lua's TR.phone.send(id, action, data) comes as a window message { action, data }, as SendNUIMessage's do.
// window.TRPhone.typing(on) stops the player walking while they type, where the phone has a way to.
(() => {
  const app = document.currentScript?.dataset.app ?? '';
  const resource = location.hostname.replace(/^cfx-nui-/, '');
  // The frame is the phone's: name the page's own resource for its fetches to Lua.
  window.GetParentResourceName = () => resource;

  const post = (name, data) =>
    fetch(`https://${resource}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data ?? {}),
    }).catch(() => {});

  new BroadcastChannel(`tr_phone:${app}`).onmessage = (event) => {
    window.dispatchEvent(new MessageEvent('message', { data: event.data }));
  };

  window.TRPhone = { app, resource, typing: (on) => post('tr_phone:typing', { on: on === true }) };
})();
