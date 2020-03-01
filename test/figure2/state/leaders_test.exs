defmodule BargeTest.Figure2.State.LeadersTest do

  use ExUnit.Case, async: true

  alias BargeTest.ListLog
  alias Barge.RPC.AppendEntries


  describe "on election, leader state's" do
    @describetag :leader_init
    test ":next_index is set to 1, for empty log" do
      test_pid = self()
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      {:ok, barge} = Barge.start_link(
        term: 1,
        log: {ListLog, log},
        net: [test_pid],
        goto: :leader
      )

      assert %{test_pid => 1} == Barge.data(barge).next_index
    end

    test ":next_index is set to index + 1, for empty log" do
      test_pid = self()
      # set up a barge log.
      {:ok, log} = ListLog.start_link([{1, 1, :foo}])
      {:ok, barge} = Barge.start_link(
        term: 1,
        log: {ListLog, log},
        net: [test_pid],
        goto: :leader
      )

      assert %{test_pid => 2} == Barge.data(barge).next_index
    end

    test ":match_index is set to 0" do
      test_pid = self()
      # set up a barge log.
      {:ok, log} = ListLog.start_link([{1, 1, :foo}])
      {:ok, barge} = Barge.start_link(
        term: 1,
        log: {ListLog, log},
        net: [test_pid],
        goto: :leader
      )

      assert %{test_pid => 0} == Barge.data(barge).match_index
    end
  end

  describe "Upon election" do
    test "send initial empty AppendEntries RPCs (heartbeat) to each server" do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      # start a barge, make it a leader
      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        goto: :leader,
        net: [self()])

      assert_receive %AppendEntries{
        id:             ^barge,
        prev_log_index: 0,
        prev_log_term:  0,
        entries:        [],
      }
    end

    test "initial heartbeat reflects the log's head" do
      # the initial heartbeat must reflect the log's head state in order to trigger
      # correct synchronization of the log.

      # set up a barge log.
      {:ok, log} = ListLog.start_link([{1, 1, :a}])
      # start a barge, make it a leader.
      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        goto: :leader,
        net: [self()])

      assert_receive %AppendEntries{
        id:             ^barge,
        prev_log_index: 1,
        prev_log_term:  1,
        entries:        [],
      }
    end
  end

  @heartbeat_timeout Application.get_env(:barge, :heartbeat_timeout)
  @half_heartbeat_timeout div(@heartbeat_timeout, 2)

  describe "during idle periods" do
    test "heartbeat is repeated to prevent election timeouts (§5.2)" do
      # set up a barge log.
      {:ok, log} = ListLog.start_link([{1, 1, :a}])
      # start a barge, make it a leader.
      {:ok, _barge} = Barge.start_link(
        log: {ListLog, log},
        goto: :leader,
        net: [self()])

      assert_receive %AppendEntries{}

      Process.sleep(@heartbeat_timeout + @half_heartbeat_timeout)

      assert_receive %AppendEntries{}
    end
  end

  describe "If command received from client" do
    test "append entry to local log" do
      test_pid = self()
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      {:ok, barge} = Barge.start_link(
        term: 1,
        log: {ListLog, log},
        goto: :leader
      )

      # for this test we don't expect it to succeed since we have
      # have not created a network across which to communicate a
      # command.
      try do
        Barge.command(barge, :foo)
      catch
        :exit, {:timeout, _} ->
          :ok
      end

      assert [{1, 1, :foo}] == ListLog.log(log)

      # not in the official spec, but make sure that the list of pending
      # calls contains a GenServer callback.
      assert [{1, {^test_pid, _}}] = Barge.data(barge).pending_calls
    end

    test "respond after entry applied to state machine" do
      test_pid = self()
      # set up a barge log.
      {:ok, log} = ListLog.start_link([])
      {:ok, barge} = Barge.start_link(
        term: 1,
        log: {ListLog, log},
        net: [test_pid],
        goto: :leader
      )

      # this needs to be run asynchronously because we have to do other things
      # before the response triggers.
      spawn(fn ->
        result = Barge.command(barge, :foo)
        send(test_pid, {:result, result})
      end)

      # we expect the leader to propagate a message to get us going.
      assert_receive %AppendEntries{
        term:           1,
        id:             ^barge,
        prev_log_index: 0,
        prev_log_term:  0,
        entries:        [{1, 1, :foo}],
        leader_commit:  0
      }

      # send back a fake response.
      send(barge, %AppendEntries.Result{
        term: 1,
        id: test_pid,
        success: true,
        index: 1
      })

      assert_receive {:result, :ok}
    end
  end

  describe "if an AppendEntries RPC is recieved" do
    test "and it's a failure, then next_index is reset to the responded value and it's resent" do
      test_pid = self()
      # set up a barge log.
      {:ok, log} = ListLog.start_link([{1, 1, :foo}])
      {:ok, barge} = Barge.start_link(
        term: 1,
        log: {ListLog, log},
        net: [test_pid],
        goto: :leader
      )

      (assert_receive %AppendEntries{})
      #send a response
      send(barge, %AppendEntries.Result{
        term: 1,
        id: test_pid,
        success: false,
        index: 0
      })

      assert %Barge{next_index: %{^test_pid => 0}} = Barge.data(barge)
    end
  end
end
