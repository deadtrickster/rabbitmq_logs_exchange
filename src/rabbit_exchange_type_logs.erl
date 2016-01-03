-module(rabbit_exchange_type_logs).

-include_lib("rabbit_common/include/rabbit.hrl").
-include_lib("rabbit_common/include/rabbit_framing.hrl").

-behaviour(rabbit_exchange_type).

-import(rabbit_misc, [table_lookup/2]).

-export([description/0, serialise_events/0, route/2]).
-export([validate/1, validate_binding/2, create/2, delete/3, add_binding/3,
         remove_bindings/3, assert_args_equivalence/2, policy_changed/2]).

-export([enable_plugin/0, disable_plugin/0]).

-rabbit_boot_step({?MODULE,
                   [{description, "exchange type x-logs"},
                    {mfa, {?MODULE, enable_plugin,
                           []}},
                    {cleanup, {?MODULE, disable_plugin, []}},
                    {requires, rabbit_registry},
                    {enables, kernel_ready}]}).

-define(EXCHANGE(Ex), (exchange_module(Ex))).
-define(MONGODB_POOL(), (mongodb_pool_name())).

description() ->
  [{name, <<"x-logs">>},
   {description, <<"This exchange logs every message to mongodb.">>}].

enable_plugin() ->
  application:ensure_started(bson),
  application:ensure_started(crypto),
  application:ensure_started(mongodb),
  application:ensure_started(poolboy),
  application:ensure_started(mongodb_pool),
  {PoolName, PoolSize, ConnSpec} = mongodb_pool_spec(),
  mongodb_pool:create_pool(local,PoolSize,PoolName,ConnSpec),
  rabbit_registry:register(exchange, <<"x-logs">>, ?MODULE).

disable_plugin() ->
 %% mongodb_pool:delete_pool(?MONGODB_POOL()),
  %% probably should also stop related apps
  false.

route(X = #exchange{name = #resource{name = XName}},
      Delivery = #delivery{message = #basic_message{content = #content{payload_fragments_rev = PayloadFragmentsRev,
                                                                       properties = #'P_basic'{message_id = MessageId}}}}) ->
  mongodb_pool:insert(?MONGODB_POOL(), XName, [
                                               {<<"exchange">>, XName,
                                                <<"exchange_type">>, exchange_type(X),
                                                <<"timestamp">>, os:timestamp(),
                                                <<"content">>, binary:bin_to_list(concatenate_binaries(lists:reverse(PayloadFragmentsRev))),
                                                <<"message_id">>, MessageId}
                                              ]),
  %% route the message using proxy module
  ?EXCHANGE(X):route(X, Delivery).

validate(#exchange{arguments = Args} = X) ->
  case table_lookup(Args, <<"x-exchange-type">>) of
    {_ArgType, <<"x-exchange-type">>} ->
      rabbit_misc:protocol_error(precondition_failed,
                                 "Invalid argument, "
                                 "'x-exchange-type' can't be used "
                                 "for 'x-exchange-type'",
                                 []);
    {_ArgType, Type} when is_binary(Type) ->
      rabbit_exchange:check_type(Type),
      ?EXCHANGE(X):validate(X);
    _ ->
      rabbit_misc:protocol_error(precondition_failed,
                                 "Invalid argument, "
                                 "'x-exchange-type' must be "
                                 "an existing exchange type",
                                 [])
  end.

validate_binding(X, B) ->
  ?EXCHANGE(X):validate_binding(X, B).
create(Tx, X) ->
  ?EXCHANGE(X):create(Tx, X).
delete(Tx, X, Bs) ->
  ?EXCHANGE(X):delete(Tx, X, Bs).
policy_changed(X1, X2) ->
  ?EXCHANGE(X1):policy_changed(X1, X2).
add_binding(Tx, X, B) ->
  ?EXCHANGE(X):add_binding(Tx, X, B).
remove_bindings(Tx, X, Bs) ->
  ?EXCHANGE(X):remove_bindings(Tx, X, Bs).
assert_args_equivalence(X, Args) ->
  ?EXCHANGE(X):assert_args_equivalence(X, Args).
serialise_events() -> false.

%% assumes the type is set in the args and that validate/1 did its job
exchange_module(Ex) ->
  T = rabbit_registry:binary_to_type(exchange_type(Ex)),
  {ok, M} = rabbit_registry:lookup_module(exchange, T),
  M.

exchange_type(#exchange{arguments = Args}) ->
  case table_lookup(Args, <<"x-exchange-type">>) of
    {_ArgType, Type} -> Type;
    _ -> error
  end.

mongodb_pool_spec()->
  {ok, Pool} = application:get_env(rabbitmq_logs_exchange, mongodb_pool),
  Pool.

mongodb_pool_name()->
  {PoolName,_,_} = mongodb_pool_spec(),
  PoolName.

-spec concatenate_binaries([binary()]) -> binary().
concatenate_binaries([]) ->
  <<>>;
concatenate_binaries([Part]) ->
  Part;
concatenate_binaries([Head|Tail]) ->
  lists:foldl(fun (Value, Acc) -> <<Acc/binary, Value/binary>> end, Head, Tail).
