import ballerina/http;

type User record {
    string username;
    string firstName;
    string lastName;
};

service /scim/users on new http:Listener(8090) {
    resource function post .(User user) returns User {
        
        return user;
    }
}
