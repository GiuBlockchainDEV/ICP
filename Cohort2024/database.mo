import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Time "mo:base/Time";
import JSON "mo:base/JSON";
import Buffer "mo:base/Buffer";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";

actor DatabaseCanister {
    // Type definitions
    type DocumentId = Text;
    type Document = {
        id: DocumentId;
        content: JSON.JSON;
        owner: Principal;
        createdAt: Time.Time;
        updatedAt: Time.Time;
    };

    type CachedRole = {
        role: Text;
        expiresAt: Time.Time;
    };

    // State variables
    private var documents = HashMap.HashMap<DocumentId, Document>(50, Text.equal, Text.hash);
    private var userRoleCache = HashMap.HashMap<Principal, CachedRole>(50, Principal.equal, Principal.hash);

    private let managementCanister : actor {
        handleDatabaseRequest : shared (request: {
            #UserValidation: Principal;
            #AccessRightsCheck: (Principal, Text);
            #LogOperation: (Principal, Text);
        }) -> async Result.Result<Bool, Text>;
    } = actor("rrkah-fqaaa-aaaaa-aaaaq-cai"); // Replace with actual Management Canister ID

    // Helper functions for role caching

    /// Retrieves a cached role for a user if it exists and is not expired
    /// @param user: The Principal of the user
    /// @return: The cached role as Text, or null if not found or expired
    private func getCachedRole(user: Principal) : ?Text {
        switch (userRoleCache.get(user)) {
            case (?cachedRole) {
                if (Time.now() < cachedRole.expiresAt) {
                    ?cachedRole.role
                } else {
                    userRoleCache.delete(user);
                    null
                }
            };
            case null { null };
        }
    };

    /// Caches a user's role for a specified duration
    /// @param user: The Principal of the user
    /// @param role: The role to cache
    private func cacheUserRole(user: Principal, role: Text) {
        let cachedRole : CachedRole = {
            role = role;
            expiresAt = Time.now() + 5 * 60 * 1_000_000_000; // Cache for 5 minutes
        };
        userRoleCache.put(user, cachedRole);
    };

    // Helper functions for user validation and access control

    /// Validates a user by checking with the Management Canister
    /// @param user: The Principal of the user to validate
    /// @return: A boolean indicating if the user is valid
    private func validateUser(user: Principal) : async Bool {
        let result = await managementCanister.handleDatabaseRequest(#UserValidation(user));
        switch (result) {
            case (#ok(isValid)) { isValid };
            case (#err(_)) { false };
        };
    };

    /// Checks if a user has access to a specific resource
    /// First checks the local cache, then queries the Management Canister if necessary
    /// @param user: The Principal of the user
    /// @param resource: The resource to check access for
    /// @return: A boolean indicating if the user has access
    private func checkAccess(user: Principal, resource: Text) : async Bool {
        switch (getCachedRole(user)) {
            case (?role) {
                // Local access check based on cached role
                return role == "admin" or (role == "user" and resource != "admin_only");
            };
            case null {
                let result = await managementCanister.handleDatabaseRequest(#AccessRightsCheck(user, resource));
                switch (result) {
                    case (#ok(hasAccess)) { 
                        if (hasAccess) {
                            cacheUserRole(user, if (resource == "admin_only") "admin" else "user");
                        };
                        hasAccess 
                    };
                    case (#err(_)) { false };
                };
            };
        }
    };

    /// Logs an operation with the Management Canister
    /// @param user: The Principal of the user performing the operation
    /// @param operation: A description of the operation
    private func logOperation(user: Principal, operation: Text) : async () {
        ignore await managementCanister.handleDatabaseRequest(#LogOperation(user, operation));
    };

    // CRUD Operations

    /// Creates a new document
    /// Only authenticated users with write access can create documents
    /// Example:
    /// ```motoko
    /// let docId = "doc1";
    /// let content = #Object([("name", #String("John Doe")), ("age", #Number(30))]);
    /// let result = await databaseCanister.createDocument(docId, content);
    /// switch (result) {
    ///     case (#ok(_)) { Debug.print("Document created successfully") };
    ///     case (#err(message)) { Debug.print("Error: " # message) };
    /// }
    /// ```
    public shared(msg) func createDocument(id: DocumentId, content: JSON.JSON) : async Result.Result<(), Text> {
        if (not await validateUser(msg.caller)) {
            return #err("User not authenticated");
        };

        if (not await checkAccess(msg.caller, "write_document")) {
            return #err("User does not have write access");
        };

        switch (documents.get(id)) {
            case (?_) { #err("Document already exists") };
            case null {
                let newDoc : Document = {
                    id = id;
                    content = content;
                    owner = msg.caller;
                    createdAt = Time.now();
                    updatedAt = Time.now();
                };
                documents.put(id, newDoc);
                await logOperation(msg.caller, "Create Document: " # id);
                #ok(())
            };
        };
    };

    /// Reads a document
    /// Authenticated users can read documents they have access to
    /// Example:
    /// ```motoko
    /// let docId = "doc1";
    /// let result = await databaseCanister.readDocument(docId);
    /// switch (result) {
    ///     case (#ok(doc)) { Debug.print("Document content: " # debug_show(doc.content)) };
    ///     case (#err(message)) { Debug.print("Error: " # message) };
    /// }
    /// ```
    public shared(msg) func readDocument(id: DocumentId) : async Result.Result<Document, Text> {
        if (not await validateUser(msg.caller)) {
            return #err("User not authenticated");
        };

        switch (documents.get(id)) {
            case (?doc) {
                if (not await checkAccess(msg.caller, "read_document")) {
                    return #err("User does not have read access");
                };
                await logOperation(msg.caller, "Read Document: " # id);
                #ok(doc)
            };
            case null { #err("Document not found") };
        };
    };

    /// Updates an existing document
    /// Only the document owner or users with admin access can update documents
    /// Example:
    /// ```motoko
    /// let docId = "doc1";
    /// let newContent = #Object([("name", #String("Jane Doe")), ("age", #Number(31))]);
    /// let result = await databaseCanister.updateDocument(docId, newContent);
    /// switch (result) {
    ///     case (#ok(_)) { Debug.print("Document updated successfully") };
    ///     case (#err(message)) { Debug.print("Error: " # message) };
    /// }
    /// ```
    public shared(msg) func updateDocument(id: DocumentId, newContent: JSON.JSON) : async Result.Result<(), Text> {
        if (not await validateUser(msg.caller)) {
            return #err("User not authenticated");
        };

        switch (documents.get(id)) {
            case (?doc) {
                if (doc.owner != msg.caller and not await checkAccess(msg.caller, "admin_access")) {
                    return #err("User does not have permission to update this document");
                };
                let updatedDoc : Document = {
                    id = id;
                    content = newContent;
                    owner = doc.owner;
                    createdAt = doc.createdAt;
                    updatedAt = Time.now();
                };
                documents.put(id, updatedDoc);
                await logOperation(msg.caller, "Update Document: " # id);
                #ok(())
            };
            case null { #err("Document not found") };
        };
    };

    /// Deletes a document
    /// Only the document owner or users with admin access can delete documents
    /// Example:
    /// ```motoko
    /// let docId = "doc1";
    /// let result = await databaseCanister.deleteDocument(docId);
    /// switch (result) {
    ///     case (#ok(_)) { Debug.print("Document deleted successfully") };
    ///     case (#err(message)) { Debug.print("Error: " # message) };
    /// }
    /// ```
    public shared(msg) func deleteDocument(id: DocumentId) : async Result.Result<(), Text> {
        if (not await validateUser(msg.caller)) {
            return #err("User not authenticated");
        };

        switch (documents.get(id)) {
            case (?doc) {
                if (doc.owner != msg.caller and not await checkAccess(msg.caller, "admin_access")) {
                    return #err("User does not have permission to delete this document");
                };
                documents.delete(id);
                await logOperation(msg.caller, "Delete Document: " # id);
                #ok(())
            };
            case null { #err("Document not found") };
        };
    };

    // Query functions

    /// Retrieves all documents owned by the caller
    /// Example:
    /// ```motoko
    /// let result = await databaseCanister.getMyDocuments();
    /// switch (result) {
    ///     case (#ok(docs)) { 
    ///         for (doc in docs.vals()) {
    ///             Debug.print("Document ID: " # doc.id);
    ///         }
    ///     };
    ///     case (#err(message)) { Debug.print("Error: " # message) };
    /// }
    /// ```
    public shared(msg) func getMyDocuments() : async Result.Result<[Document], Text> {
        if (not await validateUser(msg.caller)) {
            return #err("User not authenticated");
        };

        let userDocs = Buffer.Buffer<Document>(0);
        for (doc in documents.vals()) {
            if (doc.owner == msg.caller) {
                userDocs.add(doc);
            };
        };
        await logOperation(msg.caller, "Get My Documents");
        #ok(Buffer.toArray(userDocs))
    };

    /// Searches for documents based on a simple string match in content
    /// Only administrators can perform this operation
    /// Example:
    /// ```motoko
    /// let searchTerm = "John";
    /// let result = await databaseCanister.searchDocuments(searchTerm);
    /// switch (result) {
    ///     case (#ok(docs)) { 
    ///         for (doc in docs.vals()) {
    ///             Debug.print("Matching Document ID: " # doc.id);
    ///         }
    ///     };
    ///     case (#err(message)) { Debug.print("Error: " # message) };
    /// }
    /// ```
    public shared(msg) func searchDocuments(searchTerm: Text) : async Result.Result<[Document], Text> {
        if (not await validateUser(msg.caller)) {
            return #err("User not authenticated");
        };

        if (not await checkAccess(msg.caller, "admin_access")) {
            return #err("Only administrators can perform search operations");
        };

        let matchingDocs = Buffer.Buffer<Document>(0);
        for (doc in documents.vals()) {
            if (Text.contains(JSON.show(doc.content), #text searchTerm)) {
                matchingDocs.add(doc);
            };
        };
        await logOperation(msg.caller, "Search Documents: " # searchTerm);
        #ok(Buffer.toArray(matchingDocs))
    };

    // System queries

    /// Returns the total number of documents in the database
    /// This is a public query that doesn't require authentication
    /// Example:
    /// ```motoko
    /// let count = await databaseCanister.getDocumentCount();
    /// Debug.print("Total documents: " # Nat.toText(count));
    /// ```
    public query func getDocumentCount() : async Nat {
        documents.size()
    };

    /// Clears the role cache for testing or maintenance purposes
    /// Only users with admin access can perform this operation
    /// Example:
    /// ```motoko
    /// let result = await databaseCanister.clearRoleCache();
    /// switch (result) {
    ///     case (#ok(_)) { Debug.print("Role cache cleared successfully") };
    ///     case (#err(message)) { Debug.print("Error: " # message) };
    /// }
    /// ```
    public shared(msg) func clearRoleCache() : async Result.Result<(), Text> {
        if (not await checkAccess(msg.caller, "admin_access")) {
            return #err("Only administrators can clear the role cache");
        };
        userRoleCache := HashMap.HashMap<Principal, CachedRole>(50, Principal.equal, Principal.hash);
        await logOperation(msg.caller, "Clear Role Cache");
        #ok(())
    };
}
