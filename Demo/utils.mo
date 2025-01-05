// utils.mo
module {
    // Funzioni di utilità per hash e codifica
    public func textToBytes(t: Text) : [Nat8] {
        Blob.toArray(Text.encodeUtf8(t))
    };

    public func bytesToHex(bytes: [Nat8]) : Text {
        let hexChars = ["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"];
        var hex = "";
        for (byte in bytes.vals()) {
            hex #= hexChars[byte >> 4] # hexChars[byte & 15];
        };
        hex
    };

    // Funzioni di generazione ID
    public func generateDeviceHash(owner: Principal, name: Text, timestamp: Int) : Text {
        let baseString = Principal.toText(owner) # name # Int.toText(timestamp);
        bytesToHex(SHA256.hash(textToBytes(baseString)))
    };

    public func generateDeviceKey(hash: Text) : Text {
        bytesToHex(SHA256.hash(textToBytes(hash # Int.toText(Time.now()))))
    };

    public func generateReadingId(deviceHash: Text, timestamp: Int) : Text {
        bytesToHex(SHA256.hash(textToBytes(deviceHash # Int.toText(timestamp))))
    };

    // Funzioni di parsing JSON
    public func parseReading(jsonText: Text) : Result.Result<[Types.ReadingData], Text> {
        try {
            switch(JSON.parse(jsonText)) {
                case(?parsed) {
                    switch(parsed) {
                        case(#Array(values)) {
                            let readings = Buffer.Buffer<Types.ReadingData>(0);
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

    public func getJsonText(obj: [(Text, JSON)], key: Text) : Text {
        switch(obj.get(key)) {
            case(?#String(val)) val;
            case(_) "";
        }
    };

    public func getJsonNumber(obj: [(Text, JSON)], key: Text) : Float {
        switch(obj.get(key)) {
            case(?#Number(val)) val;
            case(_) 0;
        }
    };
}
