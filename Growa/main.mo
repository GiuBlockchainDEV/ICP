import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Time "mo:base/Time";
import Int "mo:base/Int";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";

actor IoTDataCanister {
    private type DeviceId = Text;
    private type Timestamp = Int;

    private type IoTData = {
        deviceId: DeviceId;
        timestamp: Timestamp;
        temperature: Float;
        humidity: Float;
        pressure: Float;
    };

    private let dataStore = HashMap.HashMap<DeviceId, Buffer.Buffer<IoTData>>(10, Text.equal, Text.hash);
    private let enabledDevices = HashMap.HashMap<DeviceId, Bool>(10, Text.equal, Text.hash);
    private stable var owner : Principal = Principal.fromText("aaaaa-aa");

    // Funzione per impostare l'owner iniziale (da chiamare solo una volta durante l'inizializzazione)
    public shared(msg) func setInitialOwner() : async () {
        assert(owner == Principal.fromText("aaaaa-aa"));
        owner := msg.caller;
    };

    // Funzione per cambiare l'owner (solo l'owner corrente può farlo)
    public shared(msg) func changeOwner(newOwner: Principal) : async () {
        assert(msg.caller == owner);
        owner := newOwner;
        Debug.print("Nuovo owner impostato: " # Principal.toText(newOwner));
    };

    // Funzione per visualizzare l'owner corrente
    public query func getOwner() : async Principal {
        owner
    };

    // Funzione per abilitare un dispositivo (solo owner)
    public shared(msg) func enableDevice(deviceId: DeviceId) : async () {
        assert(msg.caller == owner);
        enabledDevices.put(deviceId, true);
        Debug.print("Dispositivo abilitato: " # deviceId);
    };

    // Funzione per disabilitare un dispositivo (solo owner)
    public shared(msg) func disableDevice(deviceId: DeviceId) : async () {
        assert(msg.caller == owner);
        enabledDevices.put(deviceId, false);
        Debug.print("Dispositivo disabilitato: " # deviceId);
    };

    // Funzione per inserire dati da dispositivi IoT (solo dispositivi abilitati)
    public shared(msg) func insertIoTData(deviceId: DeviceId, temp: Float, hum: Float, press: Float) : async () {
        assert(switch (enabledDevices.get(deviceId)) {
            case (?isEnabled) isEnabled;
            case (null) false;
        });

        let timestamp = Time.now();
        let newData : IoTData = {
            deviceId = deviceId;
            timestamp = timestamp;
            temperature = temp;
            humidity = hum;
            pressure = press;
        };

        switch (dataStore.get(deviceId)) {
            case (null) {
                let newBuffer = Buffer.Buffer<IoTData>(1);
                newBuffer.add(newData);
                dataStore.put(deviceId, newBuffer);
            };
            case (?existingBuffer) {
                existingBuffer.add(newData);
            };
        };

        Debug.print("Dati inseriti per il dispositivo: " # deviceId # " al timestamp: " # Int.toText(timestamp));
    };

    // Funzione per ottenere i dati di un dispositivo specifico
    public query func getDeviceData(deviceId: DeviceId) : async ?[IoTData] {
        switch (dataStore.get(deviceId)) {
            case (null) { null };
            case (?buffer) { ?Buffer.toArray(buffer) };
        }
    };

    // Funzione per ottenere l'ultimo dato inserito per un dispositivo
    public query func getLastDeviceData(deviceId: DeviceId) : async ?IoTData {
        switch (dataStore.get(deviceId)) {
            case (null) { null };
            case (?buffer) {
                if (buffer.size() > 0) {
                    ?buffer.get(buffer.size() - 1)
                } else {
                    null
                }
            };
        }
    };

    // Funzione per ottenere tutti i dati di tutti i dispositivi
    public query func getAllData() : async [(DeviceId, [IoTData])] {
        let entries = Iter.toArray(dataStore.entries());
        Array.map<(DeviceId, Buffer.Buffer<IoTData>), (DeviceId, [IoTData])>(entries, func (entry) {
            (entry.0, Buffer.toArray(entry.1))
        })
    };

    // Funzione per controllare se un dispositivo è abilitato
    public query func isDeviceEnabled(deviceId: DeviceId) : async Bool {
        switch (enabledDevices.get(deviceId)) {
            case (?isEnabled) isEnabled;
            case (null) false;
        }
    };
}
