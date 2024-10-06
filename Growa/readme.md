# IoT Data Canister for Internet Computer

## Overview
This smart contract, written in Motoko, is designed to manage IoT device data on the Internet Computer platform. It provides functionality for device management, data storage, and retrieval, with an emphasis on security and ownership control.

## Key Features

1. **Ownership Management**
   - Initial owner setup
   - Ability to change ownership
   - Owner verification for sensitive operations

2. **Device Management**
   - Enable/disable devices
   - Check device status

3. **Data Handling**
   - Store IoT data (temperature, humidity, pressure) with timestamps
   - Retrieve data for specific devices
   - Get the latest data entry for a device
   - Fetch all stored data across all devices

## Main Functions

### Ownership Functions
- `setInitialOwner()`: Sets the initial owner of the canister
- `changeOwner(newOwner)`: Allows the current owner to transfer ownership
- `getOwner()`: Retrieves the current owner's Principal

### Device Management Functions
- `enableDevice(deviceId)`: Enables a specific device (owner only)
- `disableDevice(deviceId)`: Disables a specific device (owner only)
- `isDeviceEnabled(deviceId)`: Checks if a device is enabled

### Data Handling Functions
- `insertIoTData(deviceId, temp, hum, press)`: Inserts new data for an enabled device
- `getDeviceData(deviceId)`: Retrieves all data for a specific device
- `getLastDeviceData(deviceId)`: Gets the most recent data entry for a device
- `getAllData()`: Retrieves all data for all devices

## Data Structure
- `IoTData`: Struct containing deviceId, timestamp, temperature, humidity, and pressure
- `dataStore`: HashMap storing device data using Buffer for efficient operations
- `enabledDevices`: HashMap tracking the enabled/disabled status of devices

## Security Considerations
- Only the owner can enable/disable devices and change ownership
- Data can only be inserted for enabled devices
- Public query functions allow data retrieval without modification risks

## Usage
1. Deploy the canister
2. Set the initial owner
3. Enable devices as needed
4. IoT devices can then send data to enabled deviceIds
5. Retrieve and analyze data using the provided query functions

This smart contract provides a robust foundation for managing IoT data on the Internet Computer, with built-in security measures and efficient data handling.
