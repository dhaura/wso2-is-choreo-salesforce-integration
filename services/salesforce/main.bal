import ballerina/http;
import ballerina/log;

type User record {
    string username;
    string firstName;
    string lastName;
};


listener http:Listener httpListener = new(8090);

service / on httpListener {
    resource function post scim/users (User user) returns User {
        
        log:printInfo("Salesforce Provisoning User : " + user.username);
        return user;
    }
}
