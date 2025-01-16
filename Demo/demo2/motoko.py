import requests
import json
import time
import random
from datetime import datetime, timedelta
import math

class HydroponicSystem:
    def __init__(self):
        # Stato iniziale del sistema
        self.current_state = {
            'ec': 1.5,          # mS/cm
            'ph': 6.0,          # pH
            'water_temp': 22.0,  # °C
            'air_temp': 25.0,    # °C
            'humidity': 60.0,    # %
            'light': 500.0      # PPFD
        }
        
        # Parametri di variazione
        self.variation_params = {
            'ec': {'drift': 0.1, 'noise': 0.05},
            'ph': {'drift': 0.05, 'noise': 0.02},
            'water_temp': {'drift': 0.2, 'noise': 0.1},
            'air_temp': {'drift': 0.5, 'noise': 0.2},
            'humidity': {'drift': 1.0, 'noise': 0.5},
            'light': {'drift': 50.0, 'noise': 20.0}
        }
        
        # Limiti per ogni parametro
        self.limits = {
            'ec': {'min': 0.8, 'max': 3.0},
            'ph': {'min': 5.5, 'max': 6.5},
            'water_temp': {'min': 18.0, 'max': 26.0},
            'air_temp': {'min': 20.0, 'max': 30.0},
            'humidity': {'min': 50.0, 'max': 70.0},
            'light': {'min': 100.0, 'max': 1000.0}
        }

    def _apply_daily_cycle(self, hour):
        """Applica variazioni basate sul ciclo giornaliero"""
        # Ciclo della luce (sinusoidale)
        day_progress = (hour - 6) % 24  # Inizia alle 6:00
        if 6 <= hour < 18:
            light_factor = math.sin(math.pi * day_progress / 12)
            self.current_state['light'] = 500 + 400 * light_factor
        else:
            self.current_state['light'] = random.uniform(0, 10)  # Luce notturna minima

        # La temperatura dell'aria segue la luce con un ritardo
        temp_factor = math.sin(math.pi * ((day_progress - 2) % 24) / 12)
        self.current_state['air_temp'] = 25 + 3 * temp_factor

        # La temperatura dell'acqua segue la temperatura dell'aria più lentamente
        water_temp_factor = math.sin(math.pi * ((day_progress - 4) % 24) / 12)
        self.current_state['water_temp'] = 22 + 2 * water_temp_factor

        # L'umidità è inversamente proporzionale alla temperatura
        humidity_factor = -math.sin(math.pi * day_progress / 12)
        self.current_state['humidity'] = 60 + 5 * humidity_factor

    def _apply_random_drift(self):
        """Applica una deriva casuale a tutti i parametri"""
        for param in self.current_state:
            drift = self.variation_params[param]['drift']
            noise = self.variation_params[param]['noise']
            
            # Applica deriva e rumore
            change = random.uniform(-drift, drift) + random.gauss(0, noise)
            self.current_state[param] += change
            
            # Mantieni nei limiti
            self.current_state[param] = max(
                self.limits[param]['min'],
                min(self.limits[param]['max'],
                    self.current_state[param])
            )

    def _apply_correlations(self):
        """Applica correlazioni tra i diversi parametri"""
        # EC influenza leggermente il pH
        ph_change = (self.current_state['ec'] - 1.5) * -0.1
        self.current_state['ph'] = max(5.5, min(6.5, self.current_state['ph'] + ph_change))
        
        # Temperatura dell'aria influenza l'umidità
        humidity_change = (25 - self.current_state['air_temp']) * 0.5
        self.current_state['humidity'] = max(50, min(70, self.current_state['humidity'] + humidity_change))

    def generate_reading(self):
        """Genera una nuova lettura nel formato richiesto dal contratto Motoko"""
        current_hour = datetime.now().hour
        
        # Applica le variazioni in sequenza
        self._apply_daily_cycle(current_hour)
        self._apply_random_drift()
        self._apply_correlations()
        
        # Formatta i dati nel formato richiesto dal contratto
        readings = [
            {
                "readingType": "ec",
                "readingValue": round(self.current_state['ec'], 2),
                "readingUnit": "mS/cm"
            },
            {
                "readingType": "ph",
                "readingValue": round(self.current_state['ph'], 2),
                "readingUnit": "pH"
            },
            {
                "readingType": "water_temperature",
                "readingValue": round(self.current_state['water_temp'], 2),
                "readingUnit": "C"
            },
            {
                "readingType": "air_temperature",
                "readingValue": round(self.current_state['air_temp'], 2),
                "readingUnit": "C"
            },
            {
                "readingType": "humidity",
                "readingValue": round(self.current_state['humidity'], 2),
                "readingUnit": "%"
            },
            {
                "readingType": "light",
                "readingValue": round(self.current_state['light'], 2),
                "readingUnit": "PPFD"
            }
        ]
        
        return readings

def send_reading(device_hash, device_key, readings, canister_id):
    """Invia i dati al canister ICP"""
    url = f"https://{canister_id}.raw.ic0.app/addReading"
    
    # Converti le letture nel formato richiesto dal contratto
    readings_text = ",".join([
        f"type:{r['readingType']},value:{r['readingValue']},unit:{r['readingUnit']}"
        for r in readings
    ])
    
    data = {
        "deviceHash": device_hash,
        "deviceKey": device_key,
        "readingText": readings_text
    }
    
    try:
        response = requests.post(
            url,
            headers={'Content-Type': 'application/json'},
            data=json.dumps(data)
        )
        return response.json()
    except Exception as e:
        print(f"Error sending data: {e}")
        return None

def simulate_readings(device_hash, device_key, canister_id, duration_hours=1, interval_minutes=5):
    """Simula letture per una durata specificata"""
    system = HydroponicSystem()
    start_time = datetime.now()
    end_time = start_time + timedelta(hours=duration_hours)
    
    print(f"Starting simulation at {start_time}")
    print(f"Will run until {end_time}")
    print(f"Sending data every {interval_minutes} minutes")
    
    while datetime.now() < end_time:
        # Genera dati
        readings = system.generate_reading()
        
        # Stampa dati generati
        print(f"\nTime: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        for reading in readings:
            print(f"{reading['readingType']}: {reading['readingValue']} {reading['readingUnit']}")
        
        # Invia dati
        result = send_reading(device_hash, device_key, readings, canister_id)
        if result:
            print(f"Response from canister: {result}")
        
        # Attendi per il prossimo ciclo
        time.sleep(interval_minutes * 60)

if __name__ == "__main__":
    # Configurazione
    DEVICE_HASH = "your_device_hash"
    DEVICE_KEY = "your_device_key"
    CANISTER_ID = "your_canister_id"
    
    # Durata simulazione e intervallo
    DURATION_HOURS = 1
    INTERVAL_MINUTES = 5
    
    try:
        simulate_readings(
            DEVICE_HASH, 
            DEVICE_KEY, 
            CANISTER_ID,
            duration_hours=DURATION_HOURS,
            interval_minutes=INTERVAL_MINUTES
        )
    except KeyboardInterrupt:
        print("\nSimulation stopped by user")
