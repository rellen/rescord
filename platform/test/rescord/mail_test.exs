defmodule Rescord.MailTest do
  @moduledoc """
  Holds the emails of `Rescord.Mail` (ADR 0070): each one has an HTML part
  and a text part that say the same, escapes what a user wrote, loads
  nothing from another host, and has the colours of
  `assets/css/layers/tokens.css` alone.
  """

  use ExUnit.Case, async: true

  alias Rescord.Mail

  @url "https://rescord.example.org/sign-in/link?token=abc&next=1"
  @dark "@media (prefers-color-scheme: dark)"

  defp doc(email), do: LazyHTML.from_document(email.html_body)

  defp text_of(doc, selector), do: doc |> LazyHTML.query(selector) |> LazyHTML.text()

  # The words of the HTML part, with one space for each run of white space.
  defp words(email) do
    email |> doc() |> text_of("body") |> String.split() |> Enum.join(" ")
  end

  # The colours of `html`: the ones outside the dark media query, and the
  # ones inside it. The query is the last rule of the one style block that
  # holds it.
  defp colours(html) do
    [before, rest] = String.split(html, @dark, parts: 2)
    [inside, after_style] = String.split(rest, "</style>", parts: 2)

    scan = fn part ->
      ~r/#[0-9a-fA-F]{6}\b/ |> Regex.scan(part) |> List.flatten() |> Enum.uniq()
    end

    {scan.(before <> after_style), scan.(inside)}
  end

  defp tokens do
    css = File.read!("assets/css/layers/tokens.css")

    pairs =
      for [_, light, dark] <-
            Regex.scan(~r/light-dark\((#[0-9a-f]{6}),\s*(#[0-9a-f]{6})\)/, css),
          do: {light, dark}

    Enum.unzip(pairs)
  end

  for {name, _email} <- Mail.previews() do
    describe "the email #{name}" do
      setup do
        {_name, email} = List.keyfind(Mail.previews(), unquote(name), 0)
        %{email: email}
      end

      test "has the sender of the settings, one address and a subject", %{email: email} do
        assert email.from == Application.fetch_env!(:rescord, :mail_from)
        assert [{"", "kim@example.org"}] = email.to
        assert email.subject != ""
      end

      test "has an HTML part with a language, a title and one heading", %{email: email} do
        doc = doc(email)

        assert LazyHTML.attribute(LazyHTML.query(doc, "html"), "lang") == ["en"]
        assert text_of(doc, "head title") == email.subject
        assert doc |> LazyHTML.query("h1") |> Enum.count() == 1
        assert text_of(doc, "h1") != ""
      end

      test "names Rescord beside the mark, which a screen reader skips", %{email: email} do
        doc = doc(email)

        assert text_of(doc, "td.rs-name") == "Rescord"
        assert doc |> LazyHTML.query("td[aria-hidden=true] table.rs-mark") |> Enum.count() == 1
      end

      test "says in the text part what the HTML part says below the card", %{email: email} do
        note = email |> doc() |> text_of("td.rs-small div") |> String.split() |> Enum.join(" ")
        last = email.text_body |> String.trim() |> String.split("\n\n") |> List.last()

        assert String.ends_with?(note, last)
      end

      test "loads nothing: no image, no font, no stylesheet, no other host", %{email: email} do
        html = email.html_body
        doc = doc(email)

        for selector <- ["img", "link", "script", "iframe", "object", "video", "audio"] do
          assert doc |> LazyHTML.query(selector) |> Enum.count() == 0,
                 "the email has a #{selector}"
        end

        refute html =~ "@import"
        refute html =~ "@font-face"
        refute html =~ "url("

        hosts =
          for [address] <- Regex.scan(~r{https?://[^\s"'<>)]+}, html), uniq: true do
            URI.parse(address).host
          end

        # The namespace of XHTML is a name, and no client fetches it.
        assert hosts -- ["www.w3.org", "rescord.example.org"] == []
      end

      test "has the colours of tokens.css alone, light inline and dark in the query", %{
        email: email
      } do
        {light, dark} = tokens()
        {outside, inside} = colours(email.html_body)

        assert outside != [] and inside != []
        assert outside -- light == [], "a colour outside the dark query is no light token"
        assert inside -- dark == [], "a colour inside the dark query is no dark token"
      end
    end
  end

  describe "the sign-in link" do
    test "has the link in both parts, and says how long it works" do
      email = Mail.sign_in_link("kim@example.org", @url)
      doc = doc(email)

      assert email.subject == "Your sign-in link for Rescord"
      assert email.text_body =~ "\n\n#{@url}\n\n"
      assert email.text_body =~ "It works one time, for 15 minutes"

      # The button, and the address as text for a program that shows no button.
      assert doc |> LazyHTML.query("a") |> LazyHTML.attribute("href") == [@url, @url]
      assert text_of(doc, "td.rs-button a") =~ "Sign in"
      assert text_of(doc, "td.rs-small a") == @url
      assert words(email) =~ "The link works one time, for 15 minutes."
      assert words(email) =~ "Nobody can sign in without this link."
    end

    test "escapes the address of the link in the HTML part" do
      email = Mail.sign_in_link("kim@example.org", @url)

      assert email.html_body =~
               ~s(href="https://rescord.example.org/sign-in/link?token=abc&amp;next=1")

      refute email.html_body =~ "token=abc&next"
    end
  end

  describe "the invitation" do
    @page "https://rescord.example.org/sign-in"

    test "names the organisation, the inviter and the address to type" do
      email = Mail.invitation("kim@example.org", "Wattle Creek Refuge", "sam@example.org", @page)
      doc = doc(email)

      assert email.subject == "You are invited to Wattle Creek Refuge on Rescord"
      assert text_of(doc, "h1") == "You are invited to Wattle Creek Refuge"
      assert words(email) =~ "sam@example.org invited you to Wattle Creek Refuge on Rescord."
      assert text_of(doc, "strong") == "kim@example.org"
      assert doc |> LazyHTML.query("a") |> LazyHTML.attribute("href") == [@page, @page]

      assert email.text_body =~ "sam@example.org invited you to Wattle Creek Refuge on Rescord."
      assert email.text_body =~ "\n\n#{@page}\n\n"
      assert email.text_body =~ "You need no password."
    end

    test "says Somebody when it does not know who invited the person" do
      email = Mail.invitation("kim@example.org", "Wattle Creek Refuge", nil, @page)

      assert words(email) =~ "Somebody invited you to Wattle Creek Refuge on Rescord."
      assert email.text_body =~ "Somebody invited you to Wattle Creek Refuge on Rescord."
    end

    test "escapes the name of an organisation in the HTML part" do
      name = ~s|Cats & <script>alert("dogs")</script>|
      email = Mail.invitation("kim@example.org", name, "sam@example.org", @page)
      doc = doc(email)

      refute email.html_body =~ "<script"
      assert email.html_body =~ "Cats &amp; &lt;script&gt;"
      assert text_of(doc, "h1") == "You are invited to #{name}"
      assert text_of(doc, "head title") == "You are invited to #{name} on Rescord"

      # The subject and the text part are no HTML: they keep the name as it is.
      assert email.subject == "You are invited to #{name} on Rescord"
      assert email.text_body =~ name
    end
  end

  describe "the test email of bin/check" do
    test "says that the mail works, with a shape and a word" do
      email = Mail.mail_works("kim@example.org")
      doc = doc(email)

      assert email.subject == "Rescord can send mail"
      assert text_of(doc, "h1") == "Rescord can send mail"
      assert text_of(doc, "td.rs-state span[aria-hidden=true]") == "✓"
      assert words(email) =~ "✓ Mail works"
      assert words(email) =~ "This email comes from bin/check."
      assert email.text_body =~ "This email comes from bin/check."
    end
  end

  test "the layout names no font that MJML fetches from Google Fonts" do
    layout = File.read!("lib/rescord/mail/layout.mjml.eex")
    [_, stack] = Regex.run(~r/<mj-all font-family="([^"]+)"/, layout)

    for font <- ["Ubuntu", "Roboto", "Lato", "Open Sans", "Droid Sans"] do
      refute stack =~ font
    end
  end
end
