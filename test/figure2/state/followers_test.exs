defmodule BargeTest.Figure2.State.FollowersTest do

  use ExUnit.Case, async: true

  alias BargeTest.ListLog
  alias Barge.RPC.AppendEntries
  alias Barge.RPC.RequestVote

  describe "respond to RPCs" do
    test "from candidates" do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      # start a barge.  It defaults into follower state.
      {:ok, barge} = Barge.start_link(log: {ListLog, log})

      # send the barge a RequestVote rpc.
      send(barge, %RequestVote{
        term:           1,
        id:             self(),
        last_log_index: 1,
        last_log_term:  1
      })

      assert_receive %RequestVote.Result{}

      # make sure the candidate has voted.
      assert self() == Barge.data(barge).voted_for
    end

    test "from leaders" do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      # start a barge.  It defaults into follower state.
      {:ok, barge} = Barge.start_link(log: {ListLog, log})

      entries = [{1, 1, :hello}]

      # send the barge an AppendEntries rpc.
      send(barge, %AppendEntries{
        term:           1,
        id:             self(),
        prev_log_index: 0,
        prev_log_term:  0,
        entries:        entries,
        leader_commit:  0
      })

      assert_receive %AppendEntries.Result{
        success: true,
        index:   1
      }

      # make sure the log has been persisted.
      assert entries == ListLog.log(log)
    end
  end

  describe "if election timeout elapses" do
    @timeout Application.get_env(:barge, :election_timeout)
    @half_timeout div(@timeout, 2)
    @quarter_timeout div(@half_timeout, 2)

    test "without receiving AppendEntries RPC from current leader or granting vote to candidate, `:timeout` to candidate." do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      # start a barge.
      {:ok, barge} = Barge.start_link(log: {ListLog, log})

      Process.sleep(@timeout + @half_timeout)

      assert Barge.state(barge) == :candidate
    end

    test "after having received AppendEntries RPC, it does not convert." do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      # start a barge.  It defaults into follower state.
      {:ok, barge} = Barge.start_link(log: {ListLog, log})

      Process.sleep(@half_timeout)

      send(barge, %AppendEntries{id: self(), term: 1, prev_log_index: 0, prev_log_term: 0, entries: []})

      Process.sleep(@half_timeout + @quarter_timeout)

      assert Barge.state(barge) == :follower
    end

    test "after having granted vote to candidate, it does not convert." do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      # start a barge.  It defaults into follower state.
      {:ok, barge} = Barge.start_link(log: {ListLog, log})

      Process.sleep(@half_timeout)

      send(barge, %RequestVote{id: self(), term: 1, last_log_index: 0, last_log_term: 0})

      Process.sleep(@half_timeout + @quarter_timeout)

      assert Barge.state(barge) == :follower
    end

    test "but if we don't grant the vote to the candidate, it can covert." do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([{1, 1, :hello}])
      # start a barge.  It defaults into follower state.
      {:ok, barge} = Barge.start_link(log: {ListLog, log}, term: 1)

      Process.sleep(@half_timeout)

      # this requestvote should fail.
      send(barge, %RequestVote{id: self(), term: 1, last_log_index: 0, last_log_term: 0})

      Process.sleep(@half_timeout + @quarter_timeout)

      assert Barge.state(barge) == :candidate
    end
  end

end
