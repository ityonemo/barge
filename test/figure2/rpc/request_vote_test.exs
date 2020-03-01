defmodule BargeTest.Figure2.RPC.RequestVoteTest do

  use ExUnit.Case, async: true

  alias BargeTest.ListLog
  alias Barge.RPC.RequestVote

  test "1. Reply `false` if RPC term < server term (§5.1)" do
    assert {%{success: false}, _} =
      RequestVote.recv(%RequestVote{term: 1}, %Barge{term: 2})
  end

  describe "2. If server's `:voted_for` is `nil`" do
    test "and candidate's log is at least as up-to-date as receiver's log, grant the vote (§5.2, §5.4)" do
      {:ok, log} = ListLog.start_link([])

      assert {%{success: true}, _} =
        RequestVote.recv(
          %RequestVote{term: 1, last_log_index: 1, last_log_term: 1},
          %Barge{term: 1, log: {ListLog, log}})
    end

    test "and candidate's log is not at least as up-to-date as receiver's log, due to deficient log_index, deny the vote" do
      {:ok, log} = ListLog.start_link([{2, 1, :hello}, {1, 1, :hello}])

      assert {%{success: false}, _} =
        RequestVote.recv(
          %RequestVote{term: 2, last_log_index: 1, last_log_term: 1},
          %Barge{term: 1, log: {ListLog, log}})
    end

    test "and candidate's log is not at least as up-to-date as receiver's log, due to deficient log_term, deny the vote" do
      {:ok, log} = ListLog.start_link([{2, 2, :hello}, {1, 1, :hello}])

      assert {%{success: false}, _} =
        RequestVote.recv(
          %RequestVote{term: 2, last_log_index: 2, last_log_term: 1},
          %Barge{term: 1, log: {ListLog, log}})
    end
  end

  describe "2. If server's `:voted_for` is `id`" do
    test "and candidate's log is at least as up-to-date as receiver's log, grant the vote (§5.2, §5.4)" do
      {:ok, log} = ListLog.start_link([])

      candidate = self()

      assert {%{success: true}, _} =
        RequestVote.recv(
          %RequestVote{term: 1, last_log_index: 1, last_log_term: 1, id: candidate},
          %Barge{term: 1, log: {ListLog, log}, voted_for: candidate})
    end

    test "and candidate's log is not at least as up-to-date as receiver's log, due to deficient log_index, deny the vote" do
      {:ok, log} = ListLog.start_link([{2, 1, :hello}, {1, 1, :hello}])

      candidate = self()

      assert {%{success: false}, _} =
        RequestVote.recv(
          %RequestVote{term: 2, last_log_index: 1, last_log_term: 1, id: candidate},
          %Barge{term: 1, log: {ListLog, log}, voted_for: candidate})
    end

    test "and candidate's log is not at least as up-to-date as receiver's log, due to deficient log_term, deny the vote" do
      {:ok, log} = ListLog.start_link([{2, 2, :hello}, {1, 1, :hello}])

      candidate = self()

      assert {%{success: false}, _} =
        RequestVote.recv(
          %RequestVote{term: 2, last_log_index: 2, last_log_term: 1, id: candidate},
          %Barge{term: 1, log: {ListLog, log}, voted_for: candidate})
    end
  end

  describe "2a. If server has already voted" do
    test "we should deny the vote" do
      {:ok, log} = ListLog.start_link([])

      candidate = self()
      already_voted_for = spawn(fn -> :ok end)

      assert {%{success: false}, _} =
        RequestVote.recv(
          %RequestVote{term: 1, last_log_index: 1, last_log_term: 1, id: candidate},
          %Barge{term: 1, log: {ListLog, log}, voted_for: already_voted_for})

    end
  end

end
