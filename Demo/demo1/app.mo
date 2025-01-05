import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Float "mo:base/Float";
import HashMap "mo:base/HashMap";
import _Array "mo:base/Array";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Char "mo:base/Char";
import Nat32 "mo:base/Nat32";

actor class IoTGateway() {
    // ===== TYPES =====
    type ReadingData = {
        readingType : Text;
        readingValue : Float;
        readingUnit : Text;
    };

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
        principal : Principal;
        name : Text;
        email : Text;
        role : Role;
        status : UserStatus;
        department : ?Text;
        created : Int;
        lastModified : Int;
    };

    type Device = {
        hash : Text;
        owner : Principal;
        name : Text;
        key : Text;
        department : ?Text;
        approved : Bool;
        created : Int;
        lastUsed : ?Int;
    };

    type Reading = {
        id : Text;
        deviceHash : Text;
        timestamp : Int;
        data : [ReadingData];
    };

    // Variabile per il primo admin
    private var initialAdmin : Principal = Principal.fromText("aaaaa-aa");

    // ===== STATE =====
    private var users = HashMap.HashMap<Principal, User>(0, Principal.equal, Principal.hash);
    private var devices = HashMap.HashMap<Text, Device>(0, Text.equal, Text.hash);
    private var readings = HashMap.HashMap<Text, Reading>(0, Text.equal, Text.hash);
    private var readingsByDevice = HashMap.HashMap<Text, [Text]>(0, Text.equal, Text.hash);

    // ===== AUTH FUNCTIONS =====
    public shared func isAdmin(caller : Principal) : async Bool {
        caller == initialAdmin or hasAdminRole(caller)
    };

    private func hasAdminRole(principal: Principal) : Bool {
        switch(users.get(principal)) {
            case(?user) user.role == #SYSTEM_ADMIN and user.status == #APPROVED;
            case(null) false;
        }
    };

    public shared(msg) func getUserRole() : async ?Role {
        switch(users.get(msg.caller)) {
            case(?user) ?user.role;
            case(null) null;
        }
    };

    // ===== USER MANAGEMENT =====
        public shared(msg) func registerUser(name: Text, email: Text, department: ?Text) : async Bool {
        // Check if user already exists
        switch(users.get(msg.caller)) {
            case(?_) return false;
            case(null) {};
        };

        // Controlla se è il primo utente
        let isFirstUser = users.size() == 0;

        let user: User = {
            principal = msg.caller;
            name = name;
            email = email;
            role = if (isFirstUser) #SYSTEM_ADMIN else #USER;
            status = #APPROVED; // Approva automaticamente il primo utente
            department = department;
            created = Time.now();
            lastModified = Time.now();
        };
        users.put(msg.caller, user);
        
        // Se è il primo utente, imposta anche il principal come admin iniziale
        if (isFirstUser) {
            initialAdmin := msg.caller;
        };
        
        // Rimuovere o spostare Debug.print se causa problemi
        true
    };

      public shared(msg) func approveUser(userPrincipal: Principal) : async Bool {
        let caller = msg.caller;
        let isAdminUser = await isAdmin(caller);
        assert(isAdminUser);
        
        switch(users.get(userPrincipal)) {
            case(?user) {
                let updatedUser : User = {
                    principal = user.principal;
                    name = user.name;
                    email = user.email;
                    role = user.role;
                    status = #APPROVED; // Stato esplicitamente cambiato ad APPROVED
                    department = user.department;
                    created = user.created;
                    lastModified = Time.now();
                };
                users.put(userPrincipal, updatedUser);
                true // Conferma che l'utente è stato effettivamente approvato
            };
            case(null) false;
        }
    };

    // ===== DEVICE MANAGEMENT =====
    public shared(msg) func registerDevice(name: Text, department: ?Text) : async ?{hash: Text; key: Text} {
        switch(users.get(msg.caller)) {
            case(?user) {
                if (user.status != #APPROVED) return null;
                
                let hash = _generateDeviceHash(msg.caller, name, Time.now());
                let key = _generateDeviceKey(hash);
                
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
                Debug.print("Device registered: " # debug_show(device));
                ?{hash; key}
            };
            case(null) null;
        }
    };

    public shared(msg) func approveDevice(deviceHash: Text) : async Bool {
      let caller = msg.caller;
      let isAdminUser = await isAdmin(caller);
      assert(isAdminUser);
      
      switch(devices.get(deviceHash)) {
          case(?device) {
              let updatedDevice : Device = {
                  hash = device.hash;
                  owner = device.owner;
                  name = device.name;
                  key = device.key;
                  department = device.department;
                  approved = true; // Stato esplicitamente cambiato ad APPROVED
                  created = device.created;
                  lastUsed = device.lastUsed;
              };
              devices.put(deviceHash, updatedDevice);
              true // Conferma che il dispositivo è stato effettivamente approvato
          };
          case(null) false;
      }
  };

    // ===== READINGS MANAGEMENT =====
    public shared(msg) func addReading(deviceHash: Text, deviceKey: Text, readingText: Text) : async Result.Result<Text, Text> {
        switch(devices.get(deviceHash)) {
            case(?device) {
                if (not device.approved or device.key != deviceKey) {
                    return #err("Invalid device authentication");
                };

                let parseResult = _parseReading(readingText);
                switch(parseResult) {
                    case(#ok(data)) {
                        let readingId = _generateReadingId(deviceHash, Time.now());
                        let newReading : Reading = {
                            id = readingId;
                            deviceHash = deviceHash;
                            timestamp = Time.now();
                            data = data;
                        };

                        readings.put(readingId, newReading);

                        // Update device lastUsed
                        devices.put(deviceHash, {
                            hash = device.hash;
                            owner = device.owner;
                            name = device.name;
                            key = device.key;
                            department = device.department;
                            approved = device.approved;
                            created = device.created;
                            lastUsed = ?Time.now();
                        });

                        // Update index
                        switch(readingsByDevice.get(deviceHash)) {
                            case(?deviceReadings) {
                                readingsByDevice.put(deviceHash, _Array.append(deviceReadings, [readingId]));
                            };
                            case(null) {
                                readingsByDevice.put(deviceHash, [readingId]);
                            };
                        };

                        Debug.print("Reading added: " # debug_show(newReading));
                        #ok(readingId)
                    };
                    case(#err(e)) #err(e);
                };
            };
            case(null) #err("Device not found");
        };
    };

    // ===== QUERIES =====
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

    // ===== UTILS =====
    // Funzione di parsing stringa personalizzata
    private func _parseReading(inputString: Text) : Result.Result<[ReadingData], Text> {
        let readings = Buffer.Buffer<ReadingData>(0);
        
        // Rimuovi eventuali spazi iniziali e finali
        let cleanText = Text.trim(inputString, #char ' ');
        
        // Dividi la stringa in parti
        let props = Text.split(cleanText, #char ',');
        
        var readingType = "";
        var readingValue : Float = 0.0;
        var readingUnit = "";
        
        for (prop in props) {
            let keyValue = Text.split(prop, #char ':');
            let keyValueArray = Iter.toArray<Text>(keyValue);
            
            if (keyValueArray.size() >= 2) {
                let key = Text.trim(keyValueArray[0], #char ' ');
                let value = Text.trim(keyValueArray[1], #char ' ');
                
                switch(key) {
                    case ("type") { readingType := value; };
                    case ("value") { 
                        readingValue := _textToFloat(value);
                    };
                    case ("unit") { readingUnit := value; };
                    case (_) {};
                };
            };
        };
        
        if (readingType != "" or readingValue != 0.0 or readingUnit != "") {
            let reading : ReadingData = {
                readingType = readingType;
                readingValue = readingValue;
                readingUnit = readingUnit;
            };
            readings.add(reading);
        };
        
        if (readings.size() > 0) {
            #ok(Buffer.toArray(readings))
        } else {
            #err("No readings parsed")
        }
    };

    // Funzione di conversione Float personalizzata
    private func _textToFloat(text : Text) : Float {
        let trimmedText = Text.trim(text, #char ' ');
        switch(_parseFloat(trimmedText)) {
            case(?v) v;
            case(null) 0.0;
        }
    };

    private func _parseFloat(text : Text) : ?Float {
        var floatValue : Float = 0.0;
        var isNegative = false;
        var hasDecimal = false;
        var decimalPlace = 0;

        for (char in text.chars()) {
            if (Char.isDigit(char)) {
                let digitValue = Nat32.toNat(Char.toNat32(char) - Char.toNat32('0'));
                if (hasDecimal) {
                    floatValue += Float.fromInt(digitValue) * Float.pow(10.0, -Float.fromInt(decimalPlace));
                    decimalPlace += 1;
                } else {
                    floatValue *= 10.0;
                    floatValue += Float.fromInt(digitValue);
                }
            } else if (char == '-') {
                isNegative := true;
            } else if (char == '.' or char == ',') {
                hasDecimal := true;
                decimalPlace := 1;
            }
        };

        if (isNegative) {
            floatValue *= -1.0;
        };

        ?floatValue
    };

    // Funzioni di generazione ID
    private func _generateDeviceHash(owner: Principal, name: Text, timestamp: Int) : Text {
        Principal.toText(owner) # name # Nat.toText(Int.abs(timestamp))
    };

    private func _generateDeviceKey(hash: Text) : Text {
        hash # Nat.toText(Int.abs(Time.now()))
    };

    private func _generateReadingId(deviceHash: Text, timestamp: Int) : Text {
        deviceHash # Nat.toText(Int.abs(timestamp))
    };
}
