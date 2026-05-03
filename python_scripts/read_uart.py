import serial
import time

# CHANGE THESE TO MATCH YOUR DEVICE
PORT = "COM3"
BAUDRATE = 921600 

try:
    # Open the serial port
    ser = serial.Serial(PORT, BAUDRATE, timeout=1)
    print(f"Hex Sniffer started on {PORT} at {BAUDRATE} baud.")
    print("Waiting for raw Ethernet data... Press Ctrl+C to stop.\n")

    # A buffer to hold bytes until we have a neat row of 16
    byte_buffer = bytearray()

    while True:
        if ser.in_waiting > 0:
            # Read all currently waiting bytes
            raw_data = ser.read(ser.in_waiting)
            byte_buffer.extend(raw_data)
            
            # Print rows of 16 bytes
            while len(byte_buffer) >= 16:
                chunk = byte_buffer[:16]     # Grab the first 16 bytes
                del byte_buffer[:16]         # Remove them from the buffer
                
                # Convert the chunk to uppercase hex with spaces
                hex_row = chunk.hex(' ').upper()
                print(hex_row)
                
        # A tiny sleep prevents the loop from maxing out your CPU
        time.sleep(0.01)

except KeyboardInterrupt:
    print("\nStopping sniffer...")
    
    # Print any leftover bytes that didn't make a full row of 16
    if byte_buffer:
        print("Leftover bytes:", byte_buffer.hex(' ').upper())

except serial.SerialException as e:
    print(f"\nSerial error: {e}")

finally:
    if 'ser' in locals() and ser.is_open:
        ser.close()
        print("Port closed cleanly.")