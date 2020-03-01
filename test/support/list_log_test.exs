defmodule BargeTest.ListLogTest do
  use ExUnit.Case, async: true

  alias BargeTest.ListLog

  @moduletag :list_log

  test "list log can have data appended as we expect" do
    {:ok, test_log} = ListLog.start_link()
    assert 1 == ListLog.append(test_log, [{1, 1, :hello}])
    assert [{1, 1, :hello}] == ListLog.log(test_log)
  end

  test "list log can have data appended but it will dedupe" do
    old_log = [{1, 1, :hello}]
    {:ok, test_log} = ListLog.start_link(old_log)

    new_log = [{2, 1, :hello}] ++ old_log
    assert 2 == ListLog.append(test_log, new_log)
    assert new_log == ListLog.log(test_log)
  end

  test "list log can have data pushed to it" do
    {:ok, test_log} = ListLog.start_link()
    assert 1 == ListLog.push(test_log, {1, :hello})
    assert [{1, 1, :hello}] == ListLog.log(test_log)
  end

  test "a populated list log can have data pushed to it" do
    {:ok, test_log} = ListLog.start_link([{1, 1, :hello}])
    assert 2 == ListLog.push(test_log, {2, :hello})
    assert [{2, 2, :hello}, {1, 1, :hello}] == ListLog.log(test_log)
  end

  test "list log correctly reports last index" do
    {:ok, test_log} = ListLog.start_link([{1, 1, :hello}])
    assert 1 == ListLog.last_log_index(test_log)
  end

  test "list log correctly reports term for index" do
    {:ok, test_log} = ListLog.start_link([{1, 1, :hello}])
    assert 1 == ListLog.term_for(test_log, 1)
  end

  test "list log correctly reports term for as nil for a nonexistent index" do
    {:ok, test_log} = ListLog.start_link([{1, 1, :hello}])
    assert is_nil(ListLog.term_for(test_log, 2))
  end

  test "list log correctly deletes from index" do
    {:ok, test_log} = ListLog.start_link([{1, 1, :hello}])
    assert :ok == ListLog.delete_from_index(test_log, 1)
    assert [] == ListLog.log(test_log)
  end

  test "list log correctly retrieves entries when empty" do
    {:ok, test_log} = ListLog.start_link([])
    assert [] == ListLog.entries_from(test_log, 1)
  end

  test "list log correctly retrieves an entry when nonempty" do
    {:ok, test_log} = ListLog.start_link([{1, 1, :foo}])
    assert [{1, 1, :foo}] == ListLog.entries_from(test_log, 1)
  end

  test "list log correctly retrieves multiple entries when nonempty" do
    {:ok, test_log} = ListLog.start_link([{2, 1, :bar}, {1, 1, :foo}])
    assert [{2, 1, :bar}, {1, 1, :foo}] == ListLog.entries_from(test_log, 1)
  end
end
