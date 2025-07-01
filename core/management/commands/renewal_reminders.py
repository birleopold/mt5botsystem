from django.core.management.base import BaseCommand
from core.models import Subscription
from django.utils import timezone
from django.core.mail import send_mail
from django.conf import settings
from datetime import timedelta

class Command(BaseCommand):
    help = 'Send renewal reminder emails to users whose subscriptions expire soon.'

    def handle(self, *args, **kwargs):
        now = timezone.now()
        soon = now + timedelta(days=7)
        expiring = Subscription.objects.filter(is_active=True, end_date__range=(now, soon))
        count = 0
        for sub in expiring:
            send_mail(
                subject='Your Subscription is Expiring Soon',
                message=f'Dear {sub.user.username}, your subscription to {sub.plan.name} will expire on {sub.end_date.date()}. Please renew to avoid interruption.',
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[sub.user.email],
                fail_silently=True,
            )
            count += 1
        self.stdout.write(self.style.SUCCESS(f"{count} renewal reminders sent."))
