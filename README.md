# RabbitMQ Logs Exchange

Saves message to MongoDB before routing. Routes messages transparently using exchange-type specified by `x-exchange-type`

Exchange Type: `x-logs`

## Example

```lisp
(bunny:with-connection ()
  (bunny:with-channel ()
    (let ((x (bunny:exchange.declare "hmm" :type "x-logs"
                                           :arguments '(("x-exchange-type" . "direct"))
                                           :auto-delete t))
          (q (bunny:queue.declare-temp)))
      (bunny:queue.bind q x :routing-key q)
      (bunny:subscribe-sync q)
      (bunny:publish x "Hello World!" :routing-key q :properties '(:message-id "message-id"))
      (bunny:consume :one-shot t))))
      
=> 
#<CL-BUNNY::MESSAGE consumer-tag=amq.ctag--0fCpdj1fdU2oS9JLVqLkQ delivery-tag=1 body=#b"Hello World!" {1008F85963}>
```

Corresponding MongoDB document:

```javascript
{
  "_id" : ObjectId("56880cdbe72f45050f000006"),
  "exchange" : "hmm",
  "exchange_type" : "direct",
  "content" : [ 72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100, 33 ],
  "message_id" : "message-id"
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
