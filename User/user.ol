from database import Database
from console import Console
from string_utils import StringUtils
from ..Broker.broker import BrokerAPI

type DeleteUserRequest{
    userID : int
}
type DeleteUserResponse : void
type CreateUserRequest{
    userName : string
    password : string
}
type CreateUserResponse{
    userID : int 
}

type LoginRequest{
    userName: string
    password: string
}
type LoginResponse{
    userID : int
}

// type logoutRequest{
//     userID : string
// }

// type logoutReponse{
//     succes : bool
// }


interface UserAPI {
    RequestResponse: 
        deleteUser(DeleteUserRequest)(DeleteUserResponse) throws UserNotFound,
        createUser(CreateUserRequest)(CreateUserResponse) throws UsernameTaken,
        login(LoginRequest)(LoginResponse) throws UserNotFound,
        //logout()()
}

service User {
    execution : sequential

    embed Console as console
    embed StringUtils as stringutils
    embed Database as database

    inputPort input {
        location: "socket://localhost:8082"
        protocol: sodep 
        interfaces : UserAPI 
    }

    outputPort broker {
        location: "socket://localhost:8000"
        protocol: sodep
        interfaces: BrokerAPI
    }

    init {
        // database configuration
        config.connection << {
        username = ""
        password = ""
        host = ""
        database = "file:user.sqlite"
        driver = "sqlite"
        }
        // initialise the table
        connect@database( config.connection )()
        update@database( "CREATE TABLE IF NOT EXISTS user
        (userID INTEGER PRIMARY KEY AUTOINCREMENT, userName TEXT UNIQUE, password TEXT);" )()
        close@database()()
    }

    main{
        [deleteUser(request)(response){
            connect@database( config.connection )()
            query@database( "DELETE FROM user WHERE userID == :userID RETURNING userID;" { 
                userID = request.userID
            } )( result )

            if ( #result.row == 0 ) {
                // no such user
                close@database()()
                with( errorMessage ) {
                    .message = "Tried to delete non-existent user"
                } 
                throw ( UserNotFound, errorMessage )
            } // else: delete success
            close@database()()

            /* publishes the userID to subscribers ( the Group service ) of
            the topic "userDeleted" such that they may keep an updated view
            on the users in the system.
            */
            publish@broker( { topic = "userDeleted" message -> result.row } )()

        }]

        [createUser(request)(response){
            connect@database( config.connection )()

            /* Ensure that an error is thrown if
            the userName already exists in the database.

            The database is constrained, but we implement
            fault handling like this so we do not have
            to trigger and catch the SQLException.
            */
            query@database(
                "SELECT * FROM user
                 WHERE userName = :userName" {
                    userName = request.userName
            } )( result )
            if ( #result.row != 0 ) {
                // userName is already taken
                with( errorMessage ) {
                    .message = "Username is already taken"
                }
                throw( UsernameTaken, errorMessage )
            }
            //<

            /* userName does not exist yet, so create
            a new user.
            */
            query@database( 
            "INSERT INTO user (userName, password) 
                VALUES ( :userName, :password)
                RETURNING userID" {
                userName = request.userName
                password = request.password
            })( result )
            close@database()()
            response << result.row
            //<

            /* publishes the userID to subscribers ( the Group service ) of
            the topic "userCreated" such that they may keep an updated view
            on the users in the system.
            */
            publish@broker( { topic = "userCreated" message -> response } )()
        }]

        [login(request)(response){
            query << "SELECT userID FROM user  
                    WHERE userName == :userName AND password == :password;" {
                    userName = request.userName
                    password = request.password
                    }
            connect@database( config.connection )()
            query@database( query )( result )
            close@database()()
            if ( #result.row == 0 ) {
                with( errorMessage ) {
                    .message = "Wrong username or password"
                }
                throw( UserNotFound, errorMessage )
            }
            response << result.row
        }]
        // [logout(request)(response){

        // }]
    }
}
