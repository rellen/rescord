defmodule Rescord.Metrics do
  @moduledoc """
  The metrics of the core (ADR 0077): the queries, the jobs, the actions of
  Ash, the emails, the replies of the assistant, the photos and the VM.
  `RescordWeb.Telemetry` adds those
  of the requests and of the pages, and gives the whole list to a reporter
  when the operator names a port.

  A metric describes the server, for the person who runs it. A number about
  the work of a rescue is on a page of that rescue, from the database.

  No tag of a metric holds a value that a person or a client sends: an id,
  a name, the path of a request, the name of an event of a page. Such a tag
  would make a series for each value, with no end. A tag is a module, an
  atom, or a number that the server sets.

  Ash emits an event for each kind of action of each domain, such as
  `[:ash, :residents, :create, :stop]`. `attach/0` listens to them and
  emits one event, `[:rescord, :action, :stop]`, with the domain and the
  kind as metadata, so that one metric covers each action.
  """

  import Telemetry.Metrics

  @kinds [:create, :read, :update, :destroy, :action]
  @handler "rescord-metrics-actions"

  @doc "The metrics of the core, as `Telemetry.Metrics` definitions."
  @spec metrics() :: [struct]
  def metrics do
    [
      duration("rescord.repo.query.duration.milliseconds",
        event_name: [:rescord, :repo, :query],
        measurement: :total_time,
        description: "The time of a query, with the wait for a connection"
      ),
      duration("rescord.repo.queue.duration.milliseconds",
        event_name: [:rescord, :repo, :query],
        measurement: &queue_time/1,
        description: "The time that a query waited for a connection"
      ),
      duration("rescord.action.duration.milliseconds",
        event_name: [:rescord, :action, :stop],
        measurement: :duration,
        tags: [:domain, :kind, :resource, :action],
        description: "The time of an action of Ash"
      ),
      duration("rescord.job.duration.milliseconds",
        event_name: [:oban, :job, :stop],
        measurement: :duration,
        tags: [:worker, :queue, :state],
        tag_values: &job_tags/1,
        description: "The time of a job that ended with no fault"
      ),
      counter("rescord.job.exception.count",
        event_name: [:oban, :job, :exception],
        tags: [:worker, :queue, :state],
        tag_values: &job_tags/1,
        description: "The jobs that failed: failure runs again, discard was the last try"
      ),
      counter("rescord.mail.count",
        event_name: [:swoosh, :deliver, :stop],
        tags: [:result],
        tag_values: &mail_tags/1,
        description: "The emails that Rescord gave to the mail server"
      ),
      counter("rescord.mail.exception.count",
        event_name: [:swoosh, :deliver, :exception],
        description: "The emails whose delivery raised an error"
      ),
      counter("rescord.ruby.reply.count",
        event_name: [:rescord, :ruby, :reply, :stop],
        tags: [:state, :reason],
        description: "The replies of the assistant, by how each ended and why one failed"
      ),
      sum("rescord.ruby.reply.requests.total",
        event_name: [:rescord, :ruby, :reply, :stop],
        measurement: :requests,
        description: "The requests that the assistant sent to a provider"
      ),
      sum("rescord.ruby.reply.input.tokens",
        event_name: [:rescord, :ruby, :reply, :stop],
        measurement: :input_tokens,
        description: "The new tokens of the prompts of the assistant"
      ),
      sum("rescord.ruby.reply.cache_read.tokens",
        event_name: [:rescord, :ruby, :reply, :stop],
        measurement: :cache_read_tokens,
        description: "The tokens of the prompts of the assistant that came from the cache"
      ),
      sum("rescord.ruby.reply.cache_write.tokens",
        event_name: [:rescord, :ruby, :reply, :stop],
        measurement: :cache_write_tokens,
        description: "The tokens of the prompts of the assistant that went to the cache"
      ),
      sum("rescord.ruby.reply.output.tokens",
        event_name: [:rescord, :ruby, :reply, :stop],
        measurement: :output_tokens,
        description: "The tokens of the answers of the assistant"
      ),
      sum("rescord.ruby.reply.cost.microdollars",
        event_name: [:rescord, :ruby, :reply, :stop],
        measurement: :cost_microdollars,
        description: "About what the replies of the assistant cost, in millionths of a US dollar"
      ),
      counter("rescord.photo.refused.count",
        event_name: [:rescord, :photos, :refused],
        description: "The photos that waited too long for a slot of libvips"
      ),
      last_value("rescord.vm.memory.bytes",
        event_name: [:vm, :memory],
        measurement: :total,
        description: "The memory of the VM"
      ),
      last_value("rescord.vm.run_queue.length",
        event_name: [:vm, :total_run_queue_lengths],
        measurement: :total,
        description: "The work that waits for a scheduler"
      ),
      last_value("rescord.vm.process.count",
        event_name: [:vm, :system_counts],
        measurement: :process_count,
        description: "The processes of the VM"
      )
    ]
  end

  @doc """
  A distribution of a time in milliseconds, from a measurement in the
  native unit, with the buckets of `Rescord.Metrics.Milliseconds`.
  """
  @spec duration(String.t(), keyword) :: struct
  def duration(name, options) do
    distribution(
      name,
      [
        unit: {:native, :millisecond},
        reporter_options: [peep_bucket_calculator: Rescord.Metrics.Milliseconds]
      ] ++ options
    )
  end

  @doc """
  Starts to listen to the actions of Ash. A second call changes nothing.
  Ash measures an action only while something listens.
  """
  @spec attach() :: :ok
  def attach do
    events =
      for domain <- Application.fetch_env!(:rescord, :ash_domains),
          kind <- @kinds,
          do: [:ash, Ash.Domain.Info.short_name(domain), kind, :stop]

    case :telemetry.attach_many(@handler, events, &__MODULE__.relay/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc false
  def relay([:ash, domain, kind, :stop], measurements, metadata, _config) do
    :telemetry.execute([:rescord, :action, :stop], measurements, %{
      domain: domain,
      kind: kind,
      resource: metadata[:resource_short_name],
      action: metadata[:action]
    })
  end

  # A query that needed no wait has no such measurement.
  defp queue_time(measurements), do: measurements[:queue_time] || 0

  defp job_tags(%{job: job} = metadata),
    do: %{worker: job.worker, queue: job.queue, state: metadata[:state]}

  defp mail_tags(metadata),
    do: %{result: if(Map.has_key?(metadata, :error), do: :error, else: :ok)}
end
