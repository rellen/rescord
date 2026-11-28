defmodule Rescord.Reports.Render do
  @moduledoc """
  Runs a report action (ADR 0076), in three steps.

    1. **The facts.** The module of the report under `Rescord.Reports.Facts`
       reads the records through the domains, as the actor, in the
       organisation of the request. It never passes `authorize?: false`:
       when the caller turned the authorization off, the reads here still
       ask the policies.
    2. **The words.** `Rescord.Reports.Wording` turns the facts into the
       data of the template: text that is ready to show.
    3. **The document.** The data goes to the template in the virtual file
       `data.typ`, as the value `d`, which `AshTypst.Code` encodes. No text
       becomes markup of Typst. The files of the facts, the photos, go in as
       virtual files. The context comes from `AshTypst.ContextPool`, which
       clears it before another request uses it, and it reads no file
       outside `priv/typst`.

  The action returns an `AshTypst.Document` with the bytes of the PDF.
  """

  use Ash.Resource.Actions.Implementation

  alias AshTypst.{Context, ContextPool, Document}
  alias AshTypst.Resource.Info
  alias Rescord.Reports.{Facts, Wording}

  @impl true
  def run(input, opts, context) do
    report = Keyword.fetch!(opts, :report)
    organisation = Rescord.Accounts.organisation_of(context.tenant)
    made_at = DateTime.utc_now()
    options = [actor: context.actor, tenant: organisation]

    with {:ok, facts} <- Facts.read(report, input.arguments, options, made_at) do
      {files, facts} = Map.pop(facts, :files, %{})

      data =
        Wording.module().data(
          report,
          Map.merge(facts, %{organisation: organisation, made_at: made_at})
        )

      render(input.resource, report, data, files)
    end
  end

  defp render(resource, report, data, files) do
    template = Info.template!(resource, report)
    root = resource |> Info.typst_root!() |> AshTypst.PathResolver.resolve()

    options = %Context.Options{
      root: root,
      font_paths: resource |> Info.typst_font_paths!() |> AshTypst.PathResolver.resolve_all(),
      ignore_system_fonts: Info.typst_ignore_system_fonts!(resource)
    }

    with {:ok, markup} <- File.read(Path.join(root, template.source)) do
      ContextPool.with_context(options, fn ctx ->
        with :ok <- Context.set_markup(ctx, markup),
             :ok <- put_files(ctx, files),
             :ok <- Context.set_virtual_file(ctx, "data.typ", data_file(data)),
             {:ok, compiled} <- compile(ctx),
             {:ok, pdf} <- Context.export_pdf(ctx, []) do
          {:ok,
           %Document{
             format: :pdf,
             data: pdf,
             page_count: compiled.page_count,
             warnings: compiled.warnings
           }}
        end
      end)
    end
  end

  # The data of the template, as Typst code: `#let d = (...)`.
  defp data_file(data), do: "#let d = " <> AshTypst.Code.encode(data, %{}) <> "\n"

  defp put_files(ctx, files) do
    Enum.reduce_while(files, :ok, fn {path, bytes}, :ok ->
      case Context.set_virtual_file_binary(ctx, path, bytes) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp compile(ctx) do
    case Context.compile(ctx) do
      {:ok, compiled} -> {:ok, compiled}
      {:error, error} -> {:error, AshTypst.Resource.Errors.CompileError.from(error)}
    end
  end
end
