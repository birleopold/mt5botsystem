from django import forms
from .models import Payment, Subscription

class ManualPaymentForm(forms.ModelForm):
    class Meta:
        model = Payment
        fields = ['proof_of_payment', 'notes']
        widgets = {
            'notes': forms.Textarea(attrs={'rows': 3}),
        }

class SubscriptionForm(forms.ModelForm):
    class Meta:
        model = Subscription
        fields = ['plan']
