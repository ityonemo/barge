defmodule BargeTest.Figure2.RPC.AppendEntriesTest do

  use ExUnit.Case, async: true

  alias Barge.RPC.AppendEntries
  alias BargeTest.ListLog

  test "1. Reply `false` if RPC term < server term. (§5.1)" do
    assert {%{success: false}, _} =
      AppendEntries.recv(%AppendEntries{term: 1}, %Barge{term: 2})
  end

  describe "2. Reply `false` if log doesn't contain an entry at `:prev_log_index` whose term matches `:prev_log_term` (§5.3)" do
    test "because the log doesn't have that entry yet" do
      {:ok, log} = ListLog.start_link([])

      assert {%{success: false, index: 0}, _} =
        AppendEntries.recv(
          %AppendEntries{term: 1, prev_log_index: 1, prev_log_term: 1},
          %Barge{term: 1, log: {ListLog, log}})
    end

    test "because the log index and term conflict" do
      {:ok, log} = ListLog.start_link([{1, 1, :foo}])

      assert ListLog.last_log_index(log) == 1

      assert {%{success: false, index: 0}, _} =
        AppendEntries.recv(
          %AppendEntries{term: 2, prev_log_index: 1, prev_log_term: 2},
          %Barge{term: 2, log: {ListLog, log}}
        )
    end
  end

  test "3. If an existing entry conflicts with a new one (same index but different terms), delete the existing entry and all that follow it (§5.3)" do
    {:ok, log} = ListLog.start_link([{1, 1, :foo}])

    assert ListLog.last_log_index(log) == 1

    assert {%{success: false, index: 0}, _} = AppendEntries.recv(
      %AppendEntries{term: 2, prev_log_index: 1, prev_log_term: 2},
      %Barge{term: 2, log: {ListLog, log}}
    )

    assert [] == ListLog.log(log)
  end

  describe "4. Append any new entries not already in the log" do
    test "when all entries are new" do
      {:ok, log} = ListLog.start_link([])

      entries = [{1, 1, :hello}]

      assert {%{success: true}, _} = AppendEntries.recv(
        %AppendEntries{term: 1, prev_log_index: 0, prev_log_term: 0, entries: entries},
        %Barge{term: 1, log: {ListLog, log}}
      )

      assert entries == ListLog.log(log)
    end

    test "when there's overlap in the entries" do
      old_entries = [{1, 1, :hello}]
      {:ok, log} = ListLog.start_link(old_entries)

      new_entries = [{2, 1, :hello}] ++ old_entries

      assert {%{success: true}, _} = AppendEntries.recv(
        %AppendEntries{term: 1, prev_log_index: 0, prev_log_term: 0, entries: new_entries},
        %Barge{term: 1, log: {ListLog, log}}
      )

      assert new_entries == ListLog.log(log)
    end
  end

  describe "5. If leader commit > commit index set commit index to the minimum of leader commit and the last new entry" do
    test "when an append action has not happened and the leader commit is higher." do
      entries = [{1, 1, :hello}]
      {:ok, log} = ListLog.start_link(entries)

      assert {_, %{commit_index: 1}} = AppendEntries.recv(
        %AppendEntries{leader_commit: 2, term: 1},
        %Barge{term: 1, log: {ListLog, log}}
      )
    end

    test "when an append action has not happened an the leader commit is lower." do
      entries = [{2, 1, :hello}, {1, 1, :hello}]
      {:ok, log} = ListLog.start_link(entries)

      assert {_, %{commit_index: 1}} = AppendEntries.recv(
        %AppendEntries{leader_commit: 1, term: 1},
        %Barge{term: 1, log: {ListLog, log}}
      )
    end

    test "when an append action has happened and the leader commit is higher." do
      entries = [{1, 1, :hello}]
      {:ok, log} = ListLog.start_link(entries)

      assert {_, %{commit_index: 2}} = AppendEntries.recv(
        %AppendEntries{leader_commit: 3,
                       prev_log_index: 1,
                       prev_log_term: 1,
                       entries: [{2, 1, :hello}],
                       term: 1},
        %Barge{term: 1, log: {ListLog, log}}
      )
    end

    test "when an append action has happened and the leader commit is lower." do
      entries = [{1, 1, :hello}]
      {:ok, log} = ListLog.start_link(entries)

      assert {_, %{commit_index: 1}} = AppendEntries.recv(
        %AppendEntries{leader_commit: 1,
                       prev_log_index: 1,
                       prev_log_term: 1,
                       entries: [{2, 1, :hello}],
                       term: 1},
        %Barge{term: 1, log: {ListLog, log}}
      )
    end
  end

end
