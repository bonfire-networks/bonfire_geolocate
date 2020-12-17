use Mix.Config

config :bonfire_geolocate,
  otp_app: :your_app_name,
  web_module: Bonfire.Web,
  repo_module: Bonfire.Repo,
  user_schema: CommonsPub.Users.User
