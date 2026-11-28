/// <reference lib="webworker" />
// The service worker of Rescord (issue 29, ADR 0106). It does one thing: it
// shows a notification that a push service brings, and opens its page when
// a person presses it. It keeps no page and no file offline, so it has no
// handler of `fetch`: each request goes to the network as before.
//
// esbuild writes it to `priv/static/sw.js`, a file at the root with no
// digest, so its scope is the whole site. The hook `Push`
// (`assets/js/push.ts`) registers it.
//
// A push holds a pointer only: the name of the refuge, one sentence of its
// kind, and the address of the page of notifications
// (`Rescord.Notifications.Message`). It names no resident, no person and no
// words of a comment.

const worker = self as unknown as ServiceWorkerGlobalScope

type Pointer = {title: string; body: string; url: string; tag: string}

// What the server sent, or nothing when it is not the shape that the server
// writes. A push that is not ours still shows a notification: a browser may
// take the subscription away from a worker that shows none.
function pointer(data: PushMessageData | null): Pointer | null {
  if (!data) return null

  let value: unknown
  try {
    value = data.json()
  } catch {
    return null
  }

  if (typeof value !== "object" || value === null) return null
  const {title, body, url, tag} = value as Record<string, unknown>
  if (typeof title !== "string" || typeof body !== "string") return null
  if (typeof url !== "string" || typeof tag !== "string") return null

  return {title, body, url: sameSite(url) ?? "/", tag}
}

// An address of this site, or nothing: a notification opens no other site.
function sameSite(address: string): string | null {
  try {
    const url = new URL(address, worker.location.origin)
    return url.origin === worker.location.origin ? url.href : null
  } catch {
    return null
  }
}

worker.addEventListener("install", () => {
  // A new worker takes over at once: it has no cache to fill.
  void worker.skipWaiting()
})

worker.addEventListener("activate", event => {
  event.waitUntil(worker.clients.claim())
})

worker.addEventListener("push", event => {
  const message = pointer(event.data) ?? {
    title: "Rescord",
    body: "Something is new.",
    url: "/",
    tag: "rescord",
  }

  event.waitUntil(
    worker.registration.showNotification(message.title, {
      body: message.body,
      tag: message.tag,
      icon: "/images/icon-192.png",
      data: {url: message.url},
    }),
  )
})

worker.addEventListener("notificationclick", event => {
  event.notification.close()
  const data: unknown = event.notification.data
  const wanted =
    typeof data === "object" && data !== null && typeof (data as {url?: unknown}).url === "string"
      ? sameSite((data as {url: string}).url)
      : null
  const url = wanted ?? worker.location.origin + "/"

  event.waitUntil(
    worker.clients.matchAll({type: "window", includeUncontrolled: true}).then(windows => {
      // A window of Rescord that is open goes to the page.
      const open = windows.find(client => new URL(client.url).origin === worker.location.origin)
      if (open) {
        return open
          .focus()
          .then(client => client.navigate(url))
          // A window that this worker does not control cannot be sent to a
          // page: a new window opens instead.
          .catch(() => worker.clients.openWindow(url))
          .then(() => undefined)
      }
      return worker.clients.openWindow(url).then(() => undefined)
    }),
  )
})
