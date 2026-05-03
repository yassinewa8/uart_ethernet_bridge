from scapy.all import Ether, sendp

# CHANGE THIS to the exact name of the network adapter connected to your FPGA 
# (e.g., "Ethernet 2" on Windows, or "eth0" on Linux)
INTERFACE = "Ethernet" 

# 1. Prepare your custom raw bytes
custom_payload = bytes.fromhex("AAAAAAAAAA")

# 2. Craft the Layer 2 Ethernet Frame
# We use recognizable dummy MAC addresses so you can easily spot them in your FPGA output
packet = Ether(src="12:34:56:78:9A:CB", dst="11:22:33:44:55:66", type=0x1111) / custom_payload

# 3. Send the packet directly out of the physical interface
print(f"Sending custom packet out of {INTERFACE}...")
sendp(packet, iface=INTERFACE, verbose=True)

print("Packet sent!")