%% Copyright (c) 2016 Ilya Khaprov <ilya.khaprov@publitechs.com>. All rights reserved.
%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%% This code is partly based on work by Pivotal Software Inc.
%% Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.

-module(rabbit_message_id_interceptor).

-include_lib("rabbit_common/include/rabbit.hrl").
-include_lib("rabbit_common/include/rabbit_framing.hrl").

-behaviour(rabbit_channel_interceptor).

-export([description/0, intercept/3, applies_to/0, init/1]).

-record(ch, {
  %% starting | running | flow | closing
  state,
  %% same as reader's protocol. Used when instantiating
  %% (protocol) exceptions.
  protocol,
  %% channel number
  channel,
  %% reader process
  reader_pid,
  %% writer process
  writer_pid,
  %%
  conn_pid,
  %% same as reader's name, see #v1.name
  %% in rabbit_reader
  conn_name,
  %% limiter pid, see rabbit_limiter
  limiter,
  %% none | {Msgs, Acks} | committing | failed |
  tx,
  %% (consumer) delivery tag sequence
  next_tag,
  %% messages pending consumer acknowledgement
  unacked_message_q,
  %% same as #v1.user in the reader, used in
  %% authorisation checks
  user,
  %% same as #v1.user in the reader
  virtual_host,
  %% when queue.bind's queue field is empty,
  %% this name will be used instead
  most_recently_declared_queue,
  %% a dictionary of queue pid to queue name
  queue_names,
  %% queue processes are monitored to update
  %% queue names
  queue_monitors,
  %% a dictionary of consumer tags to
  %% consumer details: #amqqueue record, acknowledgement mode,
  %% consumer exclusivity, etc
  consumer_mapping,
  %% a dictionary of queue pids to consumer tag lists
  queue_consumers,
  %% a set of pids of queues that have unacknowledged
  %% deliveries
  delivering_queues,
  %% when a queue is declared as exclusive, queue
  %% collector must be notified.
  %% see rabbit_queue_collector for more info.
  queue_collector_pid,
  %% timer used to emit statistics
  stats_timer,
  %% are publisher confirms enabled for this channel?
  confirm_enabled,
  %% publisher confirm delivery tag sequence
  publish_seqno,
  %% a dtree used to track unconfirmed
  %% (to publishers) messages
  unconfirmed,
  %% a list of tags for published messages that were
  %% delivered but are yet to be confirmed to the client
  confirmed,
  %% a dtree used to track oustanding notifications
  %% for messages published as mandatory
  mandatory,
  %% same as capabilities in the reader
  capabilities,
  %% tracing exchange resource if tracing is enabled,
  %% 'none' otherwise
  trace_state,
  consumer_prefetch,
  %% used by "one shot RPC" (amq.
  reply_consumer,
  %% flow | noflow, see rabbitmq-server#114
  delivery_flow,
  interceptor_state
}).

init(Ch) ->
  #ch{virtual_host = VHost} = Ch,
  VHost.

description() ->
  [{description,
    <<"Sets message_id property (if not set) to messages as they enter RabbitMQ">>}].

intercept(#'basic.publish'{exchange = XName} = Method, Content, IState) ->
  Content2 = case rabbit_exchange:lookup(#resource{virtual_host = IState, kind = exchange, name = XName}) of
               {ok, #exchange{type = XType}} ->
                 case XType of
                   'x-logs' ->
                     maybe_set_content_message_id(rabbit_binary_parser:ensure_content_decoded(Content));
                   _ ->
                     Content
                 end;
               _ -> Content
             end,
  {Method, Content2};

intercept(Method, Content, _VHost) ->
  {Method, Content}.

applies_to() ->
  ['basic.publish'].

%%----------------------------------------------------------------------------

maybe_set_content_message_id(#content{properties = #'P_basic'{message_id = MessageId} = Props} = Content) ->
  case MessageId of
    undefined ->
      Props2 = Props#'P_basic'{message_id = rabbit_guid:binary(rabbit_guid:gen_secure(), "amq.mid")},
      %% we need to reset properties_bin = none so the new properties
      %% get serialized when deliverying the message.
      Content#content{properties = Props2, properties_bin = none};
    _ ->
      Content
  end.
