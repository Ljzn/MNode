-module(sv_peer).

% -liciense("MIT")
% -author("terriblecodebutwork aka. Jay Zhang")
% -email("bitcoinsv@yahoo.com")
% -paymail("390@moneybutton.com")

-compile([export_all]).
-define(MAGIC, 16#E3E1F3E8).
-define(PROTOCOL_VERSION, 31800).
-define(GENESIS, <<111, 226, 140, 10, 182, 241, 179, 114, 193, 166, 162, 70, 174, 99, 247, 79,
  147, 30, 131, 101, 225, 90, 8, 156, 104, 214, 25, 0, 0, 0, 0, 0>>).
-define(GENESIS_TARGET, decode_bits(16#1d00ffff)).

-record(peer, {state = start, host, port, socket, buffer, parent, handshake = false}).

connect(Host) -> connect(Host, false).

connect(Host, Parent) ->
    spawn_link(fun() -> do_connect(Host, Parent) end).

handshake(Host) ->
    case gen_tcp:connect(Host, 8333, [binary, {packet, 0}, {active, false}]) of
        {ok, Socket} ->
            loop(#peer{socket=Socket, host=Host, handshake=true, parent=false});
        _ ->
            timer:sleep(10000),
            error
    end.

do_connect(Host, Parent) ->
    case gen_tcp:connect(Host, 8333, [binary, {packet, 0}, {active, false}]) of
        {ok, Socket} ->
            loop(#peer{socket=Socket, host=Host, parent=Parent});
        _ ->
            timer:sleep(5000),
            do_connect(Host, Parent)
    end.

loop(#peer{state = start} = P) ->
    send_message(P#peer.socket, version_msg()),
    loop(P#peer{state = version_sent});

loop(#peer{state = version_sent} = P) ->
    case gen_tcp:recv(P#peer.socket, 0, 5000) of
        {ok, B} ->
            loop(P#peer{state = loop, buffer = B});
        _ ->
            gen_tcp:close(P#peer.socket),
            timer:sleep(5000),
            do_connect(P#peer.host, P#peer.parent)
    end;

loop(#peer{state = loop, socket = Socket, handshake = Handshake} = P) ->
    receive
        version ->
            case Handshake of
                true ->
                    gen_tcp:close(Socket),
                    exit(normal);
                _ ->
                    send_message(Socket, version_msg())
            end;
        ping ->
            send_message(Socket, ping_msg());
        getheaders ->
            send_message(Socket, getheaders_msg([?GENESIS]));
        getaddr ->
            send_message(Socket, getaddr_msg());
        mempool ->
            send_message(Socket, mempool_msg());
        {tx, Tx} ->
            send_message(Socket, tx_msg(Tx));
        close ->
            gen_tcp:close(Socket),
            exit(normal);
        _Other ->
            invalid_msg
    after 0 ->
        ok
    end,
    case parse_message(P#peer.buffer) of
        {ok, Command, Payload} ->
            {Data, _Rest} = parse(Command, Payload),
            case P#peer.parent of
                false -> ok;
                Parent when is_pid(Parent) ->
                    Parent ! {Command, Data}
                    % io:format("[remote] ~s\n~p\n", [Command, Data]);
            end,
            handle_command(Command, Data, Socket),
            loop(P#peer{buffer = <<>>});
        {error, incomplete} ->
            case gen_tcp:recv(Socket, 0, 5000) of
                {ok, B} ->
                    Buffer = P#peer.buffer,
                    loop(P#peer{buffer = <<Buffer/bytes, B/bytes>>});
                {error, _} ->
                    gen_tcp:close(P#peer.socket),
                    timer:sleep(10000),
                    do_connect(P#peer.host, P#peer.parent)
            end
    end.


send_message(Socket, Msg) ->
    % {ok, Command, P} = parse_message(Msg),
    % {Data, _Rest} = parse(Command, P),
    % io:format("[local ] ~s\n~p\n", [Command, Data]),
    gen_tcp:send(Socket, Msg).

get_checksum(Bin) ->
    <<C:4/bytes, _/bytes>> = double_hash256(Bin),
    C.

double_hash256(Bin) ->
    crypto:hash(sha256, crypto:hash(sha256, Bin)).

%% make messages

version_msg() ->
    Services = <<1, 0:(7*8)>>,
    Timestamp = get_timestamp(),
    Addr_recv = <<Services/binary, 0:(10*8), 16#FF, 16#FF, 0, 0, 0, 0, 0, 0>>,
    Addr_from = <<Services/binary, 0:(10*8), 16#FF, 16#FF, 0, 0, 0, 0, 0, 0>>,
    Nonce = crypto:strong_rand_bytes(8),
    User_agent = varstr(<<"\r/IS THIS A VALID USER AGNET?/">>),
    Strat_height = 0,
    Payload = <<?PROTOCOL_VERSION:32/little,
                Services/binary,
                Timestamp:64/little,
                Addr_recv/binary,
                Addr_from/binary,
                Nonce/binary,
                User_agent/binary,
                Strat_height:32/little
              >>,
    make_message(version, Payload).

verack_msg() ->
    make_message(verack, <<>>).

ping_msg() ->
    make_message(ping, <<>>).

pong_msg(Bin) ->
    make_message(pong, Bin).

getdata_msg(Bin) ->
    make_message(getdata, Bin).

getheaders_msg(Locators) ->
    N = varint(length(Locators)),
    HL = << <<Hash/bytes>> || Hash <- Locators >>,
    make_message(getheaders, <<?PROTOCOL_VERSION:32/little, N/bytes, HL/bytes, 0:(32*8)>>).

getaddr_msg() ->
    make_message(getaddr, <<>>).

mempool_msg() ->
    make_message(mempool, <<>>).

tx_msg(Tx) ->
    make_message(tx, Tx).

atom_to_cmd(A) ->
    S = list_to_binary(atom_to_list(A)),
    L = byte_size(S),
    <<S/binary, 0:((12-L)*8)>>.

make_message(Command, Payload) ->
    Size = byte_size(Payload),
    Checksum = get_checksum(Payload),
    CommandBin = atom_to_cmd(Command),
    <<?MAGIC:32/big, CommandBin/binary, Size:32/little,
      Checksum/binary, Payload/binary>>.

get_timestamp() ->
    {A, B, _} = os:timestamp(),
    A*1000000 + B.

varstr(Bin) ->
    Len = varint(byte_size(Bin)),
    <<Len/binary, Bin/binary>>.

varint(X) when X < 16#fd -> <<X>>;
varint(X) when X =< 16#ffff  -> <<16#fd, X:16/little>>;
varint(X) when X =< 16#ffffffff  -> <<16#fe, X:32/little>>;
varint(X) when X =< 16#ffffffffffffffff  -> <<16#ff, X:64/little>>.


%% parsing


parse_message(<<?MAGIC:32/big, Command:12/bytes, Size:32/little-integer,
          Checksum:4/bytes, Payload:Size/bytes, _Rest/bytes>>) ->
    Checksum = get_checksum(Payload),
    {ok, cmd_to_list(Command), Payload};

parse_message(_B) ->
    {error, incomplete}.

cmd_to_list(B) ->
    L = binary_to_list(B),
    string:strip(L, right, 0).

parse("version", <<Version:32/little,
                   Services:8/binary,
                   Timestamp:64/little,
                   Addr_recv:26/binary,
                   Addr_from:26/binary,
                   Nonce:8/binary,
                   Rest/binary
                 >>) ->
    {User_agent, Rest1} = parse_varstr(Rest),
    <<Strat_height:32/little, Rest2/binary>> = Rest1,
    {#{version => Version,
            services => Services,
            timestamp => Timestamp,
            addr_recv => parse_addr(Addr_recv),
            addr_from => parse_addr(Addr_from),
            nonce => Nonce,
            user_agent => User_agent,
            start_height => Strat_height}, Rest2};

parse("verack", <<>>) ->
    {<<>>, <<>>};

parse("ping", Payload) ->
    {Payload, <<>>};

parse("pong", Payload) ->
    {Payload, <<>>};

parse("getheaders", <<Version:32/little, Bin/binary>>) ->
    {L, Rest} = parse_varint(Bin),
    Size = 32*L,
    <<HL:Size/bytes, SH:32/bytes, Rest2/bytes>> = Rest,
    {#{version => Version,
           hash_count => L,
           block_locator_hashes => [ X || <<X:32/binary>> <= HL],
           hash_stop => SH}, Rest2};

parse("inv", Bin) ->
    {L, Rest} = parse_varint(Bin),
    Size = 36*L,
    <<INV:Size/bytes, Rest2/bytes>> = Rest,
    {#{raw => Bin, invs => [ parse_inv(X) || <<X:36/bytes>> <= INV]}, Rest2};

parse("headers", Bin) ->
    {L, Rest} = parse_varint(Bin),
    Size = 81*L,
    <<HL:Size/bytes, Rest2/bytes>> = Rest,
    {#{headers => [ parse_header(X) || <<X:81/bytes>> <= HL]}, Rest2};

parse("tx", Raw = <<Ver:32/little-signed, B/bytes>>) ->
    % io:format("transaction: ~s~n", [io_lib:parent(Raw)]),
    {TX_in_count, R1} = parse_varint(B),
    {TX_in, R2} = parse_tx_in(R1, [], TX_in_count),
    {TX_out_count, R3} = parse_varint(R2),
    {TX_out, R4} = parse_tx_out(R3, [], TX_out_count, 0),
    <<Lock_time:32/little, Rest/bytes>> = R4,
    {#{version => Ver, input => TX_in,
      output => TX_out, lock_time => Lock_time,
      txid => to_rpc_hex(double_hash256(Raw))}, Rest};

parse("addr", Bin) ->
    {L, Rest} = parse_varint(Bin),
    Size = 30*L,
    <<AL:Size/bytes, Rest2/bytes>> = Rest,
    {#{addrs => [ parse_addr(X) || <<X:30/bytes>> <= AL]}, Rest2};

parse("getdata", Bin) ->
    parse("inv", Bin);

parse("block", Bin) ->
    {parse_header(Bin), <<>>};

parse(Other, Bin) ->
    % io:format("=====================~s~n", [io_lib:parent({Other, Bin})]),
    {Bin, <<>>}.

% parse("alert", <<Ver:32/little-signed,
%                  Until:64/little-signed,
%                  Expir:64/little-signed,
%                  ID:32/little-signed,
%                  Cancel:32/little-signed,
%                  B1/bytes>>) ->
%     {LCancel, B2} = parse_varint(B1),
%     {Cancels, B3} = parse_int32_set(B2, [], LCancel),
%     <<MinVer:32/little-signed, MaxVer:32/little-signed, B4/bytes>> = B3,
%     {LSubVer, B5} = parse_varint(B4),
%     {SubVers, B6} = parse_string_set(B5, [], LSubVer),
%     <<Priority:32/little-signed, B7/bytes>> = B6,
%     {Comment, B8} = parse_varstr(B7),
%     {StatusBar, B9} = parse_varstr(B8),
%     {RPCError, _B10} = parse_varstr(B9),
%     {ok, #{version => Ver,
%            until => Until,
%            expir => Expir,
%            id => ID,
%            cancel => Cancel,
%            cancel_set => Cancels,
%            min_ver => MinVer,
%            max_ver => MaxVer,
%            subver_set => SubVers,
%            priority => Priority,
%            comment => Comment,
%            status_bar => StatusBar,
%            rpc_error => RPCError}};

get_height_from_coinbase(<<0:8/integer, _/bytes>>) ->
    0;
get_height_from_coinbase(<<N:8/integer, Rest/bytes>>) ->
    L = N*8,
    <<H:L/integer-little, _/bytes>> = Rest,
    H.

parse_tx_in(Rest, R, 0) ->
    {lists:reverse(R), Rest};

parse_tx_in(<<0:(32*8), Index:32/little, P/bytes>>, R, N) when N > 0 ->
    {L, R1} = parse_varint(P),
    <<Script:L/bytes, Seq:32/little, Rest/bytes>> = R1,
    Height = get_height_from_coinbase(Script),
    parse_tx_in(Rest, [#{
        tx_ref => <<0:(32*8)>>,
        txid => to_rpc_hex(<<0:(32*8)>>),
        index => Index,
        height => Height,
        raw_script => Script,
        hex_script => bin_to_hex(Script),
        coinbase => true,
        script => bin_to_chars(Script),
        sequence => Seq
    }|R], N - 1);

parse_tx_in(<<TX_ref:32/bytes, Index:32/little, P/bytes>>, R, N) when N > 0 ->
    {L, R1} = parse_varint(P),
    <<Script:L/bytes, Seq:32/little, Rest/bytes>> = R1,
    parse_tx_in(Rest, [#{tx_ref => TX_ref, txid => to_rpc_hex(TX_ref), index => Index, raw_script => Script, hex_script => bin_to_hex(Script), coinbase => false,
                         script => parse_script(Script), sequence => Seq}|R], N - 1).

parse_script(S) ->
    try 'Elixir.BexLib.Script':parse(S) of
        R -> R
    catch
        _:_ -> "Invalid Script"
    end.

% parse_script(<<H:8/little, T/bytes>>, R) ->
%     case opcode(H, T) of
%         {Result, T1} ->
%             parse_script(T1, [Result | R]);
%         else ->
%             {else, lists:reverse(R)};
%         endif ->
%             {endif, lists:reverse(R)}
%     end;
% parse_script(<<>>, R) ->
%     lists:reverse(R).

%%FIXME there is a bug in script parse, use BexLib.Script.parse instead.
opcode(H, Bin) when H >= 0 andalso H =< 75 ->
    <<B:H/binary, R/bytes>> = Bin,
    {{"PUSH", B}, R};
opcode(99, Bin) ->
    {Left, Right, Bin1} = cond_clause(Bin, []),
    {{"IF", Left, Right}, Bin1};
opcode(100, Bin) ->
    {Left, Right, Bin1} = cond_clause(Bin, []),
    {{"IF", Right, Left}, Bin1};
% opcode(103, _Bin) ->
%     % ELSE
%     else;
% opcode(104, _Bin) ->
%     % ENDIF
%     endif;
opcode(106, Bin) ->
    {{"RETURN", Bin}, <<>>};
opcode(108, Bin) ->
    {"FROMALTSTACK", Bin};
opcode(111, Bin) ->
    {"3DUP", Bin};
opcode(112, Bin) ->
    {"2OVER", Bin};
opcode(115, Bin) ->
    {"IFDUP", Bin};
opcode(118, Bin) ->
    {"DUP", Bin};
opcode(135, Bin) ->
    {"EQUAL", Bin};
opcode(136, Bin) ->
    {"EQUALVERIFY", Bin};
opcode(169, Bin) ->
    {"HASH160", Bin};
opcode(172, Bin) ->
    {"CHECKSIG", Bin};
opcode(H, Bin) ->
    unkonw = H,
    {{H, Bin}, <<>>}.

cond_clause(<<H:8/little, T/bytes>>, {L, R, Rest}) ->
    case H of
        99 ->
            % IF
            cond_clause(T, 1);
        103 ->
            % ELSE
            ok;

        104 ->
            % ENDIF
            ok
    end,
    {L, R, Rest}.


parse_tx_out(Rest, R, 0, _I) ->
    {lists:reverse(R), Rest};

parse_tx_out(<<Value:64/little, P/bytes>>, R, N, I) when N > 0 ->
    {L, R1} = parse_varint(P),
    <<PK_script:L/bytes, Rest/bytes>> = R1,
    parse_tx_out(Rest, [#{index => I, value => Value, raw_script => PK_script, hex_script => bin_to_hex(PK_script), script => parse_script(PK_script)}|R], N - 1, I + 1).

parse_addr(<<Time:32/little, Services:8/bytes, IP:16/bytes, Port:16/little>>) ->
    #{timestamp => Time, services => Services, ip => IP, port => Port};
parse_addr(<<Services:8/bytes, IP:16/bytes, Port:16/little>>) ->
    #{services => Services, ip => IP, port => Port}.

% parse_int32_set(Rest, R, 0) ->
%     {lists:reverse(R), Rest};

% parse_int32_set(<<H:32/little-signed, Rest/bytes>>, R, N) when N > 0 ->
%     parse_int32_set(Rest, [H | R], N - 1).

% parse_string_set(Rest, R, 0) ->
%     {lists:reverse(R), Rest};

% parse_string_set(Bytes, R, N) when N > 0 ->
%     {Data, Rest} = parse_varstr(Bytes),
%     parse_int32_set(Rest, [Data | R], N - 1).


parse_inv(<<0:32/little, _H/binary>>) -> error;
parse_inv(<<1:32/little, H:32/bytes>>) -> {tx, H};
parse_inv(<<2:32/little, H:32/bytes>>) -> {block, H};
parse_inv(<<3:32/little, H:32/bytes>>) -> {filtered_block, H};
parse_inv(<<4:32/little, H:32/bytes>>) -> {cmpct_block, H}.

parse_header(<<Head:80/bytes, Rest/binary>>) ->
    <<Version:32/signed-little-integer,
               Prev_block:32/bytes,
               Merkle_root:32/bytes,
               Timestamp:32/little-integer,
               Bits:32/little-integer,
               Nonce:4/bytes>> = Head,
    {Tx_count, Rest2} = parse_varint(Rest),
    Hash = double_hash256(Head),
    Target = decode_bits(Bits),
    #{version => Version,
      prev_block => Prev_block,
      merkle_root => Merkle_root,
      timestamp => Timestamp,
      bits => Bits,
      target => Target,
      work => bits_to_work(Bits),
      difficulty => bits_to_difficulty(Bits),
      nonce => Nonce,
      tx_count => Tx_count,
      hash => Hash,
      hex_hash => bin_to_hex(rev(Hash)),
      int_hash => binary:decode_unsigned(Hash, little),
      txs => parse_txs(Rest2, [], Tx_count),
      pow_valid => verify_pow(Hash, Target)}.


parse_merkle_block(<<Head:80/bytes, Rest/binary>>) ->
    <<Version:32/signed-little-integer,
               Prev_block:32/bytes,
               Merkle_root:32/bytes,
               Timestamp:32/little-integer,
               Bits:32/little-integer,
               Nonce:4/bytes>> = Head,
    Hash = double_hash256(Head),
    Target = decode_bits(Bits),
    {PartialMerkleTree, Rest1} = parse_partial_merkle_tree(Rest),
    {#{version => Version,
      prev_block => Prev_block,
      merkle_root => Merkle_root,
      timestamp => Timestamp,
      bits => Bits,
      target => Target,
      work => bits_to_work(Bits),
      difficulty => bits_to_difficulty(Bits),
      nonce => Nonce,
      hash => Hash,
      hex_hash => bin_to_hex(rev(Hash)),
      int_hash => binary:decode_unsigned(Hash, little),
      pow_valid => verify_pow(Hash, Target),
      partial_merkle_tree => PartialMerkleTree}, Rest1}.

% %% Constructing a partial merkle tree object
% 
% - Traverse the merkle tree from the root down, and for each eencountered
%   node:
%   - Check whether this node corresponds to a leaf node (transaction)
%     that is to be included OR any parent thereof:
%     - If so, append a '1' bit to the flag bits
%     - Otherwise, append a '0' bit
%   - Check whether this node is a internal node (non-leaf) AND is the parent
%     of an included leaf node:
%     - If so:
%       - Descend into its left child node, and process the subtree beneath
%         it entirely (depth-first).
%       - If this node has a right child node too, descend into it as well
%     - Otherwise: append this node's hash to the hash list
% 
% %% Parsing a partial merkle tree object
% 
% As the partial block message contains the number of transactions
% in the entire block, the shape of the merkle tree is known before
% hand. Again, traverse this tree, computing traversed node's hashes
% along the way:
%
% - read a bit from the flag bit list
%   - if it's '0'
%     - read a hash from the hashes list, and return it as this node's
%       hash
%   - if it's '1' and this is a leaf node
%     - read a hash from the hashes list, store it as a matched txid,
%       and return it as this node's hash
%   - if it's '1' and this is an internal node
%     - descend into its left child tree, and store its computed hash
%       as L
%     - if this node has a right child as well
%       - descend into its right child, and store its computed hash a R
%       - if L == R, the partial merkle tree object is invalid
%       - return hash(L||R)
%     - if this node has no right child, return hash(L||L)
%
%
%
%  Example:
%  txid = "220ebc64e21abece964927322cba69180ed853bb187fbc6923bac7d010b9d87a"
%  block = "0000000000013b8ab2cd513b0261a14096412195a72a0c4827d229dcc7e0f7af"
%  txoutproof = "0100000090f0a9f110702f808219ebea1173056042a714bad51b916cb6800000000000005275289558f51c9966699404ae2294730c3c9f9bda53523ce50e9b95e558da2fdb261b4d4c86041b1ab1bf930900000005fac7708a6e81b2a986dea60db2663840ed141130848162eb1bd1dee54f309a1b2ee1e12587e497ada70d9bd10d31e83f0a924825b96cb8d04e8936d793fb60db7ad8b910d0c7ba2369bc7f18bb53d80e1869ba2c32274996cebe1ae264bc0e2289189ff0316cdc10511da71da757e553cada9f3b5b1434f3923673adb57d83caac392c38af156d6fc30b55fad4112df2b95531e68114e9ad10011e72f7b7cfdb025700"
%
%
%

parse_partial_merkle_tree(<<NumTransactions:32/little-integer, Rest/bytes>>) ->
    {Hashes, Rest1} = parse_n_bytes_list(Rest, 32),
    {Bits, Rest2} = parse_n_bits_list(Rest1, 8),
    {#{
        num_transactions => NumTransactions,
        hashes => Hashes,
        flags => lists:reverse(Bits)
    }, Rest2}.

parse_n_bytes_list(Bin, N) ->
    {L, Rest} = parse_varint(Bin),
    Size = N*L,
    <<Data:Size/bytes, Rest2/bytes>> = Rest,
    {[ X || <<X:N/bytes>> <= Data], Rest2}.

parse_n_bits_list(Bin, N) ->
    {L, Rest} = parse_varint(Bin),
    Size = N*L,
    <<Data:Size/bits, Rest2/bytes>> = Rest,
    {[ X == <<1:1>> || <<X:1/bits>> <= rev(Data) ], Rest2}.


bits_to_difficulty(Bits) ->
    Target = decode_bits(Bits),
    ?GENESIS_TARGET / Target.

bits_to_work(Bits) ->
    Target = decode_bits(Bits),
    math:pow(256, 32) / Target.

verify_pow(Hash, Target) ->
    <<H:256/little-integer>> = Hash,
    H < Target.

parse_txs(_Bin, R, 0) ->
    lists:reverse(R);
parse_txs(Bin, R, N) ->
    {Tx, Rest} = parse("tx", Bin),
    parse_txs(Rest, [Tx | R], N - 1).


parse_varstr(Bin) ->
    {Len, B} = parse_varint(Bin),
    << Data:Len/bytes, Rest/binary >> = B,
    {Data, Rest}.

parse_varint(<<16#fd, X:16/little, Rest/binary>>) -> {X, Rest};
parse_varint(<<16#fe, X:32/little, Rest/binary>>) -> {X, Rest};
parse_varint(<<16#ff, X:64/little, Rest/binary>>) -> {X, Rest};
parse_varint(<<X:8, Rest/binary>>) -> {X, Rest}.

decode_bits(Bits) when is_integer(Bits) ->
    decode_bits(binary:encode_unsigned(Bits));
decode_bits(<<N, D/bytes>>) ->
    L = byte_size(D),
    B = <<D/bytes, 0:((N-L)*8)>>,
    binary:decode_unsigned(B).

% helper

bin_to_chars(Bin) ->
    io_lib:write_string(binary_to_list(Bin)).

trim_trailing(Bin) ->
    trim_trailing(Bin, 0).

trim_trailing(Bin, Byte) when is_binary(Bin) and is_integer(Byte) ->
    do_trim_trailing(rev(Bin), Byte).

do_trim_trailing(<< Byte, Bin/binary >>, Byte) ->
    do_trim_trailing(Bin, Byte);
do_trim_trailing(<< Bin/binary >>, _Byte) ->
    rev(Bin).

bin_to_hex(B) ->
    bin_to_hex(B, "").

bin_to_hex(B, D) ->
    binary:list_to_bin(string:join([io_lib:format("~2.16.0b", [X]) || <<X>> <= B ], D)).

digit(X) when X >= $0, X =< $9 ->
    X - $0;

digit(X) when X >= $a, X =< $z ->
    X - $a + 10;

digit(X) when X >= $A, X =< $Z ->
    X - $A + 10.

hex_to_bin(S) ->
    binary:list_to_bin(hex_to_bin(binary:bin_to_list(S), [])).

hex_to_bin([], R) ->
    lists:reverse(R);

hex_to_bin([$\  | T], R) ->
    hex_to_bin(T, R);

hex_to_bin([A, B | T], R) ->
    hex_to_bin(T, [digit(A)*16+digit(B)|R]).

rev(Binary) ->
   Size = erlang:size(Binary)*8,
   <<X:Size/integer-little>> = Binary,
   <<X:Size/integer-big>>.

to_rpc_hex(B) ->
    bin_to_hex(rev(B)).

from_rpc_hex(H) ->
    rev(hex_to_bin(H)).


%% validation

valid_pow(Hash, Target) ->
    rev(Hash) < Target.


%% peer behavior

handle_command("version", _Data, Socket) ->
    send_message(Socket, verack_msg());

handle_command("ping", Data, Socket) ->
    send_message(Socket, pong_msg(Data));

handle_command("getheaders", _Data, _Socket) ->
    ok;

handle_command("inv", #{raw := Bin}, Socket) ->
    % send_message(Socket, getdata_msg(Bin));
    ok;

handle_command(_Command, _Data, _Socket) ->
    ok.

%% other

block_locator(B) ->
    block_locator(B, [], 0, 1).

block_locator(?GENESIS, Re, _, _) ->
    lists:reverse(Re);
block_locator(B, Re, Len, Step) ->
    Pb = prev_block(B, Step),
    Len1 = Len + 1,
    Step1 = case Len1 > 10 of
                true ->
                    Step * 2;
                false ->
                    Step
            end,
    block_locator(Pb, [Pb | Re], Len1, Step1).

prev_block(B, 0) -> B;
prev_block(B, N) ->
    prev_block(get_prev(B), N-1).

get_prev(_B) -> todo.

%% :sv_peer.connect {139, 59, 67, 18}
%% :sv_peer.connect {159, 203, 171, 73}
%% :sv_peer.connect {159, 65, 152, 200}


%% @doc Get addrs for bootstrap from DNS.
get_addrs_ipv4_dns() ->
    L = ["seed.bitcoinsv.io",
         "seed.cascharia.com",
         "seed.satoshisvision.network"
        ],
    lists:flatten([nslookup_ipv4(A) || A <- L]).

nslookup_ipv4(Addr) ->
    Type = a,
    Class = in,
    inet_res:lookup(Addr, Class, Type).
