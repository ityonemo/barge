defmodule BargeTest.MembershipTest do
  use ExUnit.Case, async: true

  test "two barge processes can be joined" do
    {:ok, barge_1} = Barge.start_link([])
    {:ok, barge_2} = Barge.start_link([])

    Barge.join(barge_1, barge_2)

    assert [barge_2] == Barge.data(barge_1).net
    assert [barge_1] == Barge.data(barge_2).net
  end

  test "if a barge process is killed, it leaves the net" do
    {:ok, barge_1} = Barge.start_link([])
    {:ok, barge_2} = Barge.start([])

    Barge.join(barge_1, barge_2)

    Process.exit(barge_2, :kill)
    refute Process.alive?(barge_2)

    assert [] == Barge.data(barge_1).net
  end
end
