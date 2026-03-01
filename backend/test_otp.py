import requests
import json
try:
    print("Requesting OTP...")
    r1 = requests.post('http://localhost:8001/api/auth/request-otp', json={'phone': '+221770000000'})
    print(r1.json())
    print("Verifying OTP...")
    r2 = requests.post('http://localhost:8001/api/auth/verify-otp', json={'phone': '+221770000000', 'otp': '123456'})
    print(json.dumps(r2.json(), indent=2))
except Exception as e:
    print("Error:", e)
