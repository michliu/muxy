# Browser

`muxy.browser` lets an extension's **tab, panel, or popover** embed a **live, interactive web page** inside its own UI. Unlike [`muxy.http`](http.md) (which fetches API data) or an `<iframe>` (blocked by CORS and `X-Frame-Options`), the page renders in a native `WKWebView` whose origin **is the real site** — so there is **no CORS**, full JavaScript, subresources, and persistent sessions all work.

The extension ships its own chrome (address bar, tabs, buttons). Muxy renders only the viewport, positioned over a placeholder element you provide.

## How it works

You give Muxy a DOM element; Muxy renders a native browser viewport on top of it, clipped to the element and tracking its position as the page scrolls or resizes.

```js
const el = document.getElementById('viewport');
const browser = await muxy.browser.init(el, {
  url: 'https://github.com',
  profile: 'work', // optional: an isolated, persistent session
});

document.getElementById('back').onclick = () => browser.back();
browser.on('did-navigate', ({ url }) => { addressBar.value = url; });
```

The element is a reserved area — lay your address bar and tab strip out **around** it. A native view sits on top, so do not render content over the element expecting it to show through.

## `muxy.browser.init(element, options?)`

Returns a `Promise` that resolves with a **browser handle**.

`options`:

| Field | Default | Notes |
| --- | --- | --- |
| `url` | — | Initial URL to load. |
| `profile` | (ephemeral default) | A profile key. Same key → same persistent, isolated session (cookies, logins, cache). |

You can call `init` multiple times in one surface (e.g. a tab strip where each tab is its own viewport). Each returns an independent handle.

### Handle API

```js
// navigation
browser.loadURL(url);   // alias: browser.goTo(url)
browser.back();
browser.forward();
browser.reload();
browser.stop();

// live state (kept in sync)
browser.url;            // current URL or null
browser.title;          // page title or null
browser.canGoBack;
browser.canGoForward;
browser.isLoading;
browser.progress;       // 0..1

// actions
browser.find(text);            // native find-in-page
browser.executeJS(source);     // run JS in the page, resolves with the result
browser.show();
browser.hide();

// events
const off = browser.on('did-navigate', ({ url }) => {});
browser.on('title-changed', ({ title }) => {});
browser.on('loading-changed', ({ isLoading }) => {});
browser.on('progress', ({ progress }) => {});
browser.on('state', (state) => {}); // the whole state object on any change

// teardown — always call when removing the element
await browser.destroy();
```

Geometry tracks automatically via `ResizeObserver` and scroll. If you move the element in a way those don't catch, call `browser.sync()`.

## Profiles & sessions

Profiles are **scoped to your extension**. A profile key maps to its own persistent, isolated data store — cookies and logins in one profile never leak to another, or to other extensions.

```js
await muxy.browser.profiles.create('work');
await muxy.browser.profiles.list();          // ['work']
await muxy.browser.profiles.clear('work');   // wipe cookies/cache, keep the profile
await muxy.browser.profiles.delete('work');  // remove the profile and its data
```

Passing `{ profile: 'work' }` to `init` creates the profile on demand.

### Importing a session

Muxy does **not** ship a Chrome/Firefox importer — your extension owns import. Read the source browser's cookies yourself (e.g. via [`muxy.exec`](scripts.md) / [`muxy.files`](files.md)) and inject them:

```js
await muxy.browser.profiles.setCookies('work', [
  { name: 'session', value: 'abc', domain: '.github.com', path: '/', secure: true, httpOnly: true, expires: 1893456000 },
]);
```

`setCookies` cookie fields: `name`, `value`, `domain` (required); `path` (default `/`), `secure`, `httpOnly` (default false), `expires` (UNIX seconds; omit for a session cookie).

## Permission & consent

`muxy.browser` requires the **`browser:embed`** manifest permission:

```json
{ "muxy": { "permissions": ["browser:embed"] } }
```

The **first time an extension embeds a browser**, the user is prompted once — "Allow `<ext>` to embed a web browser?". After **Allow & remember**, the extension embeds and navigates freely with no further prompts. This is a real browser: the user drives navigation, so there is **no per-host prompt and no private/loopback blocking** — `localhost`, LAN hosts, and any public site all load like they would in Safari or Chrome.

The built-in browser can be disabled globally; when off, `init` rejects and any open viewports are torn down.

## Notes

- Available only on **tabs**, **panels**, and **popovers** (the WKWebView surfaces). Background scripts and [`runScript`](scripts.md) commands have no DOM and cannot embed a viewport.
- If you host the browser in a [tab type](tabs.md) opened by a command or `muxy.tabs.open`, that also needs `tabs:write` — `browser:embed` only gates the `muxy.browser.*` calls, not opening the tab.
- Only `http`, `https`, and `about:` URLs load; other schemes are ignored. `target="_blank"` links open in the same viewport (no popups).
- `browser:embed` grants full, unsandboxed web browsing under the extension — grant it only to extensions you trust.
- Always `destroy()` a handle when you remove its element, so the native view is torn down.
