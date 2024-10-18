import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Array "mo:base/Array";
import Time "mo:base/Time";
import Result "mo:base/Result";
import Error "mo:base/Error";
import Buffer "mo:base/Buffer";
import Iter "mo:base/Iter";
import Int "mo:base/Int";
import Option "mo:base/Option";
import Text "mo:base/Text";

actor ManagementCanister {
    // Type definitions

    /// Represents the different roles a user can have in the system
    public type UserRole = {
        #Owner;     // Single owner of the system
        #Admin;     // Can perform all administrative tasks
        #Moderator; // Can perform some administrative tasks
        #Regular;   // Standard user access
        #ReadOnly;  // Can only read data, no modifications
    };

    /// Stores user information
    public type User = {
        id: Principal;
        role: UserRole;
        lastActive: Time.Time;
    };

    /// Represents the current status of an IoT device
    public type DeviceStatus = {
        #Active;     // Device is currently operational
        #Inactive;   // Device is not currently in use
        #Maintenance; // Device is undergoing maintenance
    };

    /// Stores information about an IoT device
    public type IoTDevice = {
        id: Text;
        status: DeviceStatus;
        lastPing: Time.Time;
    };

    /// Represents an entry in the activity log
    public type LogEntry = {
        timestamp: Time.Time;
        user: Principal;
        action: Text;
        details: Text;
    };

    /// Types of requests that can be made by Database Canisters
    public type DatabaseCanisterRequest = {
        #UserValidation: Principal;
        #AccessRightsCheck: (Principal, Text);
        #LogOperation: (Principal, Text);
    };

    // State variables
    private stable var owner: Principal = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai"); // Example owner principal
    private var users = HashMap.HashMap<Principal, User>(10, Principal.equal, Principal.hash);
    private var iotDevices = HashMap.HashMap<Text, IoTDevice>(10, Text.equal, Text.hash);
    private var activityLog = Buffer.Buffer<LogEntry>(1000);
    private var authorizedDatabaseCanisters = HashMap.HashMap<Principal, Bool>(10, Principal.equal, Principal.hash);

    // Authorization functions

    /// Checks if a user has the required role or higher
    private func hasRole(user: Principal, requiredRole: UserRole) : Bool {
        switch (users.get(user)) {
            case (?userData) {
                switch (requiredRole) {
                    case (#Owner) { userData.role == #Owner };
                    case (#Admin) { userData.role == #Owner or userData.role == #Admin };
                    case (#Moderator) { 
                        userData.role == #Owner or userData.role == #Admin or userData.role == #Moderator 
                    };
                    case (#Regular) { 
                        userData.role == #Owner or userData.role == #Admin 
                        or userData.role == #Moderator or userData.role == #Regular 
                    };
                    case (#ReadOnly) { true };
                }
            };
            case null { false };
        }
    };

    /// Asserts that the caller has the required role
    private func assertRole(caller: Principal, requiredRole: UserRole) : async () {
        if (not hasRole(caller, requiredRole)) {
            throw Error.reject("Unauthorized: Required role " # debug_show(requiredRole));
        };
    };

    // User management functions

    /// Registers a new user in the system
    /// Only Owner, Admin, or Moderator can register new users
    /// Example:
    /// ```motoko
    /// let newUserId = Principal.fromText("aaaaa-aa");
    /// let result = await managementCanister.registerUser(newUserId, #Regular);
    /// switch (result) {
    ///     case (#ok()) { Debug.print("User registered successfully") };
    ///     case (#err(message)) { Debug.print("Error: " # message) };
    /// }
    /// ```
    public shared(msg) func registerUser(newUserId: Principal, role: UserRole) : async Result.Result<(), Text> {
        try {
            await assertRole(msg.caller, #Moderator);
            
            switch(role) {
                case (#Owner) { throw Error.reject("Cannot create new Owner") };
                case (#Admin) { await assertRole(msg.caller, #Owner) };
                case (#Moderator) { await assertRole(msg.caller, #Admin) };
                case (_) {};
            };

            switch (users.get(newUserId)) {
                case (?_) { #err("User already registered") };
                case null {
                    let newUser : User = {
                        id = newUserId;
                        role = role;
                        lastActive = Time.now();
                    };
                    users.put(newUserId, newUser);
                    logActivity(msg.caller, "User Registration", "UserID: " # Principal.toText(newUserId) # ", Role: " # debug_show(role));
                    #ok(())
                };
            }
        } catch (e) {
            #err(Error.message(e))
        }
    };

    /// Updates user's last active time and returns the user's role
    /// Example:
    /// ```motoko
    /// let result = await managementCanister.heartbeat();
    /// switch (result) {
    ///     case (#ok(role)) { Debug.print("User role: " # debug_show(role)) };
    ///     case (#err(message)) { Debug.print("Error: " # message) };
    /// }
    /// ```
    public shared(msg) func heartbeat() : async Result.Result<UserRole, Text> {
        switch (users.get(msg.caller)) {
            case (?user) {
                let updatedUser = { user with lastActive = Time.now() };
                users.put(msg.caller, updatedUser);
                logActivity(msg.caller, "User Heartbeat", "");
                #ok(user.role)
            };
            case null { #err("User not found") };
        }
    };

    // IoT device management

    /// Registers a new IoT device in the system
    /// Only Admin or higher can register devices
    /// Example:
    /// ```motoko
    /// let deviceId = "smartSensor001";
    /// let result = await managementCanister.registerDevice(deviceId);
    /// switch (result) {
    ///     case (#ok()) { Debug.print("Device registered successfully") };
    ///     case (#err(message)) { Debug.print("Error: " # message) };
    /// }
    /// ```
    public shared(msg) func registerDevice(deviceId: Text) : async Result.Result<(), Text> {
        try {
            await assertRole(msg.caller, #Admin);
            
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
        } catch (e) {
            #err(Error.message(e))
        }
    };

    /// Updates the status of an IoT device
    /// Only Admin or higher can update device status
    /// Example:
    /// ```motoko
    /// let deviceId = "smartSensor001";
    /// let newStatus = #Maintenance;
    /// let result = await managementCanister.updateDeviceStatus(deviceId, newStatus);
    /// switch (result) {
    ///     case (#ok()) { Debug.print("Device status updated successfully") };
    ///     case (#err(message)) { Debug.print("Error: " # message) };
    /// }
    /// ```
    public shared(msg) func updateDeviceStatus(deviceId: Text, newStatus: DeviceStatus) : async Result.Result<(), Text> {
        try {
            await assertRole(msg.caller, #Admin);
            
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
        } catch (e) {
            #err(Error.message(e))
        }
    };

    // Database Canister management

    /// Registers a Database Canister as authorized
    /// Only Admin or higher can register Database Canisters
    /// Example:
    /// ```motoko
    /// let dbCanisterId = Principal.fromText("bbbbb-bb");
    /// let result = await managementCanister.registerDatabaseCanister(dbCanisterId);
    /// switch (result) {
    ///     case (#ok()) { Debug.print("Database Canister registered successfully") };
    ///     case (#err(message)) { Debug.print("Error: " # message) };
    /// }
    /// ```
    public shared(msg) func registerDatabaseCanister(canisterId: Principal) : async Result.Result<(), Text> {
        try {
            await assertRole(msg.caller, #Admin);
            
            authorizedDatabaseCanisters.put(canisterId, true);
            logActivity(msg.caller, "Database Canister Registration", "CanisterID: " # Principal.toText(canisterId));
            #ok(())
        } catch (e) {
            #err(Error.message(e))
        }
    };

    /// Handles requests from authorized Database Canisters
    /// Example:
    /// ```motoko
    /// let userToValidate = Principal.fromText("ccccc-cc");
    /// let request = #UserValidation(userToValidate);
    /// let result = await managementCanister.handleDatabaseRequest(request);
    /// switch (result) {
    ///     case (#ok(isValid)) { Debug.print("User validation result: " # debug_show(isValid)) };
    ///     case (#err(message)) { Debug.print("Error: " # message) };
    /// }
    /// ```
    public shared(msg) func handleDatabaseRequest(request: DatabaseCanisterRequest) : async Result.Result<Bool, Text> {
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

        switch request {
            case (#UserValidation(userId)) {
                #ok(Option.isSome(users.get(userId)))
            };
            case (#AccessRightsCheck(userId, resource)) {
                switch (users.get(userId)) {
                    case (?user) {
                        let hasAccess = switch (user.role) {
                            case (#Owner or #Admin) { true };
                            case (#Moderator) { resource != "admin_only_resource" };
                            case (#Regular) { resource == "public_resource" or resource == "regular_user_resource" };
                            case (#ReadOnly) { resource == "public_resource" };
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

    // Query functions

    /// Retrieves the role of a specific user
    /// Example:
    /// ```motoko
    /// let userId = Principal.fromText("ddddd-dd");
    /// let roleOption = await managementCanister.getUserRole(userId);
    /// switch (roleOption) {
    ///     case (?role) { Debug.print("User role: " # debug_show(role)) };
    ///     case (null) { Debug.print("User not found") };
    /// }
    /// ```
    public query func getUserRole(user: Principal) : async ?UserRole {
        Option.map(users.get(user), func (u: User) : UserRole { u.role })
    };

    /// Retrieves the status of a specific IoT device
    /// Example:
    /// ```motoko
    /// let deviceId = "smartSensor001";
    /// let statusOption = await managementCanister.getDeviceStatus(deviceId);
    /// switch (statusOption) {
    ///     case (?status) { Debug.print("Device status: " # debug_show(status)) };
    ///     case (null) { Debug.print("Device not found") };
    /// }
    /// ```
    public query func getDeviceStatus(deviceId: Text) : async ?DeviceStatus {
        Option.map(iotDevices.get(deviceId), func (d: IoTDevice) : DeviceStatus { d.status })
    };

    /// Retrieves the entire activity log (only Admin or higher)
    /// Example:
    /// ```motoko
    /// let result = await managementCanister.getActivityLog();
    /// switch (result) {
    ///     case (#ok(log)) { 
    ///         for (entry in log.vals()) {
    ///             Debug.print("Log: " # debug_show(entry));
    ///         }
    ///     };
    ///     case (#err(message)) { Debug.print("Error: " # message) };
    /// }
    /// ```
    public shared(msg) func getActivityLog() : async Result.Result<[LogEntry], Text> {
        try {
            await assertRole(msg.caller, #Admin);
            #ok(Buffer.toArray(activityLog))
        } catch (e) {
            #err(Error.message(e))
        }
    };

    // Private helper function for logging
    private func logActivity(user: Principal, action: Text, details: Text) {
        let entry : LogEntry = {
            timestamp = Time.now();
            user = user;
            action = action;
            details = details;
        };
        activityLog.add(entry);

        if (activityLog.size() > 1000) {
            ignore activityLog.remove(0);
        };
    };

    // System initialization
    system func init() {
        // Initialize the owner
        let ownerUser : User = {
            id = owner;
            role = #Owner;
            lastActive = Time.now();
        };
        users.put(owner, ownerUser);
    };
}
