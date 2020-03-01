defmodule Barge do
  @moduledoc """
  Barge is an implementation of the Raft consensus prototcol.

  see: https://raft.github.io/

  and the primary reference:
  https://raft.github.io/raft.pdf

  The reference (Figure 2) prescribes the following state for the barge data structure

  ## State

  ### Persistent State on all servers:

  (updated on stable storage before responding to RPCs)
  - `:term` - (`non_neg_integer`) latest term server has seen (initialized to 0
    on first boot, increases monotonically)
  - `:voted_for` - (`pid`) that received vote in current term (or `nil` if none)
  - `:log` (`{module, term}`) (see below) log entries, each entry contains command
    for state machine, and term when entry was received by leader (first index is 1)

  ### Volatile state on all servers:

  - `:commit_index` (`non_neg_integer`) - index of highest log entry known to be
    committed (initialized to 0, increases monotonically)
  - `:last_applied` (`non_neg_integer`) - index of highest log entry applied to
    state machine (initialized to 0, increases monotonically)

  ### Volatile state on leaders:

  (reinitialized after election)
  - `:next_index` (`%{optional(pid) => non_neg_integer}`) - for each server,
    index of the next log entry to send to that server (initialized to
    `log.last_index() + 1`)
  - `:match_index` (`%{optional(pid) => non_neg_integer}`) - for each server,
    index of the  highest log entry known to be replicated on the server
    (initialized to 0, increases monotonically)

  ## Log

  the `:log` parameter should be a `{module, term}` value, where the module
  satisfies the Barge.Log.API behaviour

  ## Extra parameters not in figure 2

  - `:net` (`list(pid)`) - parameter should be a list of all other Barge nodes
    in the network.
  - `:votes_received` (`list(pid)`) - a list of pids which have voted for this
    candidate.  Cleared on entry to candidate.
  """

  use StateServer, follower:  [timeout: :candidate,
                               concede: :follower],
                   candidate: [timeout: :candidate,
                               accede:  :leader,
                               concede: :follower],
                   leader:    [concede: :follower]

  defstruct term: 0,
            voted_for: nil,
            commit_index: 0,
            last_applied: 0,
            next_index: %{},
            match_index: %{},
            log: nil,
            net: [],
            votes_received: [],
            pending_calls: []

  #############################################################################
  ## Barge System types

  @type barge_term :: non_neg_integer
  @type barge_index :: non_neg_integer
  @type entry :: {barge_index, barge_term, term}


  @type data :: %__MODULE__{
    term:           barge_term,
    voted_for:      pid,
    commit_index:   barge_index,
    last_applied:   barge_index,
    next_index:     %{optional(pid) => barge_index},
    match_index:    %{optional(pid) => barge_index},
    log:            {module, term},
    # fields not in the official spec:
    net:            [pid],
    votes_received: [pid],
    pending_calls:  [{barge_index, GenServer.from}]
  }

  def start(opts) do
    StateServer.start(__MODULE__, opts)
  end
  def start_link(opts) do
    StateServer.start_link(__MODULE__, opts)
  end

  @impl true
  @spec init(keyword) :: {:ok, data}
  def init(opts) do
    if opts[:goto] do
      {:ok, struct(__MODULE__, opts), goto: opts[:goto]}
    else
      {:ok, struct(__MODULE__, opts)}
    end
  end

  #############################################################################
  ## API

  def state(srv), do: StateServer.call(srv, :state)
  defp state_impl(state, _data), do: {:reply, state}

  def data(srv), do: StateServer.call(srv, :data)
  defp data_impl(_state, data), do: {:reply, data}

  @spec join(StateServer.server, pid | [pid]) :: :ok
  def join(srv, who) when is_pid(who), do: join(srv, [who])
  def join(srv, who), do: send(srv, {:join, who})

  @spec join_impl([pid], state, data) :: {:noreply, keyword}
  defp join_impl(who, _state, data = %{net: net}) do
    new_net = Enum.uniq(net ++ who -- [self()])
    unless new_net == net do
      # rebroadcast the new network to everyone.
      Enum.each(new_net, &join(&1, [self() | new_net]))

      # set up monitoring on all of the new nodes
      Enum.each(new_net -- net, &Process.monitor/1)
    end
    {:noreply, update: %{data | net: new_net}}
  end

  defp monitor_down_impl(pid, _state, data) do
    {:noreply, update: %{data | net: data.net -- [pid]}}
  end


  @command_timeout Application.get_env(:barge, :command_timeout)
  def command(srv, command) do
    # TODO: make this StateServer.call, but fix the StateServer bug first.
    StateServer.call(srv, {:command, command}, @command_timeout)
  end

  #############################################################################
  ## State modules

  defstate Barge.Follower, for: :follower
  defstate Barge.Candidate, for: :candidate
  defstate Barge.Leader, for: :leader

  #############################################################################
  ## router

  @impl true
  def handle_call(:state, _from, state, data), do: state_impl(state, data)
  def handle_call(:data, _from, state, data), do: data_impl(state, data)
  defer handle_call

  @impl true
  def handle_info({:join, who}, state, data), do: join_impl(who, state, data)
  def handle_info(%{term: rpc_term}, _, data = %{term: srv_term}) when
      rpc_term > srv_term do
    new_data = %{data | term: rpc_term}
    {:defer, transition: :concede, update: new_data}
  end
  def handle_info({:DOWN, _ref, :process, pid, reason}, state, data) when is_pid(pid) do
    monitor_down_impl(pid, state, data)
  end
  defer handle_info

end
