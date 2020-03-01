defmodule BargeTest.CandidatesTest do
  use ExUnit.Case, async: true

  alias BargeTest.ListLog
  alias Barge.RPC.AppendEntries
  alias Barge.RPC.RequestVote

  @timeout Application.get_env(:barge, :election_timeout)
  @half_timeout div(@timeout, 2)

  describe "on conversion to candidate" do
    test "the election is started: term has been incremented" do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      # start a barge.  Send it to the candidate state.
      {:ok, barge} = Barge.start_link(log: {ListLog, log}, goto: :candidate)

      assert %{term: 1} = Barge.data(barge)
    end

    test "the election is started: barge has voted for self" do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      # start a barge.  Send it to the candidate state.
      {:ok, barge} = Barge.start_link(log: {ListLog, log}, goto: :candidate)

      assert %{voted_for: ^barge} = Barge.data(barge)
    end

    test "the election is started: barge has restarted the timer" do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      # start a barge.  Send it to the candidate state.
      {:ok, barge} = Barge.start_link(log: {ListLog, log}, goto: :candidate)

      Process.sleep(@timeout + @half_timeout)

      assert :candidate == Barge.state(barge)
      assert %{term: 2} = Barge.data(barge)
    end

    test "the election is started: sent RequestVote RPC to all other servers" do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      # start a barge.  Send it to the candidate state.
      {:ok, _} = Barge.start_link(log: {ListLog, log}, net: [self()], goto: :candidate)

      assert_receive %RequestVote{}
    end

    # additional tests for things not in the paper
    test "votes_received is cleared" do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      # start a barge.  Send it to the candidate state.
      {:ok, barge} = Barge.start_link(log: {ListLog, log}, goto: :candidate)

      assert %{votes_received: []} = Barge.data(barge)
    end
  end

  describe "If votes received" do
    test "from a majority of servers (2/2) accede to leader" do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      # start a barge.  Send it to the candidate state.
      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        net: [self()],
        goto: :candidate)

      assert_receive %RequestVote{}

      # send the response
      send(barge, %RequestVote.Result{success: true})
      Process.sleep(10)

      assert :leader == Barge.state(barge)
    end

    test "from a majority of servers (2/3) accede to leader" do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])

      sp = spawn(fn -> :ok end)
      # start a barge.  Send it to the candidate state.
      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        net: [self(), sp],
        goto: :candidate)

      assert_receive %RequestVote{}

      # send the response
      send(barge, %RequestVote.Result{success: true})

      assert :leader == Barge.state(barge)
    end

    test "from a non-majority of servers (2/4), append to voted list" do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])

      test_pid = self()

      sp = spawn(fn -> :ok end)
      # start a barge.  Send it to the candidate state.
      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        net: [test_pid, sp, sp],
        goto: :candidate)

      assert_receive %RequestVote{}

      # send the response
      send(barge, %RequestVote.Result{id: test_pid, success: true})

      assert %{votes_received: [^test_pid]} = Barge.data(barge)
    end
  end

  describe "If AppendEntries RPC received" do
    test "from a new leader, `:concede` to follower." do
      {:ok, log} = ListLog.start_link([])

      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        goto: :candidate)

      send(barge, %AppendEntries{
        term:           3,
        id:             self(),
        prev_log_index: 0,
        prev_log_term:  0,
        entries:        [],
        leader_commit:  1
      })

      assert :follower = Barge.state(barge)

      assert_receive %AppendEntries.Result{success: true}
    end

    test "from a false leader (term too low), don't concede" do
      {:ok, log} = ListLog.start_link([])

      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        term: 2,
        goto: :candidate)

      assert %{term: 3} = Barge.data(barge)

      send(barge, %AppendEntries{
        term:           1,
        id:             self(),
        prev_log_index: 0,
        prev_log_term:  0,
        entries:        [],
        leader_commit:  1
      })

      assert :candidate = Barge.state(barge)

      assert_receive %AppendEntries.Result{success: false}
    end
  end

  describe "If election timeout elapses" do
    test "start a new election." do
      {:ok, log} = ListLog.start_link([])

      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        goto: :candidate)

      assert %{term: 1} = Barge.data(barge)

      Process.sleep(@timeout + @half_timeout)

      assert :candidate = Barge.state(barge)
      assert %{term: 2} = Barge.data(barge)
    end
  end
end
