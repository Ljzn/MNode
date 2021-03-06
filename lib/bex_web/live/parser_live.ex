defmodule BexWeb.ParserLive do
  @moduledoc """
  Parse raw tx.
  """
  use Phoenix.LiveView
  alias BexLib.Parser
  require Logger

  def mount(_session, socket) do
    {:ok,
     assign(socket, :tx, "")
     |> assign(:merkleblock, "")
     |> assign(:loading, false)
     |> assign(:loading1, false)}
  end

  def handle_params(%{"rawtx" => rawtx}, _url, socket) do
    handle_event("submit", %{"rawtx" => rawtx}, socket)
  end

  def handle_params(%{"rawtxoutproof" => raw}, _url, socket) do
    handle_event("submit1", %{"rawtxoutproof" => raw}, socket)
  end

  def handle_params(_, _url, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~L"""
    <h2>Parse raw bsv transaction</h2>
    <%= if @loading do %>
    <h4>Loading...</h4>
    <% end %>

    <form phx-submit="submit">
      <textarea name="rawtx"></textarea>
      <button type="submit">Parse</button>
    </form>

    <pre><code><%= @tx %></code></pre>

    <h2>Parse TxoutProof (MerkleBlock)</h2>
    <%= if @loading1 do %>
    <h4>Loading...</h4>
    <% end %>

    <form phx-submit="submit1">
      <textarea name="rawtxoutproof"></textarea>
      <button type="submit">Parse txoutproof</button>
    </form>

    <pre><code><%= @merkleblock %></code></pre>

    <section>
      <h3>changelog</h3>
      <ul>
        <li>2020.01.04: Parse TxoutProof, <a href="/mnode/parser/txoutproof/0100000090f0a9f110702f808219ebea1173056042a714bad51b916cb6800000000000005275289558f51c9966699404ae2294730c3c9f9bda53523ce50e9b95e558da2fdb261b4d4c86041b1ab1bf930900000005fac7708a6e81b2a986dea60db2663840ed141130848162eb1bd1dee54f309a1b2ee1e12587e497ada70d9bd10d31e83f0a924825b96cb8d04e8936d793fb60db7ad8b910d0c7ba2369bc7f18bb53d80e1869ba2c32274996cebe1ae264bc0e2289189ff0316cdc10511da71da757e553cada9f3b5b1434f3923673adb57d83caac392c38af156d6fc30b55fad4112df2b95531e68114e9ad10011e72f7b7cfdb025700">example</a></li>
        <li>2019.11.05: get block height from coinbase. (block should higher than 227,835) <a href="/mnode/parser/01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff3c036d44092f68747470733a2f2f636f696e6765656b2e636f6d2f6d696e65722d6f757472656163682f2f314c7a41587782831ed0616350be8d7d0000ffffffff0147f28c4a000000001976a914db3a0ec7c1d42b250a2739f71fe10b7ef8853a4688ac00000000">example</a> </li>
        <li>2019.11.04: parse miner tag from coinbase tx. <a href="/mnode/parser/01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff4d04ffff001d0104455468652054696d65732030332f4a616e2f32303039204368616e63656c6c6f72206f6e206272696e6b206f66207365636f6e64206261696c6f757420666f722062616e6b73ffffffff0100f2052a01000000434104678afdb0fe5548271967f1a67130b7105cd6a828e03909a67962e0ea1f61deb649f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5fac00000000">example<a></li>
        <li>2019.10.06: add the size of rawtx.</li>
        <li>2019.09.27: support send rawtx in url, <a href="/mnode/parser/0100000002e0be3dcef56b62c84118ccb03219077b7bfe528cda6fe6fd3d6adfb1d275510f030000006a47304402207d417371bb155aeb614f7e17feacf1e9579fd192d572043f103f37fee950aa9402202610a7560140b211b022e4569c3c2bc518fcdba2b0d651df326a3d6de612ffff4121023c4ec25273c2dee1fe44142aa83509e617b57d4e3e6c189c6d354bf9794b4dfbffffffff31fed5cd5b08cc5684e41ef0a6f71396c4e5740177141b30a65304b4f9ea3ef0010000006a47304402206eb78d4f54cb629f55198049a234bfd9229285887b1a6561f31410d884a7cb0e0220793da5287d0e89686919bccd3a78c63d5a415fc3802c0dd2db311d8f5b25cfb84121025c5553e1f1a31fc8a870a842b370328cdc3e547e761e54deef136f3e6235afa8ffffffff046d220000000000001976a914060ea6b1301c58fbeba7c5229309775d5ad0199d88ac0000000000000000e06a046d657461223132366258395666416b6b4376756b7175394b6634553969344e5036696a7572556640306635313735643262316466366133646664653636666461386335326665376237623037313933326230636331383431633836323662663563653364626565304c747b226d625f756964223a22333930222c226d625f757365726e616d65223a224a6179205a68616e67222c2274786964223a2262336437623138396432356366616361343237353634376566613933333538383430626233656363616664353530356265623939323339396637383965613162227d22020000000000001976a914b6a1d22dc737cfd5d128b717445ea0ae10f1715988ac22020000000000001976a9140c07057026e4d704e9bf3b4104aa834b7f9607af88ac00000000">example</a></li>
      </ul>
    </section>
    """
  end

  def handle_event("submit", %{"rawtx" => r}, socket) do
    send(self(), {:parse, r})
    {:noreply, assign(socket, :loading, true)}
  end

  def handle_event("submit1", %{"rawtxoutproof" => r}, socket) do
    send(self(), {:parse_merkleblock, r})
    {:noreply, assign(socket, :loading1, true)}
  end

  def handle_info({:parse, r}, socket) do
    tx =
      case Parser.parse_rawtx(r, [:human]) do
        {:ok, r} ->
          Jason.encode_to_iodata!(r, pretty: true)

        {:error, e} ->
          inspect(e)
      end

    {:noreply, assign(socket, :loading, false) |> assign(:tx, tx)}
  end

  def handle_info({:parse_merkleblock, r}, socket) do
    merkleblock =
      case Parser.parse_merkleblock(r, [:human]) do
        {:ok, r} ->
          Jason.encode_to_iodata!(r, pretty: true)

        {:error, e} ->
          inspect(e)
      end

    {:noreply, assign(socket, :loading1, false) |> assign(:merkleblock, merkleblock)}
  end
end
