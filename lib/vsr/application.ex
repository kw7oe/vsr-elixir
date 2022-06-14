defmodule Vsr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:vsr, :port)
    replica_number = Application.get_env(:vsr, :replica_number)

    children = [
      {Task.Supervisor, name: Vsr.TaskSupervisor},
      Supervisor.child_spec({Task, fn -> Vsr.Server.accept(port, replica_number) end},
        restart: :permanent
      ),
      {Vsr.Client, %{client_id: 0, port: 4000}}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Vsr.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
