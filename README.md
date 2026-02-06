# HOW TO SETUP TASKSHARE PROTOTYPE

#### SETUP RECOMMENDATION  
In order to setup the TaskShare system, open separate terminals in the path of  
each jolie file. Then run the files in each terminal in the following order:   
> jolie broker.ol  
  jolie user.ol  
  jolie group.ol  
  jolie task.ol  
  jolie gateway.ol
>
  
#### SETUP WARNINGS  
The Broker service must be online before the other services are brought online.  
This is due to the other services subscribing to topics from the Broker service  
when they are initialized.  
  
Disconnecting a service that was already connected to the Broker will cause it to  
resubscribe to the same topics once reconnected resulting in duplicate   
subscriptions. Therefore, do not disconnect a service.  
  
If you happen to disconnect a service that is not the API Gateway, then disconnect  
all services and set them up again following the setup recommendation.  
  
All services listen on fixed ports, so make sure that they are unoccupied when  
setting up the TaskShare system. The following ports are occupied by the system:
> Broker -> 8000  
  User -> 8082  
  Group -> 8080  
  Task -> 8081  
  Gateway -> 8090
>

# Introduction
TaskShare is a system that allow users to create and join groups wherein the users  
share and manage task lists and their associated tasks with other group members.  
  
This TaskShare prototype provides no UI, but provides a REST API for using the  
system.  
The base url for sending requests is http://localhost:8090. The other ports that are  
occupied by the system should not be accessed directly.
   
In the examples that demonstrate how to interact with the endpoints, the assumed  
operating system is Windows 10 or a newer version and the assumed CLI is the  
Windows Command Prompt or Powershell.  
Furthermore, the examples use curl and split the request into several lines for  
clarity. In practice, the entire command should be written in one line.

# User
This section details the operations offered by the User management service that are  
exposed to the REST API.

## Register User 
Usernames are unique across the system.  
  
Registering a user creates a new user in the system with a unique userID.  
The userID is returned to the client when he registers a user, and is used to access  
endpoints that are related to this particular userID.  
  
To register a user, send a POST request to /register.  
In the request payload, specify the username and password for the new user.
  
An example curl command for registering a user:
>curl.exe  
-X POST  
-H "Content-Type: application/json"  
-d '{\\"userName\\": \\"Bob\\", \\"password\\": \\"1234\\"}'  
http://localhost:8090/register
>

## Delete User
Deleting a user removes the user from the system completely.  
  
To delete a user, send a DELETE request to /users/{userID}.   
In the url of the request, specify the userID to be deleted.

An example curl command for deleting a user:  
>curl.exe  
-X DELETE  
http://localhost:8090/users/1  
>

#### WARNING ON DELETING A USER:  
When a user is deleted, the user is completely removed from the User management  
service, but the groups of which the user was a member are still associated with this  
deleted userID in the Group management service.  
The deleted user will not be able to perform operations offered by the Group  
management service, since Group tracks the users existing in the system.  
But the deleted user will be able to perform operations offered by the Task  
management service, since it tracks associations between users and groups, but it  
does not track the current existing users in the system.  
  
Following this, if a user is deleted and he is the last member of a group, then the  
task lists and tasks of that group should be deleted as well, but they are not.  
This both clutters up the databases with dead data and enable accessing of data  
that should not be possible to access.

Thus, deleting a user who is already a member of some group will leave the system  
in an unstable state.  
This is a flaw of the system that is to be fixed in a future iteration.

## Login
Logging into a system returns the userID of the logged in user. The client uses this  
userID to access the API endpoints to which it is related.  
  
To login, send a POST request to /login.  
In the request payload specify the username and password of the user.  
  
An example curl command for logging in:
>curl.exe  
-X POST  
-H "Content-Type: application/json"  
-d '{\\"userName\\": \\"Bob\\", \\"password\\": \\"1234\\"}'  
http://localhost:8090/login
>

# Group
This section details the operations offered by the Group management service that  
are exposed to the REST API.

## Create Group
Group names are not unique across the system.  
  
Creating a new group in the system also creates an association between the group  
and the user who created the group.  
When the client succesfully creates a group, its groupID is returned. This groupID is  
used to access the API endpoints to which the group is related.  
  
To create a group send a POST request to /users/{userID}/groups.  
In the url, specify the userID of the user who creates the group to whom the  
group will be associated.  
In the request payload, specify the name for the group.  
  
An example curl command for creating a group:
>curl.exe  
-X POST  
-H "Content-Type: application/json"  
-d '{\\"groupName\\": \\"Personal\\"}'  
http://localhost:8090/users/1/groups
>

## Delete Group
Deleting a group removes the group and its associations from the  system   
completely.  
  
Users can only delete groups of which they are a member.

To delete a group send a DELETE request to /users/{userID}/groups/{groupID}.  
In the url, specify the userID of the user who wants to delete the group and the  
groupID of the group to be deleted.

An example curl command for deleting a group:
>curl.exe  
-X DELETE  
http://localhost:8090/users/1/groups/1
>

#### WARNING ON DELETING A GROUP
When a group is deleted, all of its associations to users in that group are deleted as  
well from the Group management service.  
But the task lists and tasks associated with the group are not deleted from the Task  
management service.  
These task lists and their tasks cannot, howevever, be accessed, since the Task  
management service keeps track of the users' associations to groups.  
But the task lists and their tasks are not removed from the system, cluttering up  
the database with dead data.

Thus, deleting a group with some task list will leave the system in an unstable state.  
This is a flaw of the system that is to be fixed in a future iteration.

## Add User to Group
Adding a user to a group in the system creates an association between the group  
and the user in the system.  

When a user is added to a group, its groupID along with the users userID are  
returned.

To add a user to a group send a POST request to /groups/{groupID}/members.  
In the url, specify the groupID of the group to which the user is to be added.  
In the request payload, specify the userID of the user to add to the group.  
  
An example curl command for adding a user to a group:
>curl.exe  
-X POST  
-H "Content-Type: application/json"  
-d '{\\"userID\\": 1}'  
http://localhost:8090/groups/1/members
>

## Remove User From Group
Removing a user from a group in the system removes the association between the  
group and the user.  

When a user is removed from a group, its groupID along with the users userID are  
returned.
   
To remove a user from a group, send a DELETE request to  
/groups/{groupID}/members.  
In the url, specify the groupID of the group from which the user is to be deleted.  
In the request payload, specify the userID of the user to remove from the group.  
  
An example curl command for removing a user from a group:
>curl.exe  
-X DELETE  
-H "Content-Type: application/json"  
-d '{\\"userID\\": 1}'  
http://localhost:8090/groups/1/members
>
  
#### WARNING ON REMOVING A USER FROM A GROUP
If a user is the last member of a group and he is removed, then the task lists and  
their associated tasks of the group should be removed as well.  
They are not removed in the Task management service, but they cannot be accessed  
anymore, since the Task management service keeps track of the users' associations  
to groups. The system is thus cluttered up with dead data.

Removing the last user from a group will leave the system in an unstable state.  
This is a flaw of the system that is to be fixed in a future iteration.

## Display Groups
Displaying the groups of a specified user returns the groupIDs and their associated  
group names for each group of which the user is a member.

To display the groups of a user, send a GET request to /users/{userID}/groups.  
In the url, specify the userID of the user whose associated groups are to be  
retrieved.

An example curl command for displaying the groups of a user:
>curl.exe  
http://localhost:8090/users/1/groups
>


# Task
This section details the operations offered by the Task management service that  
are exposed to the REST API.

## Create Task List
Creating a task list creates an association between the task list and the group to  
which it belongs. Every member of the group can access its task lists.

When a task list is created, its taskListID is returned in the response body.

Only a member of a group can create a task list for that group.

To create a task list for a group, send a POST request to  
/users/{userID}/groups/{groupID}/taskLists.  
In the url specify the userID of the user creating the task list and the groupID of the  
group for which the user is creating the task list.

An example of a curl command for creating a task list for a group of a user:
>curl.exe  
-X POST  
-H "Content-Type: application/json"  
-d '{\\"taskListName\\": \\"Chores\\"}'  
http://localhost:8090/users/1/groups/1/taskLists
>

## Delete Task List
Deleting a task list deletes the association between the task list and the group to  
which it belonged. 

Only a member of a group can delete a task list of that group.

To delete a task list of a group, send a DELETE request to  
/users/{userID}/groups/{groupID}/taskLists/{taskListID}.  
In the url, specify the userID of the user deleting the task list and the groupID of the  
group of which the user is deleting the task list.

An example of a curl command for deleting a task list of a group of a user:
>curl.exe  
-X DELETE  
http://localhost:8090/users/1/groups/1/taskLists/1
>

## Create Task
When a task is created, the task id, task name, description, and status are returned  
in the response body.

To create a task in a task list, send POST request to  
/users/{userID}/groups/{groupID}/taskLists/{taskListID}/tasks.  
In the url, specify the userID of the user creating the task, the groupID of the group  
for which the task is created, and the taskListID of the task list in which the task is  
created.  
In the request payload, specify the task name and the description of the task.
 
An example of a curl command for creating a task in a task list:
>curl.exe  
-X POST  
-H "Content-Type: application/json"  
-d '{\\"taskName\\": \\"Dishes\\", \\"description\\": \\"do all the dishes\\"}'  
http://localhost:8090/users/1/groups/1/taskLists/1/tasks
>

## Delete Task

To delete a task from a task list, send a DELETE request to  
/users/{userID}/groups/{groupID}/taskLists/{taskListID}/tasks/{taskID}.  

An example of a curl command for deleting a task from a task list:
>curl.exe  
http://localhost:8090/users/1/groups/1/taskLists/1/tasks/1
>

## Update Task
This operation is yet to be implemented in the prototype, thus it cannot be used.  
This operation should allow a user to update any attributes of a task except for its  
ids.

## Display Task Lists
Displaying the task lists of a group returns the task list ids and their associated task  
names for each task list belonging to the group.

To display the task lists of a group, send a GET request to  
/users/{userID}/groups/{groupID}/taskLists  
In the url, specify the userID and the groupID of the user who wants to display the  
task lists of the group that he specified of which he is a member.

An example curl command for displaying the task lists of a group:
>curl.exe  
http://localhost:8090/users/1/groups/1/taskLists
>

## Display Task List
Displaying the tasks of a task list returns the task id, task name, description, and status in the response body.

To display the tasks of a task list, send a GET request to  
/users/{userID}/groups/{groupID}/taskLists/{taskListID}/tasks.

An example curl command for displaying the tasks of a task list:
>curl.exe  
http://localhost:8090/users/1/groups/1/taskLists/1/tasks
>