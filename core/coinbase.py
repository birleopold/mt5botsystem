import requests
from django.conf import settings

COINBASE_API_URL = 'https://api.commerce.coinbase.com/charges'

# You must add your Coinbase Commerce API key to settings.py
# COINBASE_COMMERCE_API_KEY = 'your_api_key_here'

def create_charge(plan_name, price, user_email):
    headers = {
        'Content-Type': 'application/json',
        'X-CC-Api-Key': settings.COINBASE_COMMERCE_API_KEY,
        'X-CC-Version': '2018-03-22',
    }
    data = {
        'name': plan_name,
        'description': f'Subscription for {plan_name}',
        'pricing_type': 'fixed_price',
        'local_price': {
            'amount': str(price),
            'currency': 'USD',
        },
        'metadata': {
            'user_email': user_email,
        }
    }
    response = requests.post(COINBASE_API_URL, json=data, headers=headers)
    if response.status_code == 201:
        return response.json()['data']
    return None
