defmodule BargeTest.AllServersTest do
  use ExUnit.Case, async: true

  alias BargeTest.ListLog
  alias Barge.RPC.AppendEntries
  alias Barge.RPC.RequestVote

  @moduletag :all_servers_test

  describe "If RPC request or response contains term greater than the server's term" do
    test "with leader/AppendEntries, convert to follower (§5.1)" do
      {:ok, log} = ListLog.start_link([])
      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        goto: :leader)

      send(barge, %AppendEntries{id: self(), term: 2})

      assert :follower == Barge.state(barge)
      assert %{term: 2} = Barge.data(barge)
    end

    test "with leader/AppendEntries.Result, convert to follower (§5.1)" do
      {:ok, log} = ListLog.start_link([])
      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        goto: :leader)

      send(barge, %AppendEntries.Result{id: self(), term: 2})

      assert :follower == Barge.state(barge)
      assert %{term: 2} = Barge.data(barge)
    end

    test "with leader/RequestVote, convert to follower (§5.1)" do
      {:ok, log} = ListLog.start_link([])
      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        goto: :leader)

      send(barge, %RequestVote{id: self(), term: 2})

      assert :follower == Barge.state(barge)
      assert %{term: 2} = Barge.data(barge)
    end

    test "with leader/RequestVote.Result, convert to follower (§5.1)" do
      {:ok, log} = ListLog.start_link([])
      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        goto: :leader)

      send(barge, %RequestVote.Result{id: self(), term: 2})

      assert :follower == Barge.state(barge)
      assert %{term: 2} = Barge.data(barge)
    end

    test "with candidate/AppendEntries, convert to follower (§5.1)" do
      {:ok, log} = ListLog.start_link([])
      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        goto: :candidate)

      send(barge, %AppendEntries{id: self(), term: 2})

      assert :follower == Barge.state(barge)
      assert %{term: 2} = Barge.data(barge)
    end

    test "with candidate/AppendEntries.Result, convert to follower (§5.1)" do
      {:ok, log} = ListLog.start_link([])
      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        goto: :candidate)

      send(barge, %AppendEntries.Result{id: self(), term: 2})

      assert :follower == Barge.state(barge)
      assert %{term: 2} = Barge.data(barge)
    end

    test "with candidate/RequestVote, convert to follower (§5.1)" do
      {:ok, log} = ListLog.start_link([])
      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        goto: :candidate)

      send(barge, %RequestVote{id: self(), term: 2})

      assert :follower == Barge.state(barge)
      assert %{term: 2} = Barge.data(barge)
    end

    test "with candidate/RequestVote.Result, convert to follower (§5.1)" do
      {:ok, log} = ListLog.start_link([])
      {:ok, barge} = Barge.start_link(
        log: {ListLog, log},
        goto: :candidate)

      send(barge, %RequestVote.Result{id: self(), term: 2})

      assert :follower == Barge.state(barge)
      assert %{term: 2} = Barge.data(barge)
    end
  end

  #- If `:commit_index` > `:last_applied`, apply `log[last_applied]` to the state
  #machine (§5.3)
end
