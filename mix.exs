defmodule Bex.MixProject do
  use Mix.Project

  def project do
    [
      app: :bex,
      version: "0.1.0",
      elixir: "~> 1.5",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Bex.Application, []},
      extra_applications: [:logger, :runtime_tools, :logger_file_backend, :inets, :ssl]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:binary, "0.0.4"},
      {:cubdb, "~> 0.13.0"},
      {:decimal, "~> 1.0"},
      {:ecto_sql, "~> 3.2"},
      {:ecto_enum, "~> 1.3"},
      {:elixir_uuid, "~> 1.2"},
      {:gettext, "~> 0.11"},
      {:hackney, ">= 1.15.2", override: true},
      {:httpoison, "~> 1.5", override: true},
      {:jason, "~> 1.2", override: true},
      {:logger_file_backend, "~> 0.0.10"},
      {:nodejs, "~> 1.0"},
      {:phoenix, "~> 1.4.9"},
      {:phoenix_pubsub, "~> 1.1"},
      {:phoenix_ecto, "~> 4.0"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 2.11"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:plug_cowboy, "~> 2.0"},
      {:phoenix_live_view, "~> 0.3.1"},
      {:sv_api, github: "terriblecodebutwork/sv_api"},
      {:tentacat, github: "terriblecodebutwork/tentacat"},
      {:tesla, "~> 1.3", override: true},
      {:manic, "~> 0.0.1"},
      {:bsv, "~> 0.2"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to create, migrate and run the seeds file at once:
  #
  #     $ mix ecto.setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate", "test"]
    ]
  end
end
