# ADR 0003: Pages are compositions of live widgets

Status: accepted (chosen by the maintainer)

## Context

A LiveView that holds all the state of a page, and handles every event and
message itself, grows into one large module. A LiveComponent gives a part of
a page its own state, but it cannot receive messages, so its LiveView has to
forward them, and it hides its state from the page.

## Decision

- Follow the live widget pattern of Curiosum's "Hooking up with LiveView:
  stateful widgets with function components", as the `shoddy_phoenix` guide
  "Build a widget with lifecycle hooks" builds it:
  - a widget's state is a struct with a `:key`, stored in the page's assigns
    under that key, so a page can hold several instances;
  - `assign_widget/2,3` puts the state, subscribes with
    `ShoddyPhoenix.LiveView.Subscriptions` (one subscription per topic, so a
    message arrives once), routes the widget's events with
    `ShoddyPhoenix.LiveView.Widgets.route_events/3`, and attaches its
    `:handle_info` hook with `ShoddyPhoenix.LiveView.put_hook/4` (a second
    instance replaces the hook);
  - its event names are written with `event/1` of
    `ShoddyPhoenix.LiveView.Events`, so a misspelt name fails the compile.
    Each event names its instance in a `"widget"` parameter, which
    `RescordWeb.Widget.fetch/3` compares as text, never as an atom;
  - each event clause checks the shape of its params, and ends with a clause
    that ignores anything else;
  - `render/1` is a pure function component.
- `RescordWeb.Widget` holds the bookkeeping that every widget repeats, and
  `use RescordWeb, :widget` sets up a widget module.
- A page LiveView routes and lays out. It ends with a catch-all
  `handle_info/2`, because the hooks pass on the messages that are not
  theirs, and a catch-all `handle_event/3` that ignores an event that no
  widget owns.
- There are no LiveComponents. `RescordWeb` has no `live_component/0`.
- Widgets live in `lib/rescord_web/widgets/`.

## Consequences

- There is one process per page, so a widget is as cheap as an assign. A
  widget that crashes takes its page down with it.
- A widget keeps the compile-time check of its event names, so it has no
  catch-all clause for an unknown action. A crafted event such as
  `"counter:bogus"` raises in the widget and crashes the sender's page,
  which mounts again. A page's catch-all `handle_event/3` turns off that
  check for the page's own events.
- Every hook sees every message, which costs one function call per hook per
  message. Profile before a page holds many widget modules.
- `test/rescord_web/widget_test.exs` shows the behaviour on a real LiveView.
