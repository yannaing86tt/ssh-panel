#!/usr/bin/env python3
import sys
import qrcode
from io import BytesIO

def generate_qr(data):
    qr = qrcode.QRCode(version=1, box_size=10, border=5)
    qr.add_data(data)
    qr.make(fit=True)
    return qr.make_image(fill_color="black", back_color="white")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: generate_qr.py <data>")
        sys.exit(1)
    
    data = sys.argv[1]
    img = generate_qr(data)
    img.save("/tmp/qr.png")
    print("/tmp/qr.png")
