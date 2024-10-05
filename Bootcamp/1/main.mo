import Buffer "mo:base/Buffer";

actor {
    let name : Text = "Blockchain Oracle";
    var manifesto : Text = "Whitepaper of the Oracle";
    let goals = Buffer.Buffer<Text>(0);

    public shared query func getName() : async Text {
        return name;
    };

    public shared query func getManifesto() : async Text {
        return manifesto;
    };

    public func setManifesto(newManifesto : Text) : async () {
        manifesto := newManifesto;
        return;
    };

    public func addGoal(newGoal : Text) : async () {
        goals.add(newGoal);
        return;
    };

    public shared query func getGoals() : async [Text] {
        Buffer.toArray(goals);
    };
};
