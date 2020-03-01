defmodule Barge.Log.API do

  @typep entry :: Barge.entry
  @typep barge_index :: Barge.barge_index
  @typep barge_term :: Barge.barge_term

  @doc """
  it is a requirement that the `append` function not append values that already
  exist in the log.
  """
  @callback append(term, [entry]) :: barge_index
  @callback push(term, {barge_term, term}) :: barge_index
  @callback last_log_index(term) :: barge_index

  @doc """
  must return nil if we supply an index that's too high.
  """
  @callback term_for(term, barge_index) :: barge_term
  @callback delete_from_index(term, barge_index) :: :ok
  @callback entries_from(term, barge_index) :: [entry]

end
