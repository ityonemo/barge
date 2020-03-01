defmodule Barge.RPC.AppendEntries do

  @moduledoc """
  implements the Raft AppendEntries RPC.

  according to Figure 2, the RPC should be implemented as follows:

  ## AppendEntries RPC

  invoked by leader to replicate log entries (§5.3); also used as a heartbeat (§5.2)

  ### Arguments

  - `:term` (`non_neg_integer`) - leader's `:term`
  - `:id` (`non_neg_integer`) - return address, saved by followers to redirect
    clients
  - `:prev_log_index` (`non_neg_integer`) - index of log entry immediately
    preceding new ones
  - `:prev_log_term` (`non_neg_integer`) - term of the `:prev_log_index` entry
  - `:entries` (`list(entry)`) - log entries to store (empty for heartbeat; may
    send more than one for efficiency)
  - `:leader_commit` (`non_neg_integer`) - leader's commit index

  ### Results

  - `:term` (`non_neg_integer`) - current term, for leader to update itself.
  - `:success` (`boolean`) - `true` if follower contained entry matching
    `:prev_log_index` and `:prev_log_term`

  ### Receiver Implementation:

  1. Reply `false` if RPC term < server term. (§5.1)
  2. Reply `false` if log doesn't contain an entry at `:prev_log_index` whose
    term matches `:prev_log_term` (§5.3)
  3. If an existing entry conflicts with a new one (same index but different
    terms), delete the existing entry and all that follow it (§5.3)
  4. Append an new entries not already in the log
  5. If leader commit > commit index set commit index to the minimum of
    leader commit and the last new entry.
  """

  defstruct [:id, :entries, :leader_commit , :prev_log_index, :prev_log_term, term: 0]

  @typep barge_term  :: Barge.barge_term
  @typep barge_index :: Barge.barge_index
  @typep entry       :: Barge.entry

  @type t :: %__MODULE__{
    term:           barge_term,
    id:             pid,
    prev_log_index: barge_index,
    prev_log_term:  barge_term,
    entries:        [entry],
    leader_commit:  barge_index
  }

  defmodule Result do

    @moduledoc """
    ### Results

    - `:term` (`t:Barge.term/0`) - current term, for leader to update itself.
    - `:success` (`t:boolean/0`) - `true` if follower contained entry matching
      `:prev_log_index` and `:prev_log_term`

    #### Not in official spec:

    - `:index` (`t:Barge.index/0`) - if successful, index of last appended term.
      if unsuccessful, the previous reliable appended term.  If the leader tried
      to send log entries that are too far forward, reply with the last existing
      index.  If the leader tried to send a conflicting log entry, reply with the
      index prior to the attempted index.
    """

    defstruct [:id, success: false, index: 0, term: 0]

    alias Barge.RPC

    @typep barge_term  :: Barge.barge_term
    @typep barge_index :: Barge.barge_index

    @type t :: %__MODULE__{
      term:    barge_term,
      id:      pid,
      success: boolean,
      index:   barge_index
    }

    @type empty_t :: %__MODULE__{
      term:    0,
      id:      nil,
      success: boolean,
      index:   barge_index
    }

    @spec send(pid, empty_t, Barge.data) :: t
    def send(pid, rpc, data) do
      send(pid, RPC.brand(rpc, data))
    end

    @spec send_resp_term(t, Barge.data) :: nil
    def send_resp_term(_, _), do: nil

  end

  alias Barge.RPC

  @spec send(pid, non_neg_integer, Barge.data) :: t
  def send(pid, index, data = %{log: {module, log_id}}) do
    prev_log_index = index - 1
    prev_log_term = module.term_for(log_id, prev_log_index)
    send(pid, RPC.brand(%__MODULE__{
      prev_log_index: prev_log_index,
      prev_log_term:  prev_log_term,
      entries:        module.entries_from(log_id, index),
      leader_commit:  data.commit_index
    }, data))
  end

  @spec recv(t, Barge.data) :: {Result.empty_t, Barge.data}
  @doc """
  implements the Raft AppendEntries RPC receiver implementation.

  according to Figure 2, this should be implemented as follows:

  ### Receiver Implementation:

  1. Reply `false` if RPC term < server term. (§5.1)
  2. Reply `false` if log doesn't contain an entry at `:prev_log_index` whose
    term matches `:prev_log_term` (§5.3)
  3. If an existing entry conflicts with a new one (same index but different
    terms), delete the existing entry and all that follow it (§5.3)
  4. Append any new entries not already in the log
  5. If leader commit > commit index set commit index to the minimum of
    leader commit and the last new entry.
  """
  #  1. Reply `false` if RPC term < server term. (§5.1)
  def recv(%{term: rpc_term}, data = %{term: srv_term})
      when rpc_term < srv_term do
    {%Result{success: false}, data}
  end
  # 2. Reply `false` if log doesn't contain an entry at `:prev_log_index` whose
  #   term matches `:prev_log_term` (§5.3)
  def recv(rpc, data = %{log: {mod, log_id}}) do
    # as an optimization, return early if the log's top index is too low.
    last_log_index = mod.last_log_index(log_id)
    result = cond do
      rpc.prev_log_index > last_log_index ->
        # instruct the leader to roll back the log index as appropriate.
        %Result{success: false, index: last_log_index}
      rpc.prev_log_term != mod.term_for(log_id, rpc.prev_log_index) ->
        # 3. If an existing entry conflicts with a new one (same index but
        # different terms), delete the existing entry and all that follow it
        # (§5.3)
        mod.delete_from_index(log_id, rpc.prev_log_index)
        # instruct the leader to decrement the correct log index by one.
        %Result{success: false, index: rpc.prev_log_index - 1}
      true ->
        # 4. Append any new entries not already in the log
        index = mod.append(log_id, rpc.entries)
        %Result{success: true, index: index}
    end
    # 5. If leader commit > commit index set commit index to the minimum of
    #   leader commit and the last new entry.
    new_commit = min(rpc.leader_commit, mod.last_log_index(log_id))
    {result, %{data | commit_index: new_commit}}
  end

  @spec send_resp_term(t, Barge.data) :: Result.t
  def send_resp_term(rpc = %{entries: []}, data) do
    send(rpc.id, RPC.brand(%Result{success: true}, data))
  end
  def send_resp_term(rpc, data) do
    send(rpc.id, RPC.brand(%Result{success: false}, data))
  end

end

