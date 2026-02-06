from .User.user import UserAPI 
from .Group.group import GroupAPI
from .Task.task import TaskAPI

service Gateway {
    /* Note: I wanted to embed the REST proxies locally,
    but we end up with a duplicate database import error.
    */

    outputPort group {
        location: "socket://localhost:8080"
        protocol: sodep
        interfaces: GroupAPI
    }

    outputPort task {
        location: "socket://localhost:8081"
        protocol: sodep
        interfaces: TaskAPI
    }

    outputPort user {
        location: "socket://localhost:8082"
        protocol: sodep
        interfaces: UserAPI
    }

    inputPort ip {
        location: "socket://localhost:8090"
        protocol: "http" {
            format = "json"
            osc << {
                //> USER REST API 
                login << {
                    template = "/login"
                    method = "POST"
                    statusCodes = 200 // OK
                    statusCodes.TypeMismatch = 400 // Bad Request
                    statusCodes.UserNotFound = 404 // Not Found
                }
                createUser << {
                    template = "/register"
                    method = "POST"
                    statusCodes = 201 // Created
                    statusCodes.TypeMismatch = 400 // Bad Request
                    statusCodes.UsernameTaken = 400 // Bad Request
                    response.headers -> httpResponseHeaders
                }
                deleteUser << {
                    template = "/users/{userID}"
                    method = "DELETE"
                    statusCodes = 204 // No Content 
                    statusCodes.UserNotFound = 404 // Not Found
                }
                //< USER REST API 

                //> GROUP REST API
                displayGroups << {
                    template = "/users/{userID}/groups"
                    method = "GET"
                    statusCodes = 200 // OK
                    statusCodes.UserNotFound = 404 // Not Found
                    statusCodes.TypeMismatch = 400 // Bad Request
                }
                createGroup << {
                    template = "/users/{userID}/groups"
                    method = "POST"
                    statusCodes = 201 // Created
                    statusCodes.TypeMismatch = 400 // Bad Request
                    response.headers -> httpResponseHeaders
                }
                deleteGroup << {
                    template = "/users/{userID}/groups/{groupID}"
                    method = "DELETE"
                    statusCodes = 204 // No Content 
                    statusCodes.ForbiddenAction = 403 // Forbidden
                    statusCodes.UserNotFound = 404 // Not Found
                    statusCodes.GroupNotFound = 404 // Not Found
                    statusCodes.TypeMismatch = 400 // Bad Request
                }
                addToGroup << {
                    template = "/groups/{groupID}/members"
                    method = "POST"
                    statusCodes = 201 // Created
                    statusCodes.UserNotFound = 404 // Not Found
                    statusCodes.GroupNotFound = 404 // Not Found
                    statusCodes.TypeMismatch = 400 // Bad Request
                }
                removeFromGroup << {
                    template = "/groups/{groupID}/members"
                    method = "DELETE"
                    statusCodes = 204 // No Content 
                    statusCodes.UserNotFound = 404 // Not Found
                    statusCodes.GroupNotFound = 404 // Not Found
                    statusCodes.TypeMismatch = 400 // Bad Request
                }
                //< GROUP REST API

                //> TASK REST API
                createTaskList << {
                    template = "/users/{userID}/groups/{groupID}/taskLists"
                    method = "POST"
                    statusCodes = 201 // Created 
                    statusCodes.ForbiddenAction = 403 // Forbidden
                    statusCodes.TypeMismatch = 400 // Bad Request
                }
                deleteTaskList << {
                    template = "/users/{userID}/groups/{groupID}/taskLists/{taskListID}"
                    method = "DELETE"
                    statusCodes = 204 // No Content
                    statusCodes.TaskListNotFound = 404 // Not Found
                    statusCodes.ForbiddenAction = 403 // Forbidden
                    statusCodes.TypeMismatch = 400 // Bad Request
                }
                displayTaskLists << {
                    template = "/users/{userID}/groups/{groupID}/taskLists"
                    method = "GET"
                    statusCodes = 200 // OK 
                    statusCodes.ForbiddenAction = 403 // Forbidden
                    statusCodes.TypeMismatch = 400 // Bad Request
                }
                createTask << {
                    template = "/users/{userID}/groups/{groupID}/taskLists/{taskListID}/tasks"
                    method = "POST"
                    statusCodes = 201 // Created
                    statusCodes.TaskListNotFound = 404 // Not Found
                    statusCodes.ForbiddenAction = 403 // Forbidden
                    statusCodes.TypeMismatch = 400 // Bad Request
                }
                deleteTask << {
                    template = "/users/{userID}/groups/{groupID}/taskLists/{taskListID}/tasks/{taskID}"
                    method = "DELETE"
                    statusCodes = 204 // No Content
                    statusCodes.TaskListNotFound = 404 // Not Found
                    statusCodes.ForbiddenAction = 403 // Forbidden
                    statusCodes.TypeMismatch = 400 // Bad Request
                }
                displayTaskList << {
                    template = "/users/{userID}/groups/{groupID}/taskLists/{taskListID}/tasks"
                    method = "GET"
                    statusCodes = 200 // OK 
                    statusCodes.ForbiddenAction = 403 // Forbidden
                    statusCodes.TaskListNotFound = 404 // Not Found
                    statusCodes.TypeMismatch = 400 // Bad Request
                }
                //< TASK REST API
            }
        }
        aggregates: user, group, task
    }

    main {
        linkIn( l )
    }

}
