import serial

# CHANGE THIS TO YOUR PORT
PORT = "COM3"
BAUDRATE = 921_600  

ser = serial.Serial(PORT, BAUDRATE, timeout=1)
print("Ready! Type something and press Enter...")

while True:
    text = input("Send: ")
    
    if text == 'quit':
        break
    
    # Send the text
    ser.write(text.encode())
    
    #Read it back
    received = ser.read(len(text)).decode()
    print(f"Received: {received}")

ser.close()