// The form of the message to Ruby (ADR 0069). Both parts are optional:
// without this script the button sends, and the member scrolls.
//
//   <form data-composer phx-submit="send">
//     <textarea>…</textarea>
//   </form>

/** Listens, on the whole page, for the keys of the field and for a send. */
export function listen(): void {
  // Enter sends the message where the keyboard has a key Enter of its own
  // and the pointer is a mouse. On a phone Enter is a new line, and the
  // button sends. Shift+Enter is a new line everywhere, and Enter in the
  // middle of a word of an input method (Japanese, Chinese, Korean) stays
  // with that method.
  const fine = window.matchMedia("(hover: hover) and (pointer: fine)")

  document.addEventListener("keydown", event => {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing || !fine.matches) return

    const field = event.target
    if (!(field instanceof HTMLTextAreaElement)) return
    if (!field.form?.hasAttribute("data-composer")) return

    event.preventDefault()
    field.form.requestSubmit()
  })

  // After the server has the message of the member, the page goes to the
  // newest message: the server pushes the event once the message is in
  // the page. LiveView has no command that scrolls.
  window.addEventListener("phx:ruby:newest", () => {
    document.getElementById("newest")?.scrollIntoView({block: "end"})
  })
}
