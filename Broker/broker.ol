/* This is a generic broker implementation except
subscribers cannot unsubscribe and concurrency is unsupported.
The unsubscribe feature is not needed for now,
and may be implemented later on demand.
*/

from .subscriberInterface import SubscriberInterface
from types.Binding import Binding

type PublishRequest {
    topic : string
    message : undefined
}

type SubscribeRequest {
    topic : string
    binding : Binding
}

interface BrokerAPI {
    RequestResponse:
        publish( PublishRequest )( void ),
        subscribe( SubscribeRequest )( void /*unsubscribeKey*/ )
        // unsubscribe // unsubscribe is left unimplemented for now
        // topics // not needed for now
}

service Broker {
    /* execution is sequential so we do not
    need to worry about synchronizing
    */
    execution: sequential

    inputPort ip {
        location: "socket://localhost:8000"
        protocol: sodep
        interfaces: BrokerAPI
    }

    outputPort output { // subscriber port
        interfaces: SubscriberInterface
    }

    main {
        [ publish( request )() {
            for ( subscriber in global.topics.( request.topic ) ) {
                output.location = subscriber.location
                output.protocol << subscriber.protocol
                notify@output( request )()
            }
        } ]

        [ subscribe( request )() {
            i = #global.topics.( request.topic )
            global.topics.( request.topic )[i] << request.binding
        } ]
    }
}
