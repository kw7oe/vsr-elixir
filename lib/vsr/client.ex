defmodule Vsr.Client do
  def send(port, data) do
    {:ok, sock} = :gen_tcp.connect('localhost', port, [:binary, packet: :line, active: false])
    :gen_tcp.send(sock, data)
    {:ok, resp} = :gen_tcp.recv(sock, 0)
    IO.puts(resp)
    :gen_tcp.close(sock)
  end
end
