defmodule BargeTest.ListLog do
  # a list-based raft log.  Not to be used in prod.

  use GenServer

  @behaviour Barge.Log.API

  @typep barge_index :: Barge.barge_index
  @typep barge_term :: Barge.barge_term
  @typep entry :: Barge.entry

  @type state :: {last_commit :: barge_index, [entry]}

  def start_link(lst \\ []) do
    GenServer.start_link(__MODULE__, lst)
  end

  @spec init(any) :: {:ok, state}
  @impl true
  def init(lst) do
    {:ok, {0, lst}}
  end

  #############################################################################
  ## Barge.Log.API implementations

  @impl true
  @spec append(GenServer.server, [entry]) :: barge_index
  def append(srv, new_entries), do: GenServer.call(srv, {:append, new_entries})

  @spec append_impl([entry], state) :: {:reply, barge_index, state}
  defp append_impl(new_entries, {commit, old_log}) do
    new_log = Enum.uniq(new_entries ++ old_log)
    head_index = case new_log do
      [{index, _, _} | _] -> index
      [] -> 0
    end
    {:reply, head_index, {commit, new_log}}
  end

  @impl true
  @spec push(GenServer.server, {barge_term, term}) :: barge_index
  def push(srv, new_entry), do: GenServer.call(srv, {:push, new_entry})

  @spec push_impl({barge_term, term}, state) :: {:reply, barge_index, state}
  def push_impl({term, command}, {commit, old_log}) do
    head_index = case old_log do
      [{index, _, _} | _] -> index + 1
      [] -> 1
    end
    {:reply, head_index, {commit, [{head_index, term, command} | old_log]}}
  end

  ##############################################################################

  @impl true
  @spec last_log_index(GenServer.server) :: barge_index
  def last_log_index(srv), do: GenServer.call(srv, :last_log_index)

  @spec last_log_index_impl(state) :: {:reply, barge_index, state}
  defp last_log_index_impl(state = {_, [{n, _, _} | _]}), do: {:reply, n, state}
  defp last_log_index_impl(state), do: {:reply, 0, state}

  ##############################################################################

  @impl true
  @spec term_for(GenServer.server, barge_index) :: barge_term
  def term_for(_, 0), do: 0
  def term_for(srv, index), do: GenServer.call(srv, {:term_for, index})

  @spec term_for_impl(barge_index, state) :: {:reply, barge_term, state}
  defp term_for_impl(index, state = {_, log}) do
    {:reply, find_term(index, log), state}
  end

  defp find_term(index, [{log_index, _, _} | _]) when index > log_index, do: nil
  defp find_term(index, [{index, term, _} | _]), do: term
  defp find_term(index, [_ | rest]), do: find_term(index, rest)

  ##############################################################################

  @impl true
  @spec delete_from_index(GenServer.server, barge_index) :: :ok
  def delete_from_index(srv, index) do
    GenServer.call(srv, {:delete_from_index, index})
  end

  @spec delete_from_index_impl(barge_index, state) :: {:reply, :ok, state}
  defp delete_from_index_impl(index, {commit, log}) do
    {:reply, :ok, {commit, log_before(index, log)}}
  end

  defp log_before(index, [{index, _, _} | rest]), do: rest
  defp log_before(index, [_, rest]), do: log_before(index, rest)

  @impl true
  @spec entries_from(GenServer.server, barge_index) :: [entry]
  def entries_from(srv, index) do
    GenServer.call(srv, {:entries_from, index})
  end

  @spec entries_from_impl(barge_index, state) :: {:reply, [entry], state}
  defp entries_from_impl(index, state = {_commit, log}) do
    {:reply, log_after(log, index), state}
  end

  defp log_after(log, index, so_far \\ [])
  defp log_after([entry = {index, _, _} | _], index, so_far) do
    Enum.reverse([entry | so_far])
  end
  defp log_after([entry = {entry_index, _, _} | rest], index, so_far)
      when entry_index > index do
    log_after(rest, index, [entry | so_far])
  end
  defp log_after(_, _, _), do: []

  ##############################################################################
  ## testing convenience functions

  @spec log(GenServer.server) :: [entry]
  def log(srv), do: GenServer.call(srv, :log)

  @spec log_impl(state) :: {:reply, [entry], state}
  defp log_impl(state = {_, log}) do
    {:reply, log, state}
  end

  #############################################################################
  ## router

  @impl true
  def handle_call({:append, new_entries}, _from, state) do
    append_impl(new_entries, state)
  end
  def handle_call({:push, new_entry}, _from, state) do
    push_impl(new_entry, state)
  end
  def handle_call(:last_log_index, _from, state) do
    last_log_index_impl(state)
  end
  def handle_call({:term_for, index}, _from, state) do
    term_for_impl(index, state)
  end
  def handle_call({:delete_from_index, index}, _from, state) do
    delete_from_index_impl(index, state)
  end
  def handle_call({:entries_from, index}, _from, state) do
    entries_from_impl(index, state)
  end
  def handle_call(:log, _from, state) do
    log_impl(state)
  end
end
