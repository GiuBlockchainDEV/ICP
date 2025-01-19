import Principal "mo:base/Principal";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Array "mo:base/Array";
import Error "mo:base/Error";
import Text "mo:base/Text";
import Float "mo:base/Float";

actor SmartContract {
    // Types
    type Reading = {
        entity_id: Text;
        created_at: Int;
        value: Float;
    };

    // State variables
    private stable var owner: ?Principal = null;
    private var authorizedUsers = HashMap.HashMap<Principal, Bool>(0, Principal.equal, Principal.hash);
    private var readings = HashMap.HashMap<Text, [Reading]>(0, Text.equal, Text.hash);

    // Admin assignment function - can only be called once if no owner exists
    public shared(msg) func assignAdmin() : async Text {
        switch(owner) {
            case null {
                owner := ?msg.caller;
                return "Admin rights assigned successfully";
            };
            case (?_) {
                throw Error.reject("Admin already assigned");
            };
        };
    };

    // Transfer ownership to a new admin
    public shared(msg) func transferOwnership(newOwner: Principal) : async Text {
        switch(owner) {
            case null {
                throw Error.reject("No admin assigned yet");
            };
            case (?currentOwner) {
                if (Principal.equal(msg.caller, currentOwner)) {
                    owner := ?newOwner;
                    return "Ownership transferred successfully to new admin";
                } else {
                    throw Error.reject("Only current admin can transfer ownership");
                };
            };
        };
    };

    // Check if caller is admin
    private func isAdmin(caller: Principal) : Bool {
        switch(owner) {
            case null { return false; };
            case (?currentOwner) { return Principal.equal(caller, currentOwner); };
        };
    };

    // Add authorized user
    public shared(msg) func addAuthorizedUser(user: Principal) : async Text {
        if (not isAdmin(msg.caller)) {
            throw Error.reject("Only admin can add authorized users");
        };
        authorizedUsers.put(user, true);
        return "User authorized successfully";
    };

    // Remove authorized user
    public shared(msg) func removeAuthorizedUser(user: Principal) : async Text {
        if (not isAdmin(msg.caller)) {
            throw Error.reject("Only admin can remove authorized users");
        };
        authorizedUsers.delete(user);
        return "User removed successfully";
    };

    // Insert reading
    public shared(msg) func insertReading(entity_id: Text, value: Float) : async Text {
        switch(authorizedUsers.get(msg.caller)) {
            case null {
                throw Error.reject("Unauthorized user");
            };
            case (?authorized) {
                if (not authorized) {
                    throw Error.reject("Unauthorized user");
                };
                
                let reading: Reading = {
                    entity_id = entity_id;
                    created_at = Time.now();
                    value = value;
                };

                switch(readings.get(entity_id)) {
                    case null {
                        readings.put(entity_id, [reading]);
                    };
                    case (?existingReadings) {
                        let newReadings = Array.append(existingReadings, [reading]);
                        readings.put(entity_id, newReadings);
                    };
                };

                return "Reading inserted successfully";
            };
        };
    };

    // Get readings by time range
    public query func getReadings(entity_id: Text, start_time: Int, end_time: Int) : async [Reading] {
        switch(readings.get(entity_id)) {
            case null { return []; };
            case (?entityReadings) {
                return Array.filter(entityReadings, func (reading: Reading) : Bool {
                    reading.created_at >= start_time and reading.created_at <= end_time
                });
            };
        };
    };

    // Get all readings for a specific entity_id
    public query func getAllReadingsForEntity(entity_id: Text) : async [(Int, Float)] {
        switch(readings.get(entity_id)) {
            case null { 
                return []; 
            };
            case (?entityReadings) {
                let mapped = Array.map<Reading, (Int, Float)>(
                    entityReadings, 
                    func (reading: Reading) : (Int, Float) {
                        (reading.created_at, reading.value)
                    }
                );
                return mapped;
            };
        };
    };

    // Get readings for multiple entities
    public query func getMultipleEntityReadings(entity_ids: [Text]) : async [(Text, [(Int, Float)])] {
        Array.map<Text, (Text, [(Int, Float)])>(
            entity_ids,
            func (entity_id: Text) : (Text, [(Int, Float)]) {
                let entityReadings = switch(readings.get(entity_id)) {
                    case null { []; };
                    case (?readings) {
                        Array.map<Reading, (Int, Float)>(
                            readings,
                            func (reading: Reading) : (Int, Float) {
                                (reading.created_at, reading.value)
                            }
                        );
                    };
                };
                (entity_id, entityReadings)
            }
        );
    };

    // Get current admin
    public query func getAdmin() : async ?Principal {
        return owner;
    };

    // Get readings for multiple entities with time range
    public query func getMultipleEntityReadingsInTimeRange(entity_ids: [Text], start_time: Int, end_time: Int) : async [(Text, [(Int, Float)])] {
        Array.map<Text, (Text, [(Int, Float)])>(
            entity_ids,
            func (entity_id: Text) : (Text, [(Int, Float)]) {
                let entityReadings = switch(readings.get(entity_id)) {
                    case null { []; };
                    case (?readings) {
                        // First filter by time range
                        let filteredReadings = Array.filter<Reading>(
                            readings,
                            func (reading: Reading) : Bool {
                                reading.created_at >= start_time and reading.created_at <= end_time
                            }
                        );
                        // Then map to (timestamp, value) tuples
                        Array.map<Reading, (Int, Float)>(
                            filteredReadings,
                            func (reading: Reading) : (Int, Float) {
                                (reading.created_at, reading.value)
                            }
                        );
                    };
                };
                (entity_id, entityReadings)
            }
        );
    };

    // Check if user is authorized
    public query func isUserAuthorized(user: Principal) : async Bool {
        switch(authorizedUsers.get(user)) {
            case null { return false; };
            case (?authorized) { return authorized; };
        };
    };
}
