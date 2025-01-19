import os
import secrets
import binascii
import time
import random
import math
from datetime import datetime, timedelta

from ic.candid import Types, encode
from ic.client import Client
from ic.agent import Agent
from ic.identity import Identity

class HydroponicDataSensor:
    def __init__(self, base_value, min_value, max_value, volatility=0.1):
        """
        Crea un sensore con andamento realistico
        
        :param base_value: Valore centrale
        :param min_value: Valore minimo
        :param max_value: Valore massimo
        :param volatility: Quanto può variare il valore
        """
        self.base_value = base_value
        self.min_value = min_value
        self.max_value = max_value
        self.volatility = volatility
        self.current_value = base_value
        self.time_index = 0

    def get_next_value(self):
        """
        Genera un valore successivo con andamento realistico
        Simula variazioni cicliche e casuali
        """
        # Componente ciclica (simula variazioni giornaliere/orarie)
        cycle_factor = math.sin(self.time_index * 0.5) * 0.3

        # Componente casuale
        random_factor = random.uniform(-self.volatility, self.volatility)

        # Calcolo del nuovo valore
        new_value = self.current_value + cycle_factor + random_factor

        # Mantieni il valore entro i limiti
        new_value = max(self.min_value, min(new_value, self.max_value))

        # Aggiorna stato
        self.current_value = new_value
        self.time_index += 1

        return round(new_value, 2)

class HydroponicDataLogger:
    def __init__(self, canister_id='ljyqf-uqaaa-aaaag-atzmq-cai', identity_path=None):
        # Configurazione dell'identità
        if identity_path is None:
            identity_path = os.path.expanduser("~/icp_identity.pem")
        
        self.identity_path = identity_path
        self.identity = self._load_or_create_identity()
        
        # ID del canister
        self.canister_id = canister_id

        # Configura il client e l'agent
        self.client = Client(url="https://icp0.io")
        self.agent = Agent(client=self.client, identity=self.identity)

    def _load_or_create_identity(self):
        """
        Carica un'identità esistente o ne crea una nuova
        """
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

    def insert_reading(self, entity_id, value):
        """
        Inserisce una lettura nel canister
        """
        try:
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
            
            print(f"Lettura per {entity_id} inserita: {value}")
            return result
        
        except Exception as e:
            print(f"Errore durante l'inserimento della lettura {entity_id}: {e}")
            return None

def main():
    # Crea il logger
    logger = HydroponicDataLogger()
    
    # Crea sensori con parametri realistici
    # Entity 11: EC (µS/cm)
    ec_sensor = HydroponicDataSensor(
        base_value=1850,  # Valore medio µS/cm
        min_value=1200,   # Minimo per colture idroponiche
        max_value=2500,   # Massimo per colture idroponiche
        volatility=50     # Variazione moderata
    )

    # Entity 12: pH
    ph_sensor = HydroponicDataSensor(
        base_value=6.0,   # pH ottimale
        min_value=5.5,    # Limite inferiore
        max_value=6.5,    # Limite superiore
        volatility=0.2    # Bassa volatilità
    )

    # Entity 13: Temperatura (°C)
    temp_sensor = HydroponicDataSensor(
        base_value=22.5,  # Temperatura media ottimale
        min_value=20,     # Minimo tollerabile
        max_value=25,     # Massimo tollerabile
        volatility=0.5    # Moderata variazione
    )

    # Entity 14: Umidità (%)
    humidity_sensor = HydroponicDataSensor(
        base_value=65,    # Umidità media ottimale
        min_value=60,     # Minimo
        max_value=70,     # Massimo
        volatility=2      # Variazione moderata
    )
    
    # Tempo totale di logging: 1 ora
    total_duration = timedelta(hours=1)
    start_time = datetime.now()
    end_time = start_time + total_duration

    print(f"Inizio logging dati idroponici: {start_time}")
    print(f"Fine logging: {end_time}")

    # Ciclo di inserimento dati ogni 5 minuti
    while datetime.now() < end_time:
        try:
            # Genera e inserisce letture
            logger.insert_reading("11", ec_sensor.get_next_value())
            logger.insert_reading("12", ph_sensor.get_next_value())
            logger.insert_reading("13", temp_sensor.get_next_value())
            logger.insert_reading("14", humidity_sensor.get_next_value())

            # Attendi 5 minuti prima del prossimo inserimento
            time.sleep(300)  # 300 secondi = 5 minuti

        except Exception as e:
            print(f"Errore durante il logging: {e}")
            # In caso di errore, attendi comunque 5 minuti
            time.sleep(300)

    print("Logging completato.")

if __name__ == "__main__":
    main()
