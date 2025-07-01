from django.conf import settings
from binascii import hexlify
import os

def generate_binance_payment_request(plan_name, price, user_email):
    # Generate a unique payment reference for the user/plan/amount
    # In a real setup, you could use Binance Pay API if available, or provide static wallet addresses
    reference = hexlify(os.urandom(8)).decode()
    return {
        'wallet_address': settings.BINANCE_WALLET_ADDRESS,
        'amount': price,
        'currency': 'USDT',
        'reference': reference,
        'plan_name': plan_name,
        'instructions': f"Send exactly {price} USDT to the Binance address below. Include reference: {reference} in the memo or upload a screenshot of your transaction.",
    }
