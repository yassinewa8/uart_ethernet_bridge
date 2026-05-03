import serial
import time

def loopback_test(port, baudrate=9600, test_data=b'Hello, Loopback!', timeout=1):
    try:
        # Configure serial port
        ser = serial.Serial(
            port=port,
            baudrate=baudrate,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=timeout
        )
        
        print(f"Testing {port} at {baudrate} baud...")
        
        # Clear buffers
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        
        # Send test data
        print(f"Sending: {test_data}")
        ser.write(test_data)
        
        # Read back the data
        received_data = ser.read(len(test_data))
        
        # Compare sent vs received
        if received_data == test_data:
            print("✓ SUCCESS: Loopback test passed!")
            print(f"Received: {received_data}")
            return True
        else:
            print("✗ FAILED: Loopback test failed!")
            print(f"Sent: {test_data}")
            print(f"Received: {received_data}")
            return False
            
    except serial.SerialException as e:
        print(f"Error: {e}")
        return False
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()

# Usage example
if __name__ == "__main__":
    # Replace 'COM3' with your actual port (Windows: COMx, Linux/Mac: /dev/ttyUSBx or /dev/ttyACMx)
    port_name = "COM3"  # Change this to your port
    loopback_test(port_name)