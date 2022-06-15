import Config

config :vsr,
  port: System.get_env("PORT", "4000") |> String.to_integer(),
  replica_number: System.get_env("REPLICA_NUMBER", "0") |> String.to_integer(),
  # Instead of IP addresses, we use ports for the time being.
  # This would need to be updated if we run on different machine.
  ports: [
    4000,
    4001,
    4002
  ]
