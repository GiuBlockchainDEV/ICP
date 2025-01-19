import os
import secrets
import binascii

from ic.candid import Types, encode

class ICPClient:
    def __init__(self, canister_id='ljyqf-uqaaa-aaaag-atzmq-cai', identity_path=None):
        # Percorso predefinito per l'identità
        if identity_path is None:
            identity_path = os.path.expanduser("~/icp_identity.pem")
        
        # Crea o carica l'identità
        self.identity_path = identity_path
        self.identity = self._load_or_create_identity()
        
        # ID del canister
        self.canister_id = canister_id

        # Configura il client e l'agent
        from ic.client import Client
        from ic.agent import Agent
        
        self.client = Client(url="https://icp0.io")
        self.agent = Agent(client=self.client, identity=self.identity)

    def _load_or_create_identity(self):
        """
        Carica un'identità esistente o ne crea una nuova
        """
        from ic.identity import Identity
        
        try:
            # Prova a caricare l'identità esistente
            if os.path.exists(self.identity_path):
                print(f"Caricamento identità esistente da {self.identity_path}")
                with open(self.identity_path, 'rb') as f:
                    return Identity.from_pem(f.read())
        except Exception as e:
            print(f"Errore nel caricamento dell'identità esistente: {e}")
        
        # Crea nuova identità
        print("Creazione nuova identità...")
        # Genera un seed casuale
        seed = secrets.token_bytes(32)
        seed_hex = binascii.hexlify(seed).decode('utf-8')
        
        try:
            identity = Identity(seed_hex)
        except Exception as e:
            print(f"Errore nella creazione dell'identità: {e}")
            raise
        
        # Assicura che la directory esista
        os.makedirs(os.path.dirname(self.identity_path), exist_ok=True)
        
        # Salva l'identità
        with open(self.identity_path, 'wb') as f:
            f.write(identity.to_pem())
        
        print(f"Nuova identità creata:")
        print(f"Principal: {identity.sender()}")
        print(f"Identità salvata in: {self.identity_path}")
        
        return identity

    def add_authorized_user(self):
        """
        Aggiunge l'utente corrente come utente autorizzato
        """
        try:
            print(f"\nAutorizzazione utente:")
            principal_str = str(self.identity.sender())
            print(f"Principal: {principal_str}")
            
            # Preparazione dell'argomento usando il tipo Principal
            params = [
                {'type': Types.Principal, 'value': principal_str}
            ]
            
            # Codifica Candid
            encoded_arg = encode(params)
            
            # Chiamata per aggiungere l'utente autorizzato
            result = self.agent.update_raw(
                canister_id=self.canister_id, 
                method_name="addAuthorizedUser", 
                arg=encoded_arg
            )
            
            print("Utente autorizzato con successo")
            print("Risultato:", result)
            
            return result
        
        except Exception as e:
            print(f"Errore durante l'autorizzazione dell'utente: {e}")
            return None

    def insert_reading(self, entity_id, value):
        """
        Inserisce una lettura nel canister
        """
        try:
            print(f"\nInserimento lettura per {entity_id}: {value}")
            print(f"Principal: {self.identity.sender()}")
            
            # Preparazione degli argomenti per la codifica Candid
            params = [
                {'type': Types.Text, 'value': str(entity_id)},
                {'type': Types.Float64, 'value': float(value)}
            ]
            
            # Codifica Candid
            encoded_args = encode(params)
            
            # Chiamata per inserire la lettura
            result = self.agent.update_raw(
                canister_id=self.canister_id, 
                method_name="insertReading", 
                arg=encoded_args
            )
            
            print("Lettura inserita con successo")
            print("Risultato:", result)
            print("Encoded args (hex):", encoded_args.hex())
            
            return result
        
        except Exception as e:
            print(f"Errore durante l'inserimento della lettura: {e}")
            return None

def main():
    # Crea il client ICP
    client = ICPClient()
    
    # IMPORTANTE: 
    print("\n--- PROCEDURA DI AUTORIZZAZIONE ---")
    print(f"1. Principal dell'utente: {client.identity.sender()}")
    print("2. Autorizzazione utente...")
    
    # Autorizza l'utente
    client.add_authorized_user()
    
    # Esempio di inserimento letture
    client.insert_reading("4", 25.5)
    client.insert_reading("5", 60.2)

if __name__ == "__main__":
    main()
