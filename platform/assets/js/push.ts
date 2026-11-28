// The hook `Push` of the page of notifications (issue 29, ADR 0106): it
// turns the notifications of this device on and off with Web Push.
//
//   <article id="push-device" phx-hook="Push" data-key="<public key>">
//     <div data-when="ask">… <button data-push-action="on">…</button></div>
//     <div data-when="on">… <button data-push-action="off">…</button></div>
//     <div data-when="home-screen">…</div>
//     <div data-when="denied">…</div>
//     <div data-when="none">…</div>
//   </article>
//
// The hook sets `data-push` on the element to one of the `data-when` values,
// and the stylesheet shows that part alone. The page keeps the attribute
// through a patch (`JS.ignore_attributes`).
//
// The subscription goes to the server with the event `push-subscribe`: its
// endpoint and keys, which the server encrypts for, and the kind of device,
// a word of a short list that the server checks. The browser asks the person
// for leave only after a press of the button.

import type {HookInterface} from "phoenix_live_view"

type State = "ask" | "on" | "home-screen" | "denied" | "none"
type PushHook = HookInterface & {key: string; worker?: ServiceWorkerRegistration}

/** The kind of device, as `RescordWeb.NotificationsLive` names it. */
function device(): string {
  const agent = navigator.userAgent
  if (/iPhone/.test(agent)) return "iphone"
  // An iPad says that it is a Mac, and a Mac has no touch screen.
  if (/iPad/.test(agent) || (/Macintosh/.test(agent) && navigator.maxTouchPoints > 1)) return "ipad"
  if (/Android/.test(agent)) return "android"
  if (/Macintosh|Mac OS X/.test(agent)) return "mac"
  if (/Windows/.test(agent)) return "windows"
  if (/Linux|X11/.test(agent)) return "linux"
  return "other"
}

/** An iPhone or an iPad that runs Rescord in Safari, not from the Home Screen. */
function outsideHomeScreen(): boolean {
  const kind = device()
  return (kind === "iphone" || kind === "ipad") && !window.matchMedia("(display-mode: standalone)").matches
}

function supported(): boolean {
  return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window
}

/** The public key of the server, as the bytes that `subscribe` takes. */
function keyBytes(key: string): Uint8Array<ArrayBuffer> {
  const base64 = (key + "=".repeat((4 - (key.length % 4)) % 4)).replace(/-/g, "+").replace(/_/g, "/")
  const text = window.atob(base64)
  const bytes = new Uint8Array(new ArrayBuffer(text.length))
  for (let i = 0; i < text.length; i++) bytes[i] = text.charCodeAt(i)
  return bytes
}

/** Whether a subscription was made with this key of the server. */
function madeWith(subscription: PushSubscription, key: string): boolean {
  const own = subscription.options.applicationServerKey
  if (!own) return false
  const theirs = new Uint8Array(own)
  const ours = keyBytes(key)
  return theirs.length === ours.length && theirs.every((byte, i) => byte === ours[i])
}

function show(hook: PushHook, state: State): void {
  hook.el.dataset.push = state
}

function send(hook: PushHook, subscription: PushSubscription): Promise<boolean> {
  return new Promise(resolve => {
    hook.pushEvent("push-subscribe", {...subscription.toJSON(), device: device()}, (reply: unknown) => {
      resolve(typeof reply === "object" && reply !== null && (reply as {ok?: unknown}).ok === true)
    })
  })
}

async function start(hook: PushHook): Promise<void> {
  if (!supported()) {
    show(hook, outsideHomeScreen() ? "home-screen" : "none")
    return
  }
  if (Notification.permission === "denied") {
    show(hook, "denied")
    return
  }

  hook.worker = await navigator.serviceWorker.register("/sw.js", {scope: "/"})
  const subscription = await hook.worker.pushManager.getSubscription()

  if (subscription && madeWith(subscription, hook.key)) {
    // The server may have forgotten the device: it hears of it again.
    show(hook, (await send(hook, subscription)) ? "on" : "ask")
  } else {
    // A subscription of old keys of the server delivers nothing now.
    if (subscription) await subscription.unsubscribe()
    show(hook, "ask")
  }
}

async function turnOn(hook: PushHook): Promise<void> {
  const worker = hook.worker ?? (await navigator.serviceWorker.register("/sw.js", {scope: "/"}))
  const permission = await Notification.requestPermission()
  if (permission !== "granted") {
    show(hook, permission === "denied" ? "denied" : "ask")
    return
  }

  const subscription = await worker.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: keyBytes(hook.key),
  })
  show(hook, (await send(hook, subscription)) ? "on" : "ask")
}

async function turnOff(hook: PushHook): Promise<void> {
  const worker = hook.worker ?? (await navigator.serviceWorker.getRegistration("/"))
  const subscription = await worker?.pushManager.getSubscription()
  if (subscription) {
    const endpoint = subscription.endpoint
    await subscription.unsubscribe()
    hook.pushEvent("push-unsubscribe", {endpoint})
  }
  show(hook, "ask")
}

export const Push = {
  mounted(this: PushHook) {
    this.key = this.el.dataset.key ?? ""

    this.el.addEventListener("click", event => {
      const target = event.target
      if (!(target instanceof Element)) return
      const button = target.closest<HTMLButtonElement>("button[data-push-action]")
      if (!button) return

      button.disabled = true
      const action = button.dataset.pushAction === "on" ? turnOn(this) : turnOff(this)
      action
        .catch(() => show(this, supported() ? "ask" : "none"))
        .finally(() => {
          button.disabled = false
        })
    })

    start(this).catch(() => show(this, "none"))
  },
}
