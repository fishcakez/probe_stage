# ProbeStage

Proof of concept to probe GenStage piplelines to discover bottlneck using
tracing.

## Usage

Subscription must be setup after ProbeStage is started and tracing started
```elixir
ProbeStage.start_link()
ProbeStage.trace(consumer)
ProbeStage.trace(producer)
GenStage.sync_subscribe(consumer, [to: producer])
```

Or setup tracing using supervisor
```elixir
ProbeStage.start_link()
ProbeStage.trace(supervisor, [:set_on_spawn])
```

## Output

ProbeStage will print subscription information every 5 seconds:

Example:
```
Subscription: #Reference<0.0.3.81> consumer
Mean Delay:   187 microseconds
Mean Batch:   10
Events:       500

Subscription: #Reference<0.0.3.81> producer
Mean Delay:   145 microseconds
Mean Batch:   10
Events:       500
```

Subscription shows the subscription reference and the part in the subscription
that took the measurements.

Mean Delay is the time between the ask message is sent/received and the events
message is received/sent for consumers/producers divided by number of events.

The different parts of the delay are:

Consumer sends ask to Producer
Delay while ask in Producers message queue
Producer receives ask
Delay while Producer creates events
Producer sends events to Consumer
Delay while events in Consumers message queue
Consumer receives events

Therefore a consumer delay contains the producer delay plus the message queue
delays for both processes. A future version should be able to differentiate
all the delays. Until then it might be difficult to identify the cause of
bottlenecks.

Mean Batch is the mean number of events per event message.

Events shows the total number of events.

## Example Configuration
```elixir
# Interval between reports in milliseconds
config :probe_stage, :interval, 5000
# Time unit of delays
config :probe_stage, :time_unit, :microseconds
```
