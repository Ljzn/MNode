defmodule BexWeb.AdLive do
  use Phoenix.LiveView
  require Logger

  alias Bex.Wallet
  alias Bex.CoinManager

  @coin_sat Decimal.cast(1000)

  def mount(%{key: id}, socket) do
    send(self(), :sync)
    key = Wallet.get_private_key!(id)

    {
      :ok,
      socket
      |> assign(:key, key)
      |> assign(:loading, true)
      |> assign(:balance, 0)
      |> assign(:buy_laba, 0)
      |> assign(:ad_count, 0)
      |> assign(:sent_box, [])
      |> assign(:content, "")
    }
  end

  def render(assigns) do
    ~L"""
    <h1>广告墙</h1>

    <section>
      <p>充值地址: <%= @key.address %></p>
      <p>我的小喇叭: <%= @balance %> 个<button phx-click="flash" <%= if @loading, do: "disabled" %>>刷新余额</button></p>
      <p>本次已发送: <%= @ad_count %></p>
    </section>

    <section>
      <form phx-submit="laba">
        <label>广告内容:</label>
        <input value="<%= @content %>" name="content" ></input>
        <label>不超过 200 汉字</label>
        <br/>
        <label>发送次数:</label>
        <input placeholder=0 type="number" name="amount" />
        <br/>
        <button type="submit">发送</button>
      </from>
    </section>

    <section>
      <%= for txid <- @sent_box do %>
        <li><a href="https://whatsonchain.com/tx/<%= txid %>"><%= txid %></a></li>
      <% end %>
    </section>

    <section>
      <h2>使用说明</h2>
      <p>可在<a target="_blank" href="https://bitcoinblocks.live/">这里</a>查看实时交易. </p>
      <p>请勿充值大量金额. 任何财产损失, 本网站概不负责.</p>
      <p>私钥ID保存在本地, 使用过程中请勿删除浏览器缓存.</p>
      <p>每条广告花费 1 个小喇叭, 每个小喇叭价值 1000 聪.</p>
    </section>
    """
  end

  def handle_event("laba", %{"amount" => a, "content" => c}, socket) do
    balance = socket.assigns.balance

    a =
      case Integer.parse(a) do
        {x, _} -> x
        _ -> 0
      end

    if a !== 0 and a <= balance and byte_size(c) <= 800 do
      send(self(), {:do_send, a, c})
    end

    {:noreply, assign(socket, :sending, true) |> assign(:content, c)}
  end

  def handle_event("flash", _, socket) do
    send(self(), :sync)
    {:noreply, assign(socket, :loading, true)}
  end

  def handle_event("gun", _, socket) do
    {:noreply, redirect(socket, to: "/")}
  end

  def handle_info(:sync, socket) do
    key = socket.assigns.key
    Wallet.sync_utxos_of_private_key(key)
    :timer.sleep(1000)
    balance = count_coins(key)
    {:noreply, assign(socket, %{loading: false, balance: balance})}
  end

  def handle_info({:do_send, 0, _}, socket) do
    {:noreply, socket}
  end

  def handle_info({:do_send, a, c}, socket) do
    key = socket.assigns.key
    ad_count = socket.assigns.ad_count + 1
    balance = socket.assigns.balance

    {:ok, txid, _} = CoinManager.send_opreturn(key.id, [c], @coin_sat,
      change_to: "1FUBsjgSju23wGqR47ywynyynigxvtTCyZ"
    )

    send(self(), {:do_send, a - 1, c})

    :timer.sleep(500)

    sent_box = [txid | socket.assigns.sent_box]

    {:noreply, assign(socket, %{sent_box: sent_box, ad_count: ad_count, balance: balance - 1})}
  end

  defp count_coins(key) do
    CoinManager.mint(key.id, @coin_sat)
    :timer.sleep(1000)
    Wallet.count_balance(key) |> Decimal.div_int(@coin_sat) |> Decimal.to_integer()
  end
end
