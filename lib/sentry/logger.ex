defmodule Sentry.Logger do
  require Logger
  @moduledoc """
    Use this if you'd like to capture all Error messages that the Plug handler might not. Simply set `use_error_logger` to true.

    This is based on the Erlang [error_logger](http://erlang.org/doc/man/error_logger.html).

    ```elixir
    config :sentry,
      use_error_logger: true
    ```
  """

  use GenEvent

  def init(_mod, []), do: {:ok, []}

  def handle_call({:configure, new_keys}, _state), do: {:ok, :ok, new_keys}

  def handle_event({_level, gl, _event}, state) when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({:error_report, _gl, {_pid, _type, [message | _]}}, state) when is_list(message) do
    try do
      {kind, exception, stacktrace, module} = get_exception_and_stacktrace(message[:error_info])
                                      |> IO.inspect(label: "get_exception_and_stacktrace")
                                      |> get_initial_call_and_module(message)
                                      |> IO.inspect(label: "get_initial_call_and_module")

      opts = get_in(message, ~w[dictionary sentry_context]a) || %{}
             |> IO.inspect(label: "get_in")
             |> Map.take(Sentry.Context.context_keys)
             |> IO.inspect(label: "take")
             |> Map.to_list()
             |> IO.inspect(label: "to_list")
             |> Keyword.put(:event_source, :logger)
             |> IO.inspect(label: "event_source")
             |> Keyword.put(:stacktrace, stacktrace)
             |> IO.inspect(label: "stacktrace")
             |> Keyword.put(:error_type, kind)
             |> IO.inspect(label: "error_type")
             |> Keyword.put(:module, module)
             |> IO.inspect(label: "module")

      Sentry.capture_exception(exception, opts)
             |> IO.inspect(label: "capture_exception")
    rescue ex ->
      Logger.warn(fn -> "Unable to notify Sentry due to #{inspect(ex)}! #{inspect(message)}" end)
    end

    {:ok, state}
  end

  def handle_event(_, state) do
    {:ok, state}
  end


  defp get_exception_and_stacktrace({kind, {exception, sub_stack}, _stack}) when is_list(sub_stack) do
    {kind, exception, sub_stack}
  end
  defp get_exception_and_stacktrace({kind, exception, stacktrace}) do
    {kind, exception, stacktrace}
  end

  # GenServer exits will usually only report a stacktrace containing core
  # GenServer functions, which causes Sentry to group unrelated exits
  # together.  This gets the `:initial_call` to help disambiguate, as it contains
  # the MFA for how the GenServer was started.
  defp get_initial_call_and_module({kind, exception, stacktrace}, error_info) do
    case Keyword.get(error_info, :initial_call) do
      {module, function, arg} ->
        {kind, exception, stacktrace ++ [{module, function, arg, []}], module}
        _ ->
          {kind, exception, stacktrace, nil}
    end
  end
end
