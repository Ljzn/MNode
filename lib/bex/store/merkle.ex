defmodule Bex.Store.Merkle do
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "merkle" do
    field :block_height, :integer
    field :root, :boolean
    field :at_left, :boolean
    belongs_to :pair, Merkle, foreign_key: :pair_id
    belongs_to :top, Merkle, foreign_key: :top_id
  end

  @doc false
  def changeset(merkle, attrs) do
    merkle
    |> cast(attrs, [:id, :block_height, :pair_id, :top_id, :root, :at_left])
    |> validate_required([:id, :block_height])
  end
end
