defmodule RescordWeb.RolesTest do
  @moduledoc "Holds how `RescordWeb.Roles` finds a part of a page by its role and name."

  use ExUnit.Case, async: true

  import RescordWeb.Roles

  @page """
  <a href="#main">Skip to content</a>
  <header>
    <nav aria-label="Site"><a href="/">Rescord</a> <a href="/tasks">Tasks</a></nav>
  </header>
  <main id="main">
    <header><hgroup><h1><svg aria-hidden="true"><title>icon</title></svg> Meadow hay</h1></hgroup></header>
    <section aria-labelledby="lots-heading">
      <h2 id="lots-heading"><svg aria-hidden="true"></svg> Lots</h2>
      <ul aria-label="The lots">
        <li id="lot-1">B-1 <button aria-label="Take off B-1"><svg aria-hidden="true"></svg> Take off</button></li>
        <li id="lot-2">B-2 <button aria-label="Take off B-2"><svg aria-hidden="true"></svg> Take off</button></li>
      </ul>
      <form id="new-lot">
        <label for="lot_quantity">Quantity</label>
        <input id="lot_quantity" name="lot[quantity]" />
        <label><input type="checkbox" name="lot[open]" value="true" /> Open now</label>
        <footer><button>Save the lot</button></footer>
      </form>
    </section>
    <section><h2>No name</h2></section>
    <article aria-labelledby="note-heading">
      <header><h3 id="note-heading">A note</h3></header>
      <p role="status">Saved</p>
      <details data-confirm-step>
        <summary aria-label="Delete the note A note"><svg aria-hidden="true"></svg> Delete</summary>
        <button data-variant="danger">Delete the note A note</button>
      </details>
    </article>
    <p role="alert">The quantity is not a number.</p>
    <figure><img src="/hay.webp" alt="A bale of hay" /><figcaption>The bale</figcaption></figure>
    <dl>
      <div><dt>In stock</dt><dd>11 bag</dd></div>
      <div><dt>State</dt><dd><span data-state="alert">Order more</span></dd></div>
    </dl>
    <details open>
      <summary><svg aria-hidden="true"></svg> Stock was used</summary>
      <label><input type="checkbox" name="use[all]" checked /> All of it</label>
      <label><input type="checkbox" name="use[wet]" /> It was wet</label>
      <form>
        <label for="use_source">From which lot and place</label>
        <select id="use_source"><option>Lot B-1</option><option selected>Lot B-2</option></select>
        <label for="use_note">Note</label>
        <textarea id="use_note">Wet</textarea>
        <button>Record the use</button>
      </form>
    </details>
    <img src="/line.svg" alt="" />
  </main>
  <footer><nav aria-label="About Rescord"><a href="/colophon">Colophon</a></nav></footer>
  <div aria-live="polite">
    <div id="client-error" role="alert" hidden><p>We can't find the internet</p></div>
  </div>
  """

  test "a landmark is the site's own, not a header or footer inside main" do
    assert [_] = all(@page, banner())
    assert [_] = all(@page, contentinfo())
    assert names(@page, banner() |> link(~r/./)) == ["Rescord", "Tasks"]
    assert has?(@page, contentinfo() |> navigation("About Rescord") |> link("Colophon"))
    assert href(@page, contentinfo() |> link("Colophon")) == "/colophon"
  end

  test "a name leaves out what is aria-hidden, and folds the spaces" do
    assert text(@page, main() |> heading(level: 1)) == "Meadow hay"
    assert names(@page, main() |> heading()) == ["Meadow hay", "Lots", "No name", "A note"]
  end

  test "a region is a section with a name, from its heading" do
    assert names(@page, region(~r/./)) == ["Lots"]
    assert has?(@page, region("Lots") |> button("Take off B-2"))
    refute has?(@page, region("Lots") |> button("Take off B-3"))
    refute has?(@page, region("Lots") |> region(~r/./))
    assert has?(@page, article("A note") |> status())
  end

  test "a field is found by its label, for and around it" do
    assert [_] = all(@page, field("Quantity"))
    assert [_] = all(@page, field("Open now"))
    assert [_] = all(@page, button("Save the lot"))
  end

  test "an alert that is hidden is not on the page" do
    assert [_] = all(@page, alert())
    assert text(@page, alert()) == "The quantity is not a number."
    refute has?(@page, contentinfo() |> alert())
  end

  test "an item of a list is found by its words" do
    assert [_, _] = all(@page, region("Lots") |> item(~r/./))
    assert has?(@page, item(~r/^B-2\b/) |> button("Take off B-2"))
    refute has?(@page, item(~r/^B-2\b/) |> button("Take off B-1"))
  end

  test "a form is found in its part, and gives its attributes" do
    assert attribute(@page, region("Lots") |> form(nil), "id") == "new-lot"
    assert [_, _] = all(@page, main() |> form(nil))
    refute has?(@page, form("The lots"))
    assert attribute(@page, region("Lots") |> form(nil), "action") == nil
    assert attribute(@page, list("The lots"), "aria-label") == "The lots"
  end

  test "a list is found by its label, and its items in it" do
    assert names(@page, list("The lots") |> item(nil)) == ["B-1 Take off", "B-2 Take off"]
    refute has?(@page, list("Other lots"))
    assert playwright(list("The lots")) == ~s(internal:role=list[name="The lots"s])
  end

  test "an image is named by its alt, and a figure by its caption" do
    assert names(@page, image(~r/./)) == ["A bale of hay"]
    assert src(@page, figure("The bale") |> image("A bale of hay")) == "/hay.webp"
    assert playwright(image("A bale of hay")) == ~s(internal:role=img[name="A bale of hay"s])
  end

  test "a definition is found by its term, and a disclosure by its summary" do
    assert text(@page, definition("In stock")) == "11 bag"
    refute has?(@page, definition("Order more"))
    assert_has(@page, definition("State"), state: "alert", text: "Order more")
    refute_has(@page, definition("State"), state: "ok")
    refute_has(@page, definition("In stock"), state: "alert")
    used = main() |> details("Stock was used")
    assert has?(@page, used |> button("Record the use"))
    assert value(@page, used |> field("From which lot and place")) == "Lot B-2"
    assert value(@page, used |> field("Note")) == "Wet"
    assert value(@page, field("Quantity")) == nil
    assert open?(@page, used)
    assert checked?(@page, used |> field("All of it"))
    refute checked?(@page, used |> field("It was wet"))

    # A confirm step is named by the label of its summary.
    step = article("A note") |> details("Delete the note A note")
    refute open?(@page, step)
    assert has?(@page, step |> button("Delete the note A note"))
    refute has?(@page, details("Delete"))

    assert playwright(details("Stock was used")) ==
             ~s|xpath=.//details[summary[@aria-label="Stock was used" or normalize-space()="Stock was used"]]|

    assert playwright(definition("In stock")) ==
             ~s|xpath=.//dd[preceding-sibling::dt[1][normalize-space()="In stock"]]|
  end

  test "one raises for none or for more than one" do
    assert_raise ArgumentError, ~r/found 2 elements/, fn -> one(@page, button(~r/^Take off/)) end
    assert_raise ArgumentError, ~r/found 0 elements/, fn -> one(@page, region("Stock")) end
  end

  test "a browser test gets a selector of Playwright by role and name" do
    assert playwright(region("Lots") |> button("Take off B-1")) ==
             ~s(internal:role=region[name="Lots"s] >> internal:role=button[name="Take off B-1"s])

    assert playwright(main() |> heading(level: 1)) ==
             "internal:role=main >> internal:role=heading[level=1]"

    assert playwright(field("Weight")) == ~s(internal:label="Weight"s)
    assert playwright(row(~r/^Meadow hay/)) == "internal:role=row[name=/^Meadow hay/]"

    assert playwright(item(~r/^B-1/)) ==
             "internal:role=listitem >> internal:has-text=/^B-1/ >> nth=0"
  end
end
