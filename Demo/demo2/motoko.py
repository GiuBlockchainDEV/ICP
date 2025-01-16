import json
import time
import random
from datetime import datetime, timedelta
import math
from ic.client import Client
from ic.identity import Identity
from ic.agent import Agent
from ic.candid import Types

class HydroponicSystem:
    def __init__(self):
        self.current_state = {
            'ec': 1.5,          
            'ph': 6.0,          
            'water_temp': 22.0,  
            'air_temp': 25.0,    
            'humidity': 60.0,    
            'light': 500.0      
        }
        
        self.variation_params = {
            'ec': {'drift': 0.1, 'noise': 0.05},
            'ph': {'drift': 0.05, 'noise': 0.02},
            'water_temp': {'drift': 0.2, 'noise': 0.1},
            'air_temp': {'drift': 0.5, 'noise': 0.2},
            'humidity': {'drift': 1.0, 'noise': 0.5},
            'light': {'drift': 50.0, 'noise': 20.0}
        }
        
        self.limits = {
            'ec': {'min': 0.8, 'max': 3.0},
            'ph': {'min': 5.5, 'max': 6.5},
            'water_temp': {'min': 18.0, 'max': 26.0},
            'air_temp': {'min': 20.0, 'max': 30.0},
            'humidity': {'min': 50.0, 'max': 70.0},
            'light': {'min': 100.0, 'max': 1000.0}
        }

    def _apply_daily_cycle(self, hour):
        day_progress = (hour - 6) % 24
        if 6 <= hour < 18:
            light_factor = math.sin(math.pi * day_progress / 12)
            self.current_state['light'] = 500 + 400 * light_factor
        else:
            self.current_state['light'] = random.uniform(0, 10)

        temp_factor = math.sin(math.pi * ((day_progress - 2) % 24) / 12)
        self.current_state['air_temp'] = 25 + 3 * temp_factor

        water_temp_factor = math.sin(math.pi * ((day_progress - 4) % 24) / 12)
        self.current_state['water_temp'] = 22 + 2 * water_temp_factor

        humidity_factor = -math.sin(math.pi * day_progress / 12)
        self.current_state['humidity'] = 60 + 5 * humidity_factor

    def _apply_random_drift(self):
        for param in self.current_state:
            drift = self.variation_params[param]['drift']
            noise = self.variation_params[param]['noise']
            change = random.uniform(-drift, drift) + random.gauss(0, noise)
            self.current_state[param] += change
            self.current_state[param] = max(
                self.limits[param]['min'],
                min(self.limits[param]['max'],
                    self.current_state[param])
            )

    def _apply_correlations(self):
        ph_change = (self.current_state['ec'] - 1.5) * -0.1
        self.current_state['ph'] = max(5.5, min(6.5, self.current_state['ph'] + ph_change))
        
        humidity_change = (25 - self.current_state['air_temp']) * 0.5
        self.current_state['humidity'] = max(50, min(70, self.current_state['humidity'] + humidity_change))

    def generate_reading(self):
        current_hour = datetime.now().hour
        self._apply_daily_cycle(current_hour)
        self._apply_random_drift()
        self._apply_correlations()
        
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

class ICPClient:
    def __init__(self, canister_id):
        # Inizializza il client ICP
        print(f"Initializing ICP client for canister: {canister_id}")
        self.client = Client(url="https://ic0.app")
        self.identity = Identity()
        self.agent = Agent(self.identity, self.client)
        self.canister_id = canister_id

    def send_reading(self, device_hash, device_key, readings):
        """Invia i dati usando ic-py"""
        # Converti le letture in una stringa
        readings_text = ""
        first = True
        for reading in readings:
            if not first:
                readings_text += ","
            readings_text += f"type:{reading['readingType']},value:{reading['readingValue']},unit:{reading['readingUnit']}"
            first = False

        try:
            from ic.candid import encode
            from ic.identity import Principal
            from ic.candid import Types

            # Prepara i parametri nel formato corretto
            params = [
                {"type": Types.Text, "value": device_hash},
                {"type": Types.Text, "value": device_key},
                {"type": Types.Text, "value": readings_text}
            ]
            
            # Codifica gli argomenti
            args = encode(params)
            
            print(f"\nDebug - Sending data to canister {self.canister_id}")
            print(f"Debug - Method: addReading")
            print(f"Debug - Device Hash: {device_hash}")
            print(f"Debug - Key: {device_key}")
            print(f"Debug - Data: {readings_text}")
            
            # Mantieni il canister ID come stringa
            principal = Principal.from_str(self.canister_id)
            canister_id_str = str(principal)  # Converti il Principal in stringa
            
            # Esegui la chiamata al canister
            response = self.agent.update_raw(
                canister_id_str,  # Usa la stringa invece del Principal
                "addReading",
                args,
                timeout=30
            )
            
            print(f"Debug - Response: {response}")
            return {"success": True, "data": response}
            
        except Exception as e:
            print(f"Error sending data: {e}")
            print(f"Full error details: {str(e)}")
            import traceback
            print(f"Traceback: {traceback.format_exc()}")
            return {"success": False, "error": str(e)}

def simulate_readings(device_hash, device_key, canister_id, duration_hours=1, interval_minutes=5):
    """Simula letture per una durata specificata"""
    system = HydroponicSystem()
    icp_client = ICPClient(canister_id)
    
    start_time = datetime.now()
    end_time = start_time + timedelta(hours=duration_hours)
    
    print(f"Starting simulation at {start_time}")
    print(f"Will run until {end_time}")
    print(f"Sending data every {interval_minutes} minutes")

    while datetime.now() < end_time:
        try:
            # Genera dati
            readings = system.generate_reading()
            
            print(f"\nTime: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            for reading in readings:
                print(f"{reading['readingType']}: {reading['readingValue']} {reading['readingUnit']}")
            
            # Invia i dati
            result = icp_client.send_reading(device_hash, device_key, readings)
            if result['success']:
                print("Data sent successfully!")
            else:
                print(f"Failed to send data: {result.get('error', 'Unknown error')}")
            
            # Attendi per il prossimo ciclo
            time.sleep(interval_minutes * 60)
            
        except KeyboardInterrupt:
            print("\nSimulation stopped by user")
            break
        except Exception as e:
            print(f"Error in simulation: {e}")
            print("Waiting before next attempt...")
            time.sleep(60)

if __name__ == "__main__":
    # Configurazione
    DEVICE_HASH = "mzg4d-slh3z-6rikt-huoiv-r34hy-rpmyb-3c5ce-ybijs-ywz37-jx6tw-saeGrowTow1737022276143932304"
    DEVICE_KEY = "mzg4d-slh3z-6rikt-huoiv-r34hy-rpmyb-3c5ce-ybijs-ywz37-jx6tw-saeGrowTow17370222761439323041737022276143932304"
    CANISTER_ID = "ysmdh-qyaaa-aaaab-qacga-cai"
    
    try:
        simulate_readings(
            DEVICE_HASH, 
            DEVICE_KEY, 
            CANISTER_ID,
            duration_hours=1,
            interval_minutes=5
        )
    except KeyboardInterrupt:
        print("\nSimulation stopped by user")
