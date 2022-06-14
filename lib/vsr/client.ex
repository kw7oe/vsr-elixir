defmodule Vsr.Client do
  use GenServer
  require Logger

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: :"client-#{config.client_id}")
  end

  def init(config) do
    {:ok, sock} =
      :gen_tcp.connect('localhost', config.port, [:binary, packet: :line, active: false])

    state =
      Map.merge(config, %{
        conn: sock,
        request_number: 0
      })

    {:ok, state}
  end

  def request(client, op) do
    GenServer.call(client, {:request, op})
  end

  def handle_call({:request, op}, _from, state) do
    s = state.request_number
    c = state.client_id
    Logger.info("client #{c}: request op=\"#{op}\" c=#{c} s=#{s}")

    resp = tcp_send(state.conn, "request,#{op},#{c},#{s}")
    {:reply, resp, %{state | request_number: s + 1}}
  end

  def tcp_send(conn, data) do
    :gen_tcp.send(conn, data <> "\n")
    {:ok, resp} = :gen_tcp.recv(conn, 0)
    resp
  end
end
