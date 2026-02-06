from database import Database
from console import Console
from string_utils import StringUtils
from ..Broker.broker import BrokerAPI
from ..Broker.subscriberInterface import SubscriberInterface

type CreateTaskListRequest {
    userID : int
    groupID : int
    taskListName : string
}

type CreateTaskListResponse {
    taskListID : int
}

type DeleteTaskListRequest {
    userID : int
    groupID : int
    taskListID : int
}

type DeleteTaskListResponse : void


type DisplayTaskListsRequest {
    userID : int
    groupID : int
}

type TaskList {
    // used in: DisplayTaskListsResponse
    taskListID : int
    taskListName : string
}

type DisplayTaskListsResponse {
    taskLists* : TaskList
}

type CreateTaskRequest {
    userID : int
    groupID : int
    taskListID : int
    taskName : string
    description : string
}

type TaskItem {
    // used in: CreateTaskResponse, DisplayTaskListResponse
    taskID : int
    taskName : string
    description : string
    status: string( enum( [ "completed", "pending" ] ) )
}

type CreateTaskResponse : TaskItem

type DeleteTaskRequest {
    userID : int
    groupID : int
    taskListID : int
    taskID : int
}

type DeleteTaskResponse : void

type DisplayTaskListRequest {
    userID : int
    groupID : int
    taskListID : int
}

type DisplayTaskListResponse {
    tasks* : TaskItem
}

/*
// for testing purposes
type InsertViewRequest {
    userID : int
    groupID : int
}
*/

interface TaskAPI {
    RequestResponse:
        createTaskList( CreateTaskListRequest )( CreateTaskListResponse ) throws ForbiddenAction,
        deleteTaskList( DeleteTaskListRequest )( DeleteTaskListResponse ) throws ForbiddenAction TaskListNotFound,
        displayTaskLists( DisplayTaskListsRequest )( DisplayTaskListsResponse ) throws ForbiddenAction,
        createTask( CreateTaskRequest )( CreateTaskResponse ) throws ForbiddenAction TaskListNotFound,
        deleteTask( DeleteTaskRequest )( DeleteTaskResponse ) throws ForbiddenAction TaskListNotFound,
        displayTaskList( DisplayTaskListRequest )( DisplayTaskListResponse ) throws ForbiddenAction TaskListNotFound,
        // insertView( InsertViewRequest )( void ) // for testing purposes
}

constants {
    /* We use constants so that we can pass the input port
    information into the binding parameter of the subscribe
    call to the broker.
    */
    INPUT_PORT_LOCATION = "socket://localhost:8081",
    INPUT_PORT_PROTOCOL = "sodep"
}

service Task {
    execution: sequential

    embed Database as database

    //> for debug purposes
    embed Console as console 
    embed StringUtils as stringutils
    //<

    outputPort broker {
        location: "socket://localhost:8000"
        protocol: sodep
        interfaces: BrokerAPI
    }

    inputPort ip {
        location: INPUT_PORT_LOCATION
        protocol: INPUT_PORT_PROTOCOL
        interfaces: TaskAPI, SubscriberInterface
    }

    init {
        // database configuration
        config.connection << {
        username = ""
        password = ""
        host = ""
        database = "file:task.sqlite"
        driver = "sqlite"
        }
        // initialise the table
        connect@database( config.connection )()
        update@database( "CREATE TABLE IF NOT EXISTS taskList
        (taskListID INTEGER PRIMARY KEY AUTOINCREMENT, taskListName TEXT, groupID INTEGER);" )()

        update@database( "CREATE TABLE IF NOT EXISTS task
        (taskID INTEGER PRIMARY KEY AUTOINCREMENT, taskName TEXT, description TEXT, status TEXT, taskListID INTEGER);" )()

        /* This table is a view of the groupUser table of the Group service.
        */
        update@database( "CREATE TABLE IF NOT EXISTS groupUserView
                        ( groupID INTEGER, userID INTEGER,
                        UNIQUE( groupID, userID ) )" )()
        close@database()()

        /* subscribe to groupCreated and groupDeleted 
        such that the Task service has an up to date view
        on which users belong to which groups.
        */
        ip.location = INPUT_PORT_LOCATION
        ip.protocol << INPUT_PORT_PROTOCOL

        subscribe@broker( { topic = "groupCreated" binding -> ip } )()
        subscribe@broker( { topic = "groupDeleted" binding -> ip } )()
        subscribe@broker( { topic = "groupAddedUser" binding -> ip } )()
        subscribe@broker( { topic = "groupRemovedUser" binding -> ip } )()
    }

    define checkUserInGroupProcedure {
        /* checks that the given user is in the given group

        assumed parameters: request.groupID, request.userID, errMessage
        used in: createTaskList, displayTaskLists
        */
        query@database(
            "SELECT * FROM groupUserView
             WHERE groupID = :groupID AND userID = :userID" {
                groupID = request.groupID
                userID = request.userID
        } )( result )

        if ( #result.row == 0 ) {
            close@database()()
            with( errorMessage ) {
                .message = errMessage
            }
            throw( ForbiddenAction, errorMessage )
        }
    }

    define checkGroupHasTaskListProcedure {
        /* checks that the given group has the given taskList 

        assumed parameters: request.groupID, request.userID, request.taskListID errMessage
        used in: createTask
        */
            query@database(
                "SELECT *
                 FROM taskList
                 INNER JOIN groupUserView ON taskList.groupID = groupUserView.groupID
                 WHERE taskList.taskListID = :taskListID AND groupUserView.groupID = :groupID AND groupUserView.userID = :userID" {
                    taskListID = request.taskListID
                    groupID = request.groupID
                    userID = request.userID
            } )( result )
            if ( #result.row == 0 ) {
                close@database()()
                with( errorMessage ) {
                    .message = errMessage
                }
                throw( TaskListNotFound, errorMessage )
            }
    }

    main {
        [ createTaskList( request )( response ) {
            connect@database( config.connection )()

            // check that the given user is in the given group
            errMessage = "Tried to create a task list for an incorrect groupID or userID." // is only used if a fault is thrown
            checkUserInGroupProcedure

            // create task list
            query@database(
                "INSERT INTO taskList ( taskListName, groupID )
                VALUES ( :taskListName, :groupID )
                RETURNING taskListID" {
                    taskListName = request.taskListName
                    groupID = request.groupID
            } )( result )

            response << result.row

            close@database()()
        } ]

        [ deleteTaskList( request )( response ) {
            connect@database( config.connection )()

            // check that the given user is in the given group
            errMessage = "Tried to create a task with an incorrect groupID or userID."
            checkUserInGroupProcedure

            // check that the given group is of the given task list
            errMessage = "The task list does not belong to the given group or it does not exist."
            checkGroupHasTaskListProcedure

            update@database(
                "DELETE FROM taskList
                 WHERE taskListID = :taskListID" {
                    taskListID = request.taskListID
                    // note that we do not need groupID, 'cause we already checked that the task list belongs to the group
            } )( result )

            update@database(
                "DELETE FROM task 
                 WHERE taskListID = :taskListID" {
                    taskListID = request.taskListID
                    // note that we do not need groupID, 'cause we already checked that the task list belongs to the group
            } )( result )

            close@database()()
        } ]

        [ displayTaskLists( request )( response ) {
            connect@database( config.connection )()

            // check that the given user is in the given group
            errMessage = "Tried to display the task lists of an incorrect groupID or userID." // is only used if a fault is thrown
            checkUserInGroupProcedure

            // display task lists
            query@database(
                "SELECT taskListID, taskListName
                 FROM taskList
                 INNER JOIN groupUserView ON taskList.groupID = groupUserView.groupID
                 WHERE groupUserView.groupID = :groupID AND groupUserView.userID = :userID" {
                    groupID = request.groupID
                    userID = request.userID
            } )( result )

            response = void
            response.taskLists << result.row

            close@database()()
        } ]
        
        [ createTask( request )( response ) {
            connect@database( config.connection )()

            // check that the given user is in the given group
            errMessage = "Tried to create a task with an incorrect groupID or userID."
            checkUserInGroupProcedure

            // check that the given group is of the given task list
            errMessage = "The task list does not belong to the given group or it does not exist."
            checkGroupHasTaskListProcedure

            // add the task to the task list
            query@database(
                "INSERT INTO task ( taskName, description, status, taskListID )
                 VALUES ( :taskName, :description, 'pending', :taskListID )
                 RETURNING taskID, taskName, description, status" {
                    taskName = request.taskName
                    description = request.description
                    taskListID = request.taskListID
            } )( result )

            close@database()()

            response << result.row
        } ]

        [ deleteTask( request )( response ) {
            connect@database( config.connection )()

            // check that the given user is in the given group
            errMessage = "Tried to create a task with an incorrect groupID or userID."
            checkUserInGroupProcedure

            // check that the given group is of the given task list
            errMessage = "The task list does not belong to the given group or it does not exist."
            checkGroupHasTaskListProcedure

            // delete task from list of tasks
            query@database(
                "DELETE FROM task
                 WHERE taskID = :taskID AND taskListID = :taskListID
                 RETURNING *" {
                    taskID = request.taskID
                    taskListID = request.taskListID
            } )( result )

            if ( #result.row == 0 ) {
                // tried to delete an invalid taskID
                close@database()()
                with( errorMessage ) {
                    .message = "Tried to delete a task from another task list or it does not exist" 
                }
                throw( ForbiddenAction, errorMessage )
            }

            close@database()()
        } ]

        [ displayTaskList( request )( response ) {
            connect@database( config.connection )()

            // check that the given user is in the given group
            errMessage = "Tried to create a task with an incorrect groupID or userID."
            checkUserInGroupProcedure

            // check that the given group is of the given task list
            errMessage = "The task list does not belong to the given group or it does not exist."
            checkGroupHasTaskListProcedure

            query@database(
                "SELECT taskID, taskName, description, status FROM task
                 WHERE taskListID = :taskListID" {
                    taskListID = request.taskListID
            } )( result )

            response = void
            response.tasks << result.row

            close@database()()
        } ]

        /*
        // for testing purposes
        [ insertView( request )() {
            connect@database( config.connection )()
            update@database(
                "INSERT INTO groupUserView ( groupID, userID )
                 VALUES ( :groupID, :userID )" {
                    groupID = request.groupID
                    userID = request.userID
            } )( result )

            close@database()()
        } ]
        */

        [ notify( request )() {
            nullProcess
        } ] {
            connect@database( config.connection )()

            if ( request.topic == "groupCreated" ) {
                /* updates the view of the Group service's groupUser
                table when a user creates a new group.
                */
                update@database(
                    "INSERT INTO groupUserView ( groupID, userID )
                    VALUES ( :groupID, :userID )" {
                        groupID = request.message.groupID
                        userID = request.message.userID
                } )( result )

            } else if ( request.topic == "groupDeleted" ) {
                /* updates the view of the Group service's groupUser
                table when a user deletes a group.
                all entries with the deleted groupID are deleted.
                */
                update@database(
                    "DELETE FROM groupUserView
                     WHERE groupID = :groupID" {
                        groupID = request.message.groupID
                } )( result )

                /* the group's task lists and associated tasks
                should be deleted as well.
                this will not be implemented.
                */

            } else if ( request.topic == "groupAddedUser" ) {
                /* updates the view of the Group service's groupUser
                table when a user is added to a group.
                */
                update@database(
                    "INSERT INTO groupUserView ( groupID, userID )
                    VALUES ( :groupID, :userID )" {
                        groupID = request.message.groupID
                        userID = request.message.userID
                } )( result )

            } else if ( request.topic == "groupRemovedUser" ) {
                /* updates the view of the Group service's groupUser
                table when a user is removed from a group.
                */
                update@database(
                    "DELETE FROM groupUserView
                     WHERE groupID = :groupID AND userID = :userID" {
                        groupID = request.message.groupID
                        userID = request.message.userID
                } )( result )

                /* if the user is the last user in the group, then
                the task lists and their associated tasks should be
                deleted as well.
                this will not be implemented.
                */
            }

            close@database()()
        }
    }
}


