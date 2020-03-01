defmodule Barge.Candidate do
  @moduledoc """

  The reference (Figure 2) prescribes the following actions to the candidate state.

  ### Candidates (§5.2):

  - On conversion to candidate, start election:
    - Increment `:term`
    - Vote for self.
    - Reset election timer.
    - Send RequestVote RPC to all other servers
  - If votes received from a majority of servers: `:accede` to leader
  - If AppendEntries RPC received from a new leader, `:concede` to follower.
  - If election timeout elapses, start a new election.
  """

  @behaviour StateServer.State

  @timeout Application.get_env(:barge, :election_timeout)

  alias Barge.RPC.AppendEntries
  alias Barge.RPC.RequestVote

  @doc """
  - On conversion to candidate, start election:
    - Increment `:term`
    - Vote for self.
    - Reset election timer.
    - Send RequestVote RPC to all other servers
  """
  def on_state_entry(_tr, data) do
    # Send RequestVote to all other servers.
    Enum.each(data.net, fn node ->
      RequestVote.send(
        node,
        %RequestVote{},
        data)
    end)

    {:noreply, update:
      %{data |
        term: data.term + 1,              # - Increment `:term`
        voted_for: self()},                # - Vote for self.
      state_timeout: {:timeout, @timeout}} # - Reset election timer.
  end

  def handle_timeout(:timeout, _data) do
    {:noreply, transition: :timeout}
  end

  @doc """
  tests if the incoming vote cast plus the candidate is more than half the size of the
  barge network.  Note that the network doesn't include self().
  """
  defguard is_majority(votes, net) when 2 * votes > net

  def handle_info(%RequestVote.Result{success: true},
                  data = %{net: net, votes_received: votes})
                  when is_majority(length(votes) + 2, length(net) + 1) do
    {:noreply, transition: :accede, update: %{data | votes_received: []}}
  end
  def handle_info(%RequestVote.Result{id: who, success: true},
                  data = %{votes_received: votes_received}) do
    {:noreply, update: %{data | votes_received: [who | votes_received]}}
  end
  def handle_info(rpc = %AppendEntries{term: rpc_term}, data = %{term: srv_term})
      when rpc_term < srv_term do
    # if we encounter an AppendEntries RPC from an invalid leader, send a unsuccesful
    # result.
    AppendEntries.Result.send(rpc.id, %AppendEntries.Result{success: false}, data)
    :noreply
  end
  def handle_info(rpc = %AppendEntries{}, data) do
    # respond to RPCs from a real leader.
    {resp, new_data} = AppendEntries.recv(rpc, data)
    # send the result.
    AppendEntries.Result.send(rpc.id, resp, data)
    {:noreply, transition: :concede, update: new_data}
  end
  def handle_info(_, _data) do
    :noreply
  end
end
