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

defmodule Vsr.VRState.ClientInfo do
  defstruct [
    :last_result,
    last_request_number: 0
  ]
end
