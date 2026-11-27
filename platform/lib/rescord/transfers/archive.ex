defmodule Rescord.Transfers.Archive do
  @moduledoc """
  The transfer file between two Rescord servers (ADR 0043): a `.rescord`
  file.

  The file is three parts in a frame, and not a zip, so that nothing
  decompresses before the signature is checked:

      "RSCD", 1, length of the header (32 bits), header,
      length of the signature (16 bits), signature, payload

    * the header is JSON: who sends it and to whom, which is not secret,
      with the fields of the encryption (`Rescord.Transfers.Crypto.seal/4`);
    * the signature is the Ed25519 signature of the exact bytes of the
      header;
    * the payload is a zip archive, encrypted for the refuge that receives
      it.

  The zip holds `transfer.json`, with the copy of the resident,
  and one entry `files/<id>` for each file of the copy: the files of its
  entries, and its photos and their thumbnails (ADR 0057).

  `read/4` checks the signature with the key of a recorded partner before
  it decrypts anything, and the zip after that before it decompresses
  more than it allows: it reads the sizes in the directory of the zip
  first, and each name must be a name of the format. The copy then goes through
  `Rescord.Transfers.Snapshot.clean/1`, and each file must be a file that
  the copy names, with its size, and of a type that Rescord takes.
  """

  alias Rescord.Transfers.{Crypto, Snapshot}

  @format "rescord-transfer"
  @version 1

  # The largest archive, and the largest decompressed contents, in bytes.
  @max_size 300_000_000
  # The copy, and the files: a photo is two of them, with its thumbnail.
  @max_entries 5001

  @doc "The largest transfer file that an import takes, in bytes."
  def max_size, do: @max_size

  @doc """
  Writes the transfer file. `transfer` holds the facts that the receiver
  reads: `"export_id"`, `"from_refuge"`, `"from_name"`, `"to_refuge"`,
  `"resident_name"`, `"parts"`, `"note"`, `"sent_at"` and `"copy"`. `files`
  is a list of `{id, bytes}`.
  """
  @spec write(map, [{String.t(), binary}], Crypto.keys(), map) :: binary
  def write(transfer, files, sender_keys, partner) do
    inner =
      zip!(
        [{~c"transfer.json", Jason.encode!(transfer)}] ++
          for({id, bytes} <- files, do: {~c"files/#{id}", bytes})
      )

    sealed =
      Crypto.seal(
        inner,
        %{
          "format" => @format,
          "version" => @version,
          "export_id" => transfer["export_id"],
          "from_refuge" => transfer["from_refuge"],
          "to_refuge" => partner.refuge_id
        },
        sender_keys.sign_private,
        partner.box_public
      )

    <<"RSCD", @version, byte_size(sealed.header)::32, sealed.header::binary,
      byte_size(sealed.signature)::16, sealed.signature::binary, sealed.payload::binary>>
  end

  @doc """
  Reads a transfer file for the refuge with the id `refuge_id` and the keys
  `keys`. `partner_of` takes the id of the refuge that sent it, and returns
  its recorded partner, or `nil`.

  Returns the partner, the facts of the transfer with a clean copy, and
  the files as a map from id to bytes. Each error is words that follow
  "File" for the person who imports it.
  """
  @spec read(binary, String.t(), Crypto.keys(), (String.t() -> map | nil)) ::
          {:ok, map, map, %{String.t() => binary}} | {:error, String.t()}
  def read(bytes, refuge_id, keys, partner_of) when is_binary(bytes) do
    with {:ok, header, signature, payload} <- frame(bytes),
         {:ok, %{"format" => @format, "version" => @version} = fields} <- Jason.decode(header),
         true <- fields["to_refuge"] == refuge_id || {:error, :not_ours},
         %{} = partner <- partner_of.(fields["from_refuge"]) || {:error, :no_partner},
         {:ok, inner, _fields} <-
           Crypto.open(header, signature, payload, partner.sign_public, keys.box_private),
         {:ok, contents} <- unzip(inner, &(&1 == "transfer.json" or file_name?(&1))),
         {:ok, transfer} <- Jason.decode(contents["transfer.json"] || ""),
         {:ok, transfer} <- check(transfer, fields, partner),
         {:ok, files} <- files(transfer["copy"], contents) do
      {:ok, partner, transfer, files}
    else
      {:error, reason} -> {:error, words(reason)}
      _other -> {:error, words(:format)}
    end
  end

  def read(_bytes, _refuge_id, _keys, _partner_of), do: {:error, words(:format)}

  defp frame(
         <<"RSCD", @version, header_size::32, header::binary-size(header_size),
           signature_size::16, signature::binary-size(signature_size), payload::binary>>
       ),
       do: {:ok, header, signature, payload}

  defp frame(_bytes), do: {:error, :format}

  defp words(:not_ours), do: "is for another refuge"
  defp words(:no_partner), do: "comes from a refuge that is not a partner of this one"
  defp words(:signature), do: "does not carry the signature of the refuge that it names"

  defp words(reason) when reason in [:payload, :decrypt],
    do: "changed on its way, or it is not for this refuge"

  defp words(:too_large), do: "holds more than Rescord takes"
  defp words(:files), do: "has files that do not match its copy"
  defp words(_format), do: "is not a transfer file of Rescord"

  # The facts inside must match the signed header, and the copy must clean.
  defp check(%{"copy" => copy} = transfer, fields, partner) do
    with true <- transfer["export_id"] == fields["export_id"],
         true <- transfer["from_refuge"] == partner.refuge_id,
         true <- transfer["to_refuge"] == fields["to_refuge"],
         {:ok, _id} <- Ecto.UUID.cast(transfer["export_id"]),
         {:ok, copy} <- Snapshot.clean(copy) do
      {:ok,
       %{
         "export_id" => transfer["export_id"],
         "resident_name" => text(transfer["resident_name"], 200),
         "note" => text(transfer["note"], 2000),
         "parts" => parts(transfer["parts"]),
         "copy" => copy
       }}
    else
      _bad -> {:error, :format}
    end
  end

  defp check(_transfer, _fields, _partner), do: {:error, :format}

  # Each file that the copy names is in the archive, with its size and a
  # type that Rescord takes, and the archive has no other file.
  defp files(copy, contents) do
    named = for file <- Snapshot.files(copy), into: %{}, do: {file["id"], file}
    present = for {"files/" <> id, bytes} <- contents, into: %{}, do: {id, bytes}

    if Map.keys(named) |> Enum.sort() == Map.keys(present) |> Enum.sort() and
         Enum.all?(named, fn {id, file} ->
           bytes = present[id]

           byte_size(bytes) == file["size"] and
             Rescord.Journal.file_type(bytes) == file["content_type"]
         end),
       do: {:ok, present},
       else: {:error, :files}
  end

  defp parts(list) when is_list(list) do
    for text <- list, part <- Snapshot.parts(), Atom.to_string(part) == text, uniq: true, do: part
  end

  defp parts(_other), do: []

  defp text(value, most) when is_binary(value), do: String.slice(value, 0, most)
  defp text(_value, _most), do: nil

  defp file_name?("files/" <> id), do: match?({:ok, ^id}, Ecto.UUID.cast(id))
  defp file_name?(_name), do: false

  defp zip!(entries) do
    {:ok, {_name, bytes}} = :zip.create(~c"rescord.zip", entries, [:memory])
    bytes
  end

  # The entries of a zip in memory, as a map from name to bytes, when each
  # name passes `allowed?`, when no name comes two times, and when the sum
  # of the sizes in its directory is within the limit.
  defp unzip(bytes, allowed?) do
    with {:ok, [_comment | files]} <- :zip.list_dir(bytes),
         names = for({:zip_file, name, info, _, _, _} <- files, do: {List.to_string(name), info}),
         true <- length(names) <= @max_entries || {:error, :too_large},
         true <- Enum.all?(names, fn {name, _info} -> allowed?.(name) end) || {:error, :format},
         true <- length(Enum.uniq_by(names, &elem(&1, 0))) == length(names) || {:error, :format},
         true <-
           Enum.sum(for {_name, info} <- names, do: elem(info, 1)) <= @max_size ||
             {:error, :too_large},
         {:ok, entries} <- :zip.unzip(bytes, [:memory]),
         true <-
           Enum.sum(for {_name, data} <- entries, do: byte_size(data)) <= @max_size ||
             {:error, :too_large} do
      {:ok, Map.new(entries, fn {name, data} -> {List.to_string(name), data} end)}
    else
      {:error, reason} when reason in [:too_large, :format] -> {:error, reason}
      _bad -> {:error, :format}
    end
  rescue
    _error -> {:error, :format}
  end
end
