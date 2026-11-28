// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/rescord"
// The hooks that Cinder writes next to its markup (ADR 0014).
import {hooks as cinderHooks} from "phoenix-colocated/cinder"
// The controls of a collection of Cinder, for a keyboard and a screen
// reader (ADR 0017 and ADR 0087).
import {
  enhance as enhanceCinderTables,
  holdOpen as holdCinderListsOpen,
  keep as keepCinderTables,
  listen as listenToCinderTables,
  watch as watchCinderLists,
} from "./cinder_tables"
// A <details> stays open when LiveView draws the page again (ADR 0031).
import {keepDetailsOpen} from "shoddy_phoenix/priv/static/shoddy_phoenix.js"
// The focus of the keyboard stays in its place when the page changes (ADR 0090).
import {listen as listenForNewPages, restore as restoreFocus, watch as watchFocus} from "./focus"
// The button that copies the address of a calendar feed (ADR 0074).
import {listen as listenForCopies} from "./copy"
// The form of the message to Ruby: Enter sends, and a send goes to the newest message (ADR 0069).
import {listen as listenToRuby} from "./ruby"
// The notifications of this device with Web Push (issue 29).
import {Push} from "./push"
// The menu of a phone closes when the Tab key leaves it (ADR 0111).
import {listen as listenToMenus} from "./menu"
// A form that opens takes the focus, and Ctrl+Enter sends a text area (ADR 0111).
import {listen as listenToForms} from "./forms"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...cinderHooks, Push},
  // LiveView patches a table from markup that has none of our attributes.
  dom: {
    onBeforeElUpdated: (from, to) => {
      keepCinderTables(from, to)
      keepDetailsOpen(from, to)
    },
    onPatchEnd: () => {
      enhanceCinderTables()
      // After LiveView put each new element in its place.
      window.setTimeout(restoreFocus, 0)
    },
  },
})

listenToCinderTables()
watchCinderLists()
holdCinderListsOpen()
enhanceCinderTables()
listenForCopies()
listenToRuby()
watchFocus()
listenForNewPages()
listenToMenus()
listenToForms()

// The bar at the top of a page that loads, on a live navigation and on a
// form that sends. The stylesheet draws it while the root element has
// `data-loading` (ADR 0090), so it has the lead colour of each scheme, and
// it does not move where the device asks for less motion.
window.addEventListener("phx:page-loading-start", _info => document.documentElement.setAttribute("data-loading", ""))
window.addEventListener("phx:page-loading-stop", _info => document.documentElement.removeAttribute("data-loading"))

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

