import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Array "mo:base/Array";
import Time "mo:base/Time";
import Result "mo:base/Result";
import Error "mo:base/Error";
import Buffer "mo:base/Buffer";
import Iter "mo:base/Iter";
import Int "mo:base/Int";

actor ManagementCanister {
    // Type definitions
    
    /// Represents the different roles a user can have in the system
    public type UserRole = {
        #Admin;    // Full access to all functions
        #Regular;  // Standard user access
        #ReadOnly; // Can only read data, no modifications
    };

    /// Stores user information
    public type User = {
        id: Principal;     // Unique identifier for the user
        role: UserRole;    // The user's role in the system
        lastLogin: Time.Time; // Timestamp of the last login
    };

    /// Represents the current status of an IoT device
    public type DeviceStatus = {
        #Active;     // Device is currently operational
        #Inactive;   // Device is not currently in use
        #Maintenance; // Device is undergoing maintenance
    };

    /// Stores information about an IoT device
    public type IoTDevice = {
        id: Text;           // Unique identifier for the device
        status: DeviceStatus; // Current status of the device
        lastPing: Time.Time;  // Timestamp of the last communication
    };

    /// Represents an entry in the activity log
    public type LogEntry = {
        timestamp: Time.Time; // When the activity occurred
        user: Principal;      // Who performed the activity
        action: Text;         // What action was taken
        details: Text;        // Additional information about the action
    };

    /// Types of requests that can be made by Database Canisters
    public type DatabaseCanisterRequest = {
        #UserValidation: Principal;
        #AccessRightsCheck: (Principal, Text); // (User, Resource)
        #LogOperation: (Principal, Text); // (User, Operation)
    };

    // State variables
    
    /// Stores all registered users
    private var users = HashMap.HashMap<Principal, User>(10, Principal.equal, Principal.hash);

    /// Stores all registered IoT devices
    private var iotDevices = HashMap.HashMap<Text, IoTDevice>(10, Text.equal, Text.hash);

    /// Stores the activity log
    private var activityLog = Buffer.Buffer<LogEntry>(1000);

    /// Stores authorized Database Canisters
    private var authorizedDatabaseCanisters = HashMap.HashMap<Principal, Bool>(10, Principal.equal, Principal.hash);

    // User management functions

    /// Registers a new user in the system
    /// @param username: The username for the new user
    /// @return Result indicating success or failure
    /// Example: await managementCanister.registerUser("alice")
    public shared(msg) func registerUser(username: Text) : async Result.Result<(), Text> {
        let caller = msg.caller;
        switch (users.get(caller)) {
            case (?_) { #err("User already registered") };
            case null {
                let newUser : User = {
                    id = caller;
                    role = #Regular; // Default role for new users
                    lastLogin = Time.now();
                };
                users.put(caller, newUser);
                logActivity(caller, "User Registration", "Username: " # username);
                #ok(())
            };
        }
    };

    /// Handles user login and updates last login time
    /// @return Result with success message or error
    /// Example: await managementCanister.login()
    public shared(msg) func login() : async Result.Result<Text, Text> {
        let caller = msg.caller;
        switch (users.get(caller)) {
            case (?user) {
                let updatedUser = { user with lastLogin = Time.now() };
                users.put(caller, updatedUser);
                logActivity(caller, "User Login", "");
                #ok("Login successful")
            };
            case null { #err("User not found") };
        }
    };

    // Role-based access control

    /// Checks if a user has the required permission
    /// @param user: The Principal of the user
    /// @param requiredRole: The role required for the action
    /// @return Boolean indicating if the user has permission
    private func hasPermission(user: Principal, requiredRole: UserRole) : Bool {
        switch (users.get(user)) {
            case (?userData) {
                switch (userData.role, requiredRole) {
                    case (#Admin, _) { true };
                    case (#Regular, #Regular) { true };
                    case (#Regular, #ReadOnly) { true };
                    case (#ReadOnly, #ReadOnly) { true };
                    case _ { false };
                }
            };
            case null { false };
        }
    };

    // IoT device management

    /// Registers a new IoT device in the system
    /// @param deviceId: Unique identifier for the device
    /// @return Result indicating success or failure
    /// Example: await managementCanister.registerDevice("device001")
    public shared(msg) func registerDevice(deviceId: Text) : async Result.Result<(), Text> {
        if (not hasPermission(msg.caller, #Admin)) {
            return #err("Only admins can register devices");
        };
        
        switch (iotDevices.get(deviceId)) {
            case (?_) { #err("Device already registered") };
            case null {
                let newDevice : IoTDevice = {
                    id = deviceId;
                    status = #Active;
                    lastPing = Time.now();
                };
                iotDevices.put(deviceId, newDevice);
                logActivity(msg.caller, "Device Registration", "DeviceID: " # deviceId);
                #ok(())
            };
        }
    };

    /// Updates the status of an IoT device
    /// @param deviceId: The ID of the device to update
    /// @param newStatus: The new status to set
    /// @return Result indicating success or failure
    /// Example: await managementCanister.updateDeviceStatus("device001", #Maintenance)
    public shared(msg) func updateDeviceStatus(deviceId: Text, newStatus: DeviceStatus) : async Result.Result<(), Text> {
        if (not hasPermission(msg.caller, #Admin)) {
            return #err("Only admins can update device status");
        };
        
        switch (iotDevices.get(deviceId)) {
            case (?device) {
                let updatedDevice = {
                    device with 
                    status = newStatus;
                    lastPing = Time.now();
                };
                iotDevices.put(deviceId, updatedDevice);
                logActivity(msg.caller, "Device Status Update", "DeviceID: " # deviceId # ", New Status: " # debug_show(newStatus));
                #ok(())
            };
            case null { #err("Device not found") };
        }
    };

    // Logging function

    /// Logs an activity in the system
    /// @param user: The Principal of the user performing the action
    /// @param action: The action being performed
    /// @param details: Additional details about the action
    private func logActivity(user: Principal, action: Text, details: Text) {
        let entry : LogEntry = {
            timestamp = Time.now();
            user = user;
            action = action;
            details = details;
        };
        activityLog.add(entry);

        // If the log buffer is full, remove the oldest entry
        if (activityLog.size() > 1000) {
            ignore activityLog.remove(0);
        };
    };

    // Query functions

    /// Retrieves the role of a specific user
    /// @param user: The Principal of the user
    /// @return The user's role, if found
    /// Example: let role = await managementCanister.getUserRole(Principal.fromText("abc123..."))
    public query func getUserRole(user: Principal) : async ?UserRole {
        switch (users.get(user)) {
            case (?userData) { ?userData.role };
            case null { null };
        }
    };

    /// Retrieves the status of a specific IoT device
    /// @param deviceId: The ID of the device
    /// @return The device's status, if found
    /// Example: let status = await managementCanister.getDeviceStatus("device001")
    public query func getDeviceStatus(deviceId: Text) : async ?DeviceStatus {
        switch (iotDevices.get(deviceId)) {
            case (?device) { ?device.status };
            case null { null };
        }
    };

    /// Retrieves the entire activity log
    /// @return An array of LogEntry
    /// Example: let logs = await managementCanister.getActivityLog()
    public query func getActivityLog() : async [LogEntry] {
        Buffer.toArray(activityLog)
    };

    // Database Canister communication

    /// Registers a Database Canister as authorized
    /// @param canisterId: The Principal of the Database Canister
    /// @return Result indicating success or failure
    /// Example: await managementCanister.registerDatabaseCanister(Principal.fromText("def456..."))
    public shared(msg) func registerDatabaseCanister(canisterId: Principal) : async Result.Result<(), Text> {
        if (not hasPermission(msg.caller, #Admin)) {
            return #err("Only admins can register Database Canisters");
        };
        authorizedDatabaseCanisters.put(canisterId, true);
        logActivity(msg.caller, "Database Canister Registration", "CanisterID: " # Principal.toText(canisterId));
        #ok(())
    };

    /// Handles requests from Database Canisters
    /// @param request: The request from the Database Canister
    /// @return Result with boolean response or error message
    /// Example: await managementCanister.handleDatabaseRequest(#UserValidation(userPrincipal))
    public shared(msg) func handleDatabaseRequest(request: DatabaseCanisterRequest) : async Result.Result<Bool, Text> {
        // Check if the caller is an authorized Database Canister
        switch (authorizedDatabaseCanisters.get(msg.caller)) {
            case (?isAuthorized) {
                if (not isAuthorized) {
                    return #err("Unauthorized Database Canister");
                };
            };
            case null {
                return #err("Unrecognized Database Canister");
            };
        };

        // Process the request based on its type
        switch request {
            case (#UserValidation(userId)) {
                switch (users.get(userId)) {
                    case (?_) { #ok(true) };
                    case null { #ok(false) };
                }
            };
            case (#AccessRightsCheck(userId, resource)) {
                switch (users.get(userId)) {
                    case (?user) {
                        // Implement your access rights logic here
                        // This is a simplified example
                        let hasAccess = switch (user.role) {
                            case (#Admin) true;
                            case (#Regular) resource != "restricted_data";
                            case (#ReadOnly) resource == "public_data";
                        };
                        #ok(hasAccess)
                    };
                    case null { #err("User not found") };
                }
            };
            case (#LogOperation(userId, operation)) {
                logActivity(userId, "Database Operation", operation);
                #ok(true)
            };
        }
    };

    /// Retrieves all registered Database Canisters
    /// @return An array of Principal IDs of registered Database Canisters
    /// Example: let dbCanisters = await managementCanister.getRegisteredDatabaseCanisters()
    public query func getRegisteredDatabaseCanisters() : async [Principal] {
        Array.map<(Principal, Bool), Principal>(
            Array.filter<(Principal, Bool)>(
                Iter.toArray(authorizedDatabaseCanisters.entries()),
                func((_, isAuthorized)) { isAuthorized }
            ),
            func((id, _)) { id }
        )
    };

    /// Clears log entries older than 30 days
    /// @return Result with the number of removed entries or an error message
    /// Example: let clearedLogs = await managementCanister.clearOldLogs()
    public shared(msg) func clearOldLogs() : async Result.Result<Nat, Text> {
        if (not hasPermission(msg.caller, #Admin)) {
            return #err("Only admins can clear logs");
        };

        let thirtyDaysAgo = Time.now() - (30 * 24 * 60 * 60 * 1_000_000_000);
        let oldSize = activityLog.size();
        activityLog := Buffer.mapFilter<LogEntry, LogEntry>(
            activityLog,
            func (entry) {
                if (entry.timestamp > thirtyDaysAgo) {
                    ?entry
                } else {
                    null
                }
            }
        );
        let removedEntries = oldSize - activityLog.size();
        logActivity(msg.caller, "Clear Old Logs", "Removed entries: " # Int.toText(removedEntries));
        #ok(removedEntries)
    };
}
