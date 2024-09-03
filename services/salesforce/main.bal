import ballerina/http;
import ballerina/log;
import ballerina/io;
import ballerinax/scim;

type User record {
    string username;
    string firstName;
    string lastName;
};


listener http:Listener httpListener = new(8090);

service /scim2 on httpListener {
    resource function post Users(http:Request request) returns error? {
        
        json jsonPayload = check request.getJsonPayload();
        scim:UserResource userResource = check jsonPayload.cloneWithType(scim:UserResource);
        string[] emails = userResource?.emails ?: [];
        string email = emails.pop();
        string firstName = userResource?.name?.givenName ?: "";
        string lastName = userResource?.name?.familyName ?: "";

        log:printInfo("Salesforce Provisoning User Email : " + email);
        io:println("Salesforce Provisoning User First Name : " + firstName);
        io:println("Salesforce Provisoning User Last Name : " + lastName);
    }
}
