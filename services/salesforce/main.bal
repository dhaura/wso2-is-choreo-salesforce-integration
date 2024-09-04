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

function checkAuth(string authHeader) returns error? {

    if authHeader.startsWith("Basic ") {
        string encodedCredentials = authHeader.substring(6);
        string decodedCredentials = check string:fromBytes(check array:fromBase64(encodedCredentials));
        string[] credentials = regex:split(decodedCredentials,":");

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

listener http:Listener httpListener = new(8090);

service /scim2 on httpListener {
    resource function post users(http:Caller caller, @http:Payload scim:UserResource userResource, @http:Header string authorization) returns error? {
        
        // Check and validate authorization credentials.
        error|null authError = check checkAuth(authorization);
        if (authError is error) {
            return authError;
        }

        // Create Salesforce client.
        salesforce:Client baseClient = check new (sfConfig);

        // Extract user info from the SCIM request.
        string[] emails = userResource?.emails ?: [];
        string email = emails.pop();
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
        if (sfResponse is salesforce:CreationResponse) {
            log:printInfo("Lead Created Successfully. Lead ID : " + sfResponse.id);

            json body = {
                "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
                "id": sfResponse.id,
                "userName":  userResource?.userName ?: "",
                "name": {
                    "givenName": userResource?.name?.givenName ?: "",
                    "familyName": userResource?.name?.familyName ?: ""
                },
                "emails": userResource?.emails ?: []
            };
            http:Response response = new;
            response.statusCode = http:STATUS_CREATED;
            response.setJsonPayload(body);
            
            check caller->respond(response);
        } else {
            log:printError(msg = sfResponse.message());
            return error(sfResponse.message());
        }
    }
}
