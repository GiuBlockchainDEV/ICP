// app.mo
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import HashMap "mo:base/HashMap";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";
import JSON "mo:json/JSON";
import Result "mo:base/Result";
import SHA256 "mo:sha256/SHA256";

actor class IoTGateway() {
    // Types
    type Role = {
        #SUPER_ADMIN;
        #SYSTEM_ADMIN;
        #USER_ADMIN;
        #DEVICE_MANAGER;
        #ANALYST;
        #OPERATOR;
        #USER;
    };

    type UserStatus = {
        #PENDING;
        #APPROVED;
        #REJECTED;
        #SUSPENDED;
    };

    type User = {
        principal: Principal;
        name: Text;
        email: Text;
        role: Role;
        status: UserStatus;
        department: ?Text;
        created: Int;
        lastModified: Int;
    };

    type Device = {
        hash: Text;
        owner: Principal;
        name: Text;
        key: Text;
        department: ?Text;
        approved: Bool;
        created: Int;
        lastUsed: ?Int;
    };

    type Reading = {
        id: Text;
        deviceHash: Text;
        timestamp: Int;
        data: [{
            type: Text;
            value: Float;
            unit: Text;
        }];
    };

    // State Variables
    private stable let SUPER_ADMIN : Principal = msg.caller;
    private var users = HashMap.HashMap<Principal, User>(0, Principal.equal, Principal.hash);
    private var devices = HashMap.HashMap<Text, Device>(0, Text.equal, Text.hash);
    private var readings = HashMap.HashMap<Text, Reading>(0, Text.equal, Text.hash);
    private var readingsByDevice = HashMap.HashMap<Text, [Text]>(0, Text.equal, Text.hash);

    // Auth Functions
    public shared query(msg) func isAdmin() : async Bool {
        msg.caller == SUPER_ADMIN or hasRole(msg.caller, #SYSTEM_ADMIN)
    };

    private func hasRole(principal: Principal, role: Role) : Bool {
        switch(users.get(principal)) {
            case(?user) user.role == role and user.status == #APPROVED;
            case(null) false;
        }
    };

    public shared query(msg) func getUserRole() : async ?Role {
        switch(users.get(msg.caller)) {
            case(?user) ?user.role;
            case(null) null;
        }
    };

    // User Management
    public shared(msg) func registerUser(name: Text, email: Text, department: ?Text) : async Bool {
        let user: User = {
            principal = msg.caller;
            name = name;
            email = email;
            role = #USER;
            status = #PENDING;
            department = department;
            created = Time.now();
            lastModified = Time.now();
        };
        users.put(msg.caller, user);
        true
    };

    public shared(msg) func approveUser(userPrincipal: Principal) : async Bool {
        assert(await isAdmin());
        switch(users.get(userPrincipal)) {
            case(?user) {
                let updatedUser = {
                    principal = user.principal;
                    name = user.name;
                    email = user.email;
                    role = user.role;
                    status = #APPROVED;
                    department = user.department;
                    created = user.created;
                    lastModified = Time.now();
                };
                users.put(userPrincipal, updatedUser);
                true
            };
            case(null) false;
        }
    };

    public shared(msg) func updateUserRole(userPrincipal: Principal, newRole: Role) : async Bool {
        assert(await isAdmin());
        switch(users.get(userPrincipal)) {
            case(?user) {
                let updatedUser = {
                    principal = user.principal;
                    name = user.name;
                    email = user.email;
                    role = newRole;
                    status = user.status;
                    department = user.department;
                    created = user.created;
                    lastModified = Time.now();
                };
                users.put(userPrincipal, updatedUser);
                true
            };
            case(null) false;
        }
    };

    // Device Management
    public shared(msg) func registerDevice(name: Text, department: ?Text) : async ?{hash: Text; key: Text} {
        switch(users.get(msg.caller)) {
            case(?user) {
                if (user.status != #APPROVED) return null;
                
                let hash = generateDeviceHash(msg.caller, name, Time.now());
                let key = generateDeviceKey(hash);
                
                let device: Device = {
                    hash = hash;
                    owner = msg.caller;
                    name = name;
                    key = key;
                    department = department;
                    approved = false;
                    created = Time.now();
                    lastUsed = null;
                };
                
                devices.put(hash, device);
                ?{hash; key}
            };
            case(null) null;
        }
    };

    public shared(msg) func approveDevice(deviceHash: Text) : async Bool {
        assert(await isAdmin());
        switch(devices.get(deviceHash)) {
            case(?device) {
                let updatedDevice = {
                    hash = device.hash;
                    owner = device.owner;
                    name = device.name;
                    key = device.key;
                    department = device.department;
                    approved = true;
                    created = device.created;
                    lastUsed = device.lastUsed;
                };
                devices.put(deviceHash, updatedDevice);
                true
            };
            case(null) false;
        }
    };

    // Readings Management
    public shared(msg) func addReading(deviceHash: Text, deviceKey: Text, reading: Text) : async Result.Result<Text, Text> {
        switch(devices.get(deviceHash)) {
            case(?device) {
                if (not device.approved or device.key != deviceKey) {
                    return #err("Invalid device authentication");
                };

                switch(parseReading(reading)) {
                    case(#ok(data)) {
                        let readingId = generateReadingId(deviceHash, Time.now());
                        let newReading : Reading = {
                            id = readingId;
                            deviceHash = deviceHash;
                            timestamp = Time.now();
                            data = data;
                        };

                        readings.put(readingId, newReading);

                        // Update device last used
                        let updatedDevice = {
                            hash = device.hash;
                            owner = device.owner;
                            name = device.name;
                            key = device.key;
                            department = device.department;
                            approved = device.approved;
                            created = device.created;
                            lastUsed = ?Time.now();
                        };
                        devices.put(deviceHash, updatedDevice);

                        // Update index
                        switch(readingsByDevice.get(deviceHash)) {
                            case(?readings) {
                                readingsByDevice.put(deviceHash, Array.append(readings, [readingId]));
                            };
                            case(null) {
                                readingsByDevice.put(deviceHash, [readingId]);
                            };
                        };

                        #ok(readingId)
                    };
                    case(#err(e)) {
                        #err(e)
                    };
                }
            };
            case(null) {
                #err("Device not found")
            };
        }
    };

    // Queries
    public query func getDevicesByOwner(owner: Principal) : async [Device] {
        Iter.toArray(
            Iter.filter(devices.vals(), func (d: Device) : Bool {
                d.owner == owner
            })
        )
    };

    public query func getPendingDevices() : async [Device] {
        Iter.toArray(
            Iter.filter(devices.vals(), func (d: Device) : Bool {
                not d.approved
            })
        )
    };

    public query func getDeviceReadings(deviceHash: Text) : async [Reading] {
        switch(readingsByDevice.get(deviceHash)) {
            case(?readingIds) {
                let result = Buffer.Buffer<Reading>(0);
                for (id in readingIds.vals()) {
                    switch(readings.get(id)) {
                        case(?r) { result.add(r); };
                        case(null) {};
                    };
                };
                Buffer.toArray(result)
            };
            case(null) { [] };
        }
    };

    public query func getAllUsers() : async [User] {
        Iter.toArray(users.vals())
    };

    public query func getPendingUsers() : async [User] {
        Iter.toArray(
            Iter.filter(users.vals(), func (u: User) : Bool {
                u.status == #PENDING
            })
        )
    };

    // Utils
    private func generateDeviceHash(owner: Principal, name: Text, timestamp: Int) : Text {
        let baseString = Principal.toText(owner) # name # Int.toText(timestamp);
        bytesToHex(SHA256.hash(textToBytes(baseString)))
    };

    private func generateDeviceKey(hash: Text) : Text {
        bytesToHex(SHA256.hash(textToBytes(hash # Int.toText(Time.now()))))
    };

    private func generateReadingId(deviceHash: Text, timestamp: Int) : Text {
        bytesToHex(SHA256.hash(textToBytes(deviceHash # Int.toText(timestamp))))
    };

    private func textToBytes(t: Text) : [Nat8] {
        Blob.toArray(Text.encodeUtf8(t))
    };

    private func bytesToHex(bytes: [Nat8]) : Text {
        let hexChars = ["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"];
        var hex = "";
        for (byte in bytes.vals()) {
            hex #= hexChars[byte >> 4] # hexChars[byte & 15];
        };
        hex
    };

    private func parseReading(jsonText: Text) : Result.Result<[{type: Text; value: Float; unit: Text}], Text> {
        try {
            switch(JSON.parse(jsonText)) {
                case(?parsed) {
                    switch(parsed) {
                        case(#Array(values)) {
                            let readings = Buffer.Buffer<{type: Text; value: Float; unit: Text}>(0);
                            for (value in values.vals()) {
                                switch(value) {
                                    case(#Object(obj)) {
                                        readings.add({
                                            type = getJsonText(obj, "type");
                                            value = getJsonNumber(obj, "value");
                                            unit = getJsonText(obj, "unit");
                                        });
                                    };
                                    case(_) {};
                                };
                            };
                            #ok(Buffer.toArray(readings))
                        };
                        case(_) #err("Invalid JSON format")
                    }
                };
                case(null) #err("Failed to parse JSON")
            }
        } catch(e) {
            #err("Error parsing JSON")
        }
    };

    private func getJsonText(obj: [(Text, JSON)], key: Text) : Text {
        switch(obj.get(key)) {
            case(?#String(val)) val;
            case(_) "";
        }
    };

    private func getJsonNumber(obj: [(Text, JSON)], key: Text) : Float {
        switch(obj.get(key)) {
            case(?#Number(val)) val;
            case(_) 0;
        }
    };

    // System Functions
    system func preupgrade() {
        // Implementare logica per salvare stato
    };

    system func postupgrade() {
        // Implementare logica per recuperare stato
    };
}
