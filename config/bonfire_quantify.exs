use Mix.Config

config :bonfire_geolocate,
  web_module: Bonfire.Web,
  repo_module: Bonfire.Repo,
  user_module: CommonsPub.Users.User,
  templates_path: "lib",
  otp_app: :bonfire

# specify what types a unit can have as context
config :bonfire_geolocate, Bonfire.Geolocate.Units, valid_contexts: [Bonfire.Geolocate.Units]
