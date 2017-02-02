defmodule ProbeStage do
  def trace(pid, flags \\ []) do
    GenServer.call(__MODULE__, {:trace, pid, flags})
  end

  def start_link() do
    GenServer.start_link(__MODULE__, nil, [name: __MODULE__])
  end

  def init(_) do
    send_ms = [{[:_, {:"$gen_producer", {:_, :_}, :_}], [], []},
               {[:_, {:"$gen_consumer", {:_, :_}, :_}], [], []}]
    recv_ms = [{[:_, :_, {:"$gen_producer", {:_, :_}, :_}], [], []},
               {[:_, :_, {:"$gen_consumer", {:_, :_}, :_}], [], []}]
    _ = :erlang.trace_pattern(:send, send_ms, [])
    _ = :erlang.trace_pattern(:receive, recv_ms, [])
    report_timer()
    {:ok, %{}}
  end

  def handle_call({:trace, pid, flags}, _, state) do
    flags =  [:send, :receive, :monotonic_timestamp] ++ flags
    {:reply, :erlang.trace(pid, true, flags), state}
  end

  def handle_info({:trace_ts, _, :send, {tag, {_, ref}, msg}, _, time}, state) do
    {:noreply, handle_trace({ref, send_tag(tag)}, msg, time, state)}
  end
  def handle_info({:trace_ts, _, :receive, {tag, {_, ref}, msg}, time}, state) do
    {:noreply, handle_trace({ref, receive_tag(tag)}, msg, time, state)}
  end
  def handle_info(:report, state) do
    report_timer()
    {:noreply, report(state)}
  end

  defp send_tag(:"$gen_producer"), do: :consumer
  defp send_tag(:"$gen_consumer"), do: :producer

  defp receive_tag(:"$gen_producer"), do: :producer
  defp receive_tag(:"$gen_consumer"), do: :consumer

  defp handle_trace(key, {:subscribe, _, _}, _, state) do
    handle_subscribe(key, state)
  end
  defp handle_trace(key, {:ask, demand}, time, state) do
    handle_ask(key, demand, time, state)
  end
  defp handle_trace(key, [_|_] = events, time, state) do
    handle_events(key, events, time, state)
  end
  defp handle_trace(key, {:cancel, _}, _, state) do
    Map.delete(state, key)
  end
  defp handle_trace(_, _, _, state) do
    state
  end

  defp handle_subscribe(key, state) do
    Map.put(state, key, {:queue.new(), 0, 0, 0, 0})
  end

  defp handle_ask(key, demand, time, state) do
    case state do
      %{^key => sub} ->
        %{state | key => sub_ask(sub, demand, time)}
      %{} ->
        state
    end
  end

  defp sub_ask({asks, ints_sum, ints, count_sum, counts}, demand, time) do
    {:queue.in({demand, time}, asks), ints_sum, ints, count_sum, counts}
  end

  defp handle_events(key, events, time, state) do
    case state do
      %{^key => sub} ->
        %{state | key => sub_events(sub, length(events), time)}
      %{} ->
        state
    end
  end

  defp sub_events({asks, int_sum, ints, count_sum, counts}, count, time) do
    {{:value, {demand, prev_time}}, asks} = :queue.out(asks)
    case count - demand do
      count when count > 0 ->
        int_sum = int_sum + (demand * (time - prev_time))
        count_sum = count_sum+demand
        sub_events({asks, int_sum, ints+demand, count_sum, counts}, count, time)
      0 ->
        int_sum = int_sum + (demand * (time - prev_time))
        {asks, int_sum, ints+demand, count_sum+count, counts+1}
      demand ->
        asks = :queue.in_r({demand, prev_time}, asks)
        int_sum = int_sum + (count * (time - prev_time))
        {asks, int_sum, ints+count, count_sum+count, counts+1}
    end
  end

  defp report_timer() do
    interval = Application.get_env(:probe_stage, :interval, 5000)
    Process.send_after(self(), :report, interval)
  end

  defp report(state) do
    :maps.map(&report/2, state)
  end

  defp report(_, {_, 0, 0, 0, 0} = sub), do: sub
  defp report({ref, type}, {asks, int_sum, ints, count_sum, counts}) do
    IO.puts(format_report(ref, type, int_sum, ints, count_sum, counts))
    {asks, 0, 0, 0, 0}
  end

  defp format_report(ref, type, int_sum, ints, count_sum, counts) do
    [?\n,
     "Subscription: ", inspect(ref), ?\s, Atom.to_string(type), ?\n,
     "Mean Delay:   ", mean_delay(int_sum, ints), ?\n,
     "Mean Batch:   ", mean_batch(count_sum, counts), ?\n,
     "Events:       ", Integer.to_string(count_sum)]
  end

  defp mean_delay(int_sum, ints) do
    units = Application.get_env(:probe_stage, :time_unit, :microseconds)
    int_sum
    |> div(ints)
    |> System.convert_time_unit(:nanoseconds, units)
    |> format_delay(units)
  end

  defp format_delay(delay, units) do
    [Integer.to_string(delay), ?\s | to_string(units)]
  end

  defp mean_batch(count_sum, counts) do
    count_sum
    |> div(counts)
    |> Integer.to_string()
  end
end
