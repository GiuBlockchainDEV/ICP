import HashMap "mo:base/HashMap";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Error "mo:base/Error";

actor Token {
    private stable var owner : Principal = Principal.fromText("aaaaa-aa"); // Sostituisci con il Principal dell'owner effettivo
    private stable var name : Text = "";
    private stable var symbol : Text = "";
    private stable var totalSupply : Nat = 0;
    private let maxSupply : Nat = 10_000_000_00000000; // 10 milioni di token, considerando 8 decimali impliciti
    private var balances = HashMap.HashMap<Principal, Nat>(1, Principal.equal, Principal.hash);
    private var allowances = HashMap.HashMap<Principal, HashMap.HashMap<Principal, Nat>>(1, Principal.equal, Principal.hash);

    // Funzione per verificare se il chiamante è l'owner
    private func isOwner(caller : Principal) : Bool {
        caller == owner;
    };

    public shared(msg) func transferOwnership(newOwner : Principal) : async Result.Result<(), Text> {
        if (isOwner(msg.caller)) {
            owner := newOwner;
            #ok();
        } else {
            #err("Solo l'owner può trasferire la proprietà");
        };
    };

    public shared(msg) func setName(newName : Text) : async Result.Result<(), Text> {
        if (isOwner(msg.caller)) {
            name := newName;
            #ok();
        } else {
            #err("Solo l'owner può impostare il nome");
        };
    };

    public shared(msg) func setSymbol(newSymbol : Text) : async Result.Result<(), Text> {
        if (isOwner(msg.caller)) {
            symbol := newSymbol;
            #ok();
        } else {
            #err("Solo l'owner può impostare il simbolo");
        };
    };

    public query func getName() : async Text {
        name;
    };

    public query func getSymbol() : async Text {
        symbol;
    };

    public func balanceOf(who : Principal) : async Nat {
        switch (balances.get(who)) {
            case null 0;
            case (?balance) balance;
        };
    };

    public shared(msg) func transfer(to : Principal, value : Nat) : async Result.Result<(), Text> {
        let from = msg.caller;
        switch (balances.get(from)) {
            case null { #err("Saldo insufficiente") };
            case (?fromBalance) {
                if (fromBalance < value) {
                    #err("Saldo insufficiente");
                } else {
                    let newFromBalance : Nat = fromBalance - value;
                    balances.put(from, newFromBalance);

                    let toBalance = switch (balances.get(to)) {
                        case null 0;
                        case (?toBalance) toBalance;
                    };
                    balances.put(to, toBalance + value);
                    #ok();
                };
            };
        };
    };

    public shared(msg) func approve(spender : Principal, value : Nat) : async () {
        let owner = msg.caller;
        switch (allowances.get(owner)) {
            case null {
                let innerMap = HashMap.HashMap<Principal, Nat>(1, Principal.equal, Principal.hash);
                innerMap.put(spender, value);
                allowances.put(owner, innerMap);
            };
            case (?innerMap) {
                innerMap.put(spender, value);
            };
        };
    };

    public shared(msg) func transferFrom(from : Principal, to : Principal, value : Nat) : async Result.Result<(), Text> {
        let spender = msg.caller;
        switch (allowances.get(from)) {
            case null { #err("Nessuna autorizzazione") };
            case (?innerMap) {
                switch (innerMap.get(spender)) {
                    case null { #err("Nessuna autorizzazione") };
                    case (?allowance) {
                        if (allowance < value) {
                            #err("Autorizzazione insufficiente");
                        } else {
                            innerMap.put(spender, allowance - value);
                            await transfer(to, value);
                        };
                    };
                };
            };
        };
    };

    public shared(msg) func mint(to : Principal, value : Nat) : async Result.Result<(), Text> {
        if (not isOwner(msg.caller)) {
            return #err("Solo l'owner può coniare nuovi token");
        };
        
        if (totalSupply + value > maxSupply) {
            return #err("Il minting eccederebbe la fornitura massima di token");
        };

        totalSupply += value;
        let balance = switch (balances.get(to)) {
            case null value;
            case (?existing) existing + value;
        };
        balances.put(to, balance);
        #ok();
    };

    public query func getTotalSupply() : async Nat {
        totalSupply;
    };

    public query func getMaxSupply() : async Nat {
        maxSupply;
    };

    public query func getOwner() : async Principal {
        owner;
    };
}
