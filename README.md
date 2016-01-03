# RabbitMQ Logs Exchange

Saves message to MongoDB before routing. Routes messages transparently using exchange-type specified by `x-exchange-type`

Exchange Type: `x-logs`

## Example

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
