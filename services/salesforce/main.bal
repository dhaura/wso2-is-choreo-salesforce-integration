import ballerina/http;
import ballerina/log;
import ballerina/io;
import ballerinax/scim;
import ballerinax/salesforce;

// Create Salesforce client configuration by reading from environment.
configurable string salesforceAppClientId = ?;
configurable string salesforceAppClientSecret = ?;
configurable string salesforceAppRefreshToken = ?;
configurable string salesforceAppRefreshUrl = ?;
configurable string salesforceAppBaseUrl = ?;

// Using direct-token config for client configuration
salesforce:ConnectionConfig sfConfig = {
    baseUrl: salesforceAppBaseUrl,
    auth: {
        clientId: salesforceAppClientId,
        clientSecret: salesforceAppClientSecret,
        refreshToken: salesforceAppRefreshToken,
        refreshUrl: salesforceAppRefreshUrl
    }
};

listener http:Listener httpListener = new(8090);

service /scim2 on httpListener {
    resource function post Users(http:Caller caller, http:Request request) returns error? {
        
        salesforce:Client baseClient = check new (sfConfig);

        json jsonPayload = check request.getJsonPayload();
        scim:UserResource userResource = check jsonPayload.cloneWithType(scim:UserResource);
        string[] emails = userResource?.emails ?: [];
        string email = emails.pop();
        string firstName = userResource?.name?.givenName ?: "";
        string lastName = userResource?.name?.familyName ?: "";

        log:printInfo("Salesforce Provisoning User Email : " + email);
        io:println("Salesforce Provisoning User First Name : " + firstName);
        io:println("Salesforce Provisoning User Last Name : " + lastName);

        record {} leadRecord = {
            "Company": string `${firstName}_${lastName}`,
            "Email": email,
            "FirstName": firstName,
            "LastName": lastName
        };

        salesforce:CreationResponse|error res = baseClient->create("Lead", leadRecord);

        // Send a response back.
        http:Response res1 = new;
        if (res is salesforce:CreationResponse) {
            log:printInfo("Lead Created Successfully. Lead ID : " + res.id);
            res1.statusCode = 200;
            res1.setPayload("Created the lead: " + res.toString());
        } else {
            log:printError(msg = res.message());
            res1.statusCode = 400;
            res1.setPayload("Lead creation failed: " + res.toString());
        }
        check caller->respond(res1);
    }
}
