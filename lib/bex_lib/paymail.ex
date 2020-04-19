defmodule Paymail do
  defstruct [
    :username,
    :nickname,
    :host,
    :api,
    :avatar_url,
    :avatar_path,
    :address,
    :capabilities,
    :version
  ]

  @ppv1 "f12f968c92d6"
  @dir "./priv/avatars"

  def parse(mail) do
    [username, host] = String.split(mail, "@")
    api = api(host)
    {version, capabilities} = cap(api)
    {nickname, avatar_url} = profile(capabilities[@ppv1], username, host)
    avatar_path = download_avatar(avatar_url, mail)

    %__MODULE__{
      username: username,
      host: host,
      api: api,
      version: version,
      capabilities: capabilities,
      nickname: nickname,
      avatar_url: avatar_url,
      avatar_path: avatar_path
    }
  end

  def api(host) do
    url = "_bsvalias._tcp.#{host}"
    [{_, _, _, api}] = :inet_res.lookup(to_list(url), :in, :srv)
    "https://" <> to_string(api) <> "/.well-known/bsvalias"
  end

  def cap(api) do
    resp = HTTPoison.get!(api)
    data = resp.body |> Jason.decode!()

    {data["bsvalias"], data["capabilities"]}
  end

  def profile(false, _, host) do
    "#{host} not suppport Public Profile V1"
  end

  def profile(url, name, host) do
    resp =
      url
      |> String.replace("{alias}", name)
      |> String.replace("{domain.tld}", host)
      |> HTTPoison.get!()

    data = resp.body |> Jason.decode!()

    {data["name"], data["avatar"]}
  end

  def download_avatar(url, mail) do
    {data, ext} = follow(url)

    path = "#{@dir}/#{mail}#{ext}" |> Path.absname()

    save_image(data, path)
    path
  end

  defp to_list(s) when is_binary(s), do: String.to_charlist(s)

  defp save_image(data, path) do
    File.write!(path, data)
  end

  def follow(url) do
    %{host: host, path: path, query: query} = URI.parse(url)

    request = %HTTPoison.Request{
      method: :get,
      url: host <> path,
      options: [
        params: request_params(query)
      ]
    }

    {:ok, resp} = HTTPoison.request(request)
    IO.inspect(resp)

    case resp do
      %{status_code: 302, headers: headers} ->
        follow(:proplists.get_value("Location", headers))

      %{headers: headers, body: body} ->
        content_type = :proplists.get_value("Content-Type", headers)
        ext = mime_to_ext(content_type)
        {body, ext}
    end
  end

  defp request_params(nil), do: []

  defp request_params(query) do
    URI.decode_query(query) |> Map.to_list()
  end

  defp mime_to_ext(type) do
    "." <> (MIME.extensions(type) |> hd())
  end
end
