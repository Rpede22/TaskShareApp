from database import Database
from console import Console
from string_utils import StringUtils
from ..Broker.subscriberInterface import SubscriberInterface
from ..Broker.broker import BrokerAPI

type CreateGroupRequest { 
    groupName : string
    userID : int
}

type CreateGroupResponse {
    groupID : int
} // make it return the created group id for the http response payload

type DeleteGroupRequest {
    groupID : int
    userID : int
}

type DeleteGroupResponse : void

type DisplayGroupsRequest {
    userID : int
}

type DisplayGroupsResponse {
    groups* : undefined
}

type AddToGroupRequest {
    groupID : int
    userID : int
}

type AddToGroupResponse {
    groupID : int
    userID : int
} // make it return the groupID and userID for the http response payload

type RemoveFromGroupRequest {
    groupID : int
    userID : int
}

type RemoveFromGroupResponse {
    groupID : int
    userID : int
} // make it return the groupID and userID for the http response payload


constants {
    INPUT_PORT_LOCATION = "socket://localhost:8080",
    INPUT_PORT_PROTOCOL = "sodep"
}

interface GroupAPI {
    RequestResponse:
        createGroup( CreateGroupRequest )( CreateGroupResponse ) throws UserNotFound,
        deleteGroup( DeleteGroupRequest )( DeleteGroupResponse ) throws UserNotFound GroupNotFound ForbiddenAction,
        displayGroups( DisplayGroupsRequest )( DisplayGroupsResponse ) throws UserNotFound,
        addToGroup( AddToGroupRequest )( AddToGroupResponse ) throws UserNotFound GroupNotFound,
        removeFromGroup( RemoveFromGroupRequest )( RemoveFromGroupResponse ) throws UserNotFound GroupNotFound
}

service Group {
    execution : sequential

    embed Database as database

    //> for debug purposes
    embed Console as console 
    embed StringUtils as stringutils
    //<

    inputPort ip {
        location: INPUT_PORT_LOCATION 
        protocol: INPUT_PORT_PROTOCOL 
        interfaces: GroupAPI, SubscriberInterface
    }

    outputPort broker {
        location: "socket://localhost:8000"
        protocol: sodep
        interfaces: BrokerAPI
    }

    init {
        /* setup the database.
        */
        config.connection << {
            username = ""
            password = ""
            host = ""
            database = "file:group.sqlite"
            driver = "sqlite"
        }
        connect@database( config.connection )()
        update@database(
            "CREATE TABLE IF NOT EXISTS groupInfo
            ( groupID INTEGER PRIMARY KEY AUTOINCREMENT, groupName TEXT )"
        )()
        update@database(
            "CREATE TABLE IF NOT EXISTS groupUser
            ( groupID INTEGER, userID INTEGER,
            FOREIGN KEY( groupID ) REFERENCES groupInfo( groupID ) ON DELETE CASCADE,
            UNIQUE( groupID, userID ) )"
        )()

        /* a view of the userIDs managed by the User service.
        */
        update@database(
            "CREATE TABLE IF NOT EXISTS userView
            ( userID INTEGER PRIMARY KEY )"
        )()
        close@database()()

        /* subscribe to userCreated and userDeleted
        such that the Group service has an up to date view
        on the current users in the system.
        */
        ip.location = INPUT_PORT_LOCATION
        ip.protocol << INPUT_PORT_PROTOCOL
        subscribe@broker( { topic = "userCreated" binding -> ip } )()
        subscribe@broker( { topic = "userDeleted" binding -> ip } )()
    }

    define checkUserIdProcedure {
        /* ensures that the provided userID exists in the system.
        
        assumes that parameters request.userID and errMessage exist
        used in: createGroup, deleteGroup, displayGroups
        */
            query@database(
                "SELECT * FROM userView
                 WHERE userID == :userID" {
                    userID = request.userID
            } )( result )
            if ( #result.row == 0 ) {
                // no such user in the system
                close@database()()
                with( errorMessage ) {
                    .message = errMessage
                }
                throw( UserNotFound, errorMessage ) 
            }
    }

    define checkGroupIdProcedure {
        /* ensures that the provided groupID exists in the system.

        assumes that parameters request.groupID and errMessage exist
        used in: deleteGroup
        */
            query@database(
                "SELECT * FROM groupInfo
                 WHERE groupID = :groupID" {
                    groupID = request.groupID
            } )( result )
            if ( #result.row == 0 ) {
                close@database()()
                with( errorMessage ) {
                    .message = errMessage
                }
                throw( GroupNotFound, errorMessage )
            }
    }

    main {
        [ createGroup( request )( response ) {
            /* Creates a group with the given groupName
            for the given userID only if the userID
            belongs to a user in the system.

            Group names are not unique.
            */

            connect@database( config.connection )()
            /* check that the user exists in the system
            */
            errMessage = "Tried to create group for a non-existent user" // is only used if a fault is thrown
            checkUserIdProcedure

            // create group
            query@database(
                "INSERT INTO groupInfo ( groupName )
                 VALUES ( :groupName )
                 RETURNING groupID" {
                    groupName = request.groupName
            } )( result )
            response << result.row

            // put user into group
            query@database(
                "INSERT INTO groupUser ( groupID, userID )
                 VALUES ( :groupID, :userID )
                 RETURNING *" {
                    groupID = result.row.groupID
                    userID = request.userID
            } )( result )
            close@database()()

            /* publishes the deleted groupUser entry to subscribers 
            ( the Task service ) of the topic "groupDeleted" such that
            they may keep an updated view on the groupUser table.
            */
            publish@broker( { topic = "groupCreated" message -> result.row } )()
        } ]

        [ deleteGroup( request )( response ) {
            /* Delete a group with the provided groupID
            only if the provided userID is a user in the group
            and only if the group exists.
            */
            connect@database( config.connection )()

            // check that user exists in the system
            errMessage = "Tried to delete group of a non-existent user" // is only used if a fault is thrown
            checkUserIdProcedure

            // check that the group exists in the system
            errMessage = "Tried to delete non-existent group" // is only used if a fault is thrown
            checkGroupIdProcedure

            /* ensures that entries of users belonging to the group
            are deleted from groupUser as well */
            update@database( "PRAGMA foreign_keys = ON;" )()

            // deletes group
            query@database(
                "DELETE FROM groupInfo
                 WHERE groupID IN (
                    SELECT groupUser.groupID
                    FROM groupUser
                    WHERE groupID = :groupID AND userID = :userID
                 )
                 RETURNING groupID" {
                    groupID = request.groupID
                    userID = request.userID
            } )( result )
            close@database()()

            /* if nothing is deleted then the specified user is not a
            part of the group. the attempted delete is a forbidden action!
            */
            if ( #result.row == 0 ) {
                with( errorMessage ) {
                    .message = "Tried to delete group of which the user is not a member"
                }
                throw( ForbiddenAction, errorMessage )
            }

            /* publishes the deleted groupID to subscribers 
            ( the Task service ) of the topic "groupDeleted" such that
            they may keep an updated view on the groupUser table.
            */
            publish@broker( { topic = "groupDeleted" message -> result.row } )()
        } ]

        [ displayGroups( request )( response ) {
            connect@database( config.connection )()

            // check that user exists in the system
            errMessage = "Tried to display groups of a non-existent user"// is only used if a fault is thrown
            checkUserIdProcedure

            query@database(
                "SELECT groupInfo.groupID, groupInfo.groupName
                FROM groupInfo
                INNER JOIN groupUser ON groupInfo.groupID = groupUser.groupID
                WHERE groupUser.userID = :userID" {
                    userID = request.userID
            } )( result )
            response = void
            response.groups << result.row
            close@database()()
            
        } ]

        [ addToGroup( request )( response ) {
            connect@database( config.connection )()

            // check that user exists in the system
            errMessage = "Tried to add non-existent user to a group" // is only used if a fault is thrown
            checkUserIdProcedure

            // check that the group exists in the system
            errMessage = "Tried to add user to non-existent group" // is only used if a fault is thrown
            checkGroupIdProcedure

            println@console( valueToPrettyString@stringutils( request ) )()

            // add user to group
            query@database(
                "INSERT INTO groupUser ( groupID, userID )
                 VALUES ( :groupID, :userID )
                 RETURNING *" {
                    groupID = request.groupID
                    userID = request.userID
            } )( result )
            close@database()()

            response << result.row


            /* publishes the deleted groupUser entry to subscribers 
            ( the Task service ) of the topic "groupAddedUser" such that
            they may keep an updated view on the groupUser table.
            */
            publish@broker( { topic = "groupAddedUser" message -> response } )()

        } ]

        [ removeFromGroup( request )( response ) {
            connect@database( config.connection )()

            // check that user exists in the system
            errMessage = "Tried to remove non-existent user from a group" // is only used if a fault is thrown
            checkUserIdProcedure

            // check that the group exists in the system
            errMessage = "Tried to add user to non-existent group" // is only used if a fault is thrown
            checkGroupIdProcedure

            // remove the user from the group
            query@database(
                "DELETE FROM groupUser
                 WHERE groupID = :groupID AND userID = :userID
                 RETURNING *" {
                    groupID = request.groupID
                    userID = request.userID
            } )( result )

            response << result.row

            /* ensure that the group is also deleted
            from groupInfo if its last member is removed.
            */
            update@database(
                "DELETE FROM groupInfo
                 WHERE groupID = :groupID AND groupID NOT IN ( SELECT groupID FROM groupUser )" {
                    groupID = request.groupID
            } )( result )
            close@database()()

            /* publishes the deleted groupUser entry to subscribers 
            ( the Task service ) of the topic "groupRemovedUser" such that
            they may keep an updated view on the groupUser table.
            */
            publish@broker( { topic = "groupRemovedUser" message -> response } )()
        } ]

        /*  SubscriberInterface */
        [ notify( request )() {
            nullProcess
        } ] {
            connect@database( config.connection )()

            /* update view of users in the system
            */
            if ( request.topic == "userCreated" ) {
                update@database(
                    "INSERT INTO userView ( userID )
                     VALUES ( :userID )" {
                        userID = request.message.userID
                } )( result )
            } else if ( request.topic == "userDeleted" ) {
                update@database(
                    "DELETE FROM userView
                     WHERE userID = :userID" {
                        userID = request.message.userID
                } )( result )
                /* the deleted user should also be removed from
                its associated groups and the group deleted
                if they were its last member.
                we will not implement this for now.
                */
            }

            close@database()()
        }
    }
}