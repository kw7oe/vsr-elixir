defmodule Vsr.VRState do
  defstruct [
    :replica_number,
    op_number: 0,
    log: [],
    commit_number: 0,
    client_table: %{},
    view_number: 0,
    status: :normal
  ]
end