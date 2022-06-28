defmodule OpenTelemetryDecorator do
  @external_resource "README.md"

  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.filter(&(&1 =~ ~R{<!\-\-\ INCLUDE\ \-\->}))
             |> Enum.join("\n")
             # compensate for anchor id differences between ExDoc and GitHub
             |> (&Regex.replace(~R{\(\#\K(?=[a-z][a-z0-9-]+\))}, &1, "module-")).()

  use Decorator.Define, trace: 1, trace: 2
  require Logger

  @doc """
  Decorate a function to add an OpenTelemetry trace with a named span.

  You can provide span attributes by specifying a list of variable names as atoms.
  This list can include:

  - any variables (in the top level closure) available when the function exits,
  - the result of the function by including the atom `:result`,
  - map/struct properties using nested lists of atoms.

  ```elixir
  defmodule MyApp.Worker do
    use OpenTelemetryDecorator

    @decorate trace("my_app.worker.do_work", include: [:arg1, [:arg2, :count], :total, :result])
    def do_work(arg1, arg2) do
      total = arg1.count + arg2.count
      {:ok, total}
    end
  end
  ```
  """
  def trace(span_name, opts \\ [], body, context) do
    include = Keyword.get(opts, :include, [])
    service = Keyword.get(opts, :service)
    type = Keyword.get(opts, :type)
    Validator.validate_args(span_name, include)

    quote location: :keep do
      require OpenTelemetry.Span
      require OpenTelemetry.Tracer

      OpenTelemetry.Tracer.update_name(unquote(service))

      OpenTelemetry.Tracer.with_span unquote(span_name) do
        span_ctx = OpenTelemetry.Tracer.current_span_ctx()
        result = unquote(body)

        included_attrs = Attributes.get(Kernel.binding(), unquote(include), result)

        OpenTelemetry.Span.set_attributes(span_ctx, included_attrs)

        result
      end
    end
  rescue
    e in ArgumentError ->
      target = "#{inspect(context.module)}.#{context.name}/#{context.arity} @decorate telemetry"
      reraise %ArgumentError{message: "#{target} #{e.message}"}, __STACKTRACE__
  end

  @doc """
  Add a new key in Logger metadata or update it
  """
  def add_metadata(module_key, key, data) do
    module_metadata =
      Logger.metadata()
      |> Keyword.get(module_key, %{})
      |> Map.put(key, data)

    update_metadata(module_key, module_metadata)
  end

  def add_metadata_from_list(module_key, metadata) when is_list(metadata) do
    current_metadata = Logger.metadata() |> Keyword.get(module_key, %{})

    module_metadata =
      Enum.reduce(metadata, current_metadata, fn {key, data}, acc ->
        Map.put(acc, key, data)
      end)

    update_metadata(module_key, module_metadata)
  end

  def add_metadata_from_list(_, _), do: nil

  defp update_metadata(key, metadata) do
    Keyword.new()
    |> Keyword.put(key, metadata)
    |> Logger.metadata()
  end
end
