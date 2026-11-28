// Copies the value of a field when a person presses a button.
//
//   <input id="feed-address" readonly value="https://…">
//   <button type="button" data-copy="feed-address" data-copied="feed-address-copied">…</button>
//   <span id="feed-address-copied" role="status"></span>
//
// The button names the field in `data-copy`, and in `data-copied` the
// element that says that the copy worked. A long address is hard to select
// with a finger on a phone. Without this script the field still works: a
// person selects its text and copies it.

/** Listens, on the whole page, for a press on a button with `data-copy`. */
export function listen(): void {
  document.addEventListener("click", event => {
    const target = event.target
    if (!(target instanceof Element)) return

    const button = target.closest<HTMLElement>("button[data-copy]")
    if (!button) return

    const field = document.getElementById(button.dataset.copy ?? "")
    if (!(field instanceof HTMLInputElement)) return

    // The selection shows what was copied, and lets a person copy by hand
    // in a browser that gives a page no clipboard.
    field.select()

    const said = document.getElementById(button.dataset.copied ?? "")
    const say = (words: string): void => {
      if (said) said.textContent = words
    }

    if (navigator.clipboard) {
      navigator.clipboard.writeText(field.value).then(
        () => say("Copied."),
        () => say("Select the address and copy it."),
      )
    } else {
      say("Select the address and copy it.")
    }
  })
}
