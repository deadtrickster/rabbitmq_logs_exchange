-module(rabbit_exchange_type_logs).

-include_lib("rabbit_common/include/rabbit.hrl").
-include_lib("rabbit_common/include/rabbit_framing.hrl").

-behaviour(rabbit_exchange_type).

-import(rabbit_misc, [table_lookup/2]).

-export([description/0, serialise_events/0, route/2]).
-export([validate/1, validate_binding/2, create/2, delete/3, add_binding/3,
         remove_bindings/3, assert_args_equivalence/2, policy_changed/2]).
%% -export([disable_plugin/0]).

-rabbit_boot_step({?MODULE,
                   [{description, "exchange type x-logs"},
                    {mfa, {rabbit_registry, register,
                           [exchange, <<"x-logs">>, ?MODULE]}},
                    {cleanup, {?MODULE, disable_plugin, []}},
                    {requires, rabbit_registry},
                    {enables, kernel_ready}]}).

-define(INTEGER_ARG_TYPES, [byte, short, signedint, long]).

description() ->
    [{name, <<"x-logs">>},
     {description, <<"Recent Logs.">>}].

serialise_events() -> false.

route(#exchange{name      =#resource{name = XName},
                arguments = Args},
      #delivery{message = #basic_message{content = #content{payload_fragments_rev = PayloadFragmentsRev,
                                                            properties = #'P_basic'{message_id = MessageId}}}}) ->
  {ok, Connection} = mongo:connect ([{database, <<"rabbit_logs">>}]),
  mongo:insert(Connection, XName, [
                            {<<"origin">>, XName,
                             <<"x">>, table_lookup(Args, <<"alternate-exchange">>),
                             <<"content">>, concatenate_binaries(lists:reverse(PayloadFragmentsRev)),
                             <<"message_id">>, MessageId}
                           ]),
  [].

validate(_X) -> ok.
  
validate_binding(_X, _B) -> ok.
create(_Tx, _X) -> ok.
delete(_Tx, _X, _Bs) -> ok.
policy_changed(_X1, _X2) -> ok.
add_binding(_Tx, _X, _B) -> ok.
remove_bindings(_Tx, _X, _Bs) -> ok.
assert_args_equivalence(X, Args) ->
  rabbit_exchange:assert_args_equivalence(X, Args).

-spec concatenate_binaries([binary()]) -> binary().
concatenate_binaries([]) ->
  <<>>;
concatenate_binaries([Part]) ->
  Part;
concatenate_binaries([Head|Tail]) ->
  lists:foldl(fun (Value, Acc) -> <<Acc/binary, Value/binary>> end, Head, Tail).
