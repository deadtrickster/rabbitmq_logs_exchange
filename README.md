# RabbitMQ Logs Exchange

Saves message to MongoDB before routing. Routes messages transparently using exchange-type specified by `x-exchange-type`

Exchange Type: `x-logs`

This plugin also includes channel interceptor which generates message_id for messages
published to `x-logs` exchanges if not already set.

## Content-type handling

* `application/bson` - while not official this still can be used - content parsed to BSON
* `application/json` - JSON parsed and converted to BSON
* `text/*` - content stored as text

All other content-types including undefined stored as byte-arrays.

## Examples

### Content-type: text/*

```lisp
(bunny:with-connection ()
  (bunny:with-channel ()
    (let ((x (bunny:exchange.declare "hmm" :type "x-logs" :auto-delete t :arguments '(("x-exchange-type" . "direct"))))
          (q (bunny:queue.declare-temp))
          (text "Hello World!"))
      (bunny:queue.bind q x :routing-key q)
      (bunny:subscribe-sync q)
      (bunny:publish x text :routing-key q :properties '(:content-type "text/plain"))
      (bunny:consume :one-shot t))))
```

Corresponding MongoDB document

```javascript
{
  "_id":ObjectId("56890410e72f45e566000001"),
  "exchange":"hmm",
  "exchange_type":"direct",
  "timestamp": ISODate("2016-01-03T11:34:30.237Z"),
  "content":"Hello World!",
  "properties":{
    "content_type":"text/plain",
    "content_encoding":null,
    "headers":null,
    "delivery_mode":null,
    "priority":null,
    "correlation_id":null,
    "reply_to":null,
    "expiration":null,
    "message_id":"amq.mid-iVGYar8yAhEY37AaSMRRUw",
    "timestamp":null,
    "type":null,
    "user_id":null,
    "app_id":null,
    "cluster_id":null
  }
}
```

### Content-type: application/json

```lisp
(bunny:with-connection ()
  (bunny:with-channel ()
    (let ((x (bunny:exchange.declare "hmm" :type "x-logs" :auto-delete t :arguments '(("x-exchange-type" . "direct"))))
          (q (bunny:queue.declare-temp))
          (json "{\"name\":\"Homer\", \"age\":32}"))
      (bunny:queue.bind q x :routing-key q)
      (bunny:subscribe-sync q)
      (bunny:publish x json :routing-key q :properties '(:message-id "message-id"
                                                         :content-type "application/json"))
      (bunny:consume :one-shot t))))
```

Corresponding MongoDB document

```javascript
{
  "_id":ObjectId("56890410e72f45e566000001"),
  "exchange":"hmm",
  "exchange_type":"direct",
  "timestamp": ISODate("2016-01-03T11:34:30.237Z"),
  "content":{
    "name":"Homer",
    "age":33
  },
  "properties":{
    "content_type":"application/json",
    "content_encoding":null,
    "headers":null,
    "delivery_mode":null,
    "priority":null,
    "correlation_id":null,
    "reply_to":null,
    "expiration":null,
    "message_id":"message-id",
    "timestamp":null,
    "type":null,
    "user_id":null,
    "app_id":null,
    "cluster_id":null
  }
}
```

### Content-type: application/bson

```lisp
(bunny:with-connection ()
  (bunny:with-channel ()
    (let ((x (bunny:exchange.declare "hmm" :type "x-logs" :auto-delete t :arguments '(("x-exchange-type" . "direct"))))
          (q (bunny:queue.declare-temp))
          (bson #b"\x1e\x00\x00\x00\x02name\x00\x06\x00\x00\x00Homer\x00\x10age\x00!\x00\x00\x00\x00"))
      (bunny:queue.bind q x :routing-key q)
      (bunny:subscribe-sync q)
      (bunny:publish x bson :routing-key q :properties '(:message-id "message-id"
                                                         :content-type "application/bson"))
      (bunny:consume :one-shot t))))
```

Corresponding MongoDB document

```javascript
{
  "_id":ObjectId("56890410e72f45e566000001"),
  "exchange":"hmm",
  "exchange_type":"direct",
  "timestamp": ISODate("2016-01-03T11:20:48.089Z"),
  "content":{
    "name":"Homer",
    "age":33
  },
  "properties":{
    "content_type":"application/bson",
    "content_encoding":null,
    "headers":null,
    "delivery_mode":null,
    "priority":null,
    "correlation_id":null,
    "reply_to":null,
    "expiration":null,
    "message_id":"message-id",
    "timestamp":null,
    "type":null,
    "user_id":null,
    "app_id":null,
    "cluster_id":null
  }
}
```

### Can serialize properties/tables/arrays to BSON

```lisp
(bunny:with-connection ()
  (bunny:with-channel ()
    (let ((x (bunny:exchange.declare "hmm" :type "x-logs" :auto-delete t :arguments '(("x-exchange-type" . "direct"))))
          (q (bunny:queue.declare-temp))
          (now (local-time:now)))
      (bunny:queue.bind q x :routing-key q)
      (bunny:subscribe-sync q)
      ;(bunny:publish x "Hello World!" :routing-key q :properties '(:message-id "message-id" :content-type "text/plain"))
      (bunny:publish x "Hello World!" :routing-key q
                                      :properties `(:content-type "text/plain"
                                                    :content-encoding "utf-8"
                                                    :headers (("coordinates" . (("lat" . 59.35)
                                                                                ("lng" . 18.066667d0)))
                                                              ("time" . ,now)
                                                              ("participants" . 11)
                                                              ("i64_field" . 99999999999)
                                                              ("true_field" . t)
                                                              ("false_field" . nil)
                                                              ("void_field" . :void)
                                                              ("array_field" . #(1 2 3))
                                                              ("decimal_field" . #$1.2))
                                                    :persistent t
                                                    :priority 8
                                                    :correlation-id "r-1"
                                                    :reply-to "a.sender"
                                                    :expiration "2000"
                                                    :message-id "m-1"
                                                    :timestamp ,now
                                                    :type "dog-or-cat?"
                                                    :user-id "guest"
                                                    :app-id "cl-bunny.tests"
                                                    :cluster-id "qwe"))
      (bunny:consume :one-shot t))))

=>
#<CL-BUNNY::MESSAGE consumer-tag=amq.ctag--0fCpdj1fdU2oS9JLVqLkQ delivery-tag=1 body=#b"Hello World!" {1008F85963}>
```

Corresponding MongoDB document:

```javascript
{
  "_id":ObjectId("5688fc87e72f458e1e000001"),
  "exchange":"hmm",
  "exchange_type":"direct",
  "timestamp": ISODate("2016-01-03T10:48:39.863Z"),
  "content":[72,101,108,108,111,32,87,111,114,108,100,33],
  "properties":{
    "content_type":"text/plain",
    "content_encoding":"utf-8",
    "headers":[
      {
        "coordinates":[
          {
            "lat":59.349998474121094
          },
          {
            "lng":18.066667
          }
        ]
      },
      {
        "time": ISODate("2015-12-24T23:57:31Z")
      },
      {
        "participants":11
      },
      {
        "i64_field":NumberLong("99999999999")
      },
      {
        "true_field":true
      },
      {
        "false_field":false
      },
      {
        "void_field":null
      },
      {
        "array_field":[
          1,
          2,
          3
        ]
      },
      {
        "decimal_field":1.2
      }
    ],
    "delivery_mode":2,
    "priority":8,
    "correlation_id":"r-1",
    "reply_to":"a.sender",
    "expiration":"2000",
    "message_id":"m-1",
    "timestamp": ISODate("2015-12-24T23:57:31Z"),
    "type":"dog-or-cat?",
    "user_id":"guest",
    "app_id":"cl-bunny.tests",
    "cluster_id":"qwe"
  }
}
```

## Configuration

This plugin can be configured as any other RabbitMQ plugin. It expects its configuration to be available
under `rabbitmq_logs_exchange` application name. Right now it looks only for mongodb related parameter i.e. [`mongodb_pool`](https://github.com/deadtrickster/mongodb-erlang-pool) configuration.

Default configuration:

```erlang
{mongodb_pool,
  {logs_exchange_mongodb_pool,
    [
      {size, 10},
      {max_overflow, 30}
    ],
    [
      {database, <<"rabbimq_logs">>},
      {w_mode, safe}
    ]}
}
```

## License

See LICENSE.md
