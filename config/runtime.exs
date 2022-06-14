import Config

config :vsr,
  port: System.fetch_env!("PORT") |> String.to_integer(),
  replica_number: System.fetch_env!("REPLICA_NUMBER") |> String.to_integer(),
  # Instead of IP addresses, we use ports for the time being.
  # This would need to be updated if we run on different machine.
  ports: [
    4000,
    4001,
    4002
  ]
