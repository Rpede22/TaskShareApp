type NotifyRequest {
    topic : string
    message : undefined
}

interface SubscriberInterface {
    RequestResponse:
        notify( NotifyRequest )( void )
}