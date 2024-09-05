import ballerina/http;
import ballerina/lang.array;
import ballerina/log;
import ballerina/regex;
import ballerinax/salesforce;
import ballerinax/scim;

// Configurable Salesforce client configuration attributes.
configurable string SF_APP_CLIENT_ID = ?;
configurable string SF_APP_CLIENT_SECRET = ?;
configurable string SF_APP_REFRESH_TOKEN = ?;
configurable string SF_APP_REFRESH_TOKEN_URL = ?;
configurable string SF_APP_BASE_URL = ?;

// Configurable authorization configuration attributes.
configurable string USERNAME = "admin";
configurable string PASSWORD = "admin";

// Using direct-token config for client configuration.
salesforce:ConnectionConfig sfConfig = {
    baseUrl: SF_APP_BASE_URL,
    auth: {
        clientId: SF_APP_CLIENT_ID,
        clientSecret: SF_APP_CLIENT_SECRET,
        refreshToken: SF_APP_REFRESH_TOKEN,
        refreshUrl: SF_APP_REFRESH_TOKEN_URL
    }
};

type LeadRecord record {
    string Id;
};

function checkAuth(string authHeader) returns error? {

    if authHeader.startsWith("Basic") {
        string encodedCredentials = authHeader.substring(6);
        string decodedCredentials = check string:fromBytes(check array:fromBase64(encodedCredentials));
        string[] credentials = regex:split(decodedCredentials, ":");

        if credentials.length() == 2 {
            string username = credentials[0];
            string password = credentials[1];

            // Check username and password.
            if (USERNAME == username && PASSWORD == password) {
                return;
            } else {
                return error("Invalid credentials.");
            }
        } else {
            return error("Invalid credentials format.");
        }
    } else {
        return error("Authorization header must be Basic Auth.");
    }
}

isolated function getUsername(string[] filter) returns string? {

    if filter.length() > 0 && filter[0].startsWith("userName Eq ") {
        return filter[0].substring(12);
    } else {
        return null;
    }
}

listener http:Listener httpListener = new (8090);

service /scim2 on httpListener {
    resource function post users(@http:Payload scim:UserResource userResource, @http:Header string authorization, http:Caller caller) returns error? {

        // Check and validate authorization credentials.
        do {
	        _ = check checkAuth(authorization);
        } on fail var e {
        	http:Response response = new;
            response.statusCode = http:STATUS_UNAUTHORIZED;
            response.setJsonPayload({"message": e.message()});
            return check caller->respond(response);
        }

        // Create Salesforce client.
        salesforce:Client baseClient = check new (sfConfig);

        // Extract user info from the SCIM request.
        string email = userResource?.userName ?: "";
        string firstName = userResource?.name?.givenName ?: "";
        string lastName = userResource?.name?.familyName ?: "";

        log:printInfo("Salesforce provisoning user info: {email: " + email +
            ", firstName: " + firstName + ", lastName: " + lastName + "}");

        // Create a Salesforce lead record.
        record {} leadRecord = {
            "Company": string `${firstName}_${lastName}`,
            "Email": email,
            "FirstName": firstName,
            "LastName": lastName
        };

        // Initiate the Salesforce lead creation request.
        salesforce:CreationResponse|error sfResponse = baseClient->create("Lead", leadRecord);

        // Send response back to IS.
        http:Response response = new;
        if (sfResponse is salesforce:CreationResponse) {
            log:printInfo("Lead Created Successfully. Lead ID : " + sfResponse.id);
            response.statusCode = http:STATUS_CREATED;
            response.setJsonPayload(userResource.toJson());
        } else {
            log:printError(msg = sfResponse.message());
            response.statusCode = http:STATUS_BAD_REQUEST;
            response.setJsonPayload({"message": sfResponse.message()});
        }
        return check caller->respond(response);
    }

    resource function get users(@http:Query string[] filter, @http:Header string authorization, http:Caller caller) returns error? {

        do {
	        _ = check checkAuth(authorization);
        } on fail var e {
        	http:Response response = new;
            response.statusCode = http:STATUS_UNAUTHORIZED;
            response.setJsonPayload({"message": e.message()});
            return check caller->respond(response);
        }

        string? userName = getUsername(filter);
        if !(userName is string) {
            http:Response response = new;
            response.statusCode = http:STATUS_BAD_REQUEST;
            response.setJsonPayload({"message": "Invalid filter query"});
            return check caller->respond(response);
        }

        // Create Salesforce client.
        salesforce:Client baseClient = check new (sfConfig);

        log:printInfo("Get user: " + userName);

        // SOQL query to fetch the Lead ID based on the email
        string query = string `SELECT Id FROM Lead WHERE Email = '${userName}'`;

        // Execute the SOQL query with an explicit return type
        stream<LeadRecord, error?> leadRecords = check baseClient->query(query);

        string leadId = "";
        // Iterate over the returned records (if any)
        error? e = leadRecords.forEach(function(LeadRecord leadRecord) {
            leadId = leadRecord.Id;
        });

        http:Response response = new;
        if !(e is error) {
            scim:UserResource userResource = {
                id: leadId
            };
            json scimResponse = {
                "totalResults": 1,
                "startIndex": 1,
                "itemsPerPage": 1,
                "schemas": [
                    "urn:ietf:params:scim:api:messages:2.0:ListResponse"
                ],
                "Resources": [userResource.toJson()]
            };
            log:printInfo("Retreived the lead: " + leadId);
            response.setJsonPayload(scimResponse.toJson());
            response.statusCode = http:STATUS_OK;
        } else {
            log:printError(msg = e.message());
            response.statusCode = http:STATUS_BAD_REQUEST;
            response.setJsonPayload({"message": e.message()});
        }
        return check caller->respond(response);
    }


    resource function delete users/[string leadId](http:Request request, @http:Header string authorization, http:Caller caller) returns error? {
        
        do {
	        _ = check checkAuth(authorization);
        } on fail var e {
        	http:Response response = new;
            response.statusCode = http:STATUS_UNAUTHORIZED;
            response.setJsonPayload({"message": e.message()});
            return check caller->respond(response);
        }

        // Create Salesforce client.
        salesforce:Client baseClient = check new (sfConfig);

        log:printInfo("Delete user: " + leadId);

        error? sfResponse = baseClient->delete("Lead", leadId);

        http:Response response = new;
        if sfResponse is error {
            log:printError(msg = sfResponse.message());
            response.statusCode = http:STATUS_BAD_REQUEST;
            response.setJsonPayload({"message": sfResponse.message()});
        } else {
            log:printInfo("Deleted the lead: " + leadId);
            response.statusCode = http:STATUS_NO_CONTENT;
        }
        return check caller->respond(response);
    }

    resource function put users/[string leadId](http:Request request, @http:Header string authorization, http:Caller caller) returns error? {

        do {
	        _ = check checkAuth(authorization);
        } on fail var e {
        	http:Response response = new;
            response.statusCode = http:STATUS_UNAUTHORIZED;
            response.setJsonPayload({"message": e.message()});
            return check caller->respond(response);
        }

        // Note: This is only a dummy method that does not call salesforce API.

        scim:UserResource userResource = {
            id: leadId,
            userName: "userName"
        };
        json scimResponse = {
            "totalResults": 1,
            "startIndex": 1,
            "itemsPerPage": 1,
            "schemas": [
                "urn:ietf:params:scim:api:messages:2.0:ListResponse"
            ],
            "Resources": [userResource.toJson()]
        };

        http:Response response = new;
        log:printInfo("Updated the lead: " + leadId);
        response.setJsonPayload(scimResponse.toJson());
        response.statusCode = http:STATUS_OK;
        return check caller->respond(response);
    }
}
