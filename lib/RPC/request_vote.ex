defmodule Barge.RPC.RequestVote do

  @moduledoc """
  implements the Raft RequestVote RPC.

  according to Figure 2, the RPC should be implemented as follows:

  ## RequestVote RPC

  invoked by candidates to gather votes (§5.2)

  ### Arguments

  - `:term` (`non_neg_integer`) - candidate's term
  - `:id` (`pid`) - candidate requesting vote
  - `:last_log_index` (`non_neg_integer`) - index of candidate's last log entry
    (§5.4)
  - `:last_log_term` (`non_neg_integer`) - term of candidate's last log entry
    (§5.4)

  ### Results

  - `:term` (`non_neg_integer`) - current term, for candidate to update itself.
  - `:success` (`boolean`) - `true` if candidate received vote

  ### Receiver implementation

  1. Reply `false` if RPC term < server term (§5.1)
  2. If server's `:voted_for` is `nil` or `:id`, and candidate's log is at least
    as up-to-date as receiver's log, grant the vote (§5.2, §5.4)

  """

  defstruct [:id, :last_log_index, :last_log_term, term: 0]

  alias Barge.RPC

  @typep barge_term  :: Barge.barge_term
  @typep barge_index :: Barge.barge_index

  @type empty_t :: %__MODULE__{
    term:           nil,
    id:             0,
    last_log_index: barge_index,
    last_log_term:  barge_term
  }

  @type t :: %__MODULE__{
    term:           barge_term,
    id:             pid,
    last_log_index: barge_index,
    last_log_term:  barge_term
  }

  defmodule Result do

    @moduledoc """
    implements the following struct:

    ### Results

    - `:term` (`non_neg_integer`) - current term, for candidate to update itself.
    - `:success` (`boolean`) - `true` if candidate received vote
    """

    defstruct [:id, success: false, term: 0]

    alias Barge.RPC

    @typep barge_term  :: Barge.barge_term

    @type empty_t :: %__MODULE__{
      term:    0,
      id:      nil,
      success: boolean
    }

    @type t :: %__MODULE__{
      term:    barge_term,
      id:      pid,
      success: boolean
    }

    @spec send(pid, empty_t, Barge.data) :: t
    def send(pid, rpc, data) do
      send(pid, RPC.brand(rpc, data))
    end

  end

  @spec recv(t, Barge.data) :: {Result.empty_t, Barge.data}
  @doc """
  implements the Raft RequestVote RPC receiver implementation.

  according to Figure 2, this should be implemented as follows:

  1. Reply `false` if RPC term < server term (§5.1)
  2. If server's `:voted_for` is `nil` or `:id`, and candidate's log is at least
    as up-to-date as receiver's log, grant the vote (§5.2, §5.4)
  """
  # 1. Reply `false` if RPC term < server term (§5.1)
  def recv(%{term: rpc_term}, data = %{term: srv_term}) when rpc_term < srv_term do
    {%Result{success: false}, data}
  end
  def recv(rpc = %{id: candidate}, data = %{log: {mod, log_id}, voted_for: whom})
      when is_nil(whom) or (whom == candidate) do
    # 2. If server's `:voted_for` is `nil` or `:id`, and candidate's log is at least
    # as up-to-date as receiver's log, grant the vote (§5.2, §5.4)
    # TODO: consider compactifying this.
    last_log_index = mod.last_log_index(log_id)
    if (rpc.last_log_index >= last_log_index) &&
        (rpc.last_log_term >= mod.term_for(log_id, last_log_index)) do
      {%Result{success: true}, %{data | voted_for: rpc.id}}
    else
      {%Result{success: false}, data}
    end
  end
  def recv(_, data) do
    {%Result{success: false}, data}
  end

  @spec send(pid, empty_t, Barge.data) :: t
  def send(pid, rpc, data = %{log: {mod, log_id}}) do
    last_log_index = mod.last_log_index(log_id)
    last_log_term = mod.term_for(log_id, last_log_index)
    send(pid, RPC.brand(%{rpc |
      last_log_index: last_log_index,
      last_log_term: last_log_term
    }, data))
  end

end

