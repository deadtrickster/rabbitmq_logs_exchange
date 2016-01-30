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
  rabbit_registry:register(channel_interceptor, <<"message_id_interceptor">>, rabbit_message_id_interceptor),
  rabbit_registry:register(exchange, <<"x-logs">>, ?MODULE).

disable_plugin() ->
  ongodb_pool:delete_pool(?MONGODB_POOL()),
  rabbit_registry:unregister(exchange, <<"x-logs">>),
  rabbit_registry:unregister(channel_interceptor, <<"message_id_interceptor">>),
  %% probably should also stop related apps
  false.

preprocess_content(<<"application/bson">>, Content) ->
  {Doc,_} = bson_binary:get_document(Content),
  Doc;
preprocess_content(<<"application/json">>, Content) ->
  json:from_binary(Content);
preprocess_content(<<"text/", _/binary>>, Content) ->
  Content;
preprocess_content(_, Content) ->
  binary:bin_to_list(Content). %% just bytes array

route(X = #exchange{name = #resource{name = XName}},
      Delivery = #delivery{message = #basic_message{content = #content{payload_fragments_rev = PayloadFragmentsRev,
                                                                       properties = #'P_basic'{content_type = ContentType} = Props},
                                                   routing_keys = RoutingKeys}}) ->
  %% Delivery1 = case MessageId of
  %%               undefined ->
  %%                 Props2 = Props#'P_basic'{message_id = rabbit_guid:binary(rabbit_guid:gen_secure(), "amq.mid")},
  %%                 %% we need to reset properties_bin = none so the new properties
  %%                 %% get serialized when deliverying the message.
  %%                 Delivery#delivery{message = Message#basic_message{content = Content#content{properties = Props2, properties_bin = none}}};
  %%               _ ->
  %%                 Delivery
  %%             end,
  Timestamp = os:timestamp(),
  Document = {<<"exchange">>, XName,
              <<"exchange_type">>, exchange_type(X),
              <<"routing_keys">>, RoutingKeys,
              <<"timestamp">>, Timestamp,
              <<"content">>, preprocess_content(ContentType, concatenate_binaries(lists:reverse(PayloadFragmentsRev))),
              <<"properties">>, basic_properties_to_bson(Props),
              <<"events">>, [{<<"event">>, <<"added">>, <<"timestamp">>, Timestamp}],
              <<"state">>, <<"added">>},
  Document1 = maybe_merge_with_custom_fields(Document, X),

  mongodb_pool:insert(?MONGODB_POOL(), XName, [Document1]),
  %% route the message using proxy module
  ?EXCHANGE(X):route(X, Delivery).

validate_x_exchange_type(#exchange{arguments = Args} = X) ->
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

validate_x_custom_fields(#exchange{arguments = Args}) ->
  case table_lookup(Args, <<"x-custom-fields">>) of
    undefined ->
      ok;
    {table, _CustomFields} ->
      ok;
    _ ->
      rabbit_misc:protocol_error(precondition_failed,
                                 "Invalid argument, "
                                 "'x-custom-fields' must be "
                                 "table or undefined",
                                 [])
  end.

validate(X) ->
  validate_x_exchange_type(X),
  validate_x_custom_fields(X).

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

maybe_merge_with_custom_fields(Document, #exchange{arguments = Args}) ->
  case table_lookup(Args, <<"x-custom-fields">>) of
    {table, CustomFieldsTable} ->
      CustomFieldsDoc = amqp_table_to_bson(CustomFieldsTable),
      bson:merge(CustomFieldsDoc, Document);
    undefined ->
      Document
  end.

mongodb_pool_spec()->
  {ok, Pool} = application:get_env(rabbitmq_logs_exchange, mongodb_pool),
  Pool.

mongodb_pool_name()->
  {PoolName,_,_} = mongodb_pool_spec(),
  PoolName.

amqp_timestamp_to_bson(Timestamp) when is_integer(Timestamp) ->
  {Timestamp div 1000000,
   Timestamp div 1000000 rem 1000000,
   0};
amqp_timestamp_to_bson(undefined) ->
  null.

amqp_field_to_bson(longstr, Value)->
  Value;
amqp_field_to_bson(signedint, Value) ->
  Value;
amqp_field_to_bson(decimal, {Scale, Value}) ->
  Value / math:pow(10, Scale);
amqp_field_to_bson(timestamp, Value) ->
  amqp_timestamp_to_bson(Value);
amqp_field_to_bson(unsignedbyte, Value) ->
  Value;
amqp_field_to_bson(unsignedshort, Value) ->
  Value;
amqp_field_to_bson(unsignedint, Value) ->
  Value;
amqp_field_to_bson(table, Value) ->
  amqp_table_to_bson(Value);
amqp_field_to_bson(byte, Value) ->
  Value;
amqp_field_to_bson(double, Value) ->
  Value;
amqp_field_to_bson(float, Value) ->
  Value;
amqp_field_to_bson(long, Value) ->
  Value;
amqp_field_to_bson(short, Value) ->
  Value;
amqp_field_to_bson(bool, Value) ->
  Value;
amqp_field_to_bson(binary, Value) ->
  binary:bin_to_list(Value); %% bytes array
amqp_field_to_bson(void, _) ->
  null;
amqp_field_to_bson(array, Value) ->
  amqp_array_to_bson(Value).

amqp_array_to_bson([], Acc) ->
  Acc;
amqp_array_to_bson([Item|Rest], Acc) ->
  {TypeBin, ValueBin} = Item,
  amqp_array_to_bson(Rest, Acc++[amqp_field_to_bson(TypeBin, ValueBin)]).

amqp_array_to_bson(Array) ->
  amqp_array_to_bson(Array, []).

amqp_table_to_bson([], Acc) ->
  list_to_tuple(Acc);
amqp_table_to_bson([Field|Rest], Acc) ->
  {Key, TypeBin, ValueBin} = Field,
  amqp_table_to_bson(Rest, Acc++[Key, amqp_field_to_bson(TypeBin, ValueBin)]).

amqp_table_to_bson(Table) when is_list(Table) ->
  amqp_table_to_bson(Table, []);
amqp_table_to_bson(undefined) ->
  null.


basic_properties_to_bson(#'P_basic'{content_type = ContentType,
                                    content_encoding = ContentEncoding,
                                    headers = Headers,
                                    delivery_mode = DeliveryMode,
                                    priority = Priority,
                                    correlation_id = CorrelationId,
                                    reply_to = ReplyTo,
                                    expiration = Expiration,
                                    message_id = MessageId,
                                    timestamp = Timestamp,
                                    type = Type,
                                    user_id = UserId,
                                    app_id = AppId,
                                    cluster_id = ClusterId}) ->

  {<<"content_type">>, ContentType,
   <<"content_encoding">>, ContentEncoding,
   <<"headers">>, amqp_table_to_bson(Headers),
   <<"delivery_mode">>, DeliveryMode,
   <<"priority">>, Priority,
   <<"correlation_id">>, CorrelationId,
   <<"reply_to">>, ReplyTo,
   <<"expiration">>, Expiration,
   <<"message_id">>, MessageId,
   <<"timestamp">>, amqp_timestamp_to_bson(Timestamp),
   <<"type">>, Type,
   <<"user_id">>, UserId,
   <<"app_id">>, AppId,
   <<"cluster_id">>, ClusterId}.

-spec concatenate_binaries([binary()]) -> binary().
concatenate_binaries([]) ->
  <<>>;
concatenate_binaries([Part]) ->
  Part;
concatenate_binaries([Head|Tail]) ->
  lists:foldl(fun (Value, Acc) -> <<Acc/binary, Value/binary>> end, Head, Tail).
