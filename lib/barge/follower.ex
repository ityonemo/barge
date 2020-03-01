defmodule Barge.Follower do
  @moduledoc """

  The reference (Figure 2) prescribes the following actions to the follower state.

  ### Followers (§5.2):

  - respond to RPCs from candidates and leaders
  - if election timeout elapses without receiving AppendEntries RPC from current
    leader or granting vote to candidate, `:timeout` to candidate.
  """

  @behaviour StateServer.State

  alias Barge.RPC.AppendEntries
  alias Barge.RPC.RequestVote

  @timeout Application.get_env(:barge, :election_timeout)

  @spec handle_info(any, Barge.data) :: {:noreply, update: Barge.data}
  # respond to RPCs from candidates.
  def handle_info(rpc = %RequestVote{}, data) do
    {resp, new_data} = RequestVote.recv(rpc, data)
    # send the result.
    RequestVote.Result.send(rpc.id, resp, data)

    # reset the timeout if we granted the request vote
    actions = [update: new_data] ++ if resp.success do
      [state_timeout: {:timeout, @timeout}]
    else
      []
    end

    {:noreply, actions}
  end
  def handle_info(rpc = %AppendEntries{}, data) do
    # respond to RPCs from candidates.
    {resp, new_data} = AppendEntries.recv(rpc, data)
    # send the result.
    AppendEntries.Result.send(rpc.id, resp, data)
    # and reset the timeout
    {:noreply, update: new_data, state_timeout: {:timeout, @timeout}}
  end
  def handle_info(_, _) do
    :noreply
  end

  def on_state_entry(_tr, _data) do
    {:noreply, state_timeout: {:timeout, @timeout}}
  end

  def handle_timeout(:timeout, _data) do
    {:noreply, transition: :timeout}
  end

end
