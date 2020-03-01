Application.put_env(:barge, :election_timeout, 1000)
Application.put_env(:barge, :heartbeat_timeout, 200)
# this is the normal GenServer call tmieout.
Application.put_env(:barge, :command_timeout, 5000)

if Mix.env == :test do
  Application.put_env(:barge, :election_timeout, 100)
  Application.put_env(:barge, :heartbeat_timeout, 30)
  Application.put_env(:barge, :command_timeout, 50)
end
