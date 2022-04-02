%% Copyright (c) 2012-2020, DNSimple Corporation
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

%% @doc The general server supervisor. Starts the UDP and TCP listers on both
%% IPv4 and IPv6 ports. Also runs the zone checker *after* the UDP and TCP
%% servers are running.
-module(erldns_server_sup).

-behavior(supervisor).

% API
-export([start_link/0]).
% Supervisor hooks
-export([init/1]).

-define(SUPERVISOR, ?MODULE).
%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type, Args), {I, {I, start_link, Args}, permanent, 5000, Type, [I]}).

%% Public API
start_link() ->
    supervisor:start_link({local, ?SUPERVISOR}, ?MODULE, []).

init(_Args) ->
    {ok, {{one_for_one, 20, 10}, define_servers(erldns_config:get_servers())}}.

define_servers(Servers) -> define_servers(Servers, []).
define_servers([], Res) -> Res;
define_servers([Server|Servers], Res) ->
    Name = erldns_config:keyget(name, Server),
    Family = erldns_config:keyget(family, Server),
    Processes = erldns_config:keyget(processes, Server, 1),
    Children = case erldns_config:keyget(fd, Server) of
        undefined ->
            Address = erldns_config:keyget(address, Server),
            Port = erldns_config:keyget(port, Server),
            define_server(Name, {ip, Address, Port, Family}, Processes);
        _ ->
            Fd = erldns_config:keyget(fd, Server),
            Proto = erldns_config:keyget(proto, Server),
            define_server(Name, {fd, Fd, Family, Proto}, Processes)
    end,
    define_servers(Servers, Res ++ Children).

define_server(Name, Proto, N) ->
    define_server(Name, Proto, N, []).

worker_module(udp) -> erldns_udp_server;
worker_module(tcp) -> erldns_tcp_server.

define_server(_, _, 0, Definitions) ->
    Definitions;
define_server(Name0, {fd, Fd, Family, Proto}, 1, []) ->
    Name = list_to_atom(lists:concat([Proto, '_', Name0, '_fd', Fd])),
    [
        {Name,
         {worker_module(Proto), start_link, [Name, {fd, Fd}, Family]},
         permanent, 5000, worker, [Name]
        }
    ];
define_server(Name0, {fd, Fd, Family, Proto}, N, Definitions) ->
    Name = list_to_atom(lists:concat([Proto, '_', Name0, '_fd', Fd, '_', N])),
    Definition = [
        {Name,
         {worker_module(Proto), start_link, [Name, {fd, Fd}, Family]},
         permanent, 5000, worker, [Name]
        }
    ],
    define_server(Name, {fd, Fd, Family, Proto}, N - 1, Definitions ++ Definition);
define_server(Name, {ip, Address, Port, Family}, 1, []) ->
    UDPName = list_to_atom(lists:concat([udp, '_', Name])),
    TCPName = list_to_atom(lists:concat([tcp, '_', Name])),
    [{UDPName, {erldns_udp_server, start_link, [UDPName, Family, Address, Port]}, permanent, 5000, worker, [UDPName]},
     {TCPName, {erldns_tcp_server, start_link, [TCPName, Family, Address, Port]}, permanent, 5000, worker, [TCPName]}];
define_server(Name, {ip, Address, Port, Family}, N = 1, Definitions) ->
    UDPName = list_to_atom(lists:concat([udp, '_', Name, '_', N])),
    TCPName = list_to_atom(lists:concat([tcp, '_', Name])),
    Definition =
        [{UDPName, {erldns_udp_server, start_link, [UDPName, Family, Address, Port, socket_opts()]}, permanent, 5000, worker, [UDPName]},
         {TCPName, {erldns_tcp_server, start_link, [TCPName, Family, Address, Port]}, permanent, 5000, worker, [TCPName]}],
    define_server(Name, {ip, Address, Port, Family}, N - 1, Definitions ++ Definition);
define_server(Name, {ip, Address, Port, Family}, N, Definitions) ->
    UDPName = list_to_atom(lists:concat([udp, '_', Name, '_', N])),
    Definition = [{UDPName, {erldns_udp_server, start_link, [UDPName, Family, Address, Port, socket_opts()]}, permanent, 5000, worker, [UDPName]}],
    define_server(Name, {ip, Address, Port, Family}, N - 1, Definitions ++ Definition).

socket_opts() ->
    case os:type() of
        {unix, linux} ->
            [{raw, 1, 15, <<1:32/native>>}];
        {unix, darwin} ->
            [{raw, 16#ffff, 16#0200, <<1:32/native>>}];
        _ ->
            []
    end.
