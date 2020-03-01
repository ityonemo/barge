defmodule Barge.Leader do
  @moduledoc """
  The reference (Figure 2) prescribes the following actions to the leader state.

  ### Leaders:

  - Upon election: send initial empty AppendEntries RPCs (heartbeat) to each
    server, repeat during idle periods to prevent election timeouts (§5.2)
  - If command received from client: append entry to local log, respond after
    entry applied to state machine (§5.3)
  - If `log.last_index()` >= `:next_index` for a follower, send AppendEntries RPC
    with log entries starting at next index.
    - If successful: update `:next_index` and `:match_index` for the follower
      (§5.3)
    - If AppendEntries RPC fails because of log inconsistency: decrement nextIndex
      and retry (§5.3)
  - If there exists an N such that N > `:commit_index`, a majority of `:match_index`
    >= N and `log[N].term == :term`: set `:commit_index == N` (§5.3, §5.4).
  """

  @behaviour StateServer.State

  alias Barge.RPC.AppendEntries

  @heartbeat_timeout Application.get_env(:barge, :heartbeat_timeout)

  @spec do_send_heartbeat(Barge.data) :: :ok
  defp do_send_heartbeat(data = %{next_index: next_index}) do
    Enum.each(data.net, &AppendEntries.send(&1, next_index[&1], data))
  end

  @doc """
  ### Volatile state on leaders:

  (reinitialized after election)
  - `:next_index` (`%{optional(pid) => non_neg_integer}`) - for each server,
    index of the next log entry to send to that server (initialized to
    `log.last_index() + 1`)
  - `:match_index` (`%{optional(pid) => non_neg_integer}`) - for each server,
    index of the  highest log entry known to be replicated on the server
    (initialized to 0, increases monotonically)

  ### Instructions for leaders:

  - Upon election: send initial empty AppendEntries RPCs (heartbeat) to each
  server, repeat during idle periods to prevent election timeouts (§5.2)
  """
  def on_state_entry(_tr, data = %{net: net, log: {module, log_id}}) do
    last_log_index = module.last_log_index(log_id)

    # for each server, index of the next log entry to send to that server is initialized to
    # `log.last_index() + 1`
    next_index = for server <- net, into: %{}, do: {server, last_log_index + 1}

    # for each server, index of the  highest log entry known to be replicated on the server
    # initialized to 0
    match_index = for server <- net, into: %{}, do: {server, 0}

    new_data = %{data | next_index: next_index, match_index: match_index}

    do_send_heartbeat(new_data)
    {:noreply, update: new_data, state_timeout: {:heartbeat, @heartbeat_timeout}}
  end

  def handle_timeout(:heartbeat, data) do
    do_send_heartbeat(data)
    {:noreply, state_timeout: {:heartbeat, @heartbeat_timeout}}
  end

  def handle_info(%AppendEntries.Result{success: true, index: index, id: who}, data) do
    new_data = data
    |> Map.merge(%{
      next_index: Map.put(data.next_index, who, index + 1),
      match_index: Map.put(data.match_index, who, index)
    })
    |> do_update_commit_index
    |> do_respond_to_calls

    # check for an update on the commit_index
    {:noreply, update: new_data}
  end
  def handle_info(%AppendEntries.Result{success: false, id: who, index: index}, data) do
    new_data = %{data | next_index: Map.put(data.next_index, who, index)}
    {:noreply, update: new_data}
  end
  def handle_info(_, _), do: :noreply

  def handle_call({:command, command}, from, data = %{log: {module, log_id}}) do
    # If command received from client: append entry to local log.
    index = module.push(log_id, {data.term, command})
    # propagate the message.
    Enum.each(data.net, &AppendEntries.send(&1, index, data))
    {:noreply, update: %{data | pending_calls: [{index, from} | data.pending_calls]}}
  end

  @doc """
  fulfills the following spec:
    - If there exists an N such that N > `:commit_index`, a majority of `:match_index`
    >= N and `log[N].term == :term`: set `:commit_index == N` (§5.3, §5.4).
  """
  def do_update_commit_index(data = %{log: {module, log_id}}, proposed_commit_index \\ nil) do
    proposed_commit_index = proposed_commit_index || data.commit_index
    # perform linear search by incrementing on proposed commit index.
    # check if the two properties are fulfilled.
    forward_viable = majority_greater_than(data.match_index, proposed_commit_index)
    commit_term = module.term_for(log_id, proposed_commit_index)
    cond do
      forward_viable && commit_term && (commit_term == data.term) ->
        # update the commit index, making it permanent and finalizing it, keep trying to
        # go higher.
        do_update_commit_index(%{data | commit_index: proposed_commit_index}, proposed_commit_index + 1)
      forward_viable && commit_term ->
        # don't save the proposed commit index, but keep searching for a higher N.
        do_update_commit_index(data, proposed_commit_index + 1)
      true ->
        # quit iterating.
        data
    end
  end

  defp majority_greater_than(match_index, commit_index) do
    {gt, tot} = Enum.reduce(match_index, {0, 0}, fn
      {_, index}, {gt, tot} when index >= commit_index -> {gt + 1 , tot + 1}
      _, {gt, tot} -> {gt, tot}
    end)
    2 * gt >= tot # note that the leader can serve as a tiebreaker.
  end

  def do_respond_to_calls(data = %{commit_index: commit_index, pending_calls: pending_calls}) do
    {resps, remaining_calls} = Enum.split_with(pending_calls, fn {idx, _} -> idx <= commit_index end)
    Enum.each(resps, fn {_, from} -> GenServer.reply(from, :ok) end)
    %{data | pending_calls: remaining_calls}
  end

end
