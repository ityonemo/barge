defmodule Barge.RPC do

  @moduledoc """
  describes the form that all RPCs must have.  Also provides compile-time tools
  which ensure that the RPCs follow these contracts.
  """

  @type rpc_module ::
    Barge.RPC.AppendEntries |
    Barge.RPC.AppendEntries.Result |
    Barge.RPC.RequestVote |
    Barge.RPC.RequestVote.Result

  @typep barge_term :: Barge.barge_term

  @type empty_rpc :: %{
    optional(atom) => any,
    __struct__: rpc_module,
    term:       0,
    id:         nil,
    success:    boolean,
  }

  @type rpc :: %{
    optional(atom) => any,
    __struct__: rpc_module,
    term:       barge_term,
    id:         pid,
    success:    boolean
  }

  @spec brand(empty_rpc, Barge.data) :: rpc
  @doc """
  a tool that ensures that all outgoing Barge RPCs carry with them appropriate information
  for the receiver to

  should generally be called by the `c:send/2` functions.
  """
  def brand(rpc, srv) do
    %{rpc | term: srv.term, id: self()}
  end

  @callback recv(rpc, Barge.data) :: empty_rpc | nil
  @callback send(pid, empty_rpc, Barge.data) :: rpc

end
