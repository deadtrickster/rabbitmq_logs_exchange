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

init(Ch) ->
  rabbit_channel:get_vhost(Ch).

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
